function nodes = node_layout(p)
%AERIS.NODE_LAYOUT  Placement geometry for a distributed sensing network.
%   nodes = aeris.node_layout(p)
%
%   Returns a 1xN struct array, one entry per node:
%     pos    1x3   position [x y z] in the engagement frame
%     bore   deg   sector boresight (absolute bearing the node faces)
%     label  char  'N1', 'N2', ...
%
%   FRAME. Same as aeris.spawn_threats: the threat approaches from +x, the
%   defended point sits at [-p.Dforward, 0, 0], and a single node sits at the
%   origin facing +x. Multi-node layouts spread nodes around that origin (the
%   nominal forward line) or around the defended point.
%
%   Parameters consumed:
%     p.nNodes       node count (default 1)
%     p.nodeLayout   'single' | 'line' | 'depth' | 'ring' (default 'single')
%     p.nodeSpacing  m, spacing / ring radius (default 1500)
%     p.sectorWidth  used only to orient 'ring' nodes outward
%
%   Layouts (threat from +x, defended point at -x):
%     single  one node at the origin, facing the threat. Reduces EXACTLY to
%             the single-node sim.
%     line    picket screen - nodes abreast along y at x=0, all facing +x.
%             Widens azimuth coverage of the threat corridor.
%     depth   defense in depth - nodes staggered in x (some further forward),
%             all facing +x. Trades a forward node's early look against a rear
%             node's shorter range.
%     ring    point defense - nodes on a circle around the defended point,
%             each facing radially outward. Covers all approach bearings.
%
%   Placement is the study's second variable; this is where you change it.

Pdef = [-p.Dforward, 0, 0];

n = getf(p, 'nNodes', 1);  n = max(1, round(n));
layout = lower(getf(p, 'nodeLayout', 'single'));
if strcmp(layout,'pairs'), n = 4; end          % pairs is always 2+2
if strcmp(layout,'quad'),  n = 4; end          % quad is always 4 sectors
if n == 1, layout = 'single'; end
s = getf(p, 'nodeSpacing', 1500);

switch layout
    case 'single'
        pos = [0 0 0];  bore = getf(p,'boresight',0);  % match sim3d sector centre

    case 'line'                         % abreast across y, facing +x
        yy  = ((1:n) - (n+1)/2) * s;
        pos = [zeros(n,1), yy(:), zeros(n,1)];
        bore = zeros(n,1);

    case 'depth'                        % staggered forward in x, facing +x
        xx  = ((1:n) - 1) * s;          % first node at origin, rest forward
        pos = [xx(:), zeros(n,1), zeros(n,1)];
        bore = zeros(n,1);

    case 'quad'                         % 4 co-located nodes, 90 deg sectors
        % one site, four fixed AERIS-10N facing N/E/S/W -> 360 deg coverage
        % (the short-range architecture). Each keeps its own sectorWidth.
        n = 4;
        pos  = zeros(4,3);
        bore = [0; 90; 180; 270];

    case 'ring'                         % around the defended point, facing out
        ang = (0:n-1) * (360/n);        % evenly spaced bearings
        pos = Pdef + s * [cosd(ang(:)), sind(ang(:)), zeros(n,1)];
        bore = ang(:);                  % face radially outward

    case 'pairs'                        % defense in depth: near pair + far pair
        % 4 radars in two pairs. A NEAR pair sits close to the base (x=0, i.e.
        % Dforward from the defended point); a FAR pair sits p.pairForward
        % toward the threat. Each pair is spread +/- s/2 in cross-range so the
        % two radars view a target from different bearings - that angular
        % diversity is what tightens the fix and holds the track. All face +x.
        fwd = getf(p,'pairForward', 2500);
        pos = [ 0,    s/2, 0;          % near-left
                0,   -s/2, 0;          % near-right
                fwd,  s/2, 0;          % far-left
                fwd, -s/2, 0];         % far-right
        bore = zeros(4,1);

    case 'grid'                         % width AND depth - the real 2-D array
        % rows staggered forward (depth, more warning), columns abreast
        % (width, more coverage). Fills a near-square grid, centred in y.
        nr = max(1, round(sqrt(n)));    % rows in depth (x)
        nc = ceil(n / nr);              % columns in width (y)
        [cc, rr] = meshgrid(1:nc, 1:nr);
        xx = (rr(:) - 1) * s;                       % 0, s, 2s... forward
        yy = (cc(:) - (nc+1)/2) * s;                % centred abreast
        pos = [xx, yy, zeros(numel(xx),1)];
        pos = pos(1:n, :);              % trim to exactly n
        bore = zeros(n,1);

    otherwise
        error('aeris:nodeLayout', ...
              'p.nodeLayout must be single, line, depth, ring or grid (got "%s")', layout);
end

% forward offset: push the whole layout downrange toward the threat. Lets any
% layout gain standoff (warning) without changing its shape (coverage). The
% key knob for separating the two effects.
fwd = getf(p, 'nodeForward', 0);
if fwd ~= 0, pos(:,1) = pos(:,1) + fwd; end

nodes = struct('pos', num2cell(pos, 2).', ...
               'bore', num2cell(bore(:).'), ...
               'label', arrayfun(@(k) sprintf('N%d',k), 1:size(pos,1), 'uni', 0));
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
