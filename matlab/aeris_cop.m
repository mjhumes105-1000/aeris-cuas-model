function aeris_cop(p)
% AERIS_COP  Operator common operating picture - tracked, georeferenced, clean.
%
%   aeris_cop                                   % 3-node line, random raid
%   p = aeris_params('random'); p.nNodes = 4; p.nodeLayout = 'grid';
%   aeris_cop(p)
%
% The operator surface. A real multi-target tracker (aeris.track_step) turns
% node detections into smoothed ESTIMATES with uncertainty, so the picture
% shows what the system actually knows - a track symbol, a heading, and a
% cross-range uncertainty ellipse - not ground truth. The warning feed
% (bearing/range/ETA/class/action, imperial, mm:ss) is computed from the
% estimate, and carries a lat/lon posit when a site datum is set (p.refLat).
%
% Design intent: dead simple to read at a glance. Dark scope, few colours, big
% type, one idea per element. Green = monitoring, amber = cue the effector,
% red = imminent. Truth is drawn as a faint ghost for validation only
% (p.showTruth, default true); turn it off for the operator view.
%
% Physics and detection are the shared +aeris kernel - identical to the sweep.
%
% See also AERIS.TRACK_STEP, AERIS.WARNING_REPORT, AERIS.SIM2LL, AERIS_ENGAGE.

if nargin < 1 || isempty(p)
    p = aeris_params('random'); p.nNodes = 3; p.nodeLayout = 'line';
end
p = df(p,'nNodes',1); p = df(p,'elevBeamOn',false); p = df(p,'units','imperial');
p = df(p,'showTruth',true);
p = df(p,'trackQ',3); p = df(p,'trackGate',11.8); p = df(p,'trackConfirm',3);
p = df(p,'trackMaxMiss',3); p = df(p,'trackV0',40);
p = df(p,'mapView',false); p = df(p,'basemap','satellite');
p = df(p,'leadTime',30);   % s, velocity-leader projection ahead of each track
p = df(p,'terrainOn',false); p = df(p,'mastHeight',3);
if ischar(p.rngSeed)||isstring(p.rngSeed), rng(char(p.rngSeed)); else, rng(p.rngSeed); end

if p.mapView && (~isfield(p,'refLat')||isempty(p.refLat))
    error('aeris:cop:noGeo', ['mapView needs a site datum. Set p.refLat, ' ...
        'p.refLon and p.threatBearing (see aeris.sim2ll), then retry.']);
end

if strcmpi(p.units,'si'), U = 1000; ulab='km'; ring=1000; else, U=1609.344; ulab='mi'; ring=1609.344; end

g     = aeris.derive(p);
T     = aeris.spawn_threats(p);   nT = numel(T);
% mixed drone/bird/plane stream so the live classifier has something to call
p = df(p,'mixedClasses',true);
if p.mixedClasses
    TC = aeris.target_classes(); cw = [6 3 1]; cc = cumsum(cw)/sum(cw);
    for i = 1:nT
        c = find(rand<=cc,1);
        T(i).rcs  = exp(log(TC(c).rcs(1)) + rand*(log(TC(c).rcs(2))-log(TC(c).rcs(1))));
        T(i).spd  = TC(c).spd(1) + rand*(TC(c).spd(2)-TC(c).spd(1));
        T(i).alt0 = TC(c).alt(1) + rand*(TC(c).alt(2)-TC(c).alt(1));
    end
end
nodes = aeris.node_layout(p);     nN = numel(nodes);
Pdef  = [-p.Dforward, 0, 0];
link  = aeris.comms(nodes, p);    % network connectivity (for the picture)

rangeAxis = (0:g.dR:p.Rmax).';  nR = numel(rangeAxis);
velAxis   = linspace(-g.vUnamb, g.vUnamb, p.nDoppler);  nD = p.nDoppler;
cf     = aeris.cfar_init(p, nR, nD);
Wdwell = aeris.dwell_plan(p, g);
if p.clutterOn, Cridge = aeris.clutter_ridge(rangeAxis, velAxis, p, g); else, Cridge = 0; end

