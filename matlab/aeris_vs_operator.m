function aeris_vs_operator()
% AERIS_VS_OPERATOR  What each operator actually SEES: 10X vs 4x10N.
%
%   aeris_vs_operator
%
% The same drone/bird/plane stream flies in, but each panel shows ONLY what
% that architecture's operator sees - detected tracks, labelled by what the
% RADAR called them (with the real ~15% drone/bird confusion), not the truth.
% Undetected targets are invisible (the operator cannot see a miss). Runs until
% you click STOP.
%
%   LEFT  AERIS-10X  (1 node, 360 rotating, long range)
%   RIGHT 4x AERIS-10N (fixed sectors, short range, staring)
%
% Marker = radar's CALL: red diamond = "HOSTILE" (called drone), blue = bird,
% yellow = aircraft. Size = altitude. Tallies count threats correctly flagged,
% FALSE ALARMS (bird called drone) and MISSES (drone leaked or called bird) -
% the operational cost, per architecture.

dt = 0.25;
pX = aeris_params('extended'); pX.useRfChain = true; gX = aeris.derive(pX);
pN = aeris_params('nexus');    pN.useRfChain = true; gN = aeris.derive(pN);
rotP = pX.rotationPeriod; bwX = gX.azBW;
Rmax = 7500; nexBore = [0 90 180 270];
TC = aeris.target_classes(); classW=[6 3 1]; classCum=cumsum(classW)/sum(classW);
% confusion: P(correct) per class (from aeris_discriminate); plane perfect
pCorrect = [0.85 0.85 1.0];
clsCol = [.95 .3 .3; .4 .8 .95; .95 .8 .3];   % drone / bird / plane

fig = figure('Color',[.05 .06 .08],'Position',[40 60 1500 780], ...
             'Name','operator view: 10X vs 4x10N','NumberTitle','off');
setappdata(fig,'run',true);
uicontrol(fig,'Style','pushbutton','String','STOP','FontWeight','bold', ...
    'BackgroundColor',[.9 .3 .25],'ForegroundColor','w','Units','normalized', ...
    'Position',[0.46 0.955 0.08 0.04],'Callback',@(~,~) setappdata(fig,'run',false));
tl = tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');
axX = nexttile(tl); setup_axes(axX,Rmax);
axN = nexttile(tl); setup_axes(axN,Rmax);
draw_circle(axX, reliable(pX,gX,0.03), [.2 .4 .6]);
for k=1:4, draw_wedge(axN, nexBore(k), pN.sectorWidth, reliable(pN,gN,0.03), [.2 .4 .6]); end
for c=1:3, text(axX,-Rmax*0.95,Rmax*(0.95-0.07*c),sprintf('  %s',TC(c).name),'Color',clsCol(c,:),'FontWeight','bold','FontSize',9); end

hWedge=patch(axX,'XData',0,'YData',0,'FaceColor',[.3 .6 .5],'FaceAlpha',.08,'EdgeColor','none');
hSweep=plot(axX,[0 0],[0 0],'-','Color',[.4 .8 .6],'LineWidth',1.5);
% per side: tracks (dots, coloured by CALL) + threats (red diamonds)
hTX=scatter(axX,nan,nan,30,[0 0 0],'filled'); hThX=scatter(axX,nan,nan,80,[.95 .3 .3],'d','LineWidth',1.2);
hTN=scatter(axN,nan,nan,30,[0 0 0],'filled'); hThN=scatter(axN,nan,nan,80,[.95 .3 .3],'d','LineWidth',1.2);
tX=title(axX,'','Color','w','FontWeight','normal'); tN=title(axN,'','Color','w','FontWeight','normal');

P=300;
dx=nan(P,1);dy=nan(P,1);dvx=nan(P,1);dvy=nan(P,1);alt=nan(P,1);cls=zeros(P,1);rcsv=nan(P,1);
alive=false(P,1); heldX=zeros(P,1); heldN=zeros(P,1); callX=zeros(P,1); callN=zeros(P,1);
% cumulative operational tallies [flagged falseAlarm missed] per side
tX_=[0 0 0]; tN_=[0 0 0];
beamAz=0; nextSpawn=0; t=0;

