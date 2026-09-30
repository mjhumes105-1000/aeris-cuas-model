function S = aeris_analyze_sweep(file)
% AERIS_ANALYZE_SWEEP  Turn a sweep CSV into the study findings.
%
%   aeris_analyze_sweep
%   aeris_analyze_sweep('matlab_out/aeris_sweep.csv')
%   S = aeris_analyze_sweep;
%
% Produces the two tables and four figures the argument actually needs:
%
%   TABLE 1  performance by environment, best case to worst
%   TABLE 2  performance by drone class
%   FIG 1    confirmation rate: drone class x environment (heat map)
%   FIG 2    warning time vs RCS, coloured by environment
%   FIG 3    warning time vs node placement (Dforward) - the placement question
%   FIG 4    warning-time distributions, best vs baseline vs worst
%
% The headline number is the fraction of RAIDS meeting Treq, reported per
% environment. If the baseline fails in ordinary conditions, that is the
% headline result; if it only fails in a downpour, that is a different and much
% weaker claim. This separates them.

if nargin < 1 || isempty(file)
    file = fullfile(fileparts(mfilename('fullpath')),'matlab_out','aeris_sweep.csv');
end
if ~isfile(file)
    error('aeris:noSweep','No sweep at %s\nRun aeris_sweep(15000) first.', file);
end

T = readtable(file);
if height(T)==0, error('aeris:empty','%s is empty.', file); end
Treq = median(T.Treq_s);

% raid-level rows (one per run)
[~, ia] = unique(T.run, 'stable');
R = T(ia,:);

fprintf('\n=== AERIS sweep: %s ===\n', file);
fprintf('%d drones across %d engagements\n', height(T), height(R));
fprintf('requirement: %.0f s\n', Treq);

% ---- TABLE 1: by environment -------------------------------------------
order = {'best','clear','grass','humid','haze','fog','trees', ...
         'rain_light','rain_mod','rain_heavy','rain_extreme','worst'};
envs  = present(order, T.env);
fprintf('\n--- by environment (best -> worst) ---\n');
fprintf('%-13s %6s %7s %8s %9s %9s\n','env','raids','conf%','met%','med warn','med relRng');
envStat = struct([]);
for i = 1:numel(envs)
    m  = strcmp(T.env, envs{i});
    mr = strcmp(R.env, envs{i});
    w  = R.raid_warn_s(mr); w = w(w > -1);
    fprintf('%-13s %6d %7.1f %8.1f %9s %9.0f\n', envs{i}, sum(mr), ...
        100*mean(T.confirmed(m)==1), 100*mean(R.req_met(mr)==1), ...
        med_or_dash(w), median(T.reliable_range_m(m)));
    envStat(i).name = envs{i}; %#ok<AGROW>
    envStat(i).conf = mean(T.confirmed(m)==1);
    envStat(i).met  = mean(R.req_met(mr)==1);
end

% ---- TABLE 2: by drone class -------------------------------------------
corder = {'fixedwing','heavy_quad','small_quad','fpv_attack','micro'};
cls = present(corder, T.class);
fprintf('\n--- by drone class (easiest -> hardest) ---\n');
fprintf('%-12s %6s %9s %7s %8s %9s\n','class','n','med RCS','conf%','met%','med warn');
for i = 1:numel(cls)
    m  = strcmp(T.class, cls{i});
    mr = strcmp(R.class, cls{i});
    w  = R.raid_warn_s(mr); w = w(w > -1);
    fprintf('%-12s %6d %9.4g %7.1f %8.1f %9s\n', cls{i}, sum(m), ...
        median(T.rcs_m2(m)), 100*mean(T.confirmed(m)==1), ...
        100*mean(R.req_met(mr)==1), med_or_dash(w));
end

% ---- the headline -------------------------------------------------------
fprintf('\n--- headline ---\n');
fprintf('overall: %.1f%% of raids delivered %.0f s warning\n', ...
        100*mean(R.req_met==1), Treq);
b = strcmp(R.env,'best'); w = strcmp(R.env,'worst');
if any(b) && any(w)
    fprintf('best case  %.1f%%   worst case %.1f%%\n', ...
            100*mean(R.req_met(b)==1), 100*mean(R.req_met(w)==1));
end
g = strcmp(R.env,'grass');
if any(g)
    fprintf('baseline (grass, dry): %.1f%%  <- the number that matters most\n', ...
            100*mean(R.req_met(g)==1));
end

