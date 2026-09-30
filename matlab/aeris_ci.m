function S = aeris_ci(file, nboot, minN)
% AERIS_CI  Bootstrap confidence intervals on met% by environment.
%
%   aeris_ci                              % matlab_out/sweep_modeled2.csv
%   aeris_ci('matlab_out/sweep.csv', 2000, 200)
%
% Puts 95% confidence intervals on the per-environment warning-satisfaction
% figures by resampling RAIDS with replacement. This is what settles the
% rain_extreme vs worst "inversion" - with only ~300 raids each, their CIs
% overlap heavily, so the ordering is noise, not signal. Environments with
% fewer than minN raids are flagged as under-sampled rather than reported as
% if precise.
%
% Pure re-analysis of the sweep CSV; no new runs.

if nargin < 1 || isempty(file)
    file = fullfile(fileparts(mfilename('fullpath')),'matlab_out','sweep_modeled2.csv');
end
if nargin < 2 || isempty(nboot), nboot = 2000; end
if nargin < 3 || isempty(minN),  minN  = 200;  end

T = readtable(file);
[~, ia] = unique(T.run, 'stable');  R = T(ia,:);

order = {'best','clear','grass','humid','haze','fog','trees', ...
         'rain_light','rain_mod','rain_heavy','rain_extreme','worst'};
envs = order(ismember(order, unique(R.env)));

fprintf('\n--- met%% with 95%% bootstrap CI (%d resamples) ---\n', nboot);
fprintf('%-13s %6s %8s %18s\n','env','raids','met %','95%% CI');
fprintf('%s\n', repmat('-',1,50));

met = zeros(1,numel(envs)); lo = met; hi = met; nR = met;
for e = 1:numel(envs)
    m = strcmp(R.env, envs{e});
    w = R.raid_warn_s(m); n = numel(w);
    nR(e)  = n;
    met(e) = 100*mean(w >= R.Treq_s(find(m,1)));
    % bootstrap
    bs = zeros(1,nboot);
    Treq = R.Treq_s(find(m,1));
    for b = 1:nboot
        idx = randi(n, n, 1);
        bs(b) = 100*mean(w(idx) >= Treq);
    end
    lo(e) = prctile(bs, 2.5);  hi(e) = prctile(bs, 97.5);
    flag = ''; if n < minN, flag = '  << under-sampled'; end
    fprintf('%-13s %6d %8.1f   [%5.1f, %5.1f]%s\n', envs{e}, n, met(e), lo(e), hi(e), flag);
end

% the inversion test
ie = find(strcmp(envs,'rain_extreme')); iw = find(strcmp(envs,'worst'));
if ~isempty(ie) && ~isempty(iw)
    fprintf('\nrain_extreme %.1f%% [%.1f,%.1f] vs worst %.1f%% [%.1f,%.1f]\n', ...
        met(ie),lo(ie),hi(ie), met(iw),lo(iw),hi(iw));
    if ~(hi(ie) < lo(iw) || hi(iw) < lo(ie))
        fprintf('=> CIs OVERLAP: the rain_extreme/worst ordering is NOISE, not a\n');
        fprintf('   real inversion. Do not cite either point precisely.\n');
    else
        fprintf('=> CIs separate: the ordering is real.\n');
    end
end

figure('Color','w','Position',[100 100 860 460]);
errorbar(1:numel(envs), met, met-lo, hi-met, 'o','LineWidth',1.4, ...
         'MarkerFaceColor',[.3 .45 .7],'CapSize',6);
set(gca,'XTick',1:numel(envs),'XTickLabel',envs,'XTickLabelRotation',40, ...
        'TickLabelInterpreter','none'); grid on;
ylabel('raids meeting requirement (%)'); ylim([0 100]);
title(sprintf('met%% by environment, 95%% CI (%d resamples)',nboot),'FontWeight','normal');

S = struct('envs',{envs},'met',met,'lo',lo,'hi',hi,'nRaids',nR,'minN',minN);
if nargout==0, clear S; end
end
