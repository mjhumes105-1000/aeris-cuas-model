function ok = los_clear(p1, p2, p, nsamp)
%AERIS.LOS_CLEAR  Is the line of sight from p1 to p2 clear of terrain?
%   ok = aeris.los_clear(p1, p2, p)
%   ok = aeris.los_clear(p1, p2, p, nsamp)
%
%   p1, p2 are 3-D points [x y z] (z above the datum). Samples the straight
%   line between them and returns false if the terrain rises above the sight
%   line anywhere in between - i.e. the target is masked. This is the geometric
%   heart of rung 4: a low drone behind high ground is invisible no matter how
%   good the radar is, which is a placement/terrain effect the flat-earth model
%   cannot show.
%
%   nsamp intermediate samples (default 24). A small clearance margin avoids
%   grazing false-blocks.

if nargin < 4 || isempty(nsamp), nsamp = 24; end
t  = linspace(0, 1, nsamp);
xs = p1(1) + (p2(1)-p1(1))*t;
ys = p1(2) + (p2(2)-p1(2))*t;
zs = p1(3) + (p2(3)-p1(3))*t;                 % straight sight line
th = aeris.terrain_height(xs, ys, p);
ok = all(zs >= th + 0.5);                     % clear if above terrain everywhere
end
