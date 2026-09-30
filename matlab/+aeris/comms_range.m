function [Rmax, info] = comms_range(p)
%AERIS.COMMS_RANGE  Achievable data-link range from a comms link budget.
%   [Rmax, info] = aeris.comms_range(p)
%
%   Grounds the network's connectivity range in RF physics instead of a magic
%   number. This is the DATA LINK (node<->node<->C2), which is SEPARATE from
%   the X-band sensing radar - a low-rate mesh carrying track/plot reports, not
%   raw IQ, which is why the required data rate (and thus the link budget) is
%   modest.
%
%   Model: Friis with a log-distance path-loss exponent for terrestrial /
%   partially-obstructed paths (free space is n=2 and wildly optimistic near
%   the ground; 2.7-3.5 is realistic with terrain and foliage).
%
%     sensitivity = -174 + 10log10(rate) + NF + EbN0req      [dBm]
%     max path loss = Ptx + Gtx + Grx - sensitivity - margin [dB]
%     PL(R) = PL(1 m) + 10*n*log10(R)   ->   solve for R
%
%   Parameters (aeris_params defaults are a 900 MHz, 1 W, omni COTS mesh):
%     p.commsFreq     Hz    link carrier               (default 915e6)
%     p.commsPtx      dBm   transmit power             (default 30 = 1 W)
%     p.commsGtx/Grx  dBi   antenna gains              (default 3 = omni whip)
%     p.commsNF       dB    receiver noise figure      (default 6)
%     p.commsRate     bps   data rate                  (default 100e3)
%     p.commsEbN0     dB    required Eb/N0             (default 10)
%     p.commsMargin   dB    fade/NLOS margin           (default 12)
%     p.commsPathExp  -     path-loss exponent         (default 3.0)
%
%   info returns the intermediate dB terms for a table.

c = 299792458;
fc   = getf(p,'commsFreq',   915e6);
Ptx  = getf(p,'commsPtx',    30);
Gtx  = getf(p,'commsGtx',    3);
Grx  = getf(p,'commsGrx',    3);
NF   = getf(p,'commsNF',     6);
rate = getf(p,'commsRate',   100e3);
ebn0 = getf(p,'commsEbN0',   10);
marg = getf(p,'commsMargin', 12);
n    = getf(p,'commsPathExp',3.0);

% rung-1: modeled comms antenna gain overrides the flat dBi when requested
if getf(p,'useModeledAntenna',false)
    Gm = aeris.comms_antenna_gain(p);
    if ~isnan(Gm), Gtx = Gm; Grx = Gm; end
end

lambda = c / fc;
sens   = -174 + 10*log10(rate) + NF + ebn0;         % dBm
maxPL  = Ptx + Gtx + Grx - sens - marg;             % dB budget for path loss
PL1m   = 20*log10(4*pi / lambda);                    % free-space loss at 1 m
Rmax   = 10 ^ ((maxPL - PL1m) / (10*n));             % m

info = struct('fc',fc,'lambda',lambda,'sensitivity',sens, ...
              'maxPathLoss',maxPL,'PL1m',PL1m,'pathExp',n,'Rmax',Rmax);
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
