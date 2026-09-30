function W = warning_report(tracks, p)
%AERIS.WARNING_REPORT  Turn confirmed tracks into hardware-agnostic warnings.
%   W = aeris.warning_report(tracks, p)
%
%   This is the node's OUTPUT - the message a distributed unit actually
%   receives. It is deliberately sensor-agnostic: bearing, range, closure, ETA,
%   an estimated threat class with a confidence, and a recommended action. A
%   real warning layer emits exactly this and nothing about the radar internals.
%
%   INPUT  tracks: struct array, one per confirmed target, with fields
%     id        char/label
%     pos       1x3 [x y z] in the engagement frame (defended point at
%               [-p.Dforward,0,0], threat from +x)
%     spd       m/s ground speed
%     heading   1x3 unit ground heading (toward the defended point)
%     rcs       m^2 TRUE radar cross section (a measurement estimate is derived)
%     confNodes cellstr of node labels holding the track (optional)
%     snr       dB integrated SNR at confirmation (optional, feeds confidence)
%
%   OUTPUT W: struct array, one warning per track, sorted by ETA (soonest
%   first - the triage order), with fields:
%     id, bearingDeg, rangeM, altM, closureMps, etaS,
%     classEst, classConf ('high'|'med'|'low'),
%     warnS      (etaS - p.latency, the usable warning),
%     meetsReq   (warnS >= p.Treq),
%     action     ('MONITOR'|'ALERT - CUE EFFECTOR'|'IMMINENT - TAKE COVER'),
%     nNodes     (how many nodes hold it)
%
%   Bearing and range are measured FROM THE DEFENDED POINT, because that is the
%   frame the warned unit cares about. ETA is time for the target to reach the
%   defended point at current closure.
%
%   Threat class is estimated from a NOISY RCS measurement plus the (well
%   measured) Doppler speed, classified against aeris.drone_catalog prototypes -
%   size alone cannot separate a micro-quad from an FPV attacker, but size plus
%   speed can. Set p.rcsMeasSigmaDB for the RCS measurement noise (default 3 dB).

Pdef = [-p.Dforward, 0, 0];
sigDB = 3; if isfield(p,'rcsMeasSigmaDB') && ~isempty(p.rcsMeasSigmaDB), sigDB = p.rcsMeasSigmaDB; end
lat   = 0; if isfield(p,'latency'), lat = p.latency; end
Treq  = 300; if isfield(p,'Treq'), Treq = p.Treq; end

D = aeris.drone_catalog();
protoLogRcs = cellfun(@(r) mean(log10(r)), {D.rcs});
protoSpd    = cellfun(@(s) mean(s), {D.spd});

n = numel(tracks);
W = struct('id',{},'bearingDeg',{},'rangeM',{},'altM',{},'closureMps',{}, ...
           'courseDeg',{},'speedMps',{}, ...
           'etaS',{},'classEst',{},'classConf',{},'warnS',{},'meetsReq',{}, ...
           'action',{},'nNodes',{},'reqS',{},'latDeg',{},'lonDeg',{});

Bt = 0; if isfield(p,'threatBearing') && ~isempty(p.threatBearing), Bt = p.threatBearing; end

for i = 1:n
    tk  = tracks(i);
    rel = tk.pos - Pdef;                        % vector from defended point
    rng = norm(rel(1:2));                        % ground range to defended pt
    brg = atan2d(rel(2), rel(1));                % bearing from defended pt
    % ground velocity (sim frame) -> ground speed and course-over-ground (true)
    vsim = tk.spd * tk.heading(1:2);
    spdG = norm(vsim);
    Evel = vsim(1)*sind(Bt) - vsim(2)*cosd(Bt);      % rotate sim->ENU
    Nvel = vsim(1)*cosd(Bt) + vsim(2)*sind(Bt);
    if spdG > 1e-3, courseD = mod(atan2d(Evel, Nvel), 360); else, courseD = NaN; end

    % closure toward the defended point (positive = inbound)
    clos = -dot(vsim, rel(1:2)) / max(rng,1e-6);
    eta  = rng / max(clos, 1e-6);
    warnS = eta - lat;

    % ---- threat classification (noisy RCS + Doppler speed) -------------
    rcsMeas = tk.rcs * 10^(sigDB*randn/10);      % log-normal measurement error
    [cls, conf] = classify(log10(rcsMeas), tk.spd, protoLogRcs, protoSpd, {D.name});

    % ---- recommended action --------------------------------------------
    if warnS >= Treq
        act = 'MONITOR';
    elseif warnS >= 60
        act = 'ALERT - CUE EFFECTOR';
    else
        act = 'IMMINENT - TAKE COVER';
    end

    nn = 1;
    if isfield(tk,'confNodes') && ~isempty(tk.confNodes), nn = numel(tk.confNodes); end
    if isfield(tk,'nNodes') && ~isempty(tk.nNodes), nn = tk.nNodes; end

    if isfield(tk,'classCall') && ~isempty(tk.classCall)
        cls = tk.classCall; conf = 'obs';        % live micro-Doppler call
    end
    [latD, lonD] = aeris.sim2ll(tk.pos(1:2), p);   % NaN if no georef

    W(end+1) = struct('id',tk.id, 'bearingDeg',brg, 'rangeM',rng, ...
        'altM',tk.pos(3), 'closureMps',clos, 'courseDeg',courseD, 'speedMps',spdG, ...
        'etaS',eta, 'classEst',cls, 'classConf',conf, 'warnS',warnS, ...
        'meetsReq',warnS>=Treq, 'action',act, 'nNodes',nn, 'reqS',Treq, ...
        'latDeg',latD, 'lonDeg',lonD); %#ok<AGROW>
end

if ~isempty(W)
    [~, ord] = sort([W.etaS]);                   % soonest arrival first
    W = W(ord);
end
end

% ------------------------------------------------------------------------
function [cls, conf] = classify(logRcs, spd, pLogRcs, pSpd, names)
% nearest-prototype in normalised (log RCS, speed) space; confidence from the
% margin between the best and second-best match
dr = (logRcs - pLogRcs) / 0.5;                   % ~half a decade per unit
ds = (spd - pSpd) / 15;                           % ~15 m/s per unit
d  = sqrt(dr.^2 + ds.^2);
[ds1, k] = min(d);
cls = names{k};
d2 = min(d(setdiff(1:numel(d), k)));
margin = d2 - ds1;
if     margin > 1.2, conf = 'high';
elseif margin > 0.5, conf = 'med';
else,                conf = 'low';
end
end
