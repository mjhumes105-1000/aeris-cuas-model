function results = aeris_scope_sim(p)
% AERIS_SCOPE_SIM  Animated C-UAS radar scope for the AERIS-Nexus node.
%
%   aeris_scope_sim                 % baseline params, shows + records video
%   aeris_scope_sim(aeris_params('micro'))
%   p = aeris_params(); p.Vc = 45; aeris_scope_sim(p)
%
% Simulates one engagement: a Group 1-2 UAS approaches the defended point
% through the node's fixed sector. Each displayed frame is one radar look
% (a full sector scan). The figure shows, live:
%   (1) a top-down PPI  - sector, sweeping beam, range rings, true target,
%       CFAR detections, forming track, and the warning-time clock;
%   (2) the range-Doppler map - thermal noise, the Swerling-fluctuating
%       target return, the zero-Doppler clutter ridge, and CFAR hits;
%   (3) an A-scope       - power vs range at the target Doppler, with the
%       CFAR threshold;
%   (4) a status panel   - range, radial velocity, SNR, track state, and
%       whether the 5-minute requirement is met.
%
% PHYSICS LIVES IN +aeris/ — the radar equation (aeris.snr), Swerling-1 Pd,
% clutter, CFAR and the array pattern are shared with aeris_scope_sim3d so the
% two cannot drift. Only display code is local to this file. The one MATLAB
% file that deliberately does NOT share is aeris_nexus_linkbudget.m, which is
% an independent reimplementation used to cross-check against Python.
%
% See also AERIS_SCOPE_SIM3D, AERIS_PARAMS, AERIS_NEXUS_LINKBUDGET.

if nargin < 1 || isempty(p), p = aeris_params(); end
rng(p.rngSeed);

g = aeris.derive(p);                                  % all derived constants

% ---- range-Doppler axes -------------------------------------------------
rangeAxis = (0:g.dR:p.Rmax).';      nR = numel(rangeAxis);
velAxis   = linspace(-g.vUnamb, g.vUnamb, p.nDoppler);

% ---- array pattern ------------------------------------------------------
azGrid = -90:0.5:90;
patLin = aeris.beam_pattern(azGrid, p, g);            % one-way, normalised

% ---- geometry -----------------------------------------------------------
Pd  = [-p.Dforward, 0];                               % defended point (node frame)
Pt0 = p.startRange * [cosd(p.bearingDeg), sind(p.bearingDeg)];
u   = (Pd - Pt0) / norm(Pd - Pt0);                    % unit inbound heading
flightTime = norm(Pd - Pt0) / p.Vc;
nFrames = min(p.maxFrames, ceil(flightTime / p.frameDt));

% ---- CFAR + clutter (both frame-invariant: build once) ------------------
cf = aeris.cfar_init(p, nR, p.nDoppler);
if p.clutterOn
    Cridge = aeris.clutter_ridge(rangeAxis, velAxis, p, g);
else
    Cridge = 0;
end

% ---- video --------------------------------------------------------------
vw = [];
if p.saveVideo
    try
        vw = VideoWriter(p.videoFile, 'MPEG-4'); vw.FrameRate = p.fps; open(vw);
    catch
        vw = VideoWriter(erase(p.videoFile,'.mp4'), 'Motion JPEG AVI');
        vw.FrameRate = p.fps; open(vw);
    end
end

fig = figure('Color','w','Position',[80 80 1280 820]);
tl = tiledlayout(fig, 2, 2, 'TileSpacing','compact','Padding','compact');

% ---- state --------------------------------------------------------------
detHist = false(1, nFrames);
trackConfirmed = false; tConfirm = NaN; warnTime = NaN;
trail = nan(nFrames, 2);
M = p.MofN(1); N = p.MofN(2);

