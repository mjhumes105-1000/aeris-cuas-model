function aeris_demo3d(variant, recFile, nRec)
% AERIS_DEMO3D  Capstone: 3-D "how it works" + operator map GUI, live.
%
%   aeris_demo3d               % AERIS-10N (fixed 90 deg sector, short range)
%   aeris_demo3d('nexus')      % same
%   aeris_demo3d('extended')   % AERIS-10X (360 deg rotating, long range)
%   aeris_demo3d('nexus','demo_10n.mp4',150)   % record 150 frames, then stop
%
% LEFT  ground truth in 3-D - the node, its coverage (reliable range on a
%       0.03 m^2 target), the beam as it scans, and every target at its true
%       altitude with a ground drop-line. Undetected targets are grey; a target
%       lights up in its class colour when the beam sweeps it and it is
%       detected (SNR -> Swerling-1 Pd), with a course/speed vector.
% RIGHT the operator GUI - only what the radar holds: tracks on a real land
%       map, coloured by class, with course/speed leaders, the coverage
%       outline, and a track table (course, knots, feet, miles).
% Same target stream drives both. Runs until STOP. Land datum fixed (Fort Irwin).
%
% Detection fires exactly when the drawn beam sweeps across a target, so what
% you see is what the model does. Tracks coast ~1.6 revisits between looks.
% The 10N scans its 90 deg sector at the modelled revisit (aeris.dwell_plan);
% the 10X rotates at p.rotationPeriod.

if nargin < 1 || isempty(variant), variant = 'nexus'; end
if nargin < 2, recFile = ''; end
if nargin < 3 || isempty(nRec), nRec = 150; end
rec = ~isempty(recFile);
lat0 = 35.2610; lon0 = -116.6840; basemap = 'satellite';
dt = 0.20; leadT = 25;                         % s per frame, vector lead time

p = aeris_params(variant); p.useRfChain = true; g = aeris.derive(p);
Rcov = reliable(p,g,0.03);                     % coverage (0.03 m^2 drone)
is360 = p.rotating;
if is360
    sectW = 360; revisit = p.rotationPeriod; Rmax = max(8000, 1.2*Rcov);
    lbl = 'AERIS-10X  (360 deg rotating)';
else
    sectW = p.sectorWidth; W = aeris.dwell_plan(p,g); revisit = W.revisit;
    Rmax = 5000; lbl = sprintf('AERIS-10N  (fixed %g deg sector)', sectW);
end
holdT  = 1.6*revisit;                          % coast a track across one revisit
bw     = max(g.azBW, 6);                       % drawn + gated beam width (deg)
elMax  = 25; zTop = 1600;                      % beam elevation extent, 3-D box height
TC = aeris.target_classes();
kp = strcmpi({TC.name},'plane'); TC(kp).alt = [300 1500];  % demo: keep planes in the box
cw = [6 3 1]; ccum = cumsum(cw)/sum(cw);
clsCol  = [.95 .3 .3; .4 .8 .95; .95 .8 .3];
clsName = {TC.name};

fig = figure('Color',[.06 .07 .09],'Position',[25 55 1540 820], ...
    'Name',['AERIS - ' lbl],'NumberTitle','off');
setappdata(fig,'run',true);
if ~rec
    uicontrol(fig,'Style','pushbutton','String','STOP','FontWeight','bold', ...
        'BackgroundColor',[.9 .3 .25],'ForegroundColor','w','Units','normalized', ...
        'Position',[0.46 0.955 0.08 0.04],'Callback',@(~,~) setappdata(fig,'run',false));
end

% ---- LEFT: 3-D ground truth -------------------------------------------
ax3 = axes(fig,'Position',[0.03 0.06 0.45 0.84]); hold(ax3,'on'); grid(ax3,'on');
set(ax3,'Color',[.09 .10 .13],'XColor',[.5 .55 .6],'YColor',[.5 .55 .6],'ZColor',[.5 .55 .6]);
try, ax3.Toolbar.Visible = 'off'; catch, end
th = linspace(-pi,pi,90);
for r = 1000:1000:Rmax, plot3(ax3,r*cos(th),r*sin(th),zeros(size(th)),':','Color',[.2 .23 .26]); end
[cx,cy] = coverage_xy(is360, Rcov, p.boresight, sectW);
patch(ax3,'XData',cx,'YData',cy,'ZData',zeros(size(cx)), ...
      'FaceColor',[.2 .45 .7],'FaceAlpha',.12,'EdgeColor',[.35 .6 .9],'LineWidth',1);
