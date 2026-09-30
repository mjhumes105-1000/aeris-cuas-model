function S = aeris_upgrade_trade()
% AERIS_UPGRADE_TRADE  Cost-efficient hardware upgrades for the 10N.
%
%   aeris_upgrade_trade
%
% Ranks real, COTS X-band hardware upgrades for the AERIS-10N by capability
% gained per dollar, per average watt, and per pound - so the cheap-and-light
% wins are obvious.
%
% BASELINE = a CN0566-class node with its weak reference illuminator (~2 W eff),
% 8-element patch array, ADL8107 LNA (1.43 dB cascade NF), Pluto SDR. The point
% of the study is which parts move reliable range the most for the least SWaP-C.
%
% Real components priced Sep 2026 (single-unit, distributor):
%   Qorvo QPA1010D  7.9-11 GHz GaN MMIC, 15 W sat, 38% PAE, 18 dB   ~$198
%                   DATASHEET: VD=24 V (= battery rail), IDQ=600 mA, needs
%                   +24 dBm drive (a driver amp), 32 W max dissipation.
%   Qorvo QPA1011D  7.9-11 GHz GaN MMIC, 25 W sat, 37% PAE, 20 dB   ~$300
%                   DATASHEET: IDQ ~1200 mA -> 28.8 W quiescent, ~33 W CW avg.
%   Qorvo CMD197    GaAs driver, 1-24 GHz, 16 dB gain, +22 dBm OP1dB ~$374
%                   (needed to reach the PA's +24 dBm drive; +22 dBm is a touch
%                   low - push ~2 dB into compression, or use CMD292 +27 dBm.)
%   bladeRF 2.0 micro  AD9361, 61 MHz BW (vs Pluto 20 MHz)          ~$540
%   +8 patches + 2x ADAR1000 (8->16 az elements)                   ~$400 est
%
% PA-upgrade cost INCLUDES the CMD197 driver (~$374) + heatsink/board - the
% driver is ~2x the PA cost, so the real PA line is ~$650, not ~$250.
%
% PA POWER: a class-AB GaN PA draws its QUIESCENT current continuously
% (QPA1010D: 24V x 0.6A = 14.4 W) even between pulses. So average DC is
% ~17 W CW-biased (quiescent-dominated) or ~4 W if the drain is pulsed (the
% datasheet's "Pulsed VD" mode - needs a drain modulator). We use the CW-biased
% ~17 W as the realistic simple build. PA cost includes a driver amp; weight
% includes a heatsink for the 14 W continuous dissipation.

rcs = 0.03;                                   % nominal small-UAS target

% ---- baseline (hardware-realistic CN0566) ------------------------------
b = aeris_params('nexus'); b.useRfChain = true; b.Ptpeak = 2;   % weak illuminator

% ---- upgrade configs: {label, field-deltas, +$, +avgW, +lb, note} -------
% cost includes the CMD197 driver + heatsink/board for the PA rows.
U = {
 'baseline (CN0566)',          @(p)p,                                   0,   0,   0
 'PA15W+driver (1010D+CMD197)',@(p)setf(p,'Ptpeak',15),               650,  19, 0.8
 'PA15W drain-pulsed',         @(p)setf(p,'Ptpeak',15),               750,   6, 0.8
 'PA25W+driver (1011D+CMD197)',@(p)setf(p,'Ptpeak',25),               760,  35, 0.9
 'SDR AD9361 (bladeRF)',       @(p)setf(p,'Bchirp',56e6),             540,   2, 0.2
 '16 az elements (+8)',        @(p)setf(p,'nAz',16),                  400,   8, 0.4
 'PA15W+driver + 16-el',       @(p)setf(setf(p,'Ptpeak',15),'nAz',16),1050, 27, 1.2
};

n = size(U,1);
rr = zeros(1,n); addUsd = zeros(1,n); addW = zeros(1,n); addLb = zeros(1,n);
for i = 1:n
    p = U{i,2}(b); g = aeris.derive(p);
    rr(i)   = aeris.reliable_range(setf(p,'targetRCS',rcs), g)/1000;   % km
    addUsd(i) = U{i,3}; addW(i) = U{i,4}; addLb(i) = U{i,5};
end
d = rr - rr(1);                               % range gained vs baseline (km)

fprintf('\n=========  10N cost-efficient upgrade trade  =========\n');
fprintf('baseline reliable range: %.2f km (%.3g m^2)\n\n', rr(1), rcs);
fprintf('%-24s %7s %8s %7s %6s %6s %9s\n','upgrade','range','+range','+$','+W','+lb','km/$100');
fprintf('%s\n', repmat('-',1,74));
for i = 1:n
    kmper = 100*d(i)/max(addUsd(i),1);
    fprintf('%-24s %6.2f  %+6.2f %7.0f %6.1f %6.1f %9.2f\n', ...
        U{i,1}, rr(i), d(i), addUsd(i), addW(i), addLb(i), kmper);
end
fprintf('%s\n', repmat('-',1,74));

% ranking by range per dollar (excluding baseline & the resolution-only SDR)
val = d ./ max(addUsd,1); val(1) = -inf;
[~,best] = max(val);
fprintf('best range-per-dollar: %s (%.2f km for $%.0f, +%.1f W avg)\n', ...
    U{best,1}, d(best), addUsd(best), addW(best));
fprintf('(SDR AD9361 buys bandwidth/dynamic range, not range - it improves\n');
fprintf(' range resolution %.0f->%.0f m and clutter handling, so it shows +0 km here.)\n', ...
    3e8/(2*5e6), 3e8/(2*56e6));

fprintf('\nEE notes: QPA1010D runs on VD=24 V - the same rail as the node battery,\n');
fprintf('  so no extra supply. Needs a ~+24 dBm driver amp and a heatsink for the\n');
fprintf('  ~14 W continuous quiescent dissipation. Drain-pulsing the VD (datasheet\n');
fprintf('  mode) cuts avg draw ~17 W -> ~4 W at the cost of a drain modulator.\n');
fprintf('  The SDR upgrade buys resolution/dynamic range, not detection range.\n');

figure('Color','w','Position',[100 100 820 480]);
subplot(1,2,1); bar(d,'FaceColor',[.3 .5 .7]); grid on;
set(gca,'XTick',1:n,'XTickLabel',U(:,1),'XTickLabelRotation',35,'TickLabelInterpreter','none');
ylabel('reliable range gained (km)'); title('capability gain','FontWeight','normal');
subplot(1,2,2); bar(100*d./max(addUsd,1),'FaceColor',[.4 .6 .4]); grid on;
set(gca,'XTick',1:n,'XTickLabel',U(:,1),'XTickLabelRotation',35,'TickLabelInterpreter','none');
ylabel('km per $100'); title('cost efficiency','FontWeight','normal');

S = struct('labels',{U(:,1)'},'range',rr,'dRange',d,'addUsd',addUsd,'addW',addW,'addLb',addLb);
if nargout==0, clear S; end
end

function p = setf(p,f,v), p.(f)=v; end
