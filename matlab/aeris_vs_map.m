function aeris_vs_map()
% AERIS_VS_MAP  Side-by-side on the real map: 10X (rotating) vs 4x10N (sectors).
%
%   aeris_vs_map
%
% Both architectures on a satellite basemap, same fixed land datum, live sweeps:
%   LEFT  AERIS-10X  - one node, 360 deg long range, a rotating PPI sweep.
%   RIGHT 4x AERIS-10N - four fixed 90 deg sectors, short range, staring.
% A continuous drone/bird/plane stream flies in at the defended point; held
% tracks are coloured by class. Runs until you click STOP.
%
% Datum is fixed on land (NTC Fort Irwin) and not changed between runs.
% Needs internet for 'satellite' tiles; falls back note in the code comments.

lat0 = 35.2610; lon0 = -116.6840;            % Fort Irwin NTC - on land, FIXED
basemap = 'satellite';                        % the original imagery basemap
dt = 0.25;

pX = aeris_params('extended'); pX.useRfChain = true; gX = aeris.derive(pX);
pN = aeris_params('nexus');    pN.useRfChain = true; gN = aeris.derive(pN);
Rx = reliable(pX,gX,0.03); Rn = reliable(pN,gN,0.03);
rotP = pX.rotationPeriod; bwX = gX.azBW; Rmax = 7500;
nexBore = [0 90 180 270];
TC = aeris.target_classes(); cw=[6 3 1]; cc=cumsum(cw)/sum(cw);
clsCol = [.95 .3 .3; .4 .8 .95; .95 .8 .3];

fig = figure('Color',[.05 .06 .08],'Position',[30 60 1520 800], ...
             'Name','AERIS on the map: 10X vs 4x10N','NumberTitle','off');
setappdata(fig,'run',true);
uicontrol(fig,'Style','pushbutton','String','STOP','FontWeight','bold', ...
    'BackgroundColor',[.9 .3 .25],'ForegroundColor','w','Units','normalized', ...
    'Position',[0.46 0.955 0.08 0.04],'Callback',@(~,~) setappdata(fig,'run',false));

axX = geoaxes(fig,'Position',[0.03 0.05 0.45 0.90]); geobasemap(axX,basemap);
axN = geoaxes(fig,'Position',[0.52 0.05 0.45 0.90]); geobasemap(axN,basemap);
dLat = Rmax/111320; dLon = Rmax/(111320*cosd(lat0));
for ax=[axX axN]
    geolimits(ax,[lat0-dLat lat0+dLat],[lon0-dLon lon0+dLon]); hold(ax,'on');
end
title(axX,'AERIS-10X (rotating, long range)','Color','w');
title(axN,'4x AERIS-10N (fixed sectors, short range)','Color','w');

% defended point + coverage (drawn once)
geoscatter(axX,lat0,lon0,120,[1 .82 .2],'p','filled');
geoscatter(axN,lat0,lon0,120,[1 .82 .2],'p','filled');
[cla_,clo_] = circle_ll(lat0,lon0,Rx); geoplot(axX,cla_,clo_,'-','Color',[.4 .7 1]);
for k=1:4
    [wla,wlo] = wedge_ll(lat0,lon0,nexBore(k),pN.sectorWidth,Rn);
    geoplot(axN,wla,wlo,'-','Color',[.4 .7 1]);
end

% live handles: unseen (grey) + held (class colour) per side, + sweep line
hUX=geoscatter(axX,[],[],10,[.6 .6 .6],'filled');
hHX=geoscatter(axX,[],[],30,[0 1 0],'filled');
hUN=geoscatter(axN,[],[],10,[.6 .6 .6],'filled');
hHN=geoscatter(axN,[],[],30,[0 1 0],'filled');
hSweep=geoplot(axX,[lat0 lat0],[lon0 lon0],'-','Color',[.4 .95 .6],'LineWidth',2);

P=300;
dx=nan(P,1);dy=nan(P,1);dvx=nan(P,1);dvy=nan(P,1);alt=nan(P,1);cls=zeros(P,1);rcsv=nan(P,1);
alive=false(P,1); heldX=zeros(P,1); heldN=zeros(P,1);
beamAz=0; nextSpawn=0; t=0;

