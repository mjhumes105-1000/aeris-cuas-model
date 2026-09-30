function r = aeris_engage(p)
% AERIS_ENGAGE  Headless multi-node engagement (the distributed-sensing core).
%
%   r = aeris_engage(p)
%
% Runs ONE engagement of a randomised raid against a NETWORK of nodes, with no
% graphics. Each node is the same radar (same +aeris physics) at its own
% position and boresight; a target is "confirmed by the network" as soon as
% ANY node's own M-of-N logic confirms it. This is the OR-fusion warning-layer
% model: any node that holds a track raises the warning.
%
% Reduces EXACTLY to the single-node engagement when p.nNodes = 1 (verify with
% aeris_check_net). Set the network with p.nNodes / p.nodeLayout / p.nodeSpacing
% (see aeris.node_layout). Everything else - raid, weather, drone class - is as
% in aeris_scope_sim3d.
%
% Returns a struct:
%   threats      the raid (aeris.spawn_threats output)
%   nodes        the layout (aeris.node_layout output)
%   per          1xNt struct per target:
%                  confirmed, tConfirm, warnTime, minRange,
%                  confNode  (label of the FIRST node to confirm, '' if none)
%                  nDetNodes (how many distinct nodes ever detected it)
%   warnTime     network raid warning (first-confirmed target's), NaN if none
%   requirementMet, reliableRange, formation, seed, nFrames
%   netUplift    network confirmed count / best single-node confirmed count
%
% See also AERIS.NODE_LAYOUT, AERIS.LOOK, AERIS_SCOPE_SIM3D, AERIS_SWEEP.

if nargin < 1 || isempty(p), p = aeris_params(); end
p = df(p,'nNodes',1); p = df(p,'elevBeamOn',false); p = df(p,'elevBore',0);
p = df(p,'useComms',false);   % comms reachability gates confirmation only if on
useComms = p.useComms;
p = df(p,'terrainOn',false);  % rung 4: terrain masking (LOS) - off = flat earth
p = df(p,'mastHeight',3);     % m, node antenna height above local terrain
terrainOn = p.terrainOn;
p = df(p,'multipathOn',false);% rung 4: two-ray ground-bounce lobing
multipathOn = p.multipathOn;
% rotating (mechanical 360 scan, e.g. AERIS-10X) vs fixed sector (10N).
% A rotating beam sees a target only when it sweeps past - once per rotation -
% so its look cadence is the rotation period, modelled as a per-frame look
% probability. When it looks it points AT the target (peak gain, no scan loss).
p = df(p,'rotating',false); p = df(p,'rotationPeriod',4);
rotating = p.rotating;
pLook = 1; if rotating, pLook = min(1, p.frameDt / p.rotationPeriod); end

% seed
if ischar(p.rngSeed) || isstring(p.rngSeed)
    rng(char(p.rngSeed)); s = rng; usedSeed = s.Seed;
else
    rng(p.rngSeed); usedSeed = p.rngSeed;
end

g     = aeris.derive(p);
T     = aeris.spawn_threats(p);   nT = numel(T);
nodes = aeris.node_layout(p);     nN = numel(nodes);
Pdef  = [-p.Dforward, 0, 0];
link  = aeris.comms(nodes, p);    % connectivity to the fusion cell (C2)

% shared, frame-invariant
rangeAxis = (0:g.dR:p.Rmax).';  nR = numel(rangeAxis);
velAxis   = linspace(-g.vUnamb, g.vUnamb, p.nDoppler);  nD = p.nDoppler;
cf        = aeris.cfar_init(p, nR, nD);
Wdwell    = aeris.dwell_plan(p, g);
if p.clutterOn
    Cridge = aeris.clutter_ridge(rangeAxis, velAxis, p, g);
else
    Cridge = 0;
end

% per-target reliable range (single-node, that RCS) - a reference, not the net
relRange = zeros(1,nT);
for i = 1:nT
    pi_ = p; pi_.targetRCS = T(i).rcs;
    relRange(i) = aeris.reliable_range(pi_, g);
end

% geometry / timing
gdist = zeros(1,nT); ftime = zeros(1,nT);
for i = 1:nT
    gdist(i) = norm(Pdef(1:2) - T(i).p0(1:2));
    ftime(i) = gdist(i) / T(i).spd;
end
nFrames = min(p.maxFrames, ceil(max(ftime) / p.frameDt));

M = p.MofN(1); N = p.MofN(2);

% state: detection history per (node, target)
detHist   = false(nN, nT, nFrames);
confNode  = false(nN, nT);          % node n's own M-of-N satisfied for target i
netConf   = false(1, nT);
tConfirm  = nan(1, nT);
warnT     = nan(1, nT);
minRange  = inf(1, nT);
everDet   = false(nN, nT);
alive     = true(1, nT);
firstConfirm = NaN; raidWarn = NaN;
per_confNode = repmat({''}, 1, nT);

for f = 1:nFrames
    t = (f-1) * p.frameDt;

    % ---- propagate targets (identical to aeris_scope_sim3d) -------------
    pos = nan(nT,3); ttg = nan(1,nT);
    for i = 1:nT
        if ~alive(i), continue; end
        gp   = T(i).p0(1:2) + T(i).spd * t * T(i).u(1:2);
        frac = min(1, (T(i).spd*t)/gdist(i));
        alt  = max(5, T(i).alt0 * (1 - T(i).descent*frac));
        Pt   = [gp, alt];
        if dot(Pt(1:2)-Pdef(1:2), T(i).u(1:2)) >= 0
            alive(i) = false; continue;
        end
        pos(i,:) = Pt;
        ttg(i)   = norm(Pt(1:2)-Pdef(1:2)) / T(i).spd;
    end
    if ~any(alive), nFrames = f-1; break; end

    % ---- each node takes a look ----------------------------------------
    for nn = 1:nN
        nodePos = nodes(nn).pos;
        bore    = nodes(nn).bore;

        snrv = []; riv = []; div = []; idxv = [];
        for i = 1:nT
            if ~alive(i), continue; end
            rel = pos(i,:) - nodePos;
            R   = norm(rel);
            if R > p.Rmax, continue; end                 % out of processing range
            az   = atan2d(rel(2), rel(1));
            aoff = aeris.wrap180(az - bore);
            if rotating
                % 360 coverage, but the beam is on this target only ~pLook of
                % the time (it is sweeping the rest of the azimuth)
                if rand > pLook, continue; end
                wBeam = 1;                                % points at the target
            else
                % fixed sector: soft edge (scan loss + shoulder), az_gain
                if abs(aoff) > p.sectorWidth/2 + 2.5*g.azBW, continue; end
                wBeam = aeris.az_gain(aoff, p, g);
            end
            % terrain masking: skip if the ground blocks line of sight
            if terrainOn
                nz = aeris.terrain_height(nodePos(1), nodePos(2), p) + p.mastHeight;
                if ~aeris.los_clear([nodePos(1) nodePos(2) nz], pos(i,:), p), continue; end
            end
            el  = atan2d(rel(3), hypot(rel(1),rel(2)));
            vr  = dot(rel, T(i).spd*T(i).u) / R;          % radial rate to this node

            if p.elevBeamOn
                wBeam = wBeam * aeris.elev_gain(p, g, el, Wdwell);
            end
            pi_ = p; pi_.targetRCS = T(i).rcs;
            snr = aeris.snr(pi_, g, R, wBeam);
            if multipathOn
                hr = aeris.terrain_height(nodePos(1),nodePos(2),p) + p.mastHeight;
                snr = snr * aeris.multipath_factor(R, max(pos(i,3),1), hr, g, p);
            end
            if snr <= 0, continue; end

            [~, ir] = min(abs(rangeAxis - R));
            [~, id] = min(abs(velAxis  - vr));
            snrv(end+1)=snr; riv(end+1)=ir; div(end+1)=id; idxv(end+1)=i; %#ok<AGROW>
        end

        if isempty(snrv), continue; end
        det = aeris.look(snrv, riv, div, nR, nD, cf, Cridge);

        for kk = 1:numel(idxv)
            i = idxv(kk);
            detHist(nn,i,f) = det(kk);
            if det(kk), everDet(nn,i) = true; end
            % this node's own M-of-N
            if ~confNode(nn,i) && f >= N && ...
               sum(detHist(nn,i,max(1,f-N+1):f)) >= M
                confNode(nn,i) = true;
                % comms gating is OPT-IN (p.useComms). Off by default so the
                % baseline is not silently blocked when a forward node sits
                % beyond the omni link range of C2 - that is a comms STUDY, not
                % the default sensing scenario. When on, network warning needs
                % delivery to C2 and is charged the relay latency.
                reachOK = true; commsLat = 0;
                if useComms
                    reachOK  = link.reachable(nn);
                    commsLat = link.latency(nn);
                end
                if ~netConf(i) && reachOK
                    netConf(i)   = true;
                    tConfirm(i)  = t;
                    warnT(i)     = ttg(i) - p.latency - commsLat;
                    per_confNode{i} = nodes(nn).label; %#ok<AGROW>
                    if isnan(firstConfirm)
                        firstConfirm = t; raidWarn = warnT(i);
                    end
                end
            end
        end
    end

    % track closest approach per target (to any node) for reporting
    for i = 1:nT
        if ~alive(i), continue; end
        dmin = inf;
        for nn = 1:nN, dmin = min(dmin, norm(pos(i,:)-nodes(nn).pos)); end
        minRange(i) = min(minRange(i), dmin);
    end
end

% ---- assemble results ---------------------------------------------------
netDetFrames = squeeze(sum(any(detHist,1),3));   % frames the NETWORK detected i
netDetFrames = reshape(netDetFrames, 1, []);
per = struct('confirmed',{}, 'tConfirm',{}, 'warnTime',{}, ...
             'minRange',{}, 'confNode',{}, 'nDetNodes',{}, 'detFrames',{});
for i = 1:nT
    per(i) = struct('confirmed', netConf(i), 'tConfirm', tConfirm(i), ...
        'warnTime', warnT(i), 'minRange', minRange(i), ...
        'confNode', per_confNode{i}, 'nDetNodes', sum(everDet(:,i)), ...
        'detFrames', netDetFrames(i));
end

% network uplift: net confirmations vs the best single node alone
singleConf = sum(confNode, 2);            % per node, how many it confirmed
bestSingle = max([singleConf(:); 0]);
netConfN   = sum(netConf);
uplift = netConfN / max(bestSingle, 1);

r = struct('threats',{T}, 'nodes',{nodes}, 'per',{per}, ...
           'formation',infer_form(T), 'seed',usedSeed, ...
           'warnTime',raidWarn, 'requirementMet',raidWarn>=p.Treq, ...
           'reliableRange',relRange, 'nFrames',nFrames, ...
           'nNodes',nN, 'netConfirmed',netConfN, 'bestSingleConfirmed',bestSingle, ...
           'netUplift',uplift, 'link',{link}, ...
           'connected',sum(link.reachable), 'maxHops',max([link.hops(isfinite(link.hops)) 0]));
end

% ------------------------------------------------------------------------
function p = df(p,f,v), if ~isfield(p,f)||isempty(p.(f)), p.(f)=v; end, end

function f = infer_form(T)
if isfield(T,'formation') && ~isempty(T(1).formation), f = T(1).formation;
else, f = 'single'; end
end
