function S = aeris_comms_study(reps)
% AERIS_COMMS_STUDY  How much backhaul range does the forward layer need?
%
%   aeris_comms_study            % 300 reps per point
%   aeris_comms_study(1000)
%
% With p.useComms on, a track only counts as a network warning if the
% detecting node can DELIVER it to C2 (the base). The nodes sit near the
% forward line but C2 is Dforward BEHIND them, so the data has to be
% backhauled. This sweeps the comms link range and shows where warning
% satisfaction recovers - i.e. how much backhaul you need, and whether the
% baseline omni mesh is enough or you need a directional link.
%
% Layout: the 4-radar paired defense-in-depth, Dforward fixed at 6 km so the
% transition is clean. Two reference lines: the SENSING ceiling (useComms off,
% comms never limits) and the two candidate links from the comms doc - the
% omni mesh (~2.2 km) and a directional backhaul (~9 km).

if nargin < 1 || isempty(reps), reps = 300; end

base = aeris_params();
base.randomThreats = true; base.headless = true; base.quiet = true;
base.saveVideo = false; base.logData = false;
base.nodeLayout = 'pairs'; base.pairForward = 2500; base.nodeSpacing = 1500;
base.Dforward = 6000;                       % fixed, so the knee is clean

ranges = [1500 2210 3000 4000 5000 6000 7000 9000 12000];   % m
omni   = aeris.comms_range(base);           % the derived omni link range

% ---- sensing ceiling: comms never limits ------------------------------
met0 = 0;
for r = 1:reps
    p = base; p.useComms = false; p.rngSeed = 7000 + r;
    met0 = met0 + double(aeris_engage(p).requirementMet);
end
ceiling = 100*met0/reps;

% ---- sweep the comms link range with gating ON ------------------------
met  = zeros(size(ranges));
conn = zeros(size(ranges));                 % fraction of nodes reachable to C2
for k = 1:numel(ranges)
    m = 0; c = 0;
    for r = 1:reps
        p = base; p.useComms = true; p.commsRange = ranges(k); p.rngSeed = 8000 + r;
        res = aeris_engage(p);
        m = m + double(res.requirementMet);
        c = c + res.connected / res.nNodes;
    end
    met(k)  = 100*m/reps;
    conn(k) = 100*c/reps;
end

fprintf('\n--- comms backhaul study (pairs, Dforward %.0f km, %d reps) ---\n', ...
        base.Dforward/1000, reps);
fprintf('sensing ceiling (comms off): %.1f%% met\n', ceiling);
fprintf('derived omni link range:     %.2f km\n\n', omni/1000);
fprintf('%10s %10s %12s\n','range km','nodes conn','met %');
for k = 1:numel(ranges)
    fprintf('%10.1f %9.0f%% %11.1f\n', ranges(k)/1000, conn(k), met(k));
end

% ---- plot --------------------------------------------------------------
figure('Color','w','Position',[100 100 820 500]); hold on; grid on;
yyaxis left
plot(ranges/1000, met, '-o','LineWidth',1.8,'MarkerFaceColor','auto');
yline(ceiling,'--','Color',[.2 .6 .3],'LineWidth',1.5, ...
      'Label',sprintf('sensing ceiling %.0f%%',ceiling),'LabelHorizontalAlignment','left');
ylabel('raids meeting requirement (%)'); ylim([0 max(ceiling,max(met))*1.15]);
yyaxis right
plot(ranges/1000, conn, '-s','LineWidth',1.2);
ylabel('nodes connected to C2 (%)'); ylim([0 105]);
xline(omni/1000, ':','Color',[.8 .3 .2],'LineWidth',1.4, ...
      'Label','omni mesh','LabelOrientation','horizontal');
xline(9,'-.','Color',[.3 .4 .8],'LineWidth',1.4, ...
      'Label','directional backhaul','LabelOrientation','horizontal');
xline(base.Dforward/1000,':','Color',[.5 .5 .5],'Label','D_{forward}');
xlabel('comms link range (km)');
title(sprintf('backhaul: warning recovers once the link spans D_{forward} (%d km)', ...
      base.Dforward/1000),'FontWeight','normal');

S = struct('ranges',ranges,'met',met,'conn',conn,'ceiling',ceiling, ...
           'omni',omni,'Dforward',base.Dforward,'reps',reps);
if nargout==0, clear S; end
end
