% aeris_nexus_linkbudget.m
% -------------------------------------------------------------------------
% Level 3 cross-check for the Python link budget (cuas_l3), using the
% MATLAB Phased Array System Toolbox. Reproduces (1) the 8x16 URA gain and
% pattern and (2) the integrated SNR(range) and Swerling-1 Pd(range) curves,
% then writes them to CSV so they can be overlaid on the Python results
% (figures/fig16_snr_pd).
%
% Run locally (needs Phased Array System Toolbox + Radar Toolbox):
%   >> aeris_nexus_linkbudget
% Outputs: matlab_out/aeris_linkbudget.csv, aeris_array_pattern.csv, and figures.
%
% EVERY parameter below mirrors cuas_l3/radar.py RadarParams defaults. These
% are AERIS-Nexus PLACEHOLDERS; replace with the frozen repository spec and
% keep the two implementations in sync.
% -------------------------------------------------------------------------

clear; clc;
outdir = fullfile(fileparts(mfilename('fullpath')), 'matlab_out');
if ~exist(outdir, 'dir'); mkdir(outdir); end

%% Parameters (mirror RadarParams) ----------------------------------------
c      = 299792458;
freq   = 9.5e9;            % Hz  (X-band)
lambda = c / freq;
nAz    = 8;                % elements across azimuth
nEl    = 16;               % elements in elevation
dspace = 0.5 * lambda;     % element spacing
apEff  = 0.6;              % aperture efficiency (applied to gain)
Ptpeak = 20;               % W total peak radiated
tau    = 10e-6;            % s pulse width
Bchirp = 5e6;              % Hz chirp bandwidth (range resolution)
prf    = 10e3;             % Hz
cpi    = 256;              % coherent pulses per dwell
NF     = 4;                % dB noise figure
Lsys   = 6;                % dB system losses
Pfa    = 1e-6;
T0     = 290;

rcsList = [0.1 0.03 0.01]; % m^2
Rkm     = linspace(0.2, 5, 400);
R       = Rkm * 1e3;

%% Parameter drift guard ---------------------------------------------------
% This file deliberately does NOT call +aeris/ — its value as a cross-check
% comes from being an independent reimplementation. But independent physics
% must not mean silently divergent PARAMETERS, so compare against the single
% source of truth and complain loudly if anyone edits one and not the other.
try
    ref = aeris_params();
    chk = {'c',c; 'freq',freq; 'nAz',nAz; 'nEl',nEl; 'apEff',apEff; ...
           'Ptpeak',Ptpeak; 'tau',tau; 'Bchirp',Bchirp; 'prf',prf; ...
           'cpi',cpi; 'NF',NF; 'Lsys',Lsys; 'Pfa',Pfa; 'T0',T0};
    drift = {};
    for ii = 1:size(chk,1)
        name = chk{ii,1}; here = chk{ii,2};
        if isfield(ref, name) && ~isequaln(ref.(name), here)
            drift{end+1} = sprintf('  %-8s linkbudget=%g  aeris_params=%g', ...
                name, here, ref.(name)); %#ok<SAGROW>
        end
    end
    if ~isempty(drift)
        warning('aeris:paramDrift', ...
            ['link-budget parameters have drifted from aeris_params.m:\n%s\n' ...
             'The cross-check is only meaningful if both describe the same radar.'], ...
            strjoin(drift, newline));
    else
        fprintf('Parameter check: matches aeris_params.m.\n');
    end
catch
    warning('aeris:paramDrift','aeris_params.m not on the path; drift check skipped.');
end

%% Array and gain ----------------------------------------------------------
% Uniform rectangular array, isotropic elements (gain from aperture).
array = phased.URA('Size', [nEl nAz], 'ElementSpacing', [dspace dspace]);
% Aperture-formula gain with efficiency, to match the Python model exactly.
apertureArea = (nAz * dspace) * (nEl * dspace);
Glin = 4*pi*apertureArea*apEff / lambda^2;
GdB  = 10*log10(Glin);
fprintf('Array gain: %.1f dBi (aperture %.0f cm^2)\n', GdB, apertureArea*1e4);

% Beam pattern (azimuth cut) for the pattern CSV.
az = -60:0.25:60;
sv = phased.SteeringVector('SensorArray', array, 'PropagationSpeed', c);
resp = pattern(array, freq, az, 0, 'PropagationSpeed', c, 'Type', 'powerdb', ...
               'Normalize', true);
writematrix([az(:) resp(:)], fullfile(outdir, 'aeris_array_pattern.csv'));

%% Integrated SNR and Pd(range) -------------------------------------------
% Matched-filter single-pulse SNR (energy form): Pt*tau*G^2*lambda^2*sigma
%   / ((4pi)^3 R^4 k Ts L). Integration gain = cpi (coherent).
k   = physconst('Boltzmann');
Ts  = T0 * 10^(NF/10);
L   = 10^(Lsys/10);
intGain = cpi;

csv = zeros(numel(R), 1 + 2*numel(rcsList));
csv(:,1) = Rkm(:);
hdr = "range_km";
figure('Color','w'); tiledlayout(1,2);
nexttile; hold on; grid on;
for i = 1:numel(rcsList)
    sigma = rcsList(i);
    snr1 = (Ptpeak*tau*Glin^2*lambda^2*sigma) ./ ((4*pi)^3 * R.^4 * k * Ts * L);
    snr  = snr1 * intGain;
    pd   = Pfa .^ (1 ./ (1 + snr));          % Swerling-1
    csv(:, 1+i)              = 10*log10(snr(:));
    csv(:, 1+numel(rcsList)+i) = pd(:);
    hdr = hdr + sprintf(",snr_db_rcs%g", sigma) ;
    plot(Rkm, 10*log10(snr), 'LineWidth', 2, 'DisplayName', sprintf('\\sigma=%g m^2', sigma));
end
xlabel('Range (km)'); ylabel('Integrated SNR (dB)'); title('SNR vs range'); legend;
nexttile; hold on; grid on;
for i = 1:numel(rcsList)
    plot(Rkm, csv(:, 1+numel(rcsList)+i), 'LineWidth', 2, ...
         'DisplayName', sprintf('\\sigma=%g m^2', rcsList(i)));
    hdr = hdr + sprintf(",pd_rcs%g", rcsList(i));
end
yline(0.9,'--'); xlabel('Range (km)'); ylabel('Pd'); title('Pd vs range (Swerling-1)'); legend;

fid = fopen(fullfile(outdir,'aeris_linkbudget.csv'),'w');
fprintf(fid, "%s\n", hdr); fclose(fid);
writematrix(csv, fullfile(outdir,'aeris_linkbudget.csv'), 'WriteMode','append');

% Reliable range (Pd=0.9) per RCS
fprintf('\nReliable range (Pd=0.9):\n');
for i = 1:numel(rcsList)
    pd = csv(:, 1+numel(rcsList)+i);
    idx = find(pd >= 0.9, 1, 'last');
    if isempty(idx); rr = 0; else; rr = Rkm(idx); end
    fprintf('  RCS %5.3g m^2 -> %.2f km\n', rcsList(i), rr);
end
fprintf('\nCSV + pattern written to %s\n', outdir);
fprintf('Compare aeris_linkbudget.csv against Python figures/fig16_snr_pd.\n');
