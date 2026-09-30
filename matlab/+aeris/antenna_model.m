function am = antenna_model(p)
%AERIS.ANTENNA_MODEL  Modeled array gain/beamwidth/pattern (rung-1 fidelity).
%   am = aeris.antenna_model(p)
%
%   Replaces the aperture-formula gain and the analytic array factor with a
%   MODELED antenna: a real microstrip patch element (Antenna Toolbox) tiled
%   into a phased.URA of [nEl x nAz] (Phased Array System Toolbox). The single
%   patch is EM-accurate; the array uses pattern multiplication, so a full
%   128-element array is still fast. Set nEl=1 for the CN0566's 1x8 linear
%   array, or 16 for the AERIS-10 8x16.
%
%   Returns:
%     ok        true if the modeled path built (needs Antenna + Phased Array
%               Toolbox); false -> caller keeps the analytic model
%     DdBi      boresight directivity (dBi), modeled
%     Glin      realized gain (linear) = directivity * p.apEff
%     GdB       10log10(Glin)
%     azBW,elBW 3-dB beamwidths (deg), modeled
%     azGrid    -90:0.5:90
%     azPatLin  normalized one-way az power pattern on azGrid (for beam_pattern)
%
%   Cached by (freq, nAz, nEl, spacing) so repeat calls are instant. This is
%   the single change that lifts sensing gain, the beam schedule and (via the
%   comms antenna) the link budget onto measured-geometry footing.

persistent CACHE
if isempty(CACHE), CACHE = containers.Map('KeyType','char','ValueType','any'); end
key = sprintf('%.6g_%d_%d_%.4g', p.freq, p.nAz, p.nEl, p.dspaceWL);
if isKey(CACHE, key), am = CACHE(key); return; end

am = struct('ok',false);
try
    c = 299792458; lambda = c / p.freq; d = p.dspaceWL * lambda;
    azGrid = -90:0.5:90;

    % ---- element: a microstrip patch designed at the carrier -----------
    el = design(patchMicrostrip, p.freq);
    el.Tilt = 90; el.TiltAxis = [0 1 0];        % boresight along +x

    % element pattern -> custom element (fast array pattern multiplication)
    az = -180:2:180; ev = -90:2:90;
    gEl = pattern(el, p.freq, az, ev, 'Type','efield');   %#ok<NASGU> % warms cache
    ce = phased.CustomAntennaElement( ...
        'AzimuthAngles', az, 'ElevationAngles', ev, ...
        'MagnitudePattern', pattern(el, p.freq, az, ev, 'Type','powerdb'), ...
        'PhasePattern', zeros(numel(ev), numel(az)));

    arr = phased.URA('Size',[max(p.nEl,1) p.nAz], ...
                     'ElementSpacing',[d d], 'Element', ce);

    % ---- boresight directivity, beamwidths, az cut ---------------------
    DdBi = pattern(arr, p.freq, 0, 0, 'Type','directivity', 'PropagationSpeed', c);
    azBW = beamwidth(arr, p.freq, 'Cut','Azimuth',  'PropagationSpeed', c);
    if p.nEl > 1
        elBW = beamwidth(arr, p.freq, 'Cut','Elevation', 'PropagationSpeed', c);
    else
        elBW = 180;                              % a 1-row array is broad in el
    end
    pdb = pattern(arr, p.freq, azGrid, 0, 'Type','powerdb', ...
                  'Normalize',true, 'PropagationSpeed', c);

    Glin = 10^(DdBi/10) * p.apEff;
    % sanity gate: a real array is many dBi with a finite beamwidth. If the
    % modeled build degenerates (e.g. a parfor worker without the Antenna
    % Toolbox license returns junk), fall back to the analytic model rather
    % than zeroing SNR downstream.
    if ~isfinite(Glin) || 10*log10(Glin) < 6 || ~isfinite(azBW) || azBW <= 0
        error('aeris:antenna','modeled gain/beamwidth non-physical');
    end
    am.ok       = true;
    am.DdBi     = DdBi;
    am.Glin     = Glin;
    am.GdB      = 10*log10(Glin);
    am.azBW     = azBW;
    am.elBW     = elBW;
    am.azGrid   = azGrid;
    am.azPatLin = 10.^(pdb(:).'/10);
    am.azPatLin = am.azPatLin / max(am.azPatLin);
catch ME
    persistent WARNED
    if isempty(WARNED)
        warning('aeris:antenna', ...
            ['modeled antenna unavailable (%s); using the analytic model. ' ...
             'Needs Antenna Toolbox + Phased Array System Toolbox.'], ME.message);
        WARNED = true;
    end
    am.ok = false;
end

CACHE(key) = am;
end
