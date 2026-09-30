function [w, offDeg] = elev_gain(p, g, elDeg, W)
%AERIS.ELEV_GAIN  Two-way elevation beam gain from the ACTUAL scan schedule.
%   [w, offDeg] = aeris.elev_gain(p, g, elDeg)
%   [w, offDeg] = aeris.elev_gain(p, g, elDeg, W)   % pass a cached dwell plan
%
%   A scanning array does not stare at one elevation. It steps through the
%   elevation bars from aeris.dwell_plan, so a target at elevation el is
%   illuminated by the NEAREST bar, not by a beam fixed at boresight. The
%   residual loss is therefore bounded by half the bar spacing - about 3.7 dB
%   two-way for the baseline 0.9x spacing - not the tens of dB you get from
%   modelling a single fixed beam.
%
%   Returns:
%     w        two-way linear gain, 1.0 on a bar centre
%     offDeg   angular distance to the nearest bar centre
%
%   A target OUTSIDE the covered elevation extent gets the loss from the
%   nearest edge bar, which falls away fast - that is the real coverage hole,
%   and it is a scheduling choice (p.elevCoverDeg), not a beam-shape accident.
%
%   WHY THIS EXISTS. An earlier version used aeris.gauss_beam against a fixed
%   p.elevBore = 0, which manufactured 40+ dB altitude-dependent penalties
%   (-43 dB for a 300 m target at 2 km) and made altitude look like the
%   dominant driver. It is not. Do not go back to a single fixed beam unless
%   the node genuinely cannot scan in elevation.

if nargin < 4 || isempty(W)
    W = aeris.dwell_plan(p, g);
end

bars   = W.elBeams(:);
offDeg = min(abs(elDeg - bars), [], 1);        % nearest bar, per element of el
offDeg = reshape(offDeg, size(elDeg));

w = aeris.gauss_beam(offDeg, g.elBW).^2;       % one-way pattern, squared
end
