function S = aeris_analyze_runs(file)
% AERIS_ANALYZE_RUNS  Summarise and plot the accumulated engagement log.
%
%   aeris_analyze_runs                       % matlab_out/aeris_runs.csv
%   aeris_analyze_runs('path/to/runs.csv')
%   S = aeris_analyze_runs;                  % also return the table + stats
%
% Every run of aeris_scope_sim3d with p.logData = true appends one row per
% drone. Once you have a few dozen runs this turns the pile into the curves
% the study actually needs:
%
%   (1) confirmation rate vs RCS      - how small a drone the node can hold
%   (2) warning time vs RCS           - against the Treq line
%   (3) warning time distribution     - what fraction of raids meet Treq
%   (4) confirmation rate vs altitude - exposes the elevation coverage hole
%
% The headline number it prints is the fraction of RAIDS (not drones) that
% delivered the required warning, which is the study's pass/fail statistic.

if nargin < 1 || isempty(file)
    here = fileparts(mfilename('fullpath'));
    file = fullfile(here, 'matlab_out', 'aeris_runs.csv');
end
if ~isfile(file)
    error('aeris:noLog', ['No log at %s\n' ...
        'Run aeris_scope_sim3d(aeris_params(''random'')) a few times first.'], file);
end

Tbl = readtable(file);
n   = height(Tbl);
if n == 0, error('aeris:emptyLog','%s is empty.', file); end

% ---- raid-level view (one row per run) ----------------------------------
[runs, ia] = unique(Tbl.run_id, 'stable');
raidWarn   = Tbl.raid_warn_s(ia);
raidMet    = Tbl.req_met(ia) == 1;
Treq       = median(Tbl.Treq_s);

fprintf('\n=== AERIS engagement log: %s ===\n', file);
fprintf('%d drones across %d raids\n', n, numel(runs));
fprintf('RCS      %.4g – %.4g m^2\n', min(Tbl.rcs_m2), max(Tbl.rcs_m2));
fprintf('altitude %.0f – %.0f m\n',   min(Tbl.alt_m),  max(Tbl.alt_m));
fprintf('speed    %.0f – %.0f m/s\n', min(Tbl.speed_mps), max(Tbl.speed_mps));
fprintf('\nper-drone confirmation rate : %.1f%%  (%d of %d)\n', ...
    100*mean(Tbl.confirmed==1), sum(Tbl.confirmed==1), n);
fprintf('raids delivering %.0f s warning: %.1f%%  (%d of %d)\n', ...
    Treq, 100*mean(raidMet), sum(raidMet), numel(runs));
ok = raidWarn > -1;
if any(ok)
    fprintf('warning time, raids with a track: median %.0f s, IQR %.0f–%.0f s\n', ...
        median(raidWarn(ok)), prctile(raidWarn(ok),25), prctile(raidWarn(ok),75));
end

% ---- formation breakdown -------------------------------------------------
if iscellstr(Tbl.formation) || isstring(Tbl.formation) %#ok<ISCLSTR>
    forms = unique(Tbl.formation(ia));
    if numel(forms) > 1
        fprintf('\nby formation:\n');
        for i = 1:numel(forms)
            m = strcmp(Tbl.formation(ia), forms{i});
            fprintf('  %-9s %3d raids, %.0f%% met\n', ...
                forms{i}, sum(m), 100*mean(raidMet(m)));
        end
    end
end

% ========================================================================
figure('Color','w','Position',[100 100 1150 780]);
tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

% (1) confirmation rate vs RCS -------------------------------------------
nexttile; hold on; grid on;
edges = logspace(log10(max(min(Tbl.rcs_m2),1e-4)), log10(max(Tbl.rcs_m2)), 9);
[rate, ctr, cnt] = binned_rate(Tbl.rcs_m2, Tbl.confirmed==1, edges);
bar(ctr, 100*rate, 'FaceColor',[.29 .45 .69], 'EdgeColor','none');
set(gca,'XScale','log');
for i=1:numel(ctr)
    if cnt(i)>0, text(ctr(i), 100*rate(i)+3, sprintf('n=%d',cnt(i)), ...
        'HorizontalAlignment','center','FontSize',7,'Color',[.4 .4 .4]); end
