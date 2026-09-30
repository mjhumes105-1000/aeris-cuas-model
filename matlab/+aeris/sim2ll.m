function [lat, lon] = sim2ll(xy, p)
%AERIS.SIM2LL  Sim-frame (x,y) metres -> geodetic lat/lon.
%   [lat,lon] = aeris.sim2ll(xy, p)
%
%   The sim frame has +x along the sector boresight (toward the expected
%   threat) and +y 90 deg counter-clockwise (left of boresight). To place it on
%   the earth the operator supplies:
%     p.refLat, p.refLon   geodetic position of the sim origin (the site datum,
%                          e.g. the node's own GPS)
%     p.threatBearing      TRUE bearing (deg, clockwise from north) that +x
%                          points - i.e. the direction the sector faces
%
%   Returns NaN if no georeference is set (p.refLat empty). The transform
%   is WGS-84 (see aeris.enu2ll).
%
%   This is the bridge that makes the defended point and every track report in
%   real coordinates. In a fielded system the operator enters the datum and the
%   threat bearing (or drops the defended point on a loaded map, which yields
%   both); here they are parameters.

if ~isfield(p,'refLat') || isempty(p.refLat) || ~isfield(p,'refLon') || isempty(p.refLon)
    lat = NaN; lon = NaN; return
end
B = 0; if isfield(p,'threatBearing') && ~isempty(p.threatBearing), B = p.threatBearing; end

x = xy(1); y = xy(2);
E = x*sind(B) - y*cosd(B);                 % +x at bearing B, +y 90 deg CCW
N = x*cosd(B) + y*sind(B);
[lat, lon] = aeris.enu2ll(E, N, p.refLat, p.refLon);
end