while ishandle(fig) && getappdata(fig,'run')
    t=t+dt;
    if t>=nextSpawn
        s0=find(~alive,1);
        if ~isempty(s0)
            c=find(rand<=cc,1); th=rand*360; s=unif(TC(c).spd);
            alt(s0)=unif(TC(c).alt); rcsv(s0)=exp(unif(log(TC(c).rcs))); cls(s0)=c;
            dx(s0)=Rmax*cosd(th); dy(s0)=Rmax*sind(th); dvx(s0)=-s*cosd(th); dvy(s0)=-s*sind(th);
            alive(s0)=true; heldX(s0)=0; heldN(s0)=0;
        end
        nextSpawn=t+1.5+rand*1.5;
    end
    for i=1:P
        if ~alive(i), continue; end
        dx(i)=dx(i)+dvx(i)*dt; dy(i)=dy(i)+dvy(i)*dt;
        if hypot(dx(i),dy(i))<150, alive(i)=false; end
    end
    beamAz=mod(beamAz+360*dt/rotP,360);
    for i=1:P
        if ~alive(i), continue; end
        Rg=hypot(dx(i),dy(i)); R=hypot(Rg,alt(i)); az=atan2d(dy(i),dx(i));
        if abs(aeris.wrap180(az-beamAz))<=bwX/2 && rand<pdet(pX,gX,R,rcsv(i)), heldX(i)=t; end
        for k=1:4
            if abs(aeris.wrap180(az-nexBore(k)))<=pN.sectorWidth/2
                if rand<pdet(pN,gN,R,rcsv(i)), heldN(i)=t; end
                break;
            end
        end
    end
    % draw (ENU metres -> lat/lon)
    live=alive; hx=live&(heldX>0)&(t-heldX<3); hn=live&(heldN>0)&(t-heldN<3);
    upd(hUX, dx(live&~hx),dy(live&~hx),lat0,lon0,[],[]);
    upd(hHX, dx(hx),dy(hx),lat0,lon0,clsCol(max(cls(hx),1),:),15+alt(hx)/12);
    upd(hUN, dx(live&~hn),dy(live&~hn),lat0,lon0,[],[]);
    upd(hHN, dx(hn),dy(hn),lat0,lon0,clsCol(max(cls(hn),1),:),15+alt(hn)/12);
    [sla,slo]=aeris.enu2ll(Rx*cosd(beamAz),Rx*sind(beamAz),lat0,lon0);
    set(hSweep,'LatitudeData',[lat0 sla],'LongitudeData',[lon0 slo]);
    drawnow; pause(0.03);
end
end

% ------------------------------------------------------------------------
function upd(h, ex, ny, lat0, lon0, cdata, sz)
if isempty(ex), set(h,'LatitudeData',[],'LongitudeData',[]); return; end
[la,lo]=aeris.enu2ll(ex,ny,lat0,lon0);
set(h,'LatitudeData',la,'LongitudeData',lo);
if ~isempty(cdata), set(h,'CData',cdata); end
if ~isempty(sz),    set(h,'SizeData',sz);  end
end

function [la,lo]=circle_ll(lat0,lon0,r)
th=linspace(0,2*pi,120); [la,lo]=aeris.enu2ll(r*cos(th),r*sin(th),lat0,lon0);
end
function [la,lo]=wedge_ll(lat0,lon0,bore,w,r)
th=linspace(bore-w/2,bore+w/2,40);
[la,lo]=aeris.enu2ll([0 r*cosd(th) 0],[0 r*sind(th) 0],lat0,lon0);
end
function R=reliable(p,g,rcs), pp=p; pp.targetRCS=rcs; R=aeris.reliable_range(pp,g); end
function pd=pdet(p,g,R,rcs), pp=p; pp.targetRCS=rcs; s=aeris.snr(pp,g,R); pd=p.Pfa.^(1./(1+s)); end
function v=unif(r), v=r(1)+rand*(r(2)-r(1)); end