end
xlabel('RCS (m^2)'); ylabel('confirmed (%)'); ylim([0 108]);
title('confirmation rate vs target size','FontWeight','normal');

% (2) warning time vs RCS -------------------------------------------------
nexttile; hold on; grid on;
c1 = Tbl.confirmed==1;
scatter(Tbl.rcs_m2(c1),  Tbl.warn_time_s(c1),  22, [.29 .45 .69], 'filled', ...
        'MarkerFaceAlpha',.55, 'DisplayName','confirmed');
if any(~c1)
    scatter(Tbl.rcs_m2(~c1), zeros(sum(~c1),1), 22, [.8 .3 .25], 'x', ...
            'DisplayName','never confirmed');
end
yline(Treq,'--','Color',[.8 .1 .1],'LineWidth',1.5,'DisplayName','requirement');
set(gca,'XScale','log');
xlabel('RCS (m^2)'); ylabel('warning time (s)');
title('warning time vs target size','FontWeight','normal');
legend('Location','southeast','Box','off');

% (3) warning time distribution -------------------------------------------
nexttile; hold on; grid on;
w = raidWarn(ok);
if ~isempty(w)
    histogram(w, max(8,round(sqrt(numel(w)))), 'FaceColor',[.45 .55 .72], ...
              'EdgeColor','w');
end
yl = ylim;
plot([Treq Treq], yl, '--', 'Color',[.8 .1 .1], 'LineWidth',1.5);
text(Treq, yl(2)*0.95, sprintf(' T_{req}=%.0fs', Treq), 'Color',[.8 .1 .1], 'FontSize',9);
xlabel('raid warning time (s)'); ylabel('raids');
title(sprintf('warning delivered  (%.0f%% meet requirement)', 100*mean(raidMet)), ...
      'FontWeight','normal');

% (4) confirmation rate vs altitude ---------------------------------------
nexttile; hold on; grid on;
aedges = linspace(min(Tbl.alt_m), max(Tbl.alt_m)+1, 8);
[arate, actr, acnt] = binned_rate(Tbl.alt_m, Tbl.confirmed==1, aedges);
bar(actr, 100*arate, 'FaceColor',[.42 .62 .48], 'EdgeColor','none');
for i=1:numel(actr)
    if acnt(i)>0, text(actr(i), 100*arate(i)+3, sprintf('n=%d',acnt(i)), ...
        'HorizontalAlignment','center','FontSize',7,'Color',[.4 .4 .4]); end
end
xlabel('altitude (m)'); ylabel('confirmed (%)'); ylim([0 108]);
title('confirmation rate vs altitude','FontWeight','normal');

sgtitle(sprintf('AERIS-Nexus: %d drones, %d raids', n, numel(runs)), 'FontSize', 12);

S = struct('table',Tbl,'nDrones',n,'nRaids',numel(runs), ...
           'confirmRate',mean(Tbl.confirmed==1), 'raidMetRate',mean(raidMet), ...
           'Treq',Treq);
end

% ------------------------------------------------------------------------
function [rate, ctr, cnt] = binned_rate(x, hit, edges)
nb = numel(edges)-1;
rate = nan(1,nb); ctr = nan(1,nb); cnt = zeros(1,nb);
for i = 1:nb
    m = x >= edges(i) & x < edges(i+1);
    ctr(i) = sqrt_or_mid(edges(i), edges(i+1));
    cnt(i) = sum(m);
    if cnt(i) > 0, rate(i) = mean(hit(m)); else, rate(i) = 0; end
end
end

function c = sqrt_or_mid(a, b)
% geometric centre for log-spaced bins, arithmetic otherwise
if a > 0 && b/a > 3, c = sqrt(a*b); else, c = (a+b)/2; end
end
