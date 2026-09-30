function S = aeris_treq_curve(file)
% AERIS_TREQ_CURVE  Warning satisfaction as a function of the requirement.
%
%   aeris_treq_curve                       % matlab_out/sweep_modeled2.csv
%   aeris_treq_curve('matlab_out/sweep.csv')
%
% The whole result hangs on Treq = 300 s, which is the most provisional number
% in the study. This reports met%(Treq) as a CURVE instead of a single point,
% so the conclusion no longer stakes everything on one unvalidated assumption -
% a reader can read off performance at whatever operational basis is agreed.
%
% Pure re-analysis of the raid-level warning times already in the sweep CSV;
% no new runs. A raid that never confirmed (raid_warn_s < 0) fails at every
% Treq, as it should.

if nargin < 1 || isempty(file)
    file = fullfile(fileparts(mfilename('fullpath')),'matlab_out','sweep_modeled2.csv');
end
T = readtable(file);
[~, ia] = unique(T.run, 'stable');  R = T(ia,:);   % raid-level

treqs = 30:15:600;                                  % s
overall = arrayfun(@(tq) 100*mean(R.raid_warn_s >= tq), treqs);

envs = {'best','grass','worst'};
cols = [.30 .60 .35; .35 .45 .70; .75 .28 .25];
curves = nan(numel(envs), numel(treqs));
for e = 1:numel(envs)
    m = strcmp(R.env, envs{e});
    if any(m)
        curves(e,:) = arrayfun(@(tq) 100*mean(R.raid_warn_s(m) >= tq), treqs);
    end
end

% read-offs at the current 300 s
i300 = find(treqs==300,1);
fprintf('\n--- met%% vs Treq (%s) ---\n', file);
fprintf('at Treq=300 s: overall %.1f%%', overall(i300));
for e=1:numel(envs)
    if ~isnan(curves(e,i300)), fprintf(', %s %.1f%%', envs{e}, curves(e,i300)); end
end
fprintf('\nTreq for 80%% overall: %s\n', treq_at(treqs, overall, 80));
fprintf('Treq for 50%% overall: %s\n', treq_at(treqs, overall, 50));

figure('Color','w','Position',[100 100 780 500]); hold on; grid on;
for e=1:numel(envs)
    if all(isnan(curves(e,:))), continue; end
    plot(treqs, curves(e,:), '-','Color',cols(e,:),'LineWidth',1.8,'DisplayName',envs{e});
end
plot(treqs, overall, 'k--','LineWidth',1.4,'DisplayName','overall (weighted)');
xline(300,':','Color',[.5 .5 .5],'Label','current Treq');
xlabel('warning requirement T_{req} (s)'); ylabel('raids meeting requirement (%)');
ylim([0 100]); legend('Location','northeast','Box','off');
title('warning satisfaction vs the requirement','FontWeight','normal');

S = struct('treqs',treqs,'overall',overall,'envs',{envs},'curves',curves);
if nargout==0, clear S; end
end

function s = treq_at(treqs, curve, pct)
% largest Treq at which the curve is still >= pct
i = find(curve >= pct, 1, 'last');
if isempty(i), s = '(never)'; else, s = sprintf('%d s', treqs(i)); end
end
