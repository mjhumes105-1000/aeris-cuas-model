function h = terrain_height(x, y, p)
%AERIS.TERRAIN_HEIGHT  Ground elevation above the datum at (x,y), metres.
%   h = aeris.terrain_height(x, y, p)
%
%   Rung-4 terrain for the MATLAB model (the Python Level 4 does this on real
%   DEMs). x,y may be arrays; returns height above the flat datum. Presets:
%     'flat'   0 everywhere (reduces exactly to the flat-earth model)
%     'ridge'  a ridgeline across the threat axis at x=ridgeX (a node behind
%              or in front of high ground - the classic masking case)
%     'hills'  rolling terrain (sinusoidal)
%     'dem'    interpolate a real DEM from p.demX/demY/demZ (e.g. loaded via
%              Mapping Toolbox from the same Copernicus tiles Level 4 uses)
%
%   Parameters: p.terrainPreset, and for 'ridge' p.ridgeX/ridgeH/ridgeW.

preset = getf(p,'terrainPreset','flat');
switch lower(preset)
    case 'flat'
        h = zeros(size(x));
    case 'ridge'
        rx = getf(p,'ridgeX',3000); rh = getf(p,'ridgeH',120); rw = getf(p,'ridgeW',400);
        h = rh * exp(-((x-rx).^2) / (2*rw^2));
    case 'hills'
        a = getf(p,'hillAmp',60); L = getf(p,'hillLen',1800);
        h = a * (0.5 + 0.5*sin(2*pi*x/L) .* cos(2*pi*y/(1.3*L)));
    case 'dem'
        h = interp2(p.demX, p.demY, p.demZ, x, y, 'linear', 0);
    otherwise
        error('aeris:terrain','unknown terrainPreset "%s"', preset);
end
end

function v = getf(s,f,d), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end, end
