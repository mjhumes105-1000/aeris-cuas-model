function W = dwell_plan(p, g)
%AERIS.DWELL_PLAN  Beam positions tiling the sector, plus dwell timing.
%   W = aeris.dwell_plan(p, g)
%
%   Works out how many beam positions are needed to cover the field of regard,
%   how long each dwell takes, and therefore how long a full scan (the revisit
%   period) takes. Returns:
%
%     azBeams    1xNa  azimuth steer angles, deg
%     elBeams    1xNe  elevation steer angles, deg
%     nDwells    Na*Ne
%     dwellTime  s     cpi / prf - time on one beam position
%     revisit    s     nDwells * dwellTime - time to revisit any one beam
%     tConfirm   s     revisit * MofN(2) - earliest possible track confirmation
%     azBW,elBW  deg   3-dB beamwidths (from g)
%     spacing    -     beam spacing as a fraction of the 3-dB beamwidth
%
%   WHY THIS MATTERS. The scope sim assumes "a full sector scan each look puts
%   a beam on the target", i.e. that revisit is short compared with frameDt.
%   This function is how you check that assumption instead of trusting it. For
%   the baseline (90 deg sector, 0-20 deg elevation) revisit is ~0.8 s against
%   a 2 s frame step, so the assumption holds - but it stops holding if the
%   elevation coverage or the CPI grows.
%
%   Parameters consumed:
%     p.sectorWidth, p.boresight, p.cpi, p.prf, p.MofN
%     p.elevCoverDeg  [lo hi] elevation extent to cover, default [0 20]
%     p.beamSpacing   beam spacing / 3-dB beamwidth, default 0.9
%     p.barMode       'centered' (default) or 'horizon' - see below

if nargin < 2 || isempty(g), g = aeris.derive(p); end

cover   = getf(p, 'elevCoverDeg', [0 20]);
spacing = getf(p, 'beamSpacing',  0.9);

W.azBW   = g.azBW;
W.elBW   = g.elBW;
W.spacing = spacing;

% ---- azimuth: tile the sector, centred on boresight --------------------
azStep = spacing * g.azBW;
Na     = max(1, ceil(p.sectorWidth / azStep));
W.azBeams = p.boresight + ((1:Na) - (Na+1)/2) * azStep;

% ---- elevation: tile the requested coverage ----------------------------
% BAR PLACEMENT MATTERS, and it is a design choice, not physics:
%   'centered' bars sit half a step inside the span, so the lowest is
%              cover(1) + step/2. A target AT the horizon then sits 2.5 deg
%              off the nearest bar and loses ~3.7 dB two-way.
%   'horizon'  the lowest bar sits ON cover(1). Better for a C-UAS node,
%              whose threats are low and inbound, at the cost of spending
%              half a beamwidth below the coverage floor.
% Which you pick shifts WHICH altitudes ripple, so never report a "best" or
% "worst" altitude without saying which placement produced it.
elStep = spacing * g.elBW;
elSpan = max(diff(cover), 0);
barMode = getf(p, 'barMode', 'centered');
switch lower(barMode)
    case 'centered'
        Ne = max(1, ceil(elSpan / elStep));
        W.elBeams = cover(1) + (0.5:1:(Ne-0.5)) * (elSpan / Ne);
    case 'horizon'
        % same packing density as 'centered' - the ONLY difference is that a
        % bar sits on cover(1) and one on cover(2), so the horizon is covered
        Ne = max(2, ceil(elSpan / elStep) + 1);
        W.elBeams = cover(1) + (0:Ne-1) * (elSpan / (Ne-1));
    otherwise
        error('aeris:barMode', ...
              'p.barMode must be centered or horizon (got "%s")', barMode);
end
if elSpan == 0, W.elBeams = cover(1); Ne = 1; end
W.barMode = barMode;

% ---- timing ------------------------------------------------------------
W.nDwells   = Na * Ne;
W.dwellTime = p.cpi / p.prf;
W.revisit   = W.nDwells * W.dwellTime;
W.tConfirm  = W.revisit * p.MofN(2);
W.cover     = cover;
W.Na = Na; W.Ne = Ne;
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