plot3(ax3,0,0,3,'^','MarkerFaceColor',[.4 .8 1],'MarkerEdgeColor','w','MarkerSize',10);
Rb = min(Rmax, 1.3*Rcov); zb = min(Rb*tand(elMax), 0.9*zTop);
hBeam3 = patch(ax3,'Faces',[1 2 3 NaN; 1 4 5 NaN; 1 2 4 NaN; 1 3 5 NaN; 2 3 5 4], ...
    'Vertices',beam_verts(0,bw,Rb,zb),'FaceColor',[.4 .95 .6],'FaceAlpha',.18, ...
    'EdgeColor',[.4 .95 .6],'EdgeAlpha',.5);
hDrop3 = plot3(ax3,nan,nan,nan,'-','Color',[.35 .37 .42],'LineWidth',.5);
hTru3  = scatter3(ax3,nan,nan,nan,26,[.55 .57 .62]);                   % undetected
hDet3  = scatter3(ax3,nan,nan,nan,48,[1 0 0],'filled','MarkerEdgeColor','k'); % detected
hVec3  = plot3(ax3,nan,nan,nan,'-','Color',[.95 .95 .55],'LineWidth',1.2);
view(ax3,-40,26); camproj(ax3,'perspective');
xlim(ax3,[-Rmax Rmax]); ylim(ax3,[-Rmax Rmax]); zlim(ax3,[0 zTop]);
xlabel(ax3,'x (m)'); ylabel(ax3,'y (m)'); zlabel(ax3,'alt (m)');

% ---- RIGHT: operator map ----------------------------------------------
gx = geoaxes(fig,'Position',[0.53 0.06 0.44 0.84]);
try, geobasemap(gx,basemap); catch, geobasemap(gx,'grayterrain'); end
try, gx.Toolbar.Visible = 'off'; catch, end
mapHW = Rmax; if ~is360, mapHW = 5600; end    % 5.6 km: full satellite coverage at this zoom
dLat = mapHW/111320; dLon = mapHW/(111320*cosd(lat0));
geolimits(gx,[lat0-dLat lat0+dLat],[lon0-dLon lon0+dLon]); hold(gx,'on');
[cla_,clo_] = aeris.enu2ll(cx,cy,lat0,lon0);
geoplot(gx,cla_,clo_,'-','Color',[.45 .75 1],'LineWidth',1.3);
geoscatter(gx,lat0,lon0,120,[1 .82 .2],'p','filled');
hVecM = geoplot(gx,nan,nan,'-','Color',[.95 .95 .55],'LineWidth',1.6);
hTrkM = geoscatter(gx,[],[],40,[0 1 0],'filled','MarkerEdgeColor','k');
hL = gobjects(1,3);
for c = 1:3, hL(c) = geoscatter(gx,[],[],40,clsCol(c,:),'filled','DisplayName',clsName{c}); end
legend(gx,hL,'TextColor','w','Color',[.08 .09 .11],'EdgeColor',[.3 .3 .35],'Location','northwest');
hTab = annotation(fig,'textbox',[0.535 0.12 0.24 0.17],'String','', ...
    'FontName','Consolas','FontSize',9,'Color','w','BackgroundColor',[.08 .09 .11], ...
    'EdgeColor',[.3 .3 .35],'FaceAlpha',.85,'Interpreter','none','VerticalAlignment','top');
if rec, drawnow; pause(15); drawnow; end       % let basemap tiles arrive before recording

% ---- target pool -------------------------------------------------------
P = 200; dx=nan(P,1); dy=nan(P,1); dvx=nan(P,1); dvy=nan(P,1); alt=nan(P,1);
cls=zeros(P,1); rcsv=nan(P,1); alive=false(P,1); held=-inf(P,1);
phi = 0; nextSpawn = 0; t = 0; nSeed = 10;     % start with targets already inbound
arc = sectW*dt/revisit;                        % beam travel per frame (deg)
if rec
    vw = VideoWriter(recFile,'MPEG-4'); vw.FrameRate = 12; vw.Quality = 90;
    open(vw); nf = 0;