% ========================================================================
% FIG 1 - class x environment heat map
figure('Color','w','Position',[60 80 1180 760]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

nexttile;
Mx = nan(numel(cls), numel(envs));
for a = 1:numel(cls)
    for b2 = 1:numel(envs)
        m = strcmp(T.class,cls{a}) & strcmp(T.env,envs{b2});
        if any(m), Mx(a,b2) = 100*mean(T.confirmed(m)==1); end
    end
end
imagesc(Mx, 'AlphaData', ~isnan(Mx)); clim_safe([0 100]);
colormap(gca, flipud(hot_safe())); cb = colorbar; cb.Label.String = 'confirmed (%)';
set(gca,'XTick',1:numel(envs),'XTickLabel',envs,'XTickLabelRotation',40, ...
        'YTick',1:numel(cls),'YTickLabel',cls,'TickLabelInterpreter','none');
title('confirmation rate: class x environment','FontWeight','normal');
for a=1:numel(cls), for b2=1:numel(envs)
    if ~isnan(Mx(a,b2))
        text(b2,a,sprintf('%.0f',Mx(a,b2)),'HorizontalAlignment','center', ...
             'FontSize',7,'Color',[.15 .15 .15]);
    end
end, end

% FIG 2 - warning time vs RCS by environment
nexttile; hold on; grid on;
cmap = lines(numel(envs));
for i = 1:numel(envs)
    m = strcmp(T.env,envs{i}) & T.confirmed==1;
    if ~any(m), continue; end
    scatter(T.rcs_m2(m), T.warn_time_s(m), 8, cmap(i,:), 'filled', ...
            'MarkerFaceAlpha',.30, 'DisplayName',envs{i});
end
yline(Treq,'--','Color',[.8 .1 .1],'LineWidth',1.5,'DisplayName','requirement');
set(gca,'XScale','log'); xlabel('RCS (m^2)'); ylabel('warning time (s)');
title('warning time vs target size','FontWeight','normal');
legend('Location','eastoutside','Box','off','Interpreter','none','FontSize',7);

% FIG 3 - warning vs placement
nexttile; hold on; grid on;
edges = linspace(min(R.Dforward_m), max(R.Dforward_m), 13);
[rate, ctr, cnt] = binned(R.Dforward_m, R.req_met==1, edges);
bar(ctr/1000, 100*rate, 'FaceColor',[.35 .5 .7], 'EdgeColor','none');
for i=1:numel(ctr)
    if cnt(i)>0, text(ctr(i)/1000, 100*rate(i)+2, sprintf('%d',cnt(i)), ...
        'HorizontalAlignment','center','FontSize',6,'Color',[.45 .45 .45]); end
end
xlabel('node placement D_{forward} (km)'); ylabel('raids meeting requirement (%)');
ylim([0 105]); title('placement vs requirement satisfaction','FontWeight','normal');

% FIG 4 - distributions, best / baseline / worst
nexttile; hold on; grid on;
show = present({'best','grass','worst'}, R.env);
cols = [.30 .60 .35; .35 .45 .70; .75 .28 .25];
for i = 1:numel(show)
    m = strcmp(R.env, show{i}); w2 = R.raid_warn_s(m); w2 = w2(w2>-1);
    if isempty(w2), continue; end
    histogram(w2, 22, 'Normalization','probability', 'FaceAlpha',.55, ...
        'FaceColor',cols(min(i,3),:), 'EdgeColor','none', 'DisplayName',show{i});
end
yl = ylim; plot([Treq Treq], yl, '--','Color',[.8 .1 .1],'LineWidth',1.5, ...
     'DisplayName','requirement');
xlabel('raid warning time (s)'); ylabel('fraction of raids');
title('warning delivered: best vs baseline vs worst','FontWeight','normal');
legend('Location','northeast','Box','off','Interpreter','none');

sgtitle(sprintf('AERIS-Nexus sweep: %d engagements, %d drones', ...
        height(R), height(T)), 'FontSize', 12);

S = struct('table',T,'raids',R,'Treq',Treq, ...
           'overallMet',mean(R.req_met==1),'byEnv',envStat);
end

% ------------------------------------------------------------------------
function out = present(order, col)
out = {};
for i = 1:numel(order)
    if any(strcmp(col, order{i})), out{end+1} = order{i}; end %#ok<AGROW>
end
extra = setdiff(unique(col), out);
out = [out, reshape(extra,1,[])];
end

function s = med_or_dash(w)
if isempty(w), s = '--'; else, s = sprintf('%.0f', median(w)); end
end

function [rate, ctr, cnt] = binned(x, hit, edges)
nb = numel(edges)-1; rate = zeros(1,nb); ctr = zeros(1,nb); cnt = zeros(1,nb);
for i = 1:nb
    m = x >= edges(i) & x < edges(i+1);
    ctr(i) = (edges(i)+edges(i+1))/2; cnt(i) = sum(m);
    if cnt(i) > 0, rate(i) = mean(hit(m)); end
end
end

function clim_safe(l), try, clim(l); catch, caxis(l); end, end %#ok<CAXIS>
function m = hot_safe(), try, m = hot(256); catch, m = gray(256); end, end
