function results = aeris_scope_sim3d(p)
% AERIS_SCOPE_SIM3D  Multi-target C-UAS scope with a live 3-D volume view.
%
%   aeris_scope_sim3d                            % deterministic baseline
%   aeris_scope_sim3d(aeris_params('random'))    % fresh random raid, logged
%   aeris_scope_sim3d(aeris_params('swarm'))     % small/low/fast swarm
%
%   p = aeris_params('random'); p.randNDrones = [3 6]; aeris_scope_sim3d(p)
%
% Five live panels: PPI, range-Doppler, 3-D volume (spans the right column),
% A-scope, and status. Handles an arbitrary number of simultaneous drones.
%
% RANDOMISED RAIDS
%   With p.randomThreats = true, every run draws a new raid - drone count,
%   RCS (log-uniform, micro-quad to Group 2), altitude, speed, formation
%   (single / line / trail / wedge / echelon / swarm) and course. Set
%   p.rngSeed = 'shuffle' so runs differ; set an integer to replay one exactly.
%   The seed actually used is printed and logged, so any run is reproducible.
%
% DATA CAPTURE
%   With p.logData = true every run appends one row per drone to
%   matlab/matlab_out/aeris_runs.csv. Run it as many times as you like and the
%   file accumulates. Read it back with:
%       Tbl = readtable('matlab_out/aeris_runs.csv');
%       scatter(Tbl.rcs_m2, Tbl.warn_time_s); set(gca,'XScale','log')
%
% PHYSICS lives in +aeris/ and is shared with aeris_scope_sim - the two cannot
% drift. Only display code is local to this file.
%
% See also AERIS_SCOPE_SIM, AERIS_PARAMS, AERIS.SPAWN_THREATS, AERIS.LOG_RUN.

if nargin < 1 || isempty(p), p = aeris_params(); end

% ---- defaults so older param structs still work -------------------------
p = default_field(p, 'targetAlt',     0);
p = default_field(p, 'elevBeamOn',    false);
p = default_field(p, 'elevBore',      0);
p = default_field(p, 'randomThreats', false);
p = default_field(p, 'logData',       false);
p = default_field(p, 'headless',      false);
p = default_field(p, 'quiet',         false);

showUI = ~p.headless;
if ~showUI, p.saveVideo = false; end       % nothing to capture
setappdata(0, 'AERIS_STOP', false);        % cleared by the Stop button

% ---- seed (integer replays; 'shuffle' gives a fresh raid) ---------------
if ischar(p.rngSeed) || isstring(p.rngSeed)
    rng(char(p.rngSeed));
    s = rng; usedSeed = s.Seed;
else
    rng(p.rngSeed); usedSeed = p.rngSeed;
end

g = aeris.derive(p);

% ---- the raid -----------------------------------------------------------
T  = aeris.spawn_threats(p);
nT = numel(T);
p.lastFormation = infer_formation(T);

% say immediately what was drawn - before the graphics build, so a raid that
% is not the size you expected is obvious straight away
if p.quiet
    % nothing
elseif p.randomThreats
    fprintf('raid: %d drone(s), %s formation, seed %s\n', ...
            nT, p.lastFormation, num2str(usedSeed));
    fprintf('  RCS %.4g–%.4g m^2 | alt %.0f–%.0f m | speed %.0f–%.0f m/s\n', ...
        min([T.rcs]), max([T.rcs]), min([T.alt0]), max([T.alt0]), ...
        min([T.spd]), max([T.spd]));
else
    fprintf(['single deterministic target (RCS %.4g m^2, %.0f m/s).\n' ...
             '  For randomised raids: aeris_scope_sim3d(aeris_params(''random''))\n' ...
             '  or set p.randomThreats = true (and p.nDrones = N for an exact count).\n'], ...
             p.targetRCS, p.Vc);
end

% ---- range-Doppler axes -------------------------------------------------
rangeAxis = (0:g.dR:p.Rmax).';      nR = numel(rangeAxis);
velAxis   = linspace(-g.vUnamb, g.vUnamb, p.nDoppler);
nD        = p.nDoppler;