end

while ishandle(fig) && getappdata(fig,'run')
    t = t + dt;
    if t >= nextSpawn || nSeed > 0
        for k = 1:max(1,nSeed)
            s0 = find(~alive,1);
            if isempty(s0), break; end
            r0 = Rmax; if nSeed > 0, r0 = Rmax*(0.2+0.8*rand); end
            c = find(rand<=ccum,1);
            if is360, th0 = rand*360; else, th0 = p.boresight + (rand-0.5)*sectW*1.2; end
            s = unif(TC(c).spd);
            alt(s0) = unif(TC(c).alt); rcsv(s0) = exp(unif(log(TC(c).rcs))); cls(s0) = c;
            dx(s0) = r0*cosd(th0); dy(s0) = r0*sind(th0);
            dvx(s0) = -s*cosd(th0); dvy(s0) = -s*sind(th0);
            alive(s0) = true; held(s0) = -inf;
        end
        nSeed = 0; nextSpawn = t + 1.0 + rand*1.2;
    end
    for i = 1:P
        if ~alive(i), continue; end
        dx(i) = dx(i) + dvx(i)*dt; dy(i) = dy(i) + dvy(i)*dt;
        if hypot(dx(i),dy(i)) < 120, alive(i) = false; end
    end

    % beam sweeps [phi, phi+arc]; anything it crosses gets a detection look
    for i = find(alive).'
        az = atan2d(dy(i),dx(i));
        if is360
            psi = mod(az,360); ok = true;
        else
            psi = aeris.wrap180(az - p.boresight) + sectW/2; ok = psi >= 0 && psi <= sectW;
        end
        if ok && swept(psi, phi, arc, bw/2, sectW, is360)
            R = hypot(hypot(dx(i),dy(i)), alt(i));
            if rand < pdet(p,g,R,rcsv(i)), held(i) = t; end
        end
    end
    phi = mod(phi + arc, sectW);
    if is360, beamAz = phi; else, beamAz = p.boresight - sectW/2 + phi; end

    ia = find(alive); iz = find(alive & (t - held) < holdT);
    set(hBeam3,'Vertices',beam_verts(beamAz,bw,Rb,zb));
    [ex,ey,ez] = drop3(dx,dy,alt,ia); set(hDrop3,'XData',ex,'YData',ey,'ZData',ez);
    iu = setdiff(ia, iz);
    set(hTru3,'XData',dx(iu),'YData',dy(iu),'ZData',alt(iu));
    if isempty(iz)
        set(hDet3,'XData',nan,'YData',nan,'ZData',nan);
        set(hVec3,'XData',nan,'YData',nan,'ZData',nan);
        set(hTrkM,'LatitudeData',[],'LongitudeData',[]);
        set(hVecM,'LatitudeData',nan,'LongitudeData',nan);
    else
        set(hDet3,'XData',dx(iz),'YData',dy(iz),'ZData',alt(iz),'CData',clsCol(cls(iz),:));
        [vx,vy,vz] = vec3(dx,dy,alt,dvx,dvy,iz,leadT); set(hVec3,'XData',vx,'YData',vy,'ZData',vz);
        [la,lo] = aeris.enu2ll(dx(iz),dy(iz),lat0,lon0);
        set(hTrkM,'LatitudeData',la,'LongitudeData',lo,'CData',clsCol(cls(iz),:),'SizeData',25+alt(iz)/12);
        [vla,vlo] = vecmap(dx,dy,dvx,dvy,iz,leadT,lat0,lon0);
        set(hVecM,'LatitudeData',vla,'LongitudeData',vlo);
    end
    set(hTab,'String',track_table(iz,dx,dy,dvx,dvy,alt,cls,clsName));
    title(ax3,{sprintf('HOW IT WORKS - %s', lbl), ...
        sprintf('coverage %.1f km | %d targets, %d detected | grey = not yet detected', ...
        Rcov/1000, numel(ia), numel(iz))},'Color','w','FontWeight','normal');
    title(gx,{'OPERATOR GUI - what the radar holds', sprintf('%d track(s)', numel(iz))}, ...
        'Color','w','FontWeight','normal');
    drawnow;
    if rec
        if t > 3                                   % let the beam make a pass first
            writeVideo(vw, getframe(fig)); nf = nf + 1;
            if nf >= nRec, break; end
        end
    else
        pause(0.02);
    end
