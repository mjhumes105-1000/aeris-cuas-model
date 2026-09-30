function S = aeris_cueing_study(file)
% AERIS_CUEING_STUDY  Warning -> operational outcome (threats defeated).
%
%   aeris_cueing_study
%   aeris_cueing_study('matlab_out/sweep_modeled2.csv')
%
% Reframes the result from "did the warning beat 300 s" to "did the node cue an
% effector in time to defeat the threat" - the outcome that actually matters in
% defense-in-depth. Applies aeris.cue_defeat across the swept raid population
% for a range of effector timelines and kill probabilities, and reports the
% system defeat fraction.
%
% The point: the required warning is set by the EFFECTOR timeline, not an
% arbitrary 300 s. A fast effector turns many "failed" warnings into defeats;
% a slow one needs the long warnings only slow threats provide. This is where
% the negative sensing result becomes a positive layered-defense contribution.
%
% Pure re-analysis of the sweep CSV; no new runs.

if nargin < 1 || isempty(file)
    file = fullfile(fileparts(mfilename('fullpath')),'matlab_out','sweep_modeled2.csv');
end
T = readtable(file);
[~, ia] = unique(T.run, 'stable');  R = T(ia,:);
w = R.raid_warn_s;                                  % raid warning time (s), <0 = none

p = aeris_params();
needed = 30:15:360;                                 % effector time-needed sweep (s)
Pks = [0.5 0.7 0.9];

def = zeros(numel(Pks), numel(needed));
for a = 1:numel(Pks)
    for b = 1:numel(needed)
        q = p; q.effPk = Pks(a); q.effReact = 0; q.effEngage = needed(b); q.effSlop = 20;
        def(a,b) = 100*mean(aeris.cue_defeat(w, q));
    end
end

% headline read-offs at a representative fast effector (needed 90 s, Pk 0.7)
q = p; q.effPk=0.7; q.effReact=0; q.effEngage=90; q.effSlop=20;
dFast = 100*mean(aeris.cue_defeat(w, q));
metReq = 100*mean(w >= p.Treq);
fprintf('\n--- cueing / defeat (%s) ---\n', file);
fprintf('warning meets %.0f s requirement:      %.1f%% of raids\n', p.Treq, metReq);
fprintf('threats defeated, fast effector\n');
fprintf('  (needs 90 s, Pk 0.7):               %.1f%% of raids\n', dFast);
fprintf('=> a fast effector converts warnings that FAIL the 300 s bar into\n');
fprintf('   defeats: the node is useful well below Treq if the effector is quick.\n');

figure('Color','w','Position',[100 100 780 500]); hold on; grid on;
c = lines(numel(Pks));
for a=1:numel(Pks)
    plot(needed, def(a,:), '-','Color',c(a,:),'LineWidth',1.8, ...
         'DisplayName',sprintf('Pk = %.1f',Pks(a)));
end
xline(p.Treq,':','Color',[.5 .5 .5],'Label','300 s req');
xlabel('effector time needed: react + engage (s)');
ylabel('threats defeated (% of raids)'); ylim([0 100]);
legend('Location','northeast','Box','off');
title('layered outcome: defeats vs effector speed','FontWeight','normal');

S = struct('needed',needed,'Pks',Pks,'defeat',def,'defeatFast',dFast,'metReq',metReq);
if nargout==0, clear S; end
end