for f = 1:nFrames
    t   = (f-1) * p.frameDt;
    Pt  = Pt0 + p.Vc * t * u;                          % target position
    if dot(Pt - Pd, u) >= 0, nFrames = f-1; break; end % passed defended point
    trail(f,:) = Pt;
    R   = norm(Pt);
    az  = atan2d(Pt(2), Pt(1));
    vr  = dot(Pt, p.Vc*u) / R;                         % range rate (neg = inbound)
    inSector = abs(aeris.wrap180(az - p.boresight)) <= p.sectorWidth/2;
    timeToGo = norm(Pt - Pd) / p.Vc;

    % beam: sweep across sector for the visual; a full scan covers the target
    beamAz = p.boresight - p.sectorWidth/2 + mod(f-1,8)/7 * p.sectorWidth;
    if trackConfirmed, beamAz = az; end
    wBeam = interp1(azGrid, patLin, aeris.wrap180(az - beamAzNearest(az,p)), 'linear', 0)^2;

    % ---- SNR (shared radar equation) -----------------------------------
    snr = aeris.snr(p, g, R, inSector * wBeam);        % 0 if outside sector

    % ---- range-Doppler map ---------------------------------------------
    P = -log(rand(nR, p.nDoppler)) + Cridge;           % exponential noise, mean 1
    [~, ri] = min(abs(rangeAxis - R));
    [~, di] = min(abs(velAxis - vr));
    if snr > 0
        P = aeris.add_target(P, ri, di, snr * -log(rand));   % Swerling-1
    end

    % ---- CFAR ----------------------------------------------------------
    [detMask, thresh] = aeris.cfar(P, cf);
    % association: any detection within a few cells of the true target cell
    detOnTgt = false;
    if snr > 0
        rW = abs((1:nR)'-ri) <= 2; dW = abs((1:p.nDoppler)-di) <= 3;
        detOnTgt = any(any(detMask(rW, dW)));
    end
    detHist(f) = detOnTgt;

    % ---- track logic ---------------------------------------------------
    if ~trackConfirmed && f >= N && sum(detHist(max(1,f-N+1):f)) >= M
        trackConfirmed = true; tConfirm = t;
        warnTime = timeToGo - p.latency;
    end

    % ================= DISPLAY ==========================================
    % (1) PPI ------------------------------------------------------------
    ax1 = nexttile(tl,1); cla(ax1); hold(ax1,'on'); axis(ax1,'equal');
    draw_sector(ax1, p);
    for rr = 1000:1000:p.Rmax                          % range rings
        th = linspace(-pi,pi,200);
        plot(ax1, rr*cos(th), rr*sin(th), ':', 'Color',[.8 .8 .8]);
    end
    % beam
    bl = p.Rmax*[cosd(beamAz) sind(beamAz)];
    plot(ax1,[0 bl(1)],[0 bl(2)],'-','Color',[.2 .5 .9 .5],'LineWidth',6);
    plot(ax1, trail(1:f,1), trail(1:f,2), '-', 'Color',[.6 .6 .6]);      % truth trail
    plot(ax1, Pt(1), Pt(2), 'o','MarkerSize',9,'MarkerFaceColor',[.9 .3 .2],'MarkerEdgeColor','k');
    plot(ax1, 0,0,'^','MarkerSize',12,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1.5);
    plot(ax1, Pd(1),Pd(2),'p','MarkerSize',16,'MarkerFaceColor',[.29 .23 .65],'MarkerEdgeColor','w');
    text(ax1, Pd(1), Pd(2)-500, 'defended pt','HorizontalAlignment','center','FontSize',8);
    if detOnTgt
        plot(ax1, R*cosd(az), R*sind(az), 'gs','MarkerSize',13,'LineWidth',2);
    end
    ttl = sprintf('PPI  t=%.0fs   %s', t, track_str(trackConfirmed));
    title(ax1, ttl,'FontWeight','normal');
    xlim(ax1,[-p.Dforward-500, p.Rmax+500]); ylim(ax1,[-p.Rmax-500, p.Rmax+500]);
    xlabel(ax1,'x (m) — toward threat'); ylabel(ax1,'y (m)'); grid(ax1,'off');
    warn_banner(ax1, trackConfirmed, warnTime, p);

    % (2) range-Doppler --------------------------------------------------
    ax2 = nexttile(tl,2); cla(ax2);
    imagesc(ax2, velAxis, rangeAxis/1000, 10*log10(P)); set(ax2,'YDir','normal');
    colormap(ax2, turbo_safe()); caxis(ax2, [-10 45]);   % fixed scale -> stable frames
    if f==1, cb=colorbar(ax2); cb.Label.String='power (dB)'; end
    hold(ax2,'on');
    [dr,dd] = find(detMask);
    plot(ax2, velAxis(dd), rangeAxis(dr)/1000, 'w.','MarkerSize',4);
    if snr>0, plot(ax2, vr, R/1000, 'wo','MarkerSize',12,'LineWidth',1.5); end
    xlabel(ax2,'radial velocity (m/s)'); ylabel(ax2,'range (km)');
    title(ax2, sprintf('range-Doppler   SNR=%.0f dB', 10*log10(max(snr,1e-3))),'FontWeight','normal');

    % (3) A-scope --------------------------------------------------------
    ax3 = nexttile(tl,3); cla(ax3); hold(ax3,'on');
    col = P(:, di);
    plot(ax3, rangeAxis/1000, 10*log10(col), '-','Color',[.2 .5 .9]);
    plot(ax3, rangeAxis/1000, 10*log10(thresh(:,di)), '--','Color',[.9 .3 .2]);
    if snr>0, xline(ax3, R/1000, ':','Color',[.1 .1 .1]); end
    xlabel(ax3,'range (km)'); ylabel(ax3,'power (dB)');
    title(ax3, sprintf('A-scope @ %.0f m/s  (blue=data, red=CFAR threshold)', vr),'FontWeight','normal');
    legend(ax3,{'data','CFAR thr'},'Location','northeast','Box','off');

    % (4) status ---------------------------------------------------------
    ax4 = nexttile(tl,4); cla(ax4); axis(ax4,'off');
    status_panel(ax4, t, R, vr, snr, az, inSector, detOnTgt, trackConfirmed, ...
                 timeToGo, warnTime, p);

    sgtitle(fig, sprintf('AERIS-Nexus C-UAS scope  |  RCS %.3g m^2  |  V_c %.0f m/s  |  reliable range set by physics', ...
        p.targetRCS, p.Vc), 'FontSize', 11);
    drawnow;
    if ~isempty(vw), writeVideo(vw, getframe(fig)); end
end

if ~isempty(vw), close(vw); fprintf('Saved video: %s\n', p.videoFile); end

results = struct('trackConfirmed',trackConfirmed,'tConfirm',tConfirm, ...
    'warnTime',warnTime,'requirementMet',warnTime>=p.Treq, ...
    'reliableRange',aeris.reliable_range(p, g), ...
    'nFrames',nFrames);
fprintf('\n--- result ---\n');
fprintf('reliable range (Pd=%.2f, RCS %.3g): %.0f m\n', p.pdReliable, p.targetRCS, results.reliableRange);
if trackConfirmed
    fprintf('track confirmed at t=%.0fs, warning time %.0f s (req %.0f s): %s\n', ...
        tConfirm, warnTime, p.Treq, ternary(results.requirementMet,'MET','NOT MET'));
else
    fprintf('track never confirmed — no warning delivered.\n');
end
end

% ========================================================================
% display helpers (presentation only - physics is in +aeris/)
% ========================================================================
function s = ternary(c,a,b), if c, s=a; else, s=b; end, end

function s = track_str(c)
if c, s = 'TRACK CONFIRMED'; else, s = 'searching...'; end
end

function b = beamAzNearest(az, p)
% nearest scan-beam azimuth to the target (full-scan assumption -> ~on target)
b = az;  % a full sector scan each look places a beam on the target
if abs(aeris.wrap180(az - p.boresight)) > p.sectorWidth/2, b = p.boresight; end
end

function draw_sector(ax, p)
th = linspace(p.boresight-p.sectorWidth/2, p.boresight+p.sectorWidth/2, 60);
xx = [0, p.Rmax*cosd(th), 0]; yy = [0, p.Rmax*sind(th), 0];
fill(ax, xx, yy, [.85 .92 .98], 'EdgeColor',[.5 .6 .7], 'FaceAlpha',.5);
end

function warn_banner(ax, confirmed, warnTime, p)
if ~confirmed
    txt = 'WARNING: pending'; col = [.6 .6 .6];
else
    met = warnTime >= p.Treq;
    txt = sprintf('WARNING @ T-%.0fs   (req %.0fs: %s)', max(warnTime,0), p.Treq, ...
        ternary(met,'MET','SHORT'));
    col = ternary(met, [0 .5 0], [.8 .1 .1]);
end
xl=xlim(ax); yl=ylim(ax);
text(ax, xl(1)+diff(xl)*0.03, yl(2)-diff(yl)*0.06, txt, 'Color',col, ...
     'FontWeight','bold','FontSize',11,'BackgroundColor','w','Margin',3);
end

function status_panel(ax, t, R, vr, snr, az, inSector, det, conf, ttg, warnTime, p)
lines = {
    sprintf('\\bf time\\rm            %.0f s', t)
    sprintf('\\bf target range\\rm    %.0f m', R)
    sprintf('\\bf radial velocity\\rm %+.1f m/s', vr)
    sprintf('\\bf integrated SNR\\rm  %.0f dB', 10*log10(max(snr,1e-3)))
    sprintf('\\bf bearing\\rm         %+.0f deg  (%s)', az, ternary(inSector,'in sector','OUT'))
    sprintf('\\bf detection\\rm       %s', ternary(det,'YES','--'))
    sprintf('\\bf track\\rm           %s', ternary(conf,'CONFIRMED','searching'))
    sprintf('\\bf time-to-go\\rm      %.0f s', ttg)
    ''
    sprintf('\\bf requirement\\rm     %.0f s warning', p.Treq)
};
if conf
    met = warnTime>=p.Treq;
    lines{end+1} = sprintf('\\bf delivered\\rm       %.0f s  \\color{%s}%s', ...
        max(warnTime,0), ternary(met,'green','red'), ternary(met,'MET','NOT MET'));
end
text(ax, 0.02, 0.98, lines, 'VerticalAlignment','top','FontName','FixedWidth', ...
     'FontSize',11,'Interpreter','tex');
title(ax,'status','FontWeight','normal');
end

function cm = turbo_safe()
try, cm = turbo(256); catch, cm = jet(256); end
end