gdist = arrayfun(@(i) norm(Pdef(1:2)-T(i).p0(1:2)), 1:nT);
ftime = gdist ./ [T.spd];
nFrames = min(p.maxFrames, ceil(max(ftime)/p.frameDt));

cfg = struct('q',p.trackQ,'gate',p.trackGate,'confirmHits',p.trackConfirm, ...
             'maxMiss',p.trackMaxMiss,'v0',p.trackV0);
tr = []; nextId = 1;

% ---- figure -------------------------------------------------------------
fig = figure('Color',[.05 .06 .08],'Position',[60 60 1460 820], ...
             'Name','AERIS-Nexus','NumberTitle','off');
if p.mapView
    % geoaxes (map) + feed, positioned manually - geoaxes and tiledlayout
    % do not always compose cleanly across versions
    try
        axC = geoaxes(fig,'Position',[0.03 0.06 0.63 0.90]);
        geobasemap(axC, p.basemap);
    catch ME
        close(fig);
        error('aeris:cop:noMapping', ['Could not create a map view (%s). ' ...
            'mapView needs the Mapping Toolbox; use the synthetic scope ' ...
            '(p.mapView=false) otherwise.'], ME.message);
    end
    axF = axes(fig,'Position',[0.69 0.06 0.29 0.90]);
    setup_geolimits(axC, p, U);   %#ok<NASGU>  % U unused in geo, kept for parity
else
    tl = tiledlayout(fig,1,3,'TileSpacing','compact','Padding','compact');
    axC = nexttile(tl,[1 2]); axF = nexttile(tl,1);
end

vw = [];
if isfield(p,'copVideo') && ~isempty(p.copVideo)
    try, vw = VideoWriter(p.copVideo,'MPEG-4'); vw.FrameRate=max(5,p.fps); open(vw); catch, vw=[]; end
end

