function aeris_iq_check(p, ntrial)
% AERIS_IQ_CHECK  Validate the fast synthesised map against the IQ front end.
%
%   aeris_iq_check
%   aeris_iq_check(aeris_params(), 200)
%
% Rung-3 validation. The 15k sweep uses the FAST synthesised range-Doppler map
% (aeris.look); this checks that map against the SIGNAL-LEVEL IQ map
% (aeris.look_iq) the same way aeris_antenna_check validated the analytic gain:
%
%   (1) Pd vs SNR, synthesised vs IQ, over many Monte-Carlo trials. Overlapping
%       curves mean the fast map is a faithful stand-in; an IQ curve shifted
%       right quantifies the PROCESSING LOSS (window + straddle) the synthesised
%       map omits.
%   (2) an example range-Doppler map from each, so the real LFM/Doppler
%       sidelobes in the IQ map are visible against the idealised synthesised one.
%
% Heavy - a full CPI datacube per IQ trial. A few tens of seconds.

if nargin < 1 || isempty(p), p = aeris_params(); end
if nargin < 2 || isempty(ntrial), ntrial = 120; end

g = aeris.derive(p);
rangeAxis = (0:g.dR:p.Rmax).';  nR = numel(rangeAxis);
R = 2000; vr = -25;                          % a representative target
[~, ri] = min(abs(rangeAxis - R));

nDs = p.nDoppler;  cfS = aeris.cfar_init(p, nR, nDs);
velS = linspace(-g.vUnamb, g.vUnamb, nDs); [~, diS] = min(abs(velS - vr));
M   = p.cpi;       cfI = aeris.cfar_init(p, nR, M);

snrdB = 4:2:20;
pdS = zeros(size(snrdB));  pdI = zeros(size(snrdB));

fprintf('\nIQ validation: %d trials/point, target R=%.0f m, vr=%.0f m/s\n', ntrial, R, vr);
for s = 1:numel(snrdB)
    snr = 10^(snrdB(s)/10);
    cS = 0; cI = 0;
    for t = 1:ntrial
        % synthesised map
        Ps = -log(rand(nR, nDs));
        Ps = aeris.add_target(Ps, ri, diS, snr * -log(rand));
        ms = aeris.cfar(Ps, cfS);
        cS = cS + any(any(ms(max(1,ri-2):min(nR,ri+2), max(1,diS-2):min(nDs,diS+2))));
        % IQ map
        [Pi, velI] = aeris.look_iq(snr, R, vr, p, g, rangeAxis);
        mi = aeris.cfar(Pi, cfI);
        [~, diI] = min(abs(velI - vr));
        cI = cI + any(any(mi(:, max(1,diI-2):min(M,diI+2))));   % target Doppler column
    end
    pdS(s) = cS/ntrial;  pdI(s) = cI/ntrial;
    fprintf('  SNR %2d dB:  synth Pd %.2f   IQ Pd %.2f\n', snrdB(s), pdS(s), pdI(s));
end

% processing-loss estimate: horizontal shift between the two Pd curves at 0.5
shift = pd50(snrdB,pdI) - pd50(snrdB,pdS);
fprintf('\nIQ Pd(0.5) is %+.1f dB vs synthesised', shift);
if isfinite(shift)
    fprintf('  -> ~%.1f dB processing loss the fast map omits.\n', max(shift,0));
else
    fprintf('.\n');
end

% ---- figures -----------------------------------------------------------
figure('Color','w','Position',[80 80 1180 460]);
subplot(1,2,1); hold on; grid on;
plot(snrdB, 100*pdS, '-o','LineWidth',1.6);
plot(snrdB, 100*pdI, '-s','LineWidth',1.6);
xlabel('target SNR (dB)'); ylabel('P_d (%)'); ylim([0 105]);
legend('synthesised (aeris.look)','IQ (aeris.look_iq)','Location','southeast','Box','off');
title('detection: fast map vs signal-level IQ','FontWeight','normal');

subplot(1,2,2);
[Pi, velI] = aeris.look_iq(10^(22/10), R, vr, p, g, rangeAxis);   % bright target
PdB = 10*log10(Pi);
imagesc(velI, rangeAxis/1000, PdB); set(gca,'YDir','normal');
colormap(turbo_or_jet());
caxis([0 max(PdB(:))]); %#ok<CAXIS>            % fix the floor at the noise level so the
cb=colorbar; cb.Label.String='power (dB)';   % target + sidelobes stand out
hold on; plot(vr, R/1000, 'wo','MarkerSize',14,'LineWidth',1.5);  % true target
xlabel('radial velocity (m/s)'); ylabel('range (km)');
title('IQ range-Doppler (22 dB target): real sidelobes','FontWeight','normal');
end

% ------------------------------------------------------------------------
function x = pd50(snrdB, pd)
% SNR (dB) where Pd crosses 0.5, by linear interpolation
i = find(pd >= 0.5, 1, 'first');
if isempty(i) || i == 1, x = NaN; return; end
x = interp1(pd(i-1:i), snrdB(i-1:i), 0.5);
end

function m = turbo_or_jet()
try, m = turbo(256); catch, m = jet(256); end
end
