function link = comms(nodes, p)
%AERIS.COMMS  Graceful connectivity of the sensing network to the fusion cell.
%   link = aeris.comms(nodes, p)
%
%   Centralized fusion with mesh relay: every radar must get its data to C2
%   (default: the base / defended point), directly if it can close the link,
%   otherwise by relaying through a connected peer.
%
%   The link is NOT a hard in-range/out-of-range switch. Each hop has a
%   PACKET-DELIVERY PROBABILITY that follows the coded-link waterfall - ~1 well
%   inside range, through 0.5 at the nominal range, tailing to 0 beyond - and
%   retransmissions (ARQ) inflate that hop's latency by ~1/PDP. So as a node
%   nears its range limit the link degrades gradually (rising loss, growing
%   delay), not off a cliff. The path to C2 is the one that minimises total
%   ARQ-inflated latency (Dijkstra).
%
%   Parameters:
%     p.commsRange    m    nominal range (PDP = 0.5); [] -> aeris.comms_range
%     p.commsPathExp  -    path-loss exponent (sets how fast PDP falls with range)
%     p.commsWaterfall dB  waterfall width (coded link ~2; smaller = sharper)
%     p.commsLatency  s    latency per hop at PDP = 1
%     p.c2Pos         1x3  fusion cell (default defended point)
%     p.nodesDown     idx  killed nodes
%
%   Returns per node (1xN): reachable, hops, latency (ARQ-inflated, s), pdp
%   (end-to-end delivery probability), plus link.c2 and link.A (edge existence).

nN = numel(nodes);
c2 = [-p.Dforward, 0, 0];
if isfield(p,'c2Pos') && ~isempty(p.c2Pos), c2 = p.c2Pos; end
R0  = getf(p,'commsRange', []);
if isempty(R0), R0 = aeris.comms_range(p); end     % nominal (PDP=0.5) range
nexp = getf(p,'commsPathExp', 3.0);
w    = getf(p,'commsWaterfall', 2.0);              % waterfall width, dB
lat  = getf(p,'commsLatency', 1.0);

down = false(1,nN);
if isfield(p,'nodesDown') && ~isempty(p.nodesDown), down(p.nodesDown) = true; end

% node + C2 positions; C2 is index nN+1
P = zeros(nN+1, 2);
for i = 1:nN, P(i,:) = nodes(i).pos(1:2); end
P(nN+1,:) = c2(1:2);
alive = [~down, true];

% ---- per-edge PDP and ARQ latency --------------------------------------
% margin(L) = 10*n*log10(R0/L) dB  ->  PDP = logistic(margin / w).
% An edge "exists" only where PDP is not vanishing (margin > -4w, PDP > ~0.02);
% below that it cannot carry a packet in any reasonable number of retries.
cost = inf(nN+1);
pdpE = zeros(nN+1);
for a = 1:nN+1
    for b = a+1:nN+1
        if ~(alive(a) && alive(b)), continue; end
        L = max(norm(P(a,:)-P(b,:)), 1);
        margin = 10*nexp*log10(R0 / L);            % dB above the PDP=0.5 point
        pdp = 1 / (1 + exp(-margin / w));
        if margin > -4*w                            % edge is usable
            cost(a,b) = lat / max(pdp, 1e-3);       % expected delivery time (ARQ)
            cost(b,a) = cost(a,b);
            pdpE(a,b) = pdp; pdpE(b,a) = pdp;
        end
    end
end

% ---- Dijkstra from C2: min ARQ-latency path, carrying end-to-end PDP -----
src = nN+1;
dist = inf(1,nN+1); dist(src) = 0;
pdpTo = zeros(1,nN+1); pdpTo(src) = 1;
hopTo = inf(1,nN+1);  hopTo(src) = 0;
visited = false(1,nN+1);
for it = 1:nN+1
    u = -1; best = inf;
    for k = 1:nN+1
        if ~visited(k) && dist(k) < best, best = dist(k); u = k; end
    end
    if u < 0, break; end
    visited(u) = true;
    for v = 1:nN+1
        if isfinite(cost(u,v)) && dist(u)+cost(u,v) < dist(v)
            dist(v)  = dist(u) + cost(u,v);
            pdpTo(v) = pdpTo(u) * pdpE(u,v);
            hopTo(v) = hopTo(u) + 1;
        end
    end
end

link.reachable = isfinite(dist(1:nN)) & ~down;
link.hops      = hopTo(1:nN);
link.latency   = dist(1:nN);                       % ARQ-inflated, seconds
link.pdp       = pdpTo(1:nN);
link.down      = down;
link.c2        = c2;
link.A         = isfinite(cost);                   % which edges exist (for drawing)
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
