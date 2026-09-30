function aeris_antenna_check(p)
% AERIS_ANTENNA_CHECK  Modeled vs analytic antenna: gain, beamwidth, range.
%
%   aeris_antenna_check                       % baseline params
%   aeris_antenna_check(aeris_params('...'))
%
% Rung-1 validation. Builds the antenna both ways - the analytic aperture
% formula and the modeled patch array (Antenna + Phased Array Toolbox) - and
% reports how far apart they are on the quantities that matter: boresight gain,
% azimuth/elevation beamwidth, reliable range, and the comms link range. A
% clean model should agree with the analytic form to about a dB and a fraction
% of a beamwidth; a large gap points to a real element/array effect the
% aperture formula misses (which is the whole point of modeling it).
%
% Also overlays the two azimuth patterns so sidelobes are visible.

if nargin < 1 || isempty(p), p = aeris_params(); end

pa = p; pa.useModeledAntenna = false;   ga = aeris.derive(pa);
pm = p; pm.useModeledAntenna = true;    gm = aeris.derive(pm);

if ~isfield(gm,'antenna') || isempty(gm.antenna) || ~gm.antenna.ok
    error('aeris:antennaCheck', ['modeled antenna did not build - needs ' ...
        'Antenna Toolbox + Phased Array System Toolbox. Check "ver".']);
end

rra = aeris.reliable_range(pa, ga);
rrm = aeris.reliable_range(pm, gm);
cra = aeris.comms_range(pa);
crm = aeris.comms_range(pm);

fprintf('\n--- antenna: analytic vs modeled ---\n');
fprintf('%-20s %12s %12s %10s\n','quantity','analytic','modeled','delta');
fprintf('%s\n', repmat('-',1,56));
fprintf('%-20s %10.1f   %10.1f   %+8.1f\n','boresight gain dBi', ...
        10*log10(ga.Glin), 10*log10(gm.Glin), 10*log10(gm.Glin)-10*log10(ga.Glin));
fprintf('%-20s %10.2f   %10.2f   %+8.2f\n','az beamwidth deg', ga.azBW, gm.azBW, gm.azBW-ga.azBW);
fprintf('%-20s %10.2f   %10.2f   %+8.2f\n','el beamwidth deg', ga.elBW, gm.elBW, gm.elBW-ga.elBW);
fprintf('%-20s %10.2f   %10.2f   %+8.2f\n','reliable range km', rra/1000, rrm/1000, (rrm-rra)/1000);
fprintf('%-20s %10.2f   %10.2f   %+8.2f\n','comms range km', cra/1000, crm/1000, (crm-cra)/1000);

% ---- overlay the azimuth patterns --------------------------------------
azGrid = -90:0.5:90;
pAna = aeris.beam_pattern(azGrid, pa, ga);
pMod = aeris.beam_pattern(azGrid, pm, gm);
figure('Color','w','Position',[100 100 760 460]);
plot(azGrid, 10*log10(pAna+1e-6), '-','LineWidth',1.4,'Color',[.5 .5 .55]); hold on;
plot(azGrid, 10*log10(pMod+1e-6), '-','LineWidth',1.6,'Color',[.2 .5 .9]);
grid on; ylim([-40 2]); xlim([-90 90]);
xlabel('azimuth (deg)'); ylabel('normalised power (dB)');
legend('analytic (aperture)','modeled (patch array)','Location','south','Box','off');
title(sprintf('azimuth pattern: %d x %d array at %.2f GHz', p.nAz, p.nEl, p.freq/1e9), ...
      'FontWeight','normal');
end
