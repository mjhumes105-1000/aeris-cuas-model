function T = spawn_threats(p)
%AERIS.SPAWN_THREATS  Build a randomised raid for one engagement.
%   T = aeris.spawn_threats(p)
%
%   Returns a 1xN struct array, one entry per drone:
%     rcs        m^2    radar cross section
%     spd        m/s    ground speed
%     p0         1x3    start position [x y z], node at origin
%     u          1x3    unit ground heading (z component 0)
%     alt0       m      start altitude
%     descent    -      fraction of altitude bled off over the run
%     label      char    e.g. 'D3'
%
%   Randomisation is controlled by the p.rand* fields in aeris_params. With
%   p.randomThreats = false a single drone is returned using the deterministic
%   p.targetRCS / p.Vc / p.bearingDeg / p.startRange / p.targetAlt, so the
%   legacy baseline is reproduced exactly.
%
%   Formations are built around a lead drone, then the whole group is aimed at
%   the defended point. Spacing is perpendicular/parallel to the group heading:
%     single   one drone
%     line     line abreast (perpendicular to heading)
%     trail    column, one behind the other
%     wedge    V, spreading back from the lead
%     echelon  diagonal, all on one side
%     swarm    random scatter in a box, per-drone heading jitter
%
%   Every draw uses the current RNG state, so seed with rng(p.rngSeed) (or
%   rng('shuffle')) before calling to control repeatability.

Pdef = [-p.Dforward, 0, 0];

% ---- deterministic single target (legacy path) --------------------------
if ~isfield(p,'randomThreats') || ~p.randomThreats
    alt = 0;
    if isfield(p,'targetAlt'), alt = p.targetAlt; end
    T = one_threat(p.targetRCS, p.Vc, ...
        [p.startRange*cosd(p.bearingDeg), p.startRange*sind(p.bearingDeg), alt], ...
        Pdef, alt, descent_default(p), 'D1');
    return
end

% ---- how many, and in what shape ---------------------------------------
if isfield(p,'nDrones') && ~isempty(p.nDrones)
    nD = max(1, round(p.nDrones));          % exact count requested
else
    nD = randi(p.randNDrones);
end
form = p.randFormations{randi(numel(p.randFormations))};
if nD == 1, form = 'single'; end

% ---- drone class (catalogue overrides the flat ranges) ------------------
% A raid is normally one airframe type, so the class is drawn once per raid.
cls = '';
D   = [];
if isfield(p,'droneClass') && ~isempty(p.droneClass)
    cls = p.droneClass;
    D   = aeris.drone_catalog(cls);
end

% ---- altitude mode ------------------------------------------------------
% 'class'       altitude from the drone class band. Realistic, but altitude is
%               then CORRELATED with RCS (fixedwing is big and high, micro is
%               small and low), so any altitude-vs-performance result from a
%               mixed sweep is confounded.
% 'independent' altitude drawn from p.randAlt regardless of class. Breaks the
%               correlation, so altitude effects can be attributed. Less
%               realistic per airframe; the right choice for a controlled study.
% 'fixed'       every drone at p.targetAlt exactly.
altMode = 'class';
if isfield(p,'altMode') && ~isempty(p.altMode), altMode = lower(p.altMode); end
if isempty(D) && strcmp(altMode,'class'), altMode = 'independent'; end

% ---- lead drone --------------------------------------------------------
leadBear  = uniform(p.randBearingDeg);
leadRange = uniform(p.randStartRange);
if isempty(D)
    leadSpd = uniform(p.randSpeed);
else
    leadSpd = uniform(D.spd);
end
switch altMode
    case 'class'
        leadAlt = uniform(D.alt);
    case 'independent'
        leadAlt = uniform(p.randAlt);
    case 'fixed'
        leadAlt = getfd(p,'targetAlt',100);
    otherwise
        error('aeris:altMode', ...
            'p.altMode must be class, independent or fixed (got "%s")', altMode);
end
lead      = [leadRange*cosd(leadBear), leadRange*sind(leadBear), leadAlt];

% group heading: from the lead toward the defended point, in the ground plane
gv = [Pdef(1)-lead(1), Pdef(2)-lead(2), 0];
ug = gv / norm(gv);
perp = [-ug(2), ug(1), 0];                    % left of heading

spacing = uniform(p.randSpacing);

% ---- place the formation ------------------------------------------------
T = repmat(one_threat(1,1,[0 0 0],Pdef,0,0,'D0',form), 1, nD);
for i = 1:nD
    switch lower(form)
        case 'single'
            off = [0 0 0];
        case 'line'                            % abreast
            off = perp * spacing * (i - (nD+1)/2);
        case 'trail'                           % column
            off = -ug * spacing * (i-1);
        case 'wedge'                           % V behind the lead
            s = (-1)^i;  r = ceil((i-1)/2);
            off = -ug*spacing*r + perp*spacing*0.6*s*r;
        case 'echelon'                         % diagonal, one side
            off = (-ug + perp) * spacing * (i-1) / sqrt(2);
        case 'swarm'                           % random scatter
            off = perp*spacing*(rand*2-1)*nD*0.5 + ug*spacing*(rand*2-1)*nD*0.5;
        otherwise
            off = [0 0 0];
    end

    pos = lead + off;
    if strcmp(altMode,'fixed')
        pos(3) = leadAlt;                                   % exactly, no jitter
    else
        pos(3) = max(10, leadAlt + uniform(p.randAltJitter));
    end

    if isempty(D)
        rcs = exp(uniform(log(p.randRCS)));     % log-uniform over the size range
    else
        rcs = exp(uniform(log(D.rcs)));         % log-uniform within the class
    end
    if isfield(p,'rcsScale') && ~isempty(p.rcsScale), rcs = rcs * p.rcsScale; end
    spd = leadSpd;
    if strcmp(form,'swarm')
        spd = max(5, leadSpd + uniform(p.randSpeedJitter));
    end

    % each drone flies at the defended point; swarm gets a course error
    gvi = [Pdef(1)-pos(1), Pdef(2)-pos(2), 0];
    ui  = gvi / norm(gvi);
    if strcmp(form,'swarm')
        th = deg2rad(uniform(p.randCourseJitter));
        ui = [ui(1)*cos(th)-ui(2)*sin(th), ui(1)*sin(th)+ui(2)*cos(th), 0];
    end

    T(i) = one_threat(rcs, spd, pos, Pdef, pos(3), descent_default(p), ...
                      sprintf('D%d',i), form);
    T(i).u     = ui;
    T(i).class = cls;
end

[~, ord] = sort([T.rcs], 'descend');            % biggest first, for legibility
T = T(ord);
for i = 1:numel(T), T(i).label = sprintf('D%d', i); end
end

% ------------------------------------------------------------------------
function t = one_threat(rcs, spd, p0, Pdef, alt0, descent, label, form)
if nargin < 8, form = 'single'; end
gv = [Pdef(1)-p0(1), Pdef(2)-p0(2), 0];
t = struct('rcs',rcs, 'spd',spd, 'p0',p0, 'u',gv/norm(gv), ...
           'alt0',alt0, 'descent',descent, 'label',label, 'formation',form, ...
           'class','');
end

function v = getfd(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end

function v = uniform(rng2)
v = rng2(1) + rand * (rng2(2) - rng2(1));
end

function d = descent_default(p)
d = 0.35;
if isfield(p,'randDescent'), d = uniform(p.randDescent); end
end
