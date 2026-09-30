function cls = classify_track(rcs, spd)
%AERIS.CLASSIFY_TRACK  Live drone/bird/plane call from measured features.
%   cls = aeris.classify_track(rcs, spd)   -> 'drone' | 'bird' | 'plane'
%
%   The operator-console classifier: it decides from what the radar MEASURES
%   (estimated RCS and speed), not from truth, so it carries the real ~15%
%   drone/bird confusion that aeris_discriminate quantified. Planes fall out on
%   RCS; the low-RCS drone/bird split is a soft, error-prone decision - which is
%   the honest operational picture.

if rcs > 0.3                                   % large -> aircraft
    cls = 'plane'; return;
end
% low RCS: drone vs bird. Drones are (mostly) larger and faster, but overlap.
score = 0.6*(log10(max(rcs,1e-4)) - log10(0.01))/0.5 + 0.4*(spd - 15)/15;
pDrone = 0.1 + 0.8/(1 + exp(-score));          % floors keep a ~15% confusion
if rand < pDrone, cls = 'drone'; else, cls = 'bird'; end
end