for f = 1:nFrames
    t = (f-1)*p.frameDt;

    % ---- propagate truth ------------------------------------------------
    pos = nan(nT,3); alv = false(1,nT);
    for i = 1:nT
        gp = T(i).p0(1:2) + T(i).spd*t*T(i).u(1:2);
        frac = min(1,(T(i).spd*t)/gdist(i));
        alt = max(5, T(i).alt0*(1 - T(i).descent*frac));
        Pt = [gp, alt];
        if dot(Pt(1:2)-Pdef(1:2), T(i).u(1:2)) < 0, pos(i,:)=Pt; alv(i)=true; end
    end
    if ~any(alv), break; end

    % ---- each node looks; collect measurements --------------------------
    Z = zeros(2,0); Rc = zeros(2,2,0); mAlt = []; mRcs = [];
    for nn = 1:nN
        snrv=[]; riv=[]; div=[]; idxv=[];
        for i = find(alv)
            rel = pos(i,:) - nodes(nn).pos; R = norm(rel);
            if R > p.Rmax, continue; end
            az = atan2d(rel(2),rel(1)); aoff = aeris.wrap180(az - nodes(nn).bore);
            if abs(aoff) > p.sectorWidth/2 + 2.5*g.azBW, continue; end
            if p.terrainOn
                nz = aeris.terrain_height(nodes(nn).pos(1), nodes(nn).pos(2), p) + p.mastHeight;
                if ~aeris.los_clear([nodes(nn).pos(1) nodes(nn).pos(2) nz], pos(i,:), p), continue; end
            end
            el = atan2d(rel(3), hypot(rel(1),rel(2)));
            vr = dot(rel, T(i).spd*T(i).u)/R;
            wB = aeris.az_gain(aoff, p, g);
            if p.elevBeamOn, wB = wB * aeris.elev_gain(p,g,el,Wdwell); end
            pi_ = p; pi_.targetRCS = T(i).rcs;
            snr = aeris.snr(pi_,g,R,wB); if snr<=0, continue; end
            [~,ir]=min(abs(rangeAxis-R)); [~,id]=min(abs(velAxis-vr));
            snrv(end+1)=snr; riv(end+1)=ir; div(end+1)=id; idxv(end+1)=i; %#ok<AGROW>
        end
        if isempty(snrv), continue; end
        det = aeris.look(snrv,riv,div,nR,nD,cf,Cridge);
        for kk = find(det)
            i = idxv(kk);
            [z,Rci] = aeris.meas_polar(nodes(nn).pos, pos(i,:), snrv(kk), g);
            Z(:,end+1)=z; Rc(:,:,end+1)=Rci; %#ok<AGROW>
            mAlt(end+1) = pos(i,3) + 15*randn;                        %#ok<AGROW>
            mRcs(end+1) = T(i).rcs * 10^(3*randn/10);                 %#ok<AGROW>
        end
    end

    % ---- tracker cycle --------------------------------------------------
    meta = struct('alt',mAlt,'rcs',mRcs);
    [tr, nextId] = aeris.track_step(tr, Z, Rc, meta, p.frameDt, cfg, nextId);

    % ---- build warnings from CONFIRMED track estimates ------------------
    ct = find([tr.confirmed]);
    tracks = struct('id',{},'pos',{},'spd',{},'heading',{},'rcs',{}, ...
                    'nNodes',{},'snr',{},'classCall',{});
    for k = ct
        v = tr(k).x(3:4); spd = norm(v); hd = [0 0 0];
        if spd > 1e-3, hd = [v.'/spd, 0]; end
        % live micro-Doppler class call, assigned once and kept (sticky)
        if isempty(tr(k).classCall)
            tr(k).classCall = aeris.classify_track(tr(k).rcs, spd);
        end
        tracks(end+1) = struct('id',tr(k).id, 'pos',[tr(k).x(1) tr(k).x(2) tr(k).alt], ...
            'spd',spd, 'heading',hd, 'rcs',tr(k).rcs, ...
            'nNodes',max(tr(k).contrib,1), 'snr',0, 'classCall',tr(k).classCall); %#ok<AGROW>
    end
    W = aeris.warning_report(tracks, p);

    if p.mapView
        draw_cop_map(axC, p, nodes, Pdef, pos, alv, tr, ct, W, tracks, t, link);
    else
        draw_cop(axC, p, nodes, Pdef, pos, alv, tr, ct, W, tracks, t, U, ulab, ring, link);
    end
    draw_feed(axF, W, t, p.units);

    drawnow limitrate
    if ~isempty(vw), writeVideo(vw, getframe(fig)); end
end
if ~isempty(vw), close(vw); end
end

% ========================================================================
function draw_cop(ax, p, nodes, Pdef, pos, alv, tr, ct, W, tracks, t, U, ulab, ring, link)
cla(ax); hold(ax,'on'); axis(ax,'equal');
set(ax,'Color',[.07 .09 .11],'XColor',[.35 .4 .45],'YColor',[.35 .4 .45], ...
       'GridColor',[.15 .18 .2]);

% comms links (C2 + node-to-node), drawn under everything
P = [reshape([nodes.pos],3,[]).'; link.c2];
for a = 1:size(link.A,1)
    for b = a+1:size(link.A,2)
        if link.A(a,b)
            plot(ax,[P(a,1) P(b,1)]/U,[P(a,2) P(b,2)]/U,'-', ...
                 'Color',[.2 .5 .4 .5],'LineWidth',1);
        end
    end
end

% range rings (subtle)
th = linspace(0,2*pi,90);
nRing = ceil((2*p.Rmax + p.Dforward)/ring);
for rr = 1:nRing
    R = rr*ring;
    plot(ax,(Pdef(1)+R*cos(th))/U,(Pdef(2)+R*sin(th))/U,'-','Color',[.12 .15 .18]);
    text(ax, Pdef(1)/U,(Pdef(2)+R)/U, sprintf(' %d %s',rr,ulab), ...
         'Color',[.28 .32 .36],'FontSize',7,'VerticalAlignment','bottom');
end

% sensing network + coverage (node colour = connectivity)
for nn = 1:numel(nodes)
    c = nodes(nn).pos; b = nodes(nn).bore;
    ths = linspace(b-p.sectorWidth/2, b+p.sectorWidth/2, 40);
    fill(ax,(c(1)+[0,p.Rmax*cosd(ths),0])/U,(c(2)+[0,p.Rmax*sind(ths),0])/U, ...
         [.25 .5 .7],'FaceAlpha',.05,'EdgeColor','none');
    if link.down(nn),        ncol=[.5 .5 .55]; mk='x';   % killed
    elseif link.reachable(nn),ncol=[.4 .75 1]; mk='^';   % connected
    else,                    ncol=[1 .5 .3];  mk='^';    % isolated
    end
    plot(ax,c(1)/U,c(2)/U,mk,'MarkerFaceColor',ncol,'MarkerEdgeColor','none', ...
         'MarkerSize',9,'LineWidth',1.5);
    text(ax,c(1)/U,c(2)/U-ring*0.13/U,nodes(nn).label,'Color',ncol, ...
         'FontSize',7,'HorizontalAlignment','center');
end

% defended point (clear anchor)
plot(ax,Pdef(1)/U,Pdef(2)/U,'o','MarkerFaceColor',[1 .82 .2], ...
     'MarkerEdgeColor','none','MarkerSize',13);
plot(ax,Pdef(1)/U,Pdef(2)/U,'o','MarkerEdgeColor',[1 .82 .2], ...
     'MarkerFaceColor','none','MarkerSize',22,'LineWidth',1);
text(ax,Pdef(1)/U,Pdef(2)/U-ring*0.35/U,'DEFENDED','Color',[1 .82 .2], ...
     'HorizontalAlignment','center','FontSize',9,'FontWeight','bold');

% truth ghost (validation only)
if p.showTruth
    for i = find(alv)
        plot(ax,pos(i,1)/U,pos(i,2)/U,'.','Color',[.3 .34 .38],'MarkerSize',9);
    end
end

% confirmed tracks: uncertainty ellipse + symbol + heading + label
for k = 1:numel(W)
    ti = ct(strcmp({tracks.id}, W(k).id));
    trk = tr(ti);
    col = urg_col(W(k).action);
    % 2-sigma uncertainty ellipse from the position covariance
    Pxy = trk.P(1:2,1:2);
    [V,Dm] = eig((Pxy+Pxy.')/2); dd = max(diag(Dm),0);
    ell = V*diag(2*sqrt(dd))*[cos(th); sin(th)];
    plot(ax,(trk.x(1)+ell(1,:))/U,(trk.x(2)+ell(2,:))/U,'-','Color',[col .55], ...
         'LineWidth',1);
    % velocity leader: projected position leadTime seconds ahead (length = speed)
    v = trk.x(3:4); hv = v * p.leadTime;
    lx = [trk.x(1) trk.x(1)+hv(1)]/U; ly = [trk.x(2) trk.x(2)+hv(2)]/U;
    plot(ax, lx, ly, '-','Color',col,'LineWidth',2);
    plot(ax, lx(2), ly(2), '.','Color',col,'MarkerSize',10);   % lead tick
    plot(ax,trk.x(1)/U,trk.x(2)/U,'d','MarkerFaceColor',col, ...
         'MarkerEdgeColor','w','MarkerSize',10,'LineWidth',1);
    crs = ''; if ~isnan(W(k).courseDeg), crs = sprintf('%03.0f/', W(k).courseDeg); end
    text(ax,trk.x(1)/U+ring*0.12/U,trk.x(2)/U, ...
        sprintf('%s  %s\n%s%.0fkt  T-%s',W(k).id,upper(W(k).classEst), ...
                crs, W(k).speedMps*1.943844, mmss(max(W(k).warnS,0))), ...
        'Color',col,'FontSize',8.5,'FontWeight','bold','VerticalAlignment','middle');
end

xlim(ax,[(-p.Dforward-ring*0.5)/U,(p.Rmax+ring)/U]);
ylim(ax,[(-p.Rmax-ring*0.5)/U,(p.Rmax+ring*0.5)/U]);
xlabel(ax,sprintf('down-threat (%s)',ulab)); ylabel(ax,sprintf('cross-range (%s)',ulab));
soon=''; if ~isempty(W), soon=sprintf('     next impact  %s', mmss(min([W.etaS]))); end
title(ax,sprintf('AERIS-NEXUS     %d TRACK(S)%s', numel(W), soon), ...
      'Color','w','FontWeight','bold','FontSize',13);
end

% ------------------------------------------------------------------------
function draw_feed(ax, W, t, units)
cla(ax); axis(ax,'off'); set(ax,'Color',[.05 .06 .08]);
text(ax,0.04,0.98,'THREAT WARNINGS','Color','w','FontWeight','bold', ...
     'FontSize',12,'VerticalAlignment','top','Units','normalized');
if isempty(W)
    text(ax,0.04,0.90,'CLEAR','Color',[.4 .85 .45],'FontWeight','bold', ...
         'FontSize',14,'VerticalAlignment','top','Units','normalized');
    return
end
y = 0.90; show = min(numel(W),5);
for k = 1:show
    w = W(k); col = urg_col(w.action);
    txt = aeris.warning_text(w, units);
    text(ax,0.04,y,txt,'Color',col,'FontName','FixedWidth','FontSize',9, ...
         'VerticalAlignment','top','Units','normalized');
    y = y - 0.185;
end
if numel(W)>show
    text(ax,0.04,y,sprintf('  +%d more',numel(W)-show),'Color',[.4 .45 .5], ...
         'FontName','FixedWidth','FontSize',9,'VerticalAlignment','top','Units','normalized');
end
end

% ========================================================================
function setup_geolimits(gx, p, ~)
% frame the whole scene: node origin region + defended point + Rmax margin
corners = [ p.Rmax, p.Rmax; p.Rmax,-p.Rmax; -p.Dforward, p.Rmax; ...
           -p.Dforward,-p.Rmax];
lat = zeros(4,1); lon = zeros(4,1);
for i = 1:4, [lat(i),lon(i)] = aeris.sim2ll(corners(i,:), p); end
mlat = 0.06*(max(lat)-min(lat)) + 1e-3;
mlon = 0.06*(max(lon)-min(lon)) + 1e-3;
geolimits(gx, [min(lat)-mlat, max(lat)+mlat], [min(lon)-mlon, max(lon)+mlon]);
end

function draw_cop_map(gx, p, nodes, Pdef, pos, alv, tr, ct, W, tracks, t, link)
% render the operating picture on a real basemap by lat/lon
[latlim, lonlim] = geolimits(gx);                  % preserve current view
cla(gx); hold(gx,'on');

% comms links
P = [reshape([nodes.pos],3,[]).'; link.c2];
for a = 1:size(link.A,1)
    for b = a+1:size(link.A,2)
        if link.A(a,b)
            [la1,lo1]=aeris.sim2ll(P(a,1:2),p); [la2,lo2]=aeris.sim2ll(P(b,1:2),p);
            geoplot(gx,[la1 la2],[lo1 lo2],'-','Color',[.3 .8 .5],'LineWidth',1);
        end
    end
end

% defended point / C2
[dlat,dlon] = aeris.sim2ll(Pdef(1:2), p);
geoplot(gx, dlat, dlon, 'o','MarkerFaceColor',[1 .82 .2], ...
        'MarkerEdgeColor','k','MarkerSize',12);
text(gx, dlat, dlon, '  DEFENDED / C2','Color',[1 .9 .3],'FontWeight','bold','FontSize',9);

% nodes, coloured by connectivity
for nn = 1:numel(nodes)
    [nlat,nlon] = aeris.sim2ll(nodes(nn).pos(1:2), p);
    if link.down(nn),         ncol=[.6 .6 .65]; mk='x';
    elseif link.reachable(nn),ncol=[.4 .75 1];  mk='^';
    else,                     ncol=[1 .5 .3];   mk='^';
    end
    geoplot(gx, nlat, nlon, mk,'MarkerFaceColor',ncol, ...
            'MarkerEdgeColor','k','MarkerSize',9,'LineWidth',1.5);
    text(gx, nlat, nlon, ['  ' nodes(nn).label],'Color',ncol,'FontSize',8);
end

% truth ghost
if p.showTruth
    for i = find(alv)
        [la,lo] = aeris.sim2ll(pos(i,1:2), p);
        geoplot(gx, la, lo, '.','Color',[.85 .85 .9],'MarkerSize',8);
    end
end

% confirmed tracks: ellipse + heading + symbol + label
th = linspace(0,2*pi,60);
for k = 1:numel(W)
    ti = ct(strcmp({tracks.id}, W(k).id));
    trk = tr(ti); col = urg_col(W(k).action);
    % uncertainty ellipse (convert each ellipse point through sim2ll)
    Pxy = (trk.P(1:2,1:2)+trk.P(1:2,1:2).')/2;
    [V,Dm] = eig(Pxy); dd = max(diag(Dm),0);
    e = V*diag(2*sqrt(dd))*[cos(th);sin(th)];
    ela = zeros(1,numel(th)); elo = zeros(1,numel(th));
    for j = 1:numel(th)
        [ela(j),elo(j)] = aeris.sim2ll([trk.x(1)+e(1,j), trk.x(2)+e(2,j)], p);
    end
    geoplot(gx, ela, elo, '-','Color',col,'LineWidth',1);
    % velocity leader: projected position leadTime seconds ahead
    lead = trk.x(1:2).' + trk.x(3:4).' * p.leadTime;
    [lla,llo] = aeris.sim2ll(lead, p);
    [tla,tlo] = aeris.sim2ll(trk.x(1:2).', p);
    geoplot(gx, [tla lla], [tlo llo], '-','Color',col,'LineWidth',2);
    geoplot(gx, tla, tlo, 'd','MarkerFaceColor',col,'MarkerEdgeColor','w', ...
            'MarkerSize',10,'LineWidth',1);
    crs = ''; if ~isnan(W(k).courseDeg), crs = sprintf('%03.0f/', W(k).courseDeg); end
    text(gx, tla, tlo, sprintf('  %s %s  %s%.0fkt  T-%s', W(k).id, ...
         upper(W(k).classEst), crs, W(k).speedMps*1.943844, mmss(max(W(k).warnS,0))), ...
         'Color',col,'FontWeight','bold','FontSize',9);
end

geobasemap(gx, p.basemap);
geolimits(gx, latlim, lonlim);                     % hold the framing steady
title(gx, sprintf('AERIS-NEXUS   %d TRACK(S)   t=%.0fs', numel(W), t), ...
      'Color','w');
end

% ------------------------------------------------------------------------
function p = df(p,f,v), if ~isfield(p,f)||isempty(p.(f)), p.(f)=v; end, end

function s = mmss(sec)
sec = max(round(sec),0); s = sprintf('%d:%02d', floor(sec/60), mod(sec,60));
end

function col = urg_col(action)
if     strcmp(action,'IMMINENT - TAKE COVER'), col=[1 .32 .28];
elseif strcmp(action,'ALERT - CUE EFFECTOR'),  col=[1 .72 .2];
else,                                          col=[.4 .85 .45];
end
end
