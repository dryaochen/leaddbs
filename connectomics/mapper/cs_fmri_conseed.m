function cs_fmri_conseed(dfold,cname,sfile,cmd,writeoutsinglefiles,outputfolder,outputmask)
tic
if ~isdeployed
    addpath(genpath('/autofs/cluster/nimlab/connectomes/software/lead_dbs'));
    addpath('/autofs/cluster/nimlab/connectomes/software/spm12');
end
if ~exist('writeoutsinglefiles','var')
    writeoutsinglefiles=0;
else
    if ischar(writeoutsinglefiles)
    writeoutsinglefiles=str2double(writeoutsinglefiles);
    end
end



if ~exist('dfold','var')
    dfold=''; % assume all data needed is stored here.
else
    if ~strcmp(dfold(end),filesep)
        dfold=[dfold,filesep];
    end
end

if ismember('>',cname)
    delim=strfind(cname,'>');
    subset=cname(delim+2:end);
    cname=cname(1:delim-2);
end


dfoldsurf=[dfold,'fMRI',filesep,cname,filesep,'surf',filesep];
dfoldvol=[dfold,'fMRI',filesep,cname,filesep,'vol',filesep]; % expand to /vol subdir.


d=load([dfold,'fMRI',filesep,cname,filesep,'dataset_info.mat']);
dataset=d.dataset;
clear d;
if exist('outputmask','var')
    if ~isempty(outputmask)
        omask=ea_load_nii(outputmask);
        omaskidx=find(omask.img(:));
        [~,maskuseidx]=ismember(omaskidx,dataset.vol.outidx);
    else
        omaskidx=dataset.vol.outidx;
        maskuseidx=1:length(dataset.vol.outidx);
    end
else
    omaskidx=dataset.vol.outidx; % use all.
        maskuseidx=1:length(dataset.vol.outidx);
end

[sfile,roilist]=ea_handleseeds(sfile);



if ~exist('outputfolder','var')
    [pth,fn,ext]=fileparts(sfile); % exit to same folder as seed.
    outputfolder=[pth,filesep];
else
    if isempty(outputfolder) % from shell wrapper.
    [pth,fn,ext]=fileparts(sfile); % exit to same folder as seed.
    outputfolder=[pth,filesep];    
    end
    if ~strcmp(outputfolder(end),filesep)
        outputfolder=[outputfolder,filesep];
    end
end



if strcmp(sfile{1}(end-2:end),'.gz')
    %gunzip(sfile)
    %sfile=sfile(1:end-3);
    usegzip=1;
else
    usegzip=0;
end

for s=1:length(sfile)
    
    seed{s}=ea_load_nii(ea_niigz(sfile{s}));
    if ~isequal(seed{s}.mat,dataset.vol.space.mat)
        oseedfname=seed{s}.fname;
        seed{s}=ea_conformseedtofmri(dataset,seed{s});
        seed{s}.fname=oseedfname; % restore original filename if even unneccessary at present.
    end
    
    [~,seedfn{s}]=fileparts(sfile{s});
    
    sweights=seed{s}.img(dataset.vol.outidx);
    sweights(isnan(sweights))=0;
    sweights(abs(sweights)<0.0001)=0;
    sweights=double(sweights);
    % assure sum of sweights is 1
    %sweights(logical(sweights))=sweights(logical(sweights))/abs(sum(sweights(logical(sweights))));
    sweightmx=repmat(sweights,1,120);
    
    sweightidx{s}=find(sweights);
    sweightidxmx{s}=double(sweightmx(sweightidx{s},:));
end
numseed=s;


pixdim=length(dataset.vol.outidx);

numsub=length(dataset.vol.subIDs);
% init vars:
switch cmd
    case {'seed'}
        for s=1:numseed
            fX{s}=nan(length(omaskidx),numsub);
            rh.fX{s}=nan(10242,numsub);
            lh.fX{s}=nan(10242,numsub);
        end
    case 'pmap'
        
        for s=1:numseed-1
            fX{s}=nan(length(omaskidx),numsub);
        end
    otherwise
        fX=nan(((numseed^2)-numseed)/2,numsub);
end

switch cmd
    case 'matrix'
        addp='';
    case 'pmatrix'
        addp='p';
end


disp([num2str(numseed),' seeds, command = ',cmd,'.']);

ea_dispercent(0,'Iterating through subjects');

if ~exist('subset','var') % use all subjects
    usesubjects=1:numsub;
else
    for ds=1:length(dataset.subsets)
        if strcmp(subset,dataset.subsets(ds).name)
            usesubjects=dataset.subsets(ds).subs;
            break
        end
    end