% ---- array pattern ------------------------------------------------------
azGrid = -90:0.5:90;
patLin = aeris.beam_pattern(azGrid, p, g);

% ---- geometry -----------------------------------------------------------
Pdef = [-p.Dforward, 0, 0];
gdist = zeros(1,nT); ftime = zeros(1,nT);
for i = 1:nT
    gdist(i) = norm(Pdef(1:2) - T(i).p0(1:2));
    ftime(i) = gdist(i) / T(i).spd;
end
nFrames = min(p.maxFrames, ceil(max(ftime) / p.frameDt));

% ---- CFAR + clutter (frame-invariant: build once) -----------------------
cf = aeris.cfar_init(p, nR, nD);
Wdwell = aeris.dwell_plan(p, g);        % elevation bars for aeris.elev_gain
if p.clutterOn
    Cridge = aeris.clutter_ridge(rangeAxis, velAxis, p, g);
else
    Cridge = 0;
end

% ---- per-drone reliable range (depends on that drone's RCS) -------------
relRange = zeros(1,nT);
for i = 1:nT
    pi_ = p; pi_.targetRCS = T(i).rcs;
    relRange(i) = aeris.reliable_range(pi_, g);
end

% ---- video --------------------------------------------------------------
vw = [];
if p.saveVideo
    vfile = 'aeris_scope3d.mp4';
    if isfield(p,'videoFile3d'), vfile = p.videoFile3d; end
    try
        vw = VideoWriter(vfile, 'MPEG-4'); vw.FrameRate = p.fps; open(vw);
    catch
        vw = VideoWriter(erase(vfile,'.mp4'), 'Motion JPEG AVI');
        vw.FrameRate = p.fps; open(vw);
    end
end

% ========================================================================
% BUILD ALL GRAPHICS ONCE (then only update data in the loop)
% ========================================================================
h = struct(); fig = [];
if showUI
% reuse the same window across runs instead of piling up figures
figTag = 'AERIS_SCOPE3D';
fig = findobj(0, 'Type','figure', 'Tag',figTag);
if isempty(fig)
    fig = figure('Color','w','Position',[60 60 1500 860], 'Tag',figTag, ...
                 'Name','AERIS-Nexus scope', 'NumberTitle','off', ...
                 'Renderer','opengl','GraphicsSmoothing','on');
else
    fig = fig(1); clf(fig); figure(fig);
end
tl  = tiledlayout(fig, 2, 3, 'TileSpacing','compact','Padding','compact');

% control-panel launcher + stop, docked in the figure corner
uicontrol(fig,'Style','pushbutton','String','Controls','Units','normalized', ...
    'Position',[0.004 0.963 0.052 0.031],'Callback',@(~,~) aeris_gui());
uicontrol(fig,'Style','pushbutton','String','Stop','Units','normalized', ...
    'Position',[0.058 0.963 0.038 0.031],'BackgroundColor',[.95 .85 .85], ...
    'Callback',@(~,~) setappdata(0,'AERIS_STOP',true));

allAlt = [T.alt0];
zMax   = max(400, 1.5*max(allAlt));
th     = linspace(-pi,pi,200);

% ---- (1) PPI ------------------------------------------------------------
ax1 = nexttile(tl,1); hold(ax1,'on'); axis(ax1,'equal');
draw_sector(ax1, p);
for rr = 1000:1000:p.Rmax
    plot(ax1, rr*cos(th), rr*sin(th), ':', 'Color',[.8 .8 .8]);
end
h.beam  = plot(ax1,[0 0],[0 0],'-','Color',[.2 .5 .9 .5],'LineWidth',6);
h.trail = plot(ax1, nan, nan, '-', 'Color',[.6 .6 .6]);
h.tgt   = plot(ax1, nan, nan, 'o','MarkerSize',7, ...
               'MarkerFaceColor',[.9 .3 .2],'MarkerEdgeColor','k','LineStyle','none');
h.det   = plot(ax1, nan, nan, 'gs','MarkerSize',12,'LineWidth',1.6,'LineStyle','none');
plot(ax1, 0,0,'^','MarkerSize',12,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1.5);
plot(ax1, Pdef(1),Pdef(2),'p','MarkerSize',16,'MarkerFaceColor',[.29 .23 .65],'MarkerEdgeColor','w');
text(ax1, Pdef(1), Pdef(2)-500, 'defended pt','HorizontalAlignment','center','FontSize',8);
xlim(ax1,[-p.Dforward-500, p.Rmax+500]); ylim(ax1,[-p.Rmax-500, p.Rmax+500]);
xlabel(ax1,'x (m) — toward threat'); ylabel(ax1,'y (m)');
h.ppiTitle = title(ax1,'PPI','FontWeight','normal');
xl = xlim(ax1); yl = ylim(ax1);
h.banner = text(ax1, xl(1)+diff(xl)*0.03, yl(2)-diff(yl)*0.06, 'WARNING: pending', ...
    'Color',[.6 .6 .6],'FontWeight','bold','FontSize',11,'BackgroundColor','w','Margin',3);

% ---- (2) range-Doppler --------------------------------------------------
ax2 = nexttile(tl,2);
h.rd = imagesc(ax2, velAxis, rangeAxis/1000, zeros(nR,nD));
set(ax2,'YDir','normal'); colormap(ax2, turbo_safe()); set_clim(ax2,[-10 45]);
cb = colorbar(ax2); cb.Label.String = 'power (dB)';
hold(ax2,'on');
h.rdDet  = plot(ax2, nan, nan, 'w.','MarkerSize',4,'LineStyle','none');
h.rdTrue = plot(ax2, nan, nan, 'wo','MarkerSize',10,'LineWidth',1.3,'LineStyle','none');
xlabel(ax2,'radial velocity (m/s)'); ylabel(ax2,'range (km)');
h.rdTitle = title(ax2,'range-Doppler','FontWeight','normal');

% ---- (3) 3-D volume (spans both rows of column 3) -----------------------
ax3d = nexttile(tl,3,[2 1]); hold(ax3d,'on'); grid(ax3d,'on'); box(ax3d,'on');
draw_sector3(ax3d, p, zMax);
for rr = 1000:1000:p.Rmax
    plot3(ax3d, rr*cos(th), rr*sin(th), zeros(size(th)), ':', 'Color',[.85 .85 .85]);
end
plot3(ax3d, 0,0,0,'^','MarkerSize',11,'MarkerFaceColor','w','MarkerEdgeColor','k','LineWidth',1.5);
plot3(ax3d, Pdef(1),Pdef(2),0,'p','MarkerSize',16,'MarkerFaceColor',[.29 .23 .65],'MarkerEdgeColor','w');
h.trail3 = plot3(ax3d, nan, nan, nan, '-','Color',[.6 .6 .6],'LineWidth',1);
h.gshadow= plot3(ax3d, nan, nan, nan, '-','Color',[.86 .86 .86],'LineWidth',1);
h.drop   = plot3(ax3d, nan, nan, nan, '-','Color',[.72 .72 .72],'LineWidth',0.8);
h.tgt3   = plot3(ax3d, nan, nan, nan, 'o','MarkerSize',7, ...
                 'MarkerFaceColor',[.9 .3 .2],'MarkerEdgeColor','k','LineStyle','none');
h.det3   = plot3(ax3d, nan, nan, nan, 'gs','MarkerSize',13,'LineWidth',1.6,'LineStyle','none');
xlim(ax3d,[-p.Dforward-500, p.Rmax+500]); ylim(ax3d,[-p.Rmax-500, p.Rmax+500]);
zlim(ax3d,[0 zMax]);
xlabel(ax3d,'x (m)'); ylabel(ax3d,'y (m)'); zlabel(ax3d,'altitude (m)');
view(ax3d, -37.5, 26); camproj(ax3d,'perspective');
% no daspect: default stretch-to-fill exaggerates altitude, which is what you
% want when the volume is 11 km wide and a few hundred m tall
h.ax3title = title(ax3d,'3-D volume','FontWeight','normal');

% ---- (4) A-scope --------------------------------------------------------
ax4 = nexttile(tl,4); hold(ax4,'on');
h.aData = plot(ax4, rangeAxis/1000, nan(nR,1), '-','Color',[.2 .5 .9]);
h.aThr  = plot(ax4, rangeAxis/1000, nan(nR,1), '--','Color',[.9 .3 .2]);
h.aX    = xline(ax4, 0, ':','Color',[.1 .1 .1]);
xlabel(ax4,'range (km)'); ylabel(ax4,'power (dB)');
xlim(ax4,[0 p.Rmax/1000]); ylim(ax4,[-20 50]);
legend(ax4,[h.aData h.aThr],{'data','CFAR thr'},'Location','northeast','Box','off');
h.aTitle = title(ax4,'A-scope','FontWeight','normal');

% ---- (5) status ---------------------------------------------------------
ax5 = nexttile(tl,5); axis(ax5,'off');
h.status = text(ax5, 0.02, 0.98, '', 'VerticalAlignment','top', ...
                'FontName','FixedWidth','FontSize',9,'Interpreter','tex');
title(ax5,'status','FontWeight','normal');

h.sg = sgtitle(fig, sprintf('AERIS-Nexus  |  %s raid, %d drone(s)  |  seed %s', ...
    p.lastFormation, nT, num2str(usedSeed)), 'FontSize', 11);
end  % showUI

% ---- state --------------------------------------------------------------
detHist  = false(nT, nFrames);
confirmed= false(1,nT);
tConfirm = nan(1,nT);  warnT = nan(1,nT);
minRange = inf(1,nT);  detCount = zeros(1,nT);
alive    = true(1,nT);
trail    = nan(nFrames, 3, nT);
M = p.MofN(1); N = p.MofN(2);
firstConfirm = NaN; raidWarn = NaN;

% ========================================================================
% MAIN LOOP
% ========================================================================
for f = 1:nFrames
    t = (f-1) * p.frameDt;

    pos = nan(nT,3); Rv = nan(1,nT); azv = nan(1,nT);
    elv = nan(1,nT); vrv = nan(1,nT); snrv = zeros(1,nT); ttg = nan(1,nT);

    for i = 1:nT
        if ~alive(i), continue; end
        gp   = T(i).p0(1:2) + T(i).spd * t * T(i).u(1:2);
        frac = min(1, (T(i).spd*t)/gdist(i));
        alt  = max(5, T(i).alt0 * (1 - T(i).descent*frac));
        Pt   = [gp, alt];
        if dot(Pt(1:2)-Pdef(1:2), T(i).u(1:2)) >= 0
            alive(i) = false; continue;              % passed the defended point
        end
        pos(i,:)   = Pt;
        trail(f,:,i) = Pt;

        Rv(i)  = norm(Pt);
        azv(i) = atan2d(Pt(2), Pt(1));
        elv(i) = atan2d(Pt(3), hypot(Pt(1),Pt(2)));
        vrv(i) = dot(Pt, T(i).spd*T(i).u) / Rv(i);
        ttg(i) = norm(Pt(1:2)-Pdef(1:2)) / T(i).spd;
        minRange(i) = min(minRange(i), Rv(i));

        inSec = abs(aeris.wrap180(azv(i) - p.boresight)) <= p.sectorWidth/2;
        wBeam = interp1(azGrid, patLin, ...
                        aeris.wrap180(azv(i) - beamAzNearest(azv(i),p)), 'linear', 0)^2;
        if p.elevBeamOn
            % nearest ELEVATION BAR from the scan schedule, not a fixed beam
            wBeam = wBeam * aeris.elev_gain(p, g, elv(i), Wdwell);
        end

        pi_ = p; pi_.targetRCS = T(i).rcs;           % per-drone RCS
        snrv(i) = aeris.snr(pi_, g, Rv(i), inSec * wBeam);
    end

    if ~any(alive), nFrames = f-1; break; end

    % ---- range-Doppler map: noise + clutter + every live target --------
    P = -log(rand(nR, nD)) + Cridge;
    ri = nan(1,nT); di = nan(1,nT);
    for i = 1:nT
        if ~alive(i) || snrv(i) <= 0, continue; end
        [~, ri(i)] = min(abs(rangeAxis - Rv(i)));
        [~, di(i)] = min(abs(velAxis  - vrv(i)));
        P = aeris.add_target(P, ri(i), di(i), snrv(i) * -log(rand));  % Swerling-1
    end

    % ---- CFAR (one pass over the whole map) ----------------------------
    [detMask, thresh] = aeris.cfar(P, cf);

    for i = 1:nT
        if ~alive(i) || snrv(i) <= 0, continue; end
        rW = abs((1:nR)'-ri(i)) <= 2; dW = abs((1:nD)-di(i)) <= 3;
        d  = any(any(detMask(rW, dW)));
        detHist(i,f) = d;
        detCount(i)  = detCount(i) + d;
        if ~confirmed(i) && f >= N && sum(detHist(i, max(1,f-N+1):f)) >= M
            confirmed(i) = true; tConfirm(i) = t;
            warnT(i) = ttg(i) - p.latency;
            if isnan(firstConfirm)
                firstConfirm = t; raidWarn = warnT(i);
            end
        end
    end

    % ---- beam ----------------------------------------------------------
    beamAz = p.boresight - p.sectorWidth/2 + mod(f-1,8)/7 * p.sectorWidth;
    if any(confirmed)
        k = find(confirmed & alive, 1);
        if ~isempty(k), beamAz = azv(k); end
    end

    % ================= UPDATE DISPLAY ===================================
    if ~showUI, continue; end                 % headless: skip all drawing

    liveIdx = find(alive & ~isnan(Rv));
    detIdx  = liveIdx(detHist(liveIdx, f));

    bl = p.Rmax*[cosd(beamAz) sind(beamAz)];
    set(h.beam,'XData',[0 bl(1)],'YData',[0 bl(2)]);
    [tx,ty,tz] = trails_nan(trail, f, nT);
    set(h.trail, 'XData',tx, 'YData',ty);
    set(h.tgt,   'XData',pos(liveIdx,1), 'YData',pos(liveIdx,2));
    set(h.det,   'XData',pos(detIdx,1),  'YData',pos(detIdx,2));
    h.ppiTitle.String = sprintf('PPI  t=%.0fs   %d/%d confirmed', ...
                                t, sum(confirmed), nT);
    update_banner(h.banner, any(confirmed), raidWarn, p);

    set(h.rd, 'CData', 10*log10(P));
    [dr,dd] = find(detMask);
    set(h.rdDet, 'XData',velAxis(dd), 'YData',rangeAxis(dr)/1000);
    set(h.rdTrue,'XData',vrv(liveIdx), 'YData',Rv(liveIdx)/1000);
    h.rdTitle.String = sprintf('range-Doppler   peak SNR=%.0f dB', ...
                               10*log10(max(max(snrv),1e-3)));

    set(h.trail3, 'XData',tx,'YData',ty,'ZData',tz);
    set(h.gshadow,'XData',tx,'YData',ty,'ZData',zeros(size(tz)));
    [dx,dy,dz] = droplines(pos, liveIdx);
    set(h.drop, 'XData',dx,'YData',dy,'ZData',dz);
    set(h.tgt3, 'XData',pos(liveIdx,1),'YData',pos(liveIdx,2),'ZData',pos(liveIdx,3));
    set(h.det3, 'XData',pos(detIdx,1), 'YData',pos(detIdx,2), 'ZData',pos(detIdx,3));
    h.ax3title.String = sprintf('3-D volume   alt %.0f–%.0f m', ...
        min(pos(liveIdx,3)), max(pos(liveIdx,3)));

    % A-scope follows the strongest live target
    [~, kk] = max(snrv);
    if ~isnan(di(kk)) && snrv(kk) > 0
        set(h.aData,'YData',10*log10(P(:,di(kk))));
        set(h.aThr, 'YData',10*log10(max(thresh(:,di(kk)),1e-12)));
        h.aX.Value = max(Rv(kk)/1000, 1e-3);
        h.aTitle.String = sprintf('A-scope @ %.0f m/s (%s)', vrv(kk), T(kk).label);
    end

    h.status.String = status_lines(t, T, Rv, snrv, elv, detHist(:,f), ...
                                   confirmed, ttg, raidWarn, alive, p);

    if isempty(vw)
        drawnow limitrate
    else
        drawnow
        writeVideo(vw, getframe(fig));
    end

    % Stop button - its callback runs during drawnow, setting this flag
    if getappdata(0,'AERIS_STOP')
        fprintf('stopped at t=%.0f s\n', t);
        nFrames = f; break
    end
end
if showUI, drawnow; end

if ~isempty(vw), close(vw); fprintf('Saved video.\n'); end

% ---- results ------------------------------------------------------------
per = struct('detFrames',num2cell(detCount), 'confirmed',num2cell(confirmed), ...
             'tConfirm',num2cell(tConfirm), 'warnTime',num2cell(warnT), ...
             'minRange',num2cell(minRange));
summary = struct('seed',usedSeed, 'firstConfirm',firstConfirm, ...
                 'warnTime',raidWarn, 'requirementMet',raidWarn>=p.Treq, ...
                 'nFrames',nFrames, 'reliableRange',relRange);

% NOTE: T and per are struct ARRAYS - they must be wrapped in cells or
% struct() expands them into a struct array of results.
results = struct('threats',{T}, 'per',{per}, 'formation',p.lastFormation, ...
                 'seed',usedSeed, 'firstConfirm',firstConfirm, ...
                 'warnTime',raidWarn, 'requirementMet',raidWarn>=p.Treq, ...
                 'reliableRange',relRange, 'nFrames',nFrames);

if p.logData
    [lf, rid] = aeris.log_run(p, g, T, per, summary);
    results.runId = rid;  results.logFile = lf;
end

% ---- report -------------------------------------------------------------
if p.quiet, return; end
fprintf('\n--- run %s (%s, %d drone(s), seed %s) ---\n', ...
    ternary(isfield(results,'runId'), get_or(results,'runId','-'), '-'), ...
    p.lastFormation, nT, num2str(usedSeed));
fprintf('%-4s %9s %7s %7s %8s %9s %8s\n', ...
        'id','RCS m^2','alt m','V m/s','relRng m','confirm s','warn s');
for i = 1:nT
    fprintf('%-4s %9.4g %7.0f %7.1f %8.0f %9s %8s\n', T(i).label, T(i).rcs, ...
        T(i).alt0, T(i).spd, relRange(i), ...
        fmt(tConfirm(i)), fmt(warnT(i)));
end
if any(confirmed)
    fprintf('raid warning %.0f s (req %.0f s): %s\n', raidWarn, p.Treq, ...
        ternary(raidWarn>=p.Treq,'MET','NOT MET'));
else
    fprintf('no track ever confirmed — no warning delivered.\n');
end
if p.logData
    fprintf('logged to %s\n', results.logFile);
end
end

% ========================================================================
% display + bookkeeping helpers (physics is in +aeris/)
% ========================================================================
function p = default_field(p, name, val)
if ~isfield(p, name), p.(name) = val; end
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end

function v = get_or(s, f, d)
if isfield(s,f), v = s.(f); else, v = d; end
end

function s = fmt(x)
if isnan(x), s = '--'; else, s = sprintf('%.0f', x); end
end

function f = infer_formation(T)
% the formation actually drawn, carried back on the threat struct
if isfield(T,'formation') && ~isempty(T(1).formation)
    f = T(1).formation;
else
    f = 'single';
end
end

function b = beamAzNearest(az, p)
b = az;
if abs(aeris.wrap180(az - p.boresight)) > p.sectorWidth/2, b = p.boresight; end
end

function set_clim(ax, lims)
try, clim(ax, lims); catch, caxis(ax, lims); end %#ok<CAXIS>
end

function [x,y,z] = trails_nan(trail, f, nT)
% concatenate all drone trails into one NaN-separated polyline (one graphics
% object for the whole raid instead of nT of them)
x = []; y = []; z = [];
for i = 1:nT
    x = [x; trail(1:f,1,i); nan]; %#ok<AGROW>
    y = [y; trail(1:f,2,i); nan]; %#ok<AGROW>
    z = [z; trail(1:f,3,i); nan]; %#ok<AGROW>
end
end

function [x,y,z] = droplines(pos, idx)
x = []; y = []; z = [];
for i = idx(:).'
    x = [x; pos(i,1); pos(i,1); nan]; %#ok<AGROW>
    y = [y; pos(i,2); pos(i,2); nan]; %#ok<AGROW>
    z = [z; 0;        pos(i,3); nan]; %#ok<AGROW>
end
end

function draw_sector(ax, p)
th = linspace(p.boresight-p.sectorWidth/2, p.boresight+p.sectorWidth/2, 60);
xx = [0, p.Rmax*cosd(th), 0]; yy = [0, p.Rmax*sind(th), 0];
fill(ax, xx, yy, [.85 .92 .98], 'EdgeColor',[.5 .6 .7], 'FaceAlpha',.5);
end

function draw_sector3(ax, p, zMax)
% ground sector patch plus a translucent roof, so the wedge reads as a volume
th = linspace(p.boresight-p.sectorWidth/2, p.boresight+p.sectorWidth/2, 60);
xx = [0, p.Rmax*cosd(th), 0]; yy = [0, p.Rmax*sind(th), 0];
patch(ax,'XData',xx,'YData',yy,'ZData',zeros(size(xx)), ...
      'FaceColor',[.85 .92 .98],'EdgeColor',[.5 .6 .7],'FaceAlpha',.45);
patch(ax,'XData',xx,'YData',yy,'ZData',zMax*ones(size(xx)), ...
      'FaceColor',[.85 .92 .98],'EdgeColor','none','FaceAlpha',.12);
for s = [-1 1]
    a  = p.boresight + s*p.sectorWidth/2;
    ex = [0 p.Rmax*cosd(a) p.Rmax*cosd(a) 0];
    ey = [0 p.Rmax*sind(a) p.Rmax*sind(a) 0];
    ez = [0 0 zMax zMax];
    patch(ax,'XData',ex,'YData',ey,'ZData',ez, ...
          'FaceColor',[.7 .8 .9],'EdgeColor',[.6 .7 .8],'FaceAlpha',.10);
end
end

function update_banner(hTxt, confirmed, warnTime, p)
if ~confirmed || isnan(warnTime)
    hTxt.String = 'WARNING: pending'; hTxt.Color = [.6 .6 .6];
else
    met = warnTime >= p.Treq;
    hTxt.String = sprintf('WARNING @ T-%.0fs   (req %.0fs: %s)', ...
        max(warnTime,0), p.Treq, ternary(met,'MET','SHORT'));
    hTxt.Color = ternary(met, [0 .5 0], [.8 .1 .1]);
end
end

function lines = status_lines(t, T, Rv, snrv, elv, detNow, conf, ttg, raidWarn, alive, p)
nT = numel(T);
lines = { sprintf('\\bf t = %.0f s\\rm', t)
          sprintf('%-4s %7s %6s %6s %5s %4s %s','id','RCS','rng km','SNR','el','det','trk') };
for i = 1:nT
    if ~alive(i)
        lines{end+1} = sprintf('%-4s %7.4g %6s %6s %5s %4s %s', ...
            T(i).label, T(i).rcs, '--','--','--','--','past'); %#ok<AGROW>
        continue
    end
    lines{end+1} = sprintf('%-4s %7.4g %6.2f %6.0f %5.1f %4s %s', ...
        T(i).label, T(i).rcs, Rv(i)/1000, 10*log10(max(snrv(i),1e-3)), elv(i), ...
        ternary(detNow(i),'Y','-'), ternary(conf(i),'CONF','...')); %#ok<AGROW>
end
lines{end+1} = '';
lines{end+1} = sprintf('\\bf requirement\\rm  %.0f s', p.Treq);
if ~isnan(raidWarn)
    met = raidWarn >= p.Treq;
    lines{end+1} = sprintf('\\bf delivered\\rm    %.0f s  \\color{%s}%s', ...
        max(raidWarn,0), ternary(met,'green','red'), ternary(met,'MET','NOT MET'));
end
lines{end+1} = sprintf('confirmed     %d of %d', sum(conf), nT);
end

function cm = turbo_safe()
try, cm = turbo(256); catch, cm = jet(256); end
end
