function w = az_gain(offDeg, p, g)
%AERIS.AZ_GAIN  Two-way azimuth gain with scan loss and a soft sector edge.
%   w = aeris.az_gain(offDeg, p, g)
%
%   Replaces the hard sector wall (full gain inside +/- sectorWidth/2, zero
%   outside) with the graceful rolloff a real fixed-sector array has - the
%   azimuth counterpart of aeris.elev_gain:
%
%     * within the sector the scan lands a beam on the target, but steering off
%       boresight costs gain (projected aperture + element pattern), modelled
%       as a two-way cos^q scan loss;
%     * past the nominal edge there is no wall - the last beam sits at the edge
%       and the target rolls off its Gaussian skirt, so coverage fades over
%       ~a beamwidth instead of switching off.
%
%   offDeg is the target bearing relative to boresight. q = p.scanLossExp
%   (default 1.5). Returns a two-way linear gain (1 at boresight).
%
%   Consequence: edge-of-sector targets are marginal (~-2 to -3 dB), not fully
%   lit, and just-outside targets are still weakly detectable - which is the
%   honest, less-optimistic coverage of a fixed-sector node.

edge = p.sectorWidth/2;
a    = abs(offDeg);
q    = 1.5;
if isfield(p,'scanLossExp') && ~isempty(p.scanLossExp), q = p.scanLossExp; end

sl = max(cosd(min(a,89)), 0.02)^q;              % two-way scan loss off boresight
if a <= edge
    w = sl;
else
    slEdge = max(cosd(min(edge,89)), 0.02)^q;
    w = slEdge * aeris.gauss_beam(a - edge, g.azBW)^2;   % soft shoulder
end
end