end



for mcfi=usesubjects
    ea_dispercent(mcfi/numsub);
    howmanyruns=ea_cs_dethowmanyruns(dataset,mcfi);
    switch cmd
        
        case 'seed'
            
            for s=1:numseed
                
                thiscorr=zeros(length(omaskidx),howmanyruns);
                for run=1:howmanyruns
                    switch dataset.type
                        case 'fMRI_matrix'
                            keyboard
                            if ~exist('mat','var') && ~exist('loaded','var')
                            mat=[]; loaded=[];
                            end
                            cnt=1;
                            Rw=nan(length(sweightidx{s}),pixdim);
                            for ix=sweightidx{s}'
                            [mat,loaded]=ea_getmat(mat,loaded,ix,dataset.vol.matchunk,[dfold,'fMRI',filesep,cname,filesep,'vol',filesep]);
                            entry=ix-loaded;
                            %    testnii.img(outidx)=mat(entry,:); % R
                            Rw(cnt,:)=(double(mat(entry,:))/((2^15)-1)); % Fz
                            cnt=cnt+1;
                            end
                        case 'fMRI_timecourses'
                            load([dfoldvol,dataset.vol.subIDs{mcfi}{run+1}])
                            gmtc=single(gmtc);
                            stc=mean(gmtc(sweightidx{s},:).*sweightidxmx{s},1);
                            thiscorr(:,run)=corr(stc',gmtc(maskuseidx,:)','type','Pearson');
                            if isfield(dataset,'surf')
                                % include surface:
                                ls=load([dfoldsurf,dataset.surf.l.subIDs{mcfi}{run+1}]);
                                rs=load([dfoldsurf,dataset.surf.r.subIDs{mcfi}{run+1}]);
                                rs.gmtc=single(rs.gmtc);
                                ls.gmtc=single(ls.gmtc);
                                ls.thiscorr(:,run)=corr(stc',ls.gmtc','type','Pearson');
                                rs.thiscorr(:,run)=corr(stc',rs.gmtc','type','Pearson');
                            end
                    end
                end
                
                fX{s}(:,mcfi)=mean(thiscorr,2);
                lh.fX{s}(:,mcfi)=mean(ls.thiscorr,2);
                rh.fX{s}(:,mcfi)=mean(rs.thiscorr,2);                
                
                
                if writeoutsinglefiles
                    ccmap=dataset.vol.space;
                    ccmap.img=single(ccmap.img);
                    ccmap.fname=[outputfolder,seedfn{s},'_',dataset.vol.subIDs{mcfi}{1},'_corr.nii'];
                    ccmap.img(omaskidx)=fX{s}(:,mcfi);  
                    ccmap.dt=[16,0];
                    spm_write_vol(ccmap,ccmap.img);
                end
            end
        case 'pmap'

            
            targetix=sweightidx{1};
            clear stc
            thiscorr=cell(numseed-1,1);
            for s=1:numseed-1
                thiscorr{s}=zeros(length(omaskidx),howmanyruns);
            end
            for run=1:howmanyruns
                for s=2:numseed
                    switch dataset.type
                        case 'fMRI_matrix'
                            keyboard
                            if ~exist('mat','var') && ~exist('loaded','var')
                                mat=[]; loaded=[];
                            end
                            cnt=1;
                            Rw=nan(length(sweightidx{s}),pixdim);
                            for ix=sweightidx{s}'
                                [mat,loaded]=ea_getmat(mat,loaded,ix,dataset.vol.matchunk,[dfold,'fMRI',filesep,cname,filesep,'vol',filesep]);
                                entry=ix-loaded;
                                %    testnii.img(outidx)=mat(entry,:); % R
                                Rw(cnt,:)=(double(mat(entry,:))/((2^15)-1)); % Fz
                                cnt=cnt+1;
                            end
                        case 'fMRI_timecourses'
                            load([dfoldvol,dataset.vol.subIDs{mcfi}{run+1}])
                            gmtc=single(gmtc);
                            stc(:,s-1)=mean(gmtc(sweightidx{s},:).*sweightidxmx{s});
                    end
                end
                % now we have all seeds, need to iterate across voxels of
                % target to get pmap values
                    
                    for s=1:size(stc,2)
                        seedstc=stc(:,s);
                        otherstc=stc;
                        otherstc(:,s)=[];
          
                        targtc=gmtc(targetix,:);
                        thiscorr{s}(targetix,run)=partialcorr(targtc',seedstc,otherstc);

                    end
            end 
            

            for s=1:size(stc,2)
                fX{s}(:,mcfi)=mean(thiscorr{s},2);
                if writeoutsinglefiles
                    ccmap=dataset.vol.space;
                    ccmap.dt=[16 0];
                    ccmap.img=single(ccmap.img);
                    ccmap.fname=[outputfolder,seedfn{s},'_',dataset.vol.subIDs{mcfi}{1},'_pmap.nii'];
                    ccmap.img(omaskidx)=fX{s}(:,mcfi);
                    spm_write_vol(ccmap,ccmap.img);
                end
            end
            
            
        otherwise
            for run=1:howmanyruns
                load([dfoldvol,dataset.vol.subIDs{mcfi}{run+1}])
                gmtc=single(gmtc);
                
                for s=1:numseed
                    stc(s,:)=mean(gmtc(sweightidx{s},:).*sweightidxmx{s});
                end
                
                switch cmd
                    case 'matrix'
                        X=corrcoef(stc');
                        
                    case 'pmatrix'
                        X=partialcorr(stc');
                end
                thiscorr(:,run)=X(:);
            end
            thiscorr=mean(thiscorr,2);
            X(:)=thiscorr;
            fX(:,mcfi)=X(logical(triu(ones(numseed),1)));
            if writeoutsinglefiles
                save([outputfolder,addp,'corrMx_',dataset.vol.subIDs{mcfi}{1},'.mat'],'X','-v7.3');
            end
    end
end
ea_dispercent(1,'end');
ispmap=strcmp(cmd,'pmap');
if ispmap
    seedfn(1)=[]; % delete first seed filename (which is target).
end
switch cmd
    case {'seed','pmap'}
        for s=1:length(seedfn) % subtract 1 in case of pmap command
     
            % export mean            
            M=nanmean(fX{s}');
            mmap=dataset.vol.space;
            mmap.dt=[16,0];
            mmap.img(:)=0;
            mmap.img=single(mmap.img);
            mmap.img(omaskidx)=M;

            mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR.nii'];
            ea_write_nii(mmap);
            if usegzip
                gzip(mmap.fname);
                delete(mmap.fname);
            end
            
            % export variance
            M=nanvar(fX{s}');
            mmap=dataset.vol.space;
            mmap.dt=[16,0];
            mmap.img(:)=0;
            mmap.img=single(mmap.img);
            mmap.img(omaskidx)=M;
            
            mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_VarR.nii'];
            ea_write_nii(mmap);
            if usegzip
                gzip(mmap.fname);
                delete(mmap.fname);
            end
            
            if ~ispmap
                % lh surf
                lM=nanmean(lh.fX{s}');
                lmmap=dataset.surf.l.space;
                lmmap.dt=[16,0];
                lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
                lmmap.img=single(lmmap.img);
                lmmap.img(:)=lM(:);
                lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_surf_lh.nii'];
                ea_write_nii(lmmap);
                if usegzip
                    gzip(lmmap.fname);
                    delete(lmmap.fname);
                end
                
                % rh surf
                rM=nanmean(rh.fX{s}');
                rmmap=dataset.surf.r.space;
                rmmap.dt=[16,0];
                rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
                rmmap.img=single(rmmap.img);
                rmmap.img(:)=rM(:);
                rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_surf_rh.nii'];
                ea_write_nii(rmmap);
                if usegzip
                    gzip(rmmap.fname);
                    delete(rmmap.fname);
                end
            end
            
            
            % fisher-transform:
            fX{s}=atanh(fX{s});
            if ~ispmap
                lh.fX{s}=atanh(lh.fX{s});
                rh.fX{s}=atanh(rh.fX{s});
            end
            % export fz-mean
            
            M=nanmean(fX{s}');
            mmap=dataset.vol.space;
            mmap.dt=[16,0];
            mmap.img(:)=0;
            mmap.img=single(mmap.img);
            mmap.img(omaskidx)=M;
            mmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz.nii'];
            spm_write_vol(mmap,mmap.img);
            if usegzip
                gzip(mmap.fname);
                delete(mmap.fname);
            end
            if ~ispmap
                % lh surf
                lM=nanmean(lh.fX{s}');
                lmmap=dataset.surf.l.space;
                lmmap.dt=[16,0];
                lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
                lmmap.img=single(lmmap.img);
                lmmap.img(:)=lM(:);
                lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz_surf_lh.nii'];
                ea_write_nii(lmmap);
                if usegzip
                    gzip(lmmap.fname);
                    delete(lmmap.fname);
                end
                
                % rh surf
                rM=nanmean(rh.fX{s}');
                rmmap=dataset.surf.r.space;
                rmmap.dt=[16,0];
                rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
                rmmap.img=single(rmmap.img);
                rmmap.img(:)=rM(:);
                rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_AvgR_Fz_surf_rh.nii'];
                ea_write_nii(rmmap);
                if usegzip
                    gzip(rmmap.fname);
                    delete(rmmap.fname);
                end
            end
            
            % export T
            
            [~,~,~,tstat]=ttest(fX{s}');
            tmap=dataset.vol.space;
            tmap.img(:)=0;
            tmap.dt=[16,0];
            tmap.img=single(tmap.img);
            
            tmap.img(omaskidx)=tstat.tstat;
            
            tmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T.nii'];
            spm_write_vol(tmap,tmap.img);
            if usegzip
                gzip(tmap.fname);
                delete(tmap.fname);
            end
            
            
            
            
            
            if ~ispmap
                % lh surf
                [~,~,~,ltstat]=ttest(lh.fX{s}');
                lmmap=dataset.surf.l.space;
                lmmap.dt=[16,0];
                lmmap.img=zeros([size(lmmap.img,1),size(lmmap.img,2),size(lmmap.img,3)]);
                lmmap.img=single(lmmap.img);
                lmmap.img(:)=ltstat.tstat(:);
                lmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T_surf_lh.nii'];
                ea_write_nii(lmmap);
                if usegzip
                    gzip(lmmap.fname);
                    delete(lmmap.fname);
                end
                
                % rh surf
                [~,~,~,rtstat]=ttest(rh.fX{s}');
                rmmap=dataset.surf.r.space;
                rmmap.dt=[16,0];
                rmmap.img=zeros([size(rmmap.img,1),size(rmmap.img,2),size(rmmap.img,3)]);
                rmmap.img=single(rmmap.img);
                rmmap.img(:)=rtstat.tstat(:);
                rmmap.fname=[outputfolder,seedfn{s},'_func_',cmd,'_T_surf_rh.nii'];
                ea_write_nii(rmmap);
                if usegzip
                    gzip(rmmap.fname);
                    delete(rmmap.fname);
                end
            end
        end
        
    otherwise
        
        % export mean
        M=nanmean(fX');
        X=zeros(numseed);
        X(logical(triu(ones(numseed),1)))=M;
        X=X+X';
        X(logical(eye(length(X))))=1;
        save([outputfolder,cmd,'_corrMx_AvgR.mat'],'X','-v7.3');
        
        % export variance
        M=nanvar(fX');
        X=zeros(numseed);
        X(logical(triu(ones(numseed),1)))=M;
        X=X+X';
        X(logical(eye(length(X))))=1;
        save([outputfolder,cmd,'_corrMx_VarR.mat'],'X','-v7.3');
        
        % fisher-transform:
        fX=atanh(fX);
        M=nanmean(fX');
        X=zeros(numseed);
        X(logical(triu(ones(numseed),1)))=M;
        X=X+X';
        X(logical(eye(length(X))))=1;
        save([outputfolder,cmd,'_corrMx_AvgR_Fz.mat'],'X','-v7.3');
        
        % export T
        [~,~,~,tstat]=ttest(fX');
        X=zeros(numseed);
        X(logical(triu(ones(numseed),1)))=tstat.tstat;
        X=X+X';
        X(logical(eye(length(X))))=1;
        save([outputfolder,cmd,'_corrMx_T.mat'],'X','-v7.3');
        
end


toc


function s=ea_conformseedtofmri(dataset,s)
td=tempdir;
dataset.vol.space.fname=[td,'tmpspace.nii'];
ea_write_nii(dataset.vol.space);
s.fname=[td,'tmpseed.nii'];
ea_write_nii(s);
ea_conformspaceto([td,'tmpspace.nii'],[td,'tmpseed.nii']);
s=ea_load_nii(s.fname);


function howmanyruns=ea_cs_dethowmanyruns(dataset,mcfi)
if strcmp(dataset.type,'fMRI_matrix')
    howmanyruns=1;
else
    howmanyruns=length(dataset.vol.subIDs{mcfi})-1;
end


function [mat,loaded]=ea_getmat(mat,loaded,idx,chunk,datadir)

rightmat=(idx-1)/chunk;
rightmat=floor(rightmat);
rightmat=rightmat*chunk;
if rightmat==loaded;
    return
end

load([datadir,num2str(rightmat),'.mat']);
loaded=rightmat;

