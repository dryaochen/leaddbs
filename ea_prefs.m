function prefs=ea_prefs(patientname)

% get default prefs
prefs=ea_prefs_default(patientname);
% now overwrite with user prefs stored in /home
home=ea_gethome;
uid=['ea_prefs_',dash2sub(ea_generate_guid)];

if ~exist([home,'.ea_prefs.m'],'file')
    copyfile([ea_getearoot,'ea_prefs_default.m'],[home,'.ea_prefs.m']);
end
try
    copyfile([home,'.ea_prefs.m'],[ea_getearoot,uid,'.m'])
    uprefs=feval(uid,patientname);
    delete([ea_getearoot,uid,'.m']);
catch
   warning('User preferences file could not be read. Please set write permissions to Lead-DBS install directory accordingly.');
   return
end

ufn=fieldnames(uprefs);

for uf=1:length(ufn) % compare user preferences with defaults and overwrite defaults where present.
    try
        ufn2=fieldnames(uprefs.(ufn{uf}));
        for uf2=1:length(ufn2)
            try
                ufn3=fieldnames(uprefs.(ufn{uf}).(ufn2{uf2}));
                for uf3=1:length(ufn3)
                    try
                        ufn4=fieldnames(uprefs.(ufn{uf}).(ufn2{uf2}).(ufn3{uf3}));
                        for uf4=1:length(ufn4) % add fourth level entries
                            prefs.(ufn{uf}).(ufn2{uf2}).(ufn3{uf3}).(ufn4{uf4})=uprefs.(ufn{uf}).(ufn2{uf2}).(ufn3{uf3}).(ufn4{uf4});
                        end
                    catch % add third level entries
                        prefs.(ufn{uf}).(ufn2{uf2}).(ufn3{uf3})=uprefs.(ufn{uf}).(ufn2{uf2}).(ufn3{uf3});
                    end
                end
            catch % add second level entries
                prefs.(ufn{uf}).(ufn2{uf2})=uprefs.(ufn{uf}).(ufn2{uf2});
            end
        end
    catch % add first level entries
        prefs.(ufn{uf})=uprefs.(ufn{uf});
    end
end

function str=dash2sub(str) % replaces subscores with spaces
str(str=='-')='_';