end
if rec
    close(vw); if ishandle(fig), close(fig); end
    fprintf('recorded %d frames -> %s\n', nf, recFile);
end
end

% ------------------------------------------------------------------------
function R = reliable(p,g,rcs), pp = p; pp.targetRCS = rcs; R = aeris.reliable_range(pp,g); end
function pd = pdet(p,g,R,rcs), pp = p; pp.targetRCS = rcs; s = aeris.snr(pp,g,R); pd = p.Pfa.^(1./(1+s)); end
function v = unif(r), v = r(1) + rand*(r(2)-r(1)); end

function hit = swept(psi, a, arc, half, L, periodic)
% true if angle psi lies in the arc the beam swept this frame, [a, a+arc] +/- half
if periodic
    hit = mod(psi - (a - half), L) <= arc + 2*half;
else
    b = a + arc;
    if b <= L, hit = psi >= a-half && psi <= b+half;
    else,      hit = psi >= a-half || psi <= (b-L)+half; end
end
end

function V = beam_verts(az, bw, Rb, zb)
% 3-D beam volume: apex at the node, azimuth width bw, elevation 0..zb at Rb
a1 = az - bw/2; a2 = az + bw/2;
V = [0 0 3;
     Rb*cosd(a1) Rb*sind(a1) 0;   Rb*cosd(a2) Rb*sind(a2) 0;
     Rb*cosd(a1) Rb*sind(a1) zb;  Rb*cosd(a2) Rb*sind(a2) zb];
end

function [x,y] = coverage_xy(is360, R, bore, sectW)
if is360
    th = linspace(0,360,121); x = R*cosd(th); y = R*sind(th);
else
    th = bore + linspace(-sectW/2, sectW/2, 60);
    x = [0 R*cosd(th) 0]; y = [0 R*sind(th) 0];
end
end

function L = track_table(iz,dx,dy,dvx,dvy,alt,cls,names)
% operator readout, closest first: class, course (deg true), knots, feet, miles
L = {sprintf('%-3s %-6s %5s %5s %7s %6s','#','CLASS','CRS','KT','ALT ft','RNG mi')};
if isempty(iz), L{end+1} = '  no tracks'; return; end
[~,o] = sort(hypot(dx(iz),dy(iz))); iz = iz(o);
for k = 1:min(6,numel(iz))
    i = iz(k);
    crs = mod(atan2d(dvx(i),dvy(i)),360);            % x = east, y = north
    L{end+1} = sprintf('%-3d %-6s %5s %5.0f %7.0f %6.2f', k, upper(names{cls(i)}), ...
        sprintf('%03.0f',crs), hypot(dvx(i),dvy(i))*1.94384, alt(i)*3.28084, ...
        hypot(dx(i),dy(i))/1609.34); %#ok<AGROW>
end
end

function [vx,vy,vz] = vec3(dx,dy,alt,dvx,dvy,iz,lead)
vx=[]; vy=[]; vz=[];
for i = iz(:).', vx=[vx dx(i) dx(i)+dvx(i)*lead nan]; vy=[vy dy(i) dy(i)+dvy(i)*lead nan]; vz=[vz alt(i) alt(i) nan]; end %#ok<AGROW>
end
function [x,y,z] = drop3(dx,dy,alt,iz)
x=[]; y=[]; z=[];
for i = iz(:).', x=[x dx(i) dx(i) nan]; y=[y dy(i) dy(i) nan]; z=[z 0 alt(i) nan]; end %#ok<AGROW>
end
function [la,lo] = vecmap(dx,dy,dvx,dvy,iz,lead,lat0,lon0)
la=[]; lo=[];
for i = iz(:).'
    [a1,o1] = aeris.enu2ll(dx(i),dy(i),lat0,lon0);
    [a2,o2] = aeris.enu2ll(dx(i)+dvx(i)*lead,dy(i)+dvy(i)*lead,lat0,lon0);
    la=[la a1 a2 nan]; lo=[lo o1 o2 nan]; %#ok<AGROW>
end
end
