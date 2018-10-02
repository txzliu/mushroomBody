realonly = 1;   % realonly == 1 only models glomeruli from which H&C recorded (n = 23),1
                % realonly == 0 makes fake data for the remainder of glomeruli (not recommended)

ORN = {}; %olfactory receptor neurons
ORN         = buildORN(ORN, realonly);

% play with ORN responses
% r2 = ORN.rates(ORN.HCList,1:110);
% r2 = reshape(r2(randperm(length(r2(:)))),23,110);
% r2 = bsxfun(@minus,r2,min(r2')');
% r2 = bsxfun(@times,r2,1./mean(r2')') * mean(r2(:));
% ORN.rates(ORN.HCList,1:110) = r2;

% new code to add mixtures of odors ---------------------------------------
% mixinds     = randperm(110,20);                  %select odors to make mixtures of
[public, private] = find_public_and_private_odors(ORN,3);
mixinds = [public;private];
ratios      = 0.2:0.2:0.8;                       %set mixing ratios
mixlist     = ORN.odornames(mixinds);
ORN = addmixtures(ORN, mixlist, ratios);
%% -------------------------------------------------------------------------

nOdor = size(ORN.rates,2);
odorlist = [public' private' 187:nOdor];

LN={};  %lateral neurons (inhbition between glomeruli)
LN          = buildLN(LN);
spRan = 0.1;%0.05:0.05:0.2;
% for use = 1
%     if(use)
%         KCmeanStore_inh = {};
%     else
%         KCmeanStore_none = {};
%     end
    for sp = 1:length(spRan)
        for rep = 1:5
            %set up PN and KC models
            [PN, KC] = initialize_cells(ORN,realonly);
            % uniform wPNKC
%             populated = ORN.HCList * PN.PN_per_glom;
%             populated = sort([populated-4 populated-3 populated-2 populated-1 populated]);
%             for i = 1:2000
%                 KC.wPNKC(populated,i) = KC.wPNKC(populated(randperm(length(populated))),i);
%             end            

            %first, measure the amount of spontaneous input to KCs
            [~,PN_t,~]  = getPNdynamics(ORN,PN,LN,1);
            PN_t = kron(PN_t,ones(PN.PN_per_glom,1));
            PN_spont    = mean(PN_t(:,(PN.tOn-PN.tmin)/PN.dt/2:(PN.tOn-PN.tmin)/PN.dt),2);
            KC.spont    = KC.wPNKC'*PN_spont;
            disp('Model initialized');

            %next, tune inhibition to set KC representation sparsity
            disp('Fitting APL inhibition (this step is slow)...');
            clear PN_sample PN_RW_sample;
            odorset = 2:3:110;     % code takes a while to run so I don't use all odors
%             odorset = randperm(110,60);
            sp_target = spRan(sp); % target sparsity of model KC population
            for i = odorset
                [~,PN_sample{i},~,PN_RW_sample{i}] = getPNdynamics(ORN,PN,LN,i);
            end
%             PN_t = PN_RW;
%             if(use)
                KC = setKCthreshold(PN,PN_sample, odorset, KC,sp_target*2);
                KC = fitSparseness(PN,PN_sample,odorset,KC,sp_target);
%             else
%                 KC.wInhKC = zeros(KC.ncells,1);
%                 KC.wKCInh = zeros(1,KC.ncells);
%                 KC = scalePNKCwts(PN, PN_sample, odorset, KC);
%                 KC = setKCthreshold(PN,PN_sample,odorset,KC,sp_target);
%             end
            disp('APL inhibition fit');


            %now, simulate responses to odors specified by odorlist
            odorspercell = zeros(KC.ncells,1);
            fr_active    = zeros(nOdor,1);
            KCmean_st    = zeros(KC.ncells,nOdor);

            for odorid = odorlist
                [~,PN_t,~,PN_RW]  = getPNdynamics(ORN,PN,LN,odorid);
%                 PN_t = PN_RW;
                PN_t = kron(PN_t,ones(PN.PN_per_glom,1));

                [KC_rasters,KC_t,~] = getKCratedynamics(PN_t,KC);

                KCmean = sum(KC_rasters,2);
                fr_active(odorid) = length(nonzeros(KCmean>0))/KC.ncells;

                odorspercell(KCmean>0) = odorspercell(KCmean>0) + 1;

                KCmean_st(:,odorid) = KCmean;
                if(mod(odorid,500)==0)
                    disp([num2str(odorid) '. ' ORN.odornames{odorid} ': ' num2str(fr_active(odorid)*100) '%']);
                end
            end
            KCmeanStore_inh{sp,rep} = KCmean_st;
%             if(use)
%                 KCmeanStore_inh{sp,rep} = KCmean_st;
%             else
%                 KCmeanStore_none{sp,rep} = KCmean_st;
%             end

            %save output for use with other functions (most of these I haven't included in this code)
        %     save(['KCsim_' num2str(rep) '.mat'],'PN','KC','fr_active','KCmean_st','ORN');
        end
    end
% end
% 
% s=svd(KCmean_st);
% dimensionality = sum(s)^2/sum(s.^2)

%% effects on similarity, with inh

toplot=0;
figure(1);clf;hold on;
i=2;
silentBars = [];
silentCellBars = [];

for use = {KCmeanStore_inh}
    vals=[]; coactive=[];
    for rep = 1:3
        M   = use{1}{i,rep}(:,1:110);
        Mand    = double(M~=0)'*double(M~=0);
        Mor     = sum(M~=0)'+sum(M~=0) - Mand;
        overlap = Mand./Mor + tril(nan(size(Mand)));
        overlap = overlap(~isnan(overlap))';
        vals        = [vals pdist(M','hamming')];
        coactive    = [coactive overlap];
    end
    silentBars(end+1) = sum(sum(M~=0)==0);
    silentCellBars(end+1) = sum(sum(M'~=0)==0);
    if(toplot)
        h=plotCDFFit(vals);
    else
        h=plotCDFFit(coactive);
    end
end
set(h,'linewidth',2,'color','r');

% normalize ORN responses
M = KCmeanStore_normORNs{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
if(toplot), plotCDFFit(vals);
else, plotCDFFit(overlap); end

% shuffle ORN responses
M = KCmeanStore_randORNs{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
if(toplot), plotCDFFit(vals);
else, plotCDFFit(overlap); end

% static PN model
M = KCmeanStore_RW_PNs{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
if(toplot), plotCDFFit(vals);
else, plotCDFFit(overlap); end

% uniform MB innervation by PNs
M = KCmeanStore_uniform_wPNKC{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
if(toplot), plotCDFFit(vals);
else, plotCDFFit(overlap); end

% finer-tuned KC thresholds
M = KCmeanStore_fineThr{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
if(toplot), h=plotCDFFit(vals);
else, h=plotCDFFit(overlap); end
set(h,'linewidth',2);

% 10% of cells for each odor
for i=1:110
    vals = rand(1,2000);
    s = sort(vals);
    M(:,i) = vals>s(round(2000*.9));
end
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = sort(pdist(M','hamming'));
if(toplot), h=plotCDFFit(vals);
else, h=plotCDFFit(overlap); end
set(h,'linewidth',2,'color','k');

legstr = {'simple thr','norm ORNs','rand ORNs','static PN model','uniform wPNKC',...
        'fine-tuned KC thresholds',...
        'rand KCs'};
legend(legstr{:},'location','best');
xlabel('fraction of overlap neurons');
% xlabel('normalized hamming distance');
ylabel('fraction of odor pairs');
xlim([0 .5]);
set(gca,'xscale','log')

%%
figure(2);clf;
bar(silentBars);
set(gca,'xtick',1:7,'xticklabels',legstr,'xticklabelrotation',30);
box off;

figure(3);clf;
bar(silentCellBars);
set(gca,'xtick',1:7,'xticklabels',legstr,'xticklabelrotation',30);
box off;

%% effects on similarity, no inh

figure(1);clf;hold on;
i=2;
silentBars = [];
silentCellBars = [];

for use = {KCmeanStore_none}
    vals=[]; coactive=[];
    for rep = 1%:3
        M   = use{1}{i,rep}(:,1:110);
        Mand    = double(M~=0)'*double(M~=0);
        Mor     = sum(M~=0)'+sum(M~=0) - Mand;
        overlap = Mand./Mor + tril(nan(size(Mand)));
        overlap = overlap(~isnan(overlap))';
        vals        = [vals pdist(M','hamming')];
        coactive    = [coactive overlap];
    end
    silentBars(end+1) = sum(sum(M~=0)==0);
    silentCellBars(end+1) = sum(sum(M'~=0)==0);
    h=plotCDFFit(vals);
%     h=plotCDFFit(coactive);
end
set(h,'linewidth',2,'color','r');

% normalize ORN responses
M = KCmeanStore_normORNs_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
plotCDFFit(vals);
% plotCDFFit(overlap);

% shuffle ORN responses
M = KCmeanStore_randORNs_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
plotCDFFit(vals);
% plotCDFFit(overlap);

% static PN model
M = KCmeanStore_RW_PNs_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
plotCDFFit(vals);
% plotCDFFit(overlap);

% uniform MB innervation by PNs
M = KCmeanStore_uniform_wPNKC_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
plotCDFFit(vals);
% plotCDFFit(overlap);

% finer-tuned KC thresholds, no inh
M = KCmeanStore_fineThr_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
plotCDFFit(vals);
% h=plotCDFFit(overlap);
set(h,'linewidth',2);

% scale PN weights "presynaptically"
M = KCmeanStore_scalePNwts_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = pdist(M','hamming');
h=plotCDFFit(vals);
% plotCDFFit(overlap);


% 10% of cells for each odor
for i=1:110
    vals = rand(1,2000);
    s = sort(vals);
    M(:,i) = vals>s(round(2000*.9));
end
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
silentBars(end+1) = sum(sum(M~=0)==0);
silentCellBars(end+1) = sum(sum(M'~=0)==0);
vals = sort(pdist(M','hamming'));
h = plotCDFFit(vals);
% h=plotCDFFit(overlap);
set(h,'linewidth',2,'color','k');

legstr = {'simple thr','norm ORNs','rand ORNs','static PN model','uniform wPNKC',...
        'fine-tuned KC thresholds','presynaptic plasticity',...
        'rand KCs'};
legend(legstr{:},'location','best');
xlabel('normalized hamming distance');
% xlabel('fraction of coactive neurons');
ylabel('fraction of odor pairs');
xlim([0 .5]);
% set(gca,'xscale','log')

figure(2);clf;
bar(silentBars);
set(gca,'xtick',1:7,'xticklabels',legstr,'xticklabelrotation',30);
box off;

figure(3);clf;
bar(silentCellBars);
set(gca,'xtick',1:7,'xticklabels',legstr,'xticklabelrotation',30);
box off;

%% effects on similarity- looking at tuning KC thresholds with diff numbers of training examples

figure(1);clf;hold on;
i=2;
doplot=0;

for use = {KCmeanStore_none}
    vals = [];coactive=[];
    for rep = 1:3
        M = use{1}{i,rep}(:,1:110);
        Mand    = double(M~=0)'*double(M~=0);
        Mor     = sum(M~=0)'+sum(M~=0) - Mand;
        overlap = Mand./Mor + tril(nan(size(Mand)));
        overlap = overlap(~isnan(overlap))';
        vals = [vals pdist(M','hamming')];
        coactive = [coactive overlap];
    end
    if(doplot), h=plotCDFFit(vals);
    else, h=plotCDFFit(coactive); end
    set(h,'linewidth',2,'color','r');
end

% finer-tuned KC thresholds, no inh
M = KCmeanStore_fineThr_noinh{1,1};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
vals = pdist(M','hamming');
if(doplot), h=plotCDFFit(vals);
else, h=plotCDFFit(overlap); end

% finer-tuned KC thresholds, no inh
for rep=1:10
M = KCmeanStore_fineThr_withinh_sample60{1,rep};
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
vals = pdist(M','hamming');
if(doplot), h=plotCDFFit(vals);
else, h=plotCDFFit(overlap); end
drawnow;
end

% 10% of cells for each odor
for i=1:110
    vals = rand(1,2000);
    s = sort(vals);
    M(:,i) = vals>s(round(2000*.9));
end
Mand    = double(M~=0)'*double(M~=0);
Mor     = sum(M~=0)'+sum(M~=0) - Mand;
overlap = Mand./Mor + tril(nan(size(Mand)));
overlap = overlap(~isnan(overlap))';
vals = pdist(M','hamming');
if(doplot), h=plotCDFFit(vals);
else, h=plotCDFFit(overlap); end
set(h,'linewidth',2,'color','k');

% legend('no inh','with inh',...
%         'fine-tuned KC thresholds, no inh','same, fewer thr examples',...
%         'rand KCs','location','best');
xlabel('fraction of coactive neurons');
ylabel('fraction of odor pairs');
xlim([0 .5]);
set(gca,'xscale','log')


%% number of missed odors
figure(2);clf;hold on;
for rep=1:10
    M = KCmeanStore_fineThr_noinh_sample5{1,rep};
    silent(rep) = sum(sum(M~=0)==0);
end
bar(1,mean(silent));
errorbar(1,mean(silent),std(silent),'k');

for rep=1:10
    M = KCmeanStore_fineThr_noinh_sample20{1,rep};
    silent(rep) = sum(sum(M~=0)==0);
end
bar(2,mean(silent));
errorbar(2,mean(silent),std(silent),'k');
ylabel('number of silent odors');

for rep=1:10
    M = KCmeanStore_fineThr_noinh_sample60{1,rep};
    silent(rep) = sum(sum(M~=0)==0);
end
bar(3,mean(silent));
errorbar(3,mean(silent),std(silent),'k');
ylabel('number of silent odors');
set(gca,'xtick',1:3,'xticklabel',{'5','20','60'});

%%
[public, private] = find_public_and_private_odors(ORN);
M = KCmeanStore_fineThr_withinh{1,1};
figure(2);clf;
bar([1:10 15:24],sum(M(:,[public; private])~=0))
%%
C1 = zeros(110);
C2 = zeros(110);
for rep = 1:5
    M1 = KCmeanStore_fineThr_withinh{1,2}(:,1:110);
    M2 = KCmeanStore_inh{1,2}(:,1:110);
    C1 = C1 + corr(M1)/5;
    C2 = C2 + corr(M2)/5;
end

figure(10);clf;
plot(corr(M1),corr(M2),'.')
xlabel('fine thr');ylabel('easy thr')
hold on;
plot([0 1],[0 1],'r')

figure(11);
subplot(2,3,1)
image(corr(ORN.rates(:,1:110))*32+32);colorbar;
title('ORNs');
subplot(2,3,2);
image(corr(PN.rates(:,1:110))*32+32);colorbar
title('PNs');
subplot(2,3,4);
image(C1*32+32);colorbar
title('KC fancy');
subplot(2,3,5);
image(C2*32+32);colorbar
title('KC simple');
subplot(2,3,6)
imagesc((C1-C2)./(abs(C1) + abs(C2)));colorbar
title('diff fancy vs simple');

%%
figure(2);clf;colors=[1 0 0;0 0 1];count=0;
for use = {KCmeanStore_inh KCmeanStore_fineThr_withinh}
    count=count+1;
    bins1 = 0:100:1200;
    nOdor = 25;
    bins2 = 0:.1:1;
    n1 = zeros(size(bins1));
    n2 = zeros(size(bins2));
    for sRep = 1:50
        nCells = [];nActive=[];
        for rep = 1:5
            sampleOdors = randperm(30,nOdor)+40;
            sampleCells = randperm(2000,10);
            M = use{:}{1,rep};
            nCells = [nCells mean(M(sampleCells,sampleOdors)~=0)];
            nActive = [nActive mean(M(sampleCells,sampleOdors)'~=0)];
        end
        n1 = [n1; hist(nCells,bins1)];
        n2 = [n2; hist(nActive,bins2)];
    end
%     subplot(2,1,1);hold on;
%     area(bins1,n1/sum(n1));
%     title('fraction of KCs active, across odors');
%     subplot(2,1,2);
    hold on;
    h(count) = bar(bins2*10-.33+count/3,mean(n2)/sum(mean(n2)),.33);
    errorbar(bins2*10-.33+count/3,mean(n2)/sum(mean(n2)),std(n2)/sum(mean(n2)),'k.');
    title(['fraction of odors per cell, n = ' num2str(nOdor) ' odors'])
    xlabel('number of odors a cell responds to');
end
legend(h,'simple','fancy');

%%
colors = hsv(10);
figure(1);clf;
for i = 1:10
    inds = find(ORN.odorclass==i);
    M1 = KCmeanStore_inh{1,1}(:,inds);
    M1b = KCmeanStore_fineThr_withinh{1,1}(:,inds);
    M2 = ORN.rates(:,inds);

    subplot(1,3,1);hold on;
    plot(corr(M2),corr(double(M1~=0)),'.','color',colors(i,:));
    xlim([-.5 1]);
    ylim([-.5 1]);
    plot([-.5 1],[-.5 1],'k');
    plot([-.5 1],[0 0],'k');
    title('original model');
    subplot(1,3,2);hold on;
    plot(corr(M2),corr(double(M1b~=0)),'k.','color',colors(i,:));
    xlim([-.5 1]);
    ylim([-.5 1]);
    plot([-.5 1],[-.5 1],'k');
    plot([-.5 1],[0 0],'k');
    title('homeostatic model');
    xlabel('ORN corr');
    ylabel('KC corr');
    subplot(1,3,3);hold on;
    plot(corr(double(M1~=0)),corr(double(M1b~=0)),'.','color',colors(i,:));
    xlabel('original');
    ylabel('homeostatic');
    xlim([-.5 1]);
    ylim([-.5 1]);
    plot([-.5 1],[-.5 1],'k');
end
%% looking at mixtures in both models!
mixStarts = 187:4:nOdor;
mixPairs = [public(1) public(2); ...
            public(1) public(3); ...
            public(2) public(3); ...
            ...
            private(1) public(1); ...
            private(1) public(2); ...
            private(1) public(3); ...
            ...
            private(2) public(1); ...
            private(2) public(2); ...
            private(2) public(3); ...
            private(2) private(1); ...
            private(2) private(3); ...
            ...
            private(3) public(1); ...
            private(3) public(2); ...
            private(3) public(3); ...
            private(3) private(1)];
pubpub = [1 2 3];
privpriv = [10 11 15];
pubpriv = setdiff(1:15,[pubpub privpriv]);
%%
            
use = KCmeanStore_inh{1,1};
clear M generalization;
for mix = 1%:length(mixStarts)
    C = zeros(5);
    for i=1:5
        if(i==1)
            M(:,i) = use(:,mixPairs(mix,1))~=0;
        elseif(i==5)
            M(:,i) = use(:,mixPairs(mix,2))~=0;
        else
            M(:,i) = use(:,mixStarts(mix)+i-1)~=0;
        end
    end

    C = corr(M);
    Cstore{mix}=C;
    for d = -4:4
       generalization(mix,d+5) = nanmean(diag(C,d));
    end
    
    clear M;
    for i=1:5
        if(i==1)
            M(:,i) = use(:,mixPairs(mix,1));
        elseif(i==5)
            M(:,i) = use(:,mixPairs(mix,2));
        else
            M(:,i) = use(:,mixStarts(mix)+i-1);
        end
    end
    explained(mix) = corr((M(:,1)+M(:,5))/2,M(:,3));
end

%%
figure(1);clf;hold on;
drawvar(-4:4,generalization(pubpub,:),'r',1);
drawvar(-4:4,generalization(privpriv,:),'b',1);
drawvar(-4:4,generalization(pubpriv,:),'g',1);

figure(2);clf;
subplot(1,3,1);
M = zeros(size(C));
for i = pubpub
    M = M + Cstore{i}/length(pubpub);
end
image(M*32+32)
subplot(1,3,2);
M = zeros(size(C));
for i = privpriv
    M = M + Cstore{i}/length(privpriv);
end
image(M*32+32)
subplot(1,3,3);
M = zeros(size(C));
for i = pubpriv
    M = M + Cstore{i}/length(pubpriv);
end
image(M*32+32);