while ishandle(fig) && getappdata(fig,'run')
    t=t+dt;
    if t>=nextSpawn
        s0=find(~alive,1);
        if ~isempty(s0)
            c=find(rand<=classCum,1); th=rand*360; s=unif(TC(c).spd);
            alt(s0)=unif(TC(c).alt); rcsv(s0)=exp(unif(log(TC(c).rcs))); cls(s0)=c;
            dx(s0)=Rmax*cosd(th); dy(s0)=Rmax*sind(th); dvx(s0)=-s*cosd(th); dvy(s0)=-s*sind(th);
            alive(s0)=true; heldX(s0)=0; heldN(s0)=0; callX(s0)=0; callN(s0)=0;
        end
        nextSpawn=t+1.5+rand*1.5;
    end
    for i=1:P
        if ~alive(i), continue; end
        dx(i)=dx(i)+dvx(i)*dt; dy(i)=dy(i)+dvy(i)*dt;
        if hypot(dx(i),dy(i))<150
            alive(i)=false;
            tX_ = tally(tX_, cls(i), callX(i));   % score at end of track life
            tN_ = tally(tN_, cls(i), callN(i));
        end
    end
    beamAz=mod(beamAz+360*dt/rotP,360);
    for i=1:P
        if ~alive(i), continue; end
        Rg=hypot(dx(i),dy(i)); R=hypot(Rg,alt(i)); az=atan2d(dy(i),dx(i));
        if abs(aeris.wrap180(az-beamAz))<=bwX/2 && rand<pdet(pX,gX,R,rcsv(i))
            heldX(i)=t; if callX(i)==0, callX(i)=classify(cls(i),pCorrect); end
        end
        for k=1:4
            if abs(aeris.wrap180(az-nexBore(k)))<=pN.sectorWidth/2
                if rand<pdet(pN,gN,R,rcsv(i)), heldN(i)=t; if callN(i)==0, callN(i)=classify(cls(i),pCorrect); end, end
                break;
            end
        end
    end
    % draw ONLY what each operator holds now, coloured by the radar's CALL
    hxN = alive & (heldN>0) & (t-heldN<3);
    hxX = alive & (heldX>0) & (t-heldX<3);
    drawside(hTX,hThX, dx,dy,alt,callX,hxX,clsCol);
    drawside(hTN,hThN, dx,dy,alt,callN,hxN,clsCol);
    tw=linspace(beamAz-40,beamAz,12);
    set(hWedge,'XData',[0 reliable(pX,gX,0.03)*cosd(tw) 0],'YData',[0 reliable(pX,gX,0.03)*sind(tw) 0]);
    set(hSweep,'XData',[0 Rmax*cosd(beamAz)],'YData',[0 Rmax*sind(beamAz)]);
    tX.String=sprintf('10X operator   threats %d  false-alarm %d  MISSED %d', tX_(1),tX_(2),tX_(3));
    tN.String=sprintf('4x10N operator   threats %d  false-alarm %d  MISSED %d', tN_(1),tN_(2),tN_(3));
    drawnow; pause(0.03);
end
if ishandle(fig)
    fprintf('\n10X : threats flagged %d, false alarms %d, missed %d\n', tX_(1),tX_(2),tX_(3));
    fprintf('4x10N: threats flagged %d, false alarms %d, missed %d\n', tN_(1),tN_(2),tN_(3));
end
end

% ------------------------------------------------------------------------
function cc = classify(trueClass, pCorrect)
if rand < pCorrect(trueClass), cc = trueClass;
else
    if trueClass==1, cc=2; elseif trueClass==2, cc=1; else, cc=3; end  % drone<->bird swap
end
end

function T = tally(T, trueC, calledC)
% [flagged falseAlarm missed]; scored once, at end of track
if trueC==1                                  % a real drone
    if calledC==1, T(1)=T(1)+1; else, T(3)=T(3)+1; end   % flagged or missed
elseif trueC==2                              % a bird
    if calledC==1, T(2)=T(2)+1; end                      % called a threat = false alarm
end
end

function drawside(hT,hTh, dx,dy,alt,call,mask,clsCol)
ix=find(mask);
if isempty(ix), set(hT,'XData',nan,'YData',nan); set(hTh,'XData',nan,'YData',nan); return; end
set(hT,'XData',dx(ix),'YData',dy(ix),'CData',clsCol(max(call(ix),1),:),'SizeData',15+alt(ix)/12);
dr = ix(call(ix)==1);                         % called-drone = highlighted threat
if isempty(dr), set(hTh,'XData',nan,'YData',nan);
else, set(hTh,'XData',dx(dr),'YData',dy(dr),'SizeData',80+alt(dr)/8); end
end

function R=reliable(p,g,rcs), pp=p; pp.targetRCS=rcs; R=aeris.reliable_range(pp,g); end
function pd=pdet(p,g,R,rcs), pp=p; pp.targetRCS=rcs; s=aeris.snr(pp,g,R); pd=p.Pfa.^(1./(1+s)); end
function v=unif(r), v=r(1)+rand*(r(2)-r(1)); end
function setup_axes(ax,Rmax)
hold(ax,'on'); axis(ax,'equal'); set(ax,'Color',[.08 .10 .12],'XColor',[.3 .35 .4],'YColor',[.3 .35 .4]);
th=linspace(0,2*pi,100); for r=2000:2000:Rmax, plot(ax,r*cos(th),r*sin(th),'-','Color',[.15 .18 .2]); end
plot(ax,0,0,'p','MarkerFaceColor',[1 .82 .2],'MarkerEdgeColor','none','MarkerSize',18);
xlim(ax,[-Rmax Rmax]); ylim(ax,[-Rmax Rmax]);
end
function draw_circle(ax,r,c), th=linspace(0,2*pi,120); fill(ax,r*cos(th),r*sin(th),c,'FaceAlpha',.06,'EdgeColor',c,'EdgeAlpha',.3); end
function draw_wedge(ax,bore,w,r,c), th=linspace(bore-w/2,bore+w/2,40); fill(ax,[0 r*cosd(th) 0],[0 r*sind(th) 0],c,'FaceAlpha',.06,'EdgeColor',c,'EdgeAlpha',.3); end
