function [lat, lon] = enu2ll(E, N, lat0, lon0)
%AERIS.ENU2LL  Local East/North metres -> WGS-84 geodetic lat/lon.
%   [lat,lon] = aeris.enu2ll(E, N, lat0, lon0)
%
%   Uses the rigorous WGS-84 ellipsoidal transform (enu2geodetic +
%   wgs84Ellipsoid) when the Mapping Toolbox is available - the same datum
%   geoplot/geobasemap assume, so reported positions land exactly on the
%   imagery. Falls back to a flat-earth (equirectangular) approximation only if
%   the toolbox is absent, which is good to a few metres over the tactical
%   ranges here (< ~10 km). Degrees in, degrees out; the site is taken at 0 m
%   ellipsoidal height (altitude is reported separately in the warning).

persistent hasMap
if isempty(hasMap)
    hasMap = exist('enu2geodetic','file')==2 && exist('wgs84Ellipsoid','file')==2;
end

if hasMap
    [lat, lon, ~] = enu2geodetic(E, N, 0, lat0, lon0, 0, wgs84Ellipsoid);
else
    mPerDegLat = 111320;                   % flat-earth fallback (no toolbox)
    lat = lat0 + N / mPerDegLat;
    lon = lon0 + E / (mPerDegLat * cosd(lat0));
end
end
