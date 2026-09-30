function aeris_vs_live()
% AERIS_VS_LIVE  Live side-by-side: 1 rotating Extended vs 4 fixed Nexus nodes.
%
%   aeris_vs_live
%
% Runs CONTINUOUSLY until you click Stop (or close the window). A never-ending
% stream of drones flies in at the defended point from random bearings.
%   LEFT  AERIS-10X : one node, 360 deg, long range, but a ROTATING sweep that
%                     only lights a target as the beam passes.
%   RIGHT 4x AERIS-10N : fixed 90 deg sectors (N/E/S/W) that STARE continuously
%                        but reach far less.
% grey = unseen, green = held (seen in the last few seconds). Titles tally who
% is holding now and how many have leaked through undetected.
%
% Fast analytic detection (SNR -> Pd); ranges are the real modeled reliable
% ranges. Click Stop to end.

dt = 0.25;                                   % sim seconds per frame
pX = aeris_params('extended'); pX.useRfChain = true; gX = aeris.derive(pX);
pN = aeris_params('nexus');    pN.useRfChain = true; gN = aeris.derive(pN);
rcs = 0.03;
Rx = reliable(pX,gX,rcs);  Rn = reliable(pN,gN,rcs);
rotP = pX.rotationPeriod; bwX = gX.azBW;
Rmax = 7500;  nexBore = [0 90 180 270];

fig = figure('Color',[.05 .06 .08],'Position',[40 60 1500 780], ...
             'Name','AERIS 10X vs 4x10N  (live)','NumberTitle','off');
setappdata(fig,'run',true);
uicontrol(fig,'Style','pushbutton','String','STOP','FontWeight','bold', ...
    'BackgroundColor',[.9 .3 .25],'ForegroundColor','w', ...
    'Units','normalized','Position',[0.46 0.955 0.08 0.04], ...
    'Callback',@(~,~) setappdata(fig,'run',false));

tl = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');
axX = nexttile(tl); setup_axes(axX,Rmax);
axN = nexttile(tl); setup_axes(axN,Rmax);
draw_circle(axX,Rx,[.2 .5 .8]);
for k=1:4, draw_wedge(axN,nexBore(k),pN.sectorWidth,Rn,[.2 .5 .8]); end

hWedge = patch(axX,'XData',0,'YData',0,'FaceColor',[.3 .8 .5],'FaceAlpha',.10,'EdgeColor','none');
hSweep = plot(axX,[0 0],[0 0],'-','Color',[.4 .95 .6],'LineWidth',2);
hUX = plot(axX,nan,nan,'o','MarkerFaceColor',[.5 .53 .57],'MarkerEdgeColor','none','MarkerSize',4);
hHX = scatter(axX,nan,nan,30,[0 1 0],'filled','MarkerEdgeColor','w','LineWidth',0.5);
hUN = plot(axN,nan,nan,'o','MarkerFaceColor',[.5 .53 .57],'MarkerEdgeColor','none','MarkerSize',4);
hHN = scatter(axN,nan,nan,30,[0 1 0],'filled','MarkerEdgeColor','w','LineWidth',0.5);
tX = title(axX,'','Color','w','FontWeight','normal');
tN = title(axN,'','Color','w','FontWeight','normal');
clsRGB = vertcat(TC.color);                    % class colours; marker size = altitude
% class colour key
for c=1:numel(TC)
    text(axX,-Rmax*0.95, Rmax*(0.95-0.07*c), sprintf('  %s',TC(c).name), ...
        'Color',clsRGB(c,:),'FontWeight','bold','FontSize',9);
end

% mixed target classes at their own speeds AND altitudes
TC = aeris.target_classes();                 % drone / bird / plane
classW = [6 3 1];                             % relative arrival mix (mostly drones)
classCum = cumsum(classW)/sum(classW);

% fixed target pool with slot recycling (runs forever without growing)
P = 300;
dx=nan(P,1); dy=nan(P,1); dvx=nan(P,1); dvy=nan(P,1);
alt=nan(P,1); cls=zeros(P,1); rcsv=nan(P,1);
alive=false(P,1); heldX=zeros(P,1); heldN=zeros(P,1);
leakX=0; leakN=0; beamAz=0; nextSpawn=0; t=0;

