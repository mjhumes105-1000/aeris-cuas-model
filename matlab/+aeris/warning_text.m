function s = warning_text(w, units)
%AERIS.WARNING_TEXT  Render one warning as the alert a unit would see.
%   s = aeris.warning_text(w)             % imperial (operator default)
%   s = aeris.warning_text(w, 'si')       % metric (analyst)
%
%   w is one element of aeris.warning_report output. The warning STRUCT is
%   always SI (canonical, hardware-agnostic); this renderer localises to the
%   operator's units. Operators here are trained on feet, miles and mph, so
%   imperial is the default - range in miles, altitude in feet, closure in mph.
%   Time stays in seconds (universal, and it is what the 300 s requirement uses).
%
%   Example (imperial):
%     *** ALERT - CUE EFFECTOR ***  hostile UAS  [T3]
%       bearing 042  range 1.5 mi  alt 394 ft  inbound 63 mph
%       ETA 118 s to defended point   (warning 99 s - SHORT of 300 s)
%       class small_quad (med conf)   held by 2 node(s)

if nargin < 2 || isempty(units), units = 'imperial'; end
imperial = ~strcmpi(units,'si');

if imperial
    rngStr = mi_str(w.rangeM);
    altStr = sprintf('%.0f ft', w.altM * 3.28084);
    kt = @(v) sprintf('%.0f kt', v * 1.943844);       % knots for everyone
else
    rngStr = sprintf('%.1f km', w.rangeM/1000);
    altStr = sprintf('%.0f m', w.altM);
    kt = @(v) sprintf('%.0f kt', v * 1.943844);
end

crsStr = '---'; if isfield(w,'courseDeg') && ~isnan(w.courseDeg), crsStr = sprintf('%03.0f', w.courseDeg); end
spdStr = kt(0);  if isfield(w,'speedMps'), spdStr = kt(w.speedMps); end

reqS = 300; if isfield(w,'reqS') && ~isempty(w.reqS), reqS = w.reqS; end
hdr = sprintf('*** %s ***  hostile UAS  [%s]', w.action, w.id);
l2  = sprintf('  bearing %03.0f  range %s  alt %s', ...
              mod(w.bearingDeg,360), rngStr, altStr);
lv  = sprintf('  course %s  speed %s  (closing %s)', crsStr, spdStr, kt(w.closureMps));
req = ternary(w.meetsReq, ['MEETS ' mmss(reqS)], ['SHORT of ' mmss(reqS)]);
l3  = sprintf('  ETA %s to defended point   (warning %s - %s)', ...
              mmss(w.etaS), mmss(max(w.warnS,0)), req);
l4  = sprintf('  class %s (%s conf)   held by %d node(s)', ...
              w.classEst, w.classConf, w.nNodes);
if isfield(w,'latDeg') && ~isempty(w.latDeg) && ~isnan(w.latDeg)
    l5 = sprintf('  posit %.5f, %.5f', w.latDeg, w.lonDeg);
    s  = sprintf('%s\n%s\n%s\n%s\n%s\n%s', hdr, l2, lv, l3, l4, l5);
else
    s  = sprintf('%s\n%s\n%s\n%s\n%s', hdr, l2, lv, l3, l4);
end
end

function s = mi_str(m)
% miles, but feet when danger-close (under ~0.2 mi), which is where a ground
% unit stops thinking in miles
mi = m / 1609.344;
if mi < 0.19
    s = sprintf('%.0f ft', m * 3.28084);
elseif mi < 1
    s = sprintf('%.2f mi', mi);
else
    s = sprintf('%.1f mi', mi);
end
end

function s = mmss(sec)
% seconds -> M:SS (e.g. 118 -> '1:58', 300 -> '5:00')
sec = max(round(sec), 0);
s = sprintf('%d:%02d', floor(sec/60), mod(sec,60));
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
