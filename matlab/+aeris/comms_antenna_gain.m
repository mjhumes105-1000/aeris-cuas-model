function G = comms_antenna_gain(p)
%AERIS.COMMS_ANTENNA_GAIN  Modeled gain (dBi) of the comms omni antenna.
%   G = aeris.comms_antenna_gain(p)
%
%   Rung-1 fidelity for the data link: models the 900 MHz mesh antenna as a
%   quarter-wave monopole over a ground plane (Antenna Toolbox) and returns its
%   peak gain, so the comms link budget uses a real antenna instead of a flat
%   3 dBi. Returns NaN if the toolbox is unavailable (caller keeps p.commsGtx).
%
%   Cached by frequency. A monopole is the honest model for a whip on a mast;
%   swap `monopole` for `dipole` or a modeled Yagi to price a directional
%   backhaul.

persistent CACHE
if isempty(CACHE), CACHE = containers.Map('KeyType','char','ValueType','double'); end
fc = p.commsFreq;
key = sprintf('%.6g', fc);
if isKey(CACHE, key), G = CACHE(key); return; end

G = NaN;
try
    ant = design(monopole, fc);        % quarter-wave monopole at the carrier
    % PEAK gain over the hemisphere. A monopole nulls at zenith (el=90) and
    % peaks toward the horizon, so sample the whole pattern and take the max -
    % do NOT sample a single angle.
    % DIRECTIVITY, not realized gain: the conventional link-budget input.
    % Realized gain ('gain') would also fold in impedance mismatch and the
    % finite-ground loss of the default monopole, which belong in the fade
    % margin, not the antenna term - using it double-counts and understates
    % range. Peak over the hemisphere (a monopole peaks toward the horizon).
    az = 0:10:350; el = 0:5:90;
    Gpat = pattern(ant, fc, az, el, 'Type','directivity');
    G = max(Gpat(:));
catch
    G = NaN;                            % no Antenna Toolbox -> caller falls back
end
CACHE(key) = G;
end