while ishandle(fig) && getappdata(fig,'run')
    t = t + dt;

    % spawn a mixed-class target into a free slot every ~1.5-3 s
    if t >= nextSpawn
        s0 = find(~alive,1);
        if ~isempty(s0)
            c = find(rand<=classCum,1);          % pick drone/bird/plane
            th=rand*360;
            s   = unif(TC(c).spd);               % class speed
            alt(s0) = unif(TC(c).alt);           % class altitude
            rcsv(s0)= exp(unif(log(TC(c).rcs))); % class RCS
            cls(s0) = c;
            dx(s0)=Rmax*cosd(th); dy(s0)=Rmax*sind(th);
            dvx(s0)=-s*cosd(th); dvy(s0)=-s*sind(th);
            alive(s0)=true; heldX(s0)=0; heldN(s0)=0;
        end
        nextSpawn = t + 1.5 + rand*1.5;
    end

    % move + arrival
    for i=1:P
        if ~alive(i), continue; end
        dx(i)=dx(i)+dvx(i)*dt; dy(i)=dy(i)+dvy(i)*dt;
        if hypot(dx(i),dy(i))<150
            alive(i)=false;
            if heldX(i)==0, leakX=leakX+1; end
            if heldN(i)==0, leakN=leakN+1; end
        end
    end

    % detect
    beamAz = mod(beamAz+360*dt/rotP,360);
    for i=1:P
        if ~alive(i), continue; end
        Rg=hypot(dx(i),dy(i)); R=hypot(Rg,alt(i)); az=atan2d(dy(i),dx(i));
        % detection scales with each target's own RCS (plane far, bird near),
        % so no hard range gate - pdet handles it. Slant range includes altitude.
        if abs(aeris.wrap180(az-beamAz))<=bwX/2 && rand<pdet(pX,gX,R,rcsv(i))
            heldX(i)=t;                                   % Extended: beam swept past
        end
        for k=1:4
            if abs(aeris.wrap180(az-nexBore(k)))<=pN.sectorWidth/2
                if rand<pdet(pN,gN,R,rcsv(i)), heldN(i)=t; end
                break;
            end
        end
    end

    % draw
    live = alive;
    hx = live & (heldX>0) & (t-heldX<3);
    hn = live & (heldN>0) & (t-heldN<3);
    ix = find(hx); in = find(hn);
    set(hUX,'XData',dx(live&~hx),'YData',dy(live&~hx));
    set(hUN,'XData',dx(live&~hn),'YData',dy(live&~hn));
    % held markers: colour by class, size by altitude (bigger = higher)
    upd_scatter(hHX, dx(ix), dy(ix), clsRGB(max(cls(ix),1),:), 15+alt(ix)/12);
    upd_scatter(hHN, dx(in), dy(in), clsRGB(max(cls(in),1),:), 15+alt(in)/12);
    tw=linspace(beamAz-40,beamAz,12);
    set(hWedge,'XData',[0 Rx*cosd(tw) 0],'YData',[0 Rx*sind(tw) 0]);
    set(hSweep,'XData',[0 Rx*cosd(beamAz)],'YData',[0 Rx*sind(beamAz)]);
    tX.String=sprintf('AERIS-10X   held %d   leaked %d   (R %.1f km, rev %.0fs)', sum(hx),leakX,Rx/1000,rotP);
    tN.String=sprintf('AERIS-10N x4   held %d   leaked %d   (R %.1f km, staring)', sum(hn),leakN,Rn/1000);

    drawnow; pause(0.03);                     % render every frame + pace it
end

if ishandle(fig)
    fprintf('\nstopped: leaked past 10X %d, past 4x10N %d\n', leakX, leakN);
end
end

% ------------------------------------------------------------------------
function R = reliable(p,g,rcs), pp=p; pp.targetRCS=rcs; R=aeris.reliable_range(pp,g); end
function pd = pdet(p,g,R,rcs), pp=p; pp.targetRCS=rcs; s=aeris.snr(pp,g,R); pd=p.Pfa.^(1./(1+s)); end
function v = unif(r), v = r(1) + rand*(r(2)-r(1)); end

function upd_scatter(h, x, y, cdata, sz)
if isempty(x), set(h,'XData',nan,'YData',nan); return; end
set(h,'XData',x,'YData',y,'CData',cdata,'SizeData',sz);
end

function setup_axes(ax,Rmax)
hold(ax,'on'); axis(ax,'equal'); set(ax,'Color',[.08 .10 .12],'XColor',[.3 .35 .4],'YColor',[.3 .35 .4]);
th=linspace(0,2*pi,100);
for r=2000:2000:Rmax, plot(ax,r*cos(th),r*sin(th),'-','Color',[.15 .18 .2]); end
plot(ax,0,0,'p','MarkerFaceColor',[1 .82 .2],'MarkerEdgeColor','none','MarkerSize',18);
xlim(ax,[-Rmax Rmax]); ylim(ax,[-Rmax Rmax]);
end

function draw_circle(ax,r,c)
th=linspace(0,2*pi,120);
fill(ax,r*cos(th),r*sin(th),c,'FaceAlpha',.06,'EdgeColor',c,'EdgeAlpha',.3);
end

function draw_wedge(ax,bore,width,r,c)
th=linspace(bore-width/2,bore+width/2,40);
fill(ax,[0 r*cosd(th) 0],[0 r*sind(th) 0],c,'FaceAlpha',.06,'EdgeColor',c,'EdgeAlpha',.3);
end
