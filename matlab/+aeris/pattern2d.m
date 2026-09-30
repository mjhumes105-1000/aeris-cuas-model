function G = pattern2d(azDeg, elDeg, p, steerAzDeg, steerElDeg)
%AERIS.PATTERN2D  One-way normalised power pattern over an (az,el) grid.
%   G = aeris.pattern2d(azDeg, elDeg, p)
%   G = aeris.pattern2d(azDeg, elDeg, p, steerAz, steerEl)
%
%   Returns numel(elDeg) x numel(azDeg) linear power gain, normalised to 1 in
%   the steer direction. Square for two-way.
%
%   Uses the separable uniform-aperture array factor for a URA in the y-z
%   plane with boresight along +x:
%       u = sin(az)cos(el),  v = sin(el)
%       AF = AF_az(u-u0) * AF_el(v-v0)
%   This is the same model as the fallback branch of aeris.beam_pattern. It is
%   used here rather than phased.URA/pattern() because a full 2-D grid through
%   the toolbox is slow, and the visualisation needs thousands of points.
%
%   Consequence: element pattern and mutual coupling are NOT included, so
%   far-off-boresight sidelobe levels are optimistic. Fine for showing beam
%   shape, tiling and dwell geometry; do not quote sidelobe numbers from it.

if nargin < 4 || isempty(steerAzDeg), steerAzDeg = 0; end
if nargin < 5 || isempty(steerElDeg), steerElDeg = 0; end

[AZ, EL] = meshgrid(azDeg(:).', elDeg(:));

u  = sind(AZ) .* cosd(EL);
v  = sind(EL);
u0 = sind(steerAzDeg) * cosd(steerElDeg);
v0 = sind(steerElDeg);

AFa = af(pi * p.dspaceWL * (u - u0), p.nAz);
AFe = af(pi * p.dspaceWL * (v - v0), p.nEl);

G = (AFa .* AFe).^2;
end

function a = af(psi, N)
% uniform array factor magnitude sin(N psi)/(N sin psi), with the psi->0 limit
den = N * sin(psi);
a   = sin(N*psi) ./ den;
a(abs(den) < 1e-12) = 1;
a = abs(a);
end
