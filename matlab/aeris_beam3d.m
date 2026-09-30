function W = aeris_beam3d(p, varargin)
% AERIS_BEAM3D  3-D beam pattern, dwell tiling, and revisit timing.
%
%   aeris_beam3d                                  % baseline
%   aeris_beam3d(aeris_params(), 'animate', true) % step through the dwells
%   aeris_beam3d(aeris_params(), 'elevCover', [0 45])
%   W = aeris_beam3d;                             % return the dwell plan
%
% Four panels:
%   (1) 3-D radiation pattern of ONE beam - the real lobe, mainlobe and
%       sidelobes, radius scaled by gain in dB.
%   (2) 3-D dwell tiling - every beam position in the sector drawn as its
%       3-dB footprint on a range shell, so gaps and overlap are visible.
%   (3) vertical coverage - which altitudes are illuminated at which ground
%       ranges, with typical drone altitudes overlaid. This is where the
%       elevation coverage hole shows up.
%   (4) dwell budget - dwell time, revisit period, and the earliest possible
%       M-of-N track confirmation against the warning requirement.
%
% Name/value options
%   'animate'    false   step the beam through every dwell position
%   'elevCover'  []      override p.elevCoverDeg, e.g. [0 45]
%   'range'      []      shell range for the footprint plot (default Rmax)
%   'save'       ''      save the figure to this file (png/pdf)
%
% The pattern comes from aeris.pattern2d (separable uniform-aperture array
% factor). Beam SHAPE and tiling are trustworthy; absolute far-out sidelobe
% levels are optimistic because the element pattern is not included.
%
% See also AERIS.DWELL_PLAN, AERIS.PATTERN2D, AERIS_SCOPE_SIM3D.

if nargin < 1 || isempty(p), p = aeris_params(); end
o = opts(varargin, struct('animate',false,'elevCover',[],'range',[],'save',''));

if ~isempty(o.elevCover), p.elevCoverDeg = o.elevCover; end

g = aeris.derive(p);
W = aeris.dwell_plan(p, g);
Rshell = o.range; if isempty(Rshell), Rshell = p.Rmax; end
DEG = char(176);

fprintf('\n--- beam / dwell geometry ---\n');
fprintf('wavelength        %.2f cm\n', g.lambda*100);
fprintf('3-dB beamwidth    %.2f deg az  x  %.2f deg el\n', W.azBW, W.elBW);
fprintf('sector            %.0f deg wide, elevation %.0f-%.0f deg\n', ...
        p.sectorWidth, W.cover(1), W.cover(2));
fprintf('beam positions    %d az x %d el = %d dwells\n', W.Na, W.Ne, W.nDwells);
fprintf('dwell time        %.1f ms  (cpi %d / prf %.0f kHz)\n', ...
        W.dwellTime*1000, p.cpi, p.prf/1e3);
fprintf('revisit period    %.2f s\n', W.revisit);
fprintf('earliest confirm  %.2f s  (%d-of-%d looks)\n', ...
        W.tConfirm, p.MofN(1), p.MofN(2));
if W.revisit <= p.frameDt
    fprintf(['=> revisit (%.2f s) <= frameDt (%.1f s): the scope sim ' ...
             'assumption\n   that one look = one full scan HOLDS.\n'], ...
             W.revisit, p.frameDt);
else
    fprintf(['=> WARNING revisit (%.2f s) EXCEEDS frameDt (%.1f s): the ' ...
             'scope sim\n   is optimistic - it gives the target more looks ' ...
             'than the beam\n   schedule can actually deliver.\n'], ...
             W.revisit, p.frameDt);
end

% ========================================================================
fig = figure('Color','w','Position',[50 50 1440 840], ...
             'Name','AERIS beams & dwells','NumberTitle','off');
tiledlayout(fig, 2, 2, 'TileSpacing','compact','Padding','compact');

% ---- (1) 3-D radiation pattern of one beam -----------------------------
ax1 = nexttile; hold(ax1,'on');
azG = -90:1:90;  elG = -30:1:60;
steerAz = p.boresight;  steerEl = mean(W.elBeams);
G = aeris.pattern2d(azG, elG, p, steerAz, steerEl);

floorDB = 35;                                   % dynamic range of the plot
GdB = 10*log10(max(G, 10^(-floorDB/10)));
r   = max(GdB + floorDB, 0) / floorDB;          % 0 at the floor, 1 at peak

[AZ, EL] = meshgrid(azG, elG);
X = r .* cosd(EL) .* cosd(AZ);
Y = r .* cosd(EL) .* sind(AZ);
Z = r .* sind(EL);
surf(ax1, X, Y, Z, GdB, 'EdgeColor','none', 'FaceAlpha',.92);
colormap(ax1, turbo_safe());
cb1 = colorbar(ax1); cb1.Label.String = 'gain (dB rel. peak)';
plot3(ax1, [0 1.25],[0 0],[0 0], 'k-','LineWidth',1);       % boresight
plot3(ax1, 0,0,0,'k^','MarkerSize',8,'MarkerFaceColor','w');
axis(ax1,'equal'); grid(ax1,'on'); box(ax1,'on');
view(ax1, 40, 22); camproj(ax1,'perspective');
xlabel(ax1,'boresight'); ylabel(ax1,'azimuth'); zlabel(ax1,'elevation');
title(ax1, sprintf('one beam: %.1f%s az x %.1f%s el   (steered %.0f%s az, %.0f%s el)', ...
      W.azBW, DEG, W.elBW, DEG, steerAz, DEG, steerEl, DEG), 'FontWeight','normal');

% ---- (2) 3-D dwell tiling ----------------------------------------------
ax2 = nexttile; hold(ax2,'on'); grid(ax2,'on'); box(ax2,'on');
thS = linspace(p.boresight-p.sectorWidth/2, p.boresight+p.sectorWidth/2, 60);
patch(ax2,'XData',[0 Rshell*cosd(thS) 0],'YData',[0 Rshell*sind(thS) 0], ...
      'ZData',zeros(1,numel(thS)+2), 'FaceColor',[.90 .93 .97], ...
      'EdgeColor',[.6 .7 .8],'FaceAlpha',.35);

t     = linspace(0, 2*pi, 40);
cmap2 = bar_colors(W.Ne);
for je = 1:W.Ne
    for ia = 1:W.Na
        a0 = W.azBeams(ia); e0 = W.elBeams(je);
        [fx,fy,fz] = sph2cart_deg(a0 + (W.azBW/2)*cos(t), ...
                                  e0 + (W.elBW/2)*sin(t), Rshell);
        patch(ax2,'XData',fx,'YData',fy,'ZData',fz, ...
              'FaceColor',cmap2(je,:),'EdgeColor',cmap2(je,:)*.6, ...
              'FaceAlpha',.28,'LineWidth',.5);
    end
end
% pencil edges on the centre beam of each elevation bar, to show the volume
iaMid = max(1, round(W.Na/2));
for je = 1:W.Ne
    a0 = W.azBeams(iaMid); e0 = W.elBeams(je);
    for s = [-1 1]
        [ex,ey,ez] = sph2cart_deg(a0 + s*W.azBW/2, e0, Rshell);
        plot3(ax2,[0 ex],[0 ey],[0 ez],'-','Color',cmap2(je,:),'LineWidth',.8);
    end
end
plot3(ax2, 0,0,0,'k^','MarkerSize',10,'MarkerFaceColor','w','LineWidth',1.2);
axis(ax2,'equal'); view(ax2, -50, 20); camproj(ax2,'perspective');
xlabel(ax2,'x (m)'); ylabel(ax2,'y (m)'); zlabel(ax2,'z (m)');
title(ax2, sprintf('%d dwells (%d az x %d el), footprints at %.1f km', ...
      W.nDwells, W.Na, W.Ne, Rshell/1000), 'FontWeight','normal');

% ---- (3) vertical coverage --------------------------------------------
ax3 = nexttile; hold(ax3,'on'); grid(ax3,'on');
Rg = linspace(0, p.Rmax, 200);
lo = max(W.cover(1) - W.elBW/2, 0);
hi = W.cover(2) + W.elBW/2;
fill(ax3, [Rg fliplr(Rg)]/1000, [Rg*tand(lo) fliplr(Rg*tand(hi))], ...
     [.80 .89 .95], 'EdgeColor',[.45 .60 .75], 'FaceAlpha',.75);
for je = 1:W.Ne
    plot(ax3, Rg/1000, Rg*tand(W.elBeams(je)), '-', ...
         'Color',cmap2(je,:),'LineWidth',1.1);
end
D = aeris.drone_catalog();
cols3 = lines(numel(D));
for i = 1:numel(D)
    yline(ax3, mean(D(i).alt), '--', strrep(D(i).name,'_','\_'), ...
        'Color',cols3(i,:), 'LabelHorizontalAlignment','left', 'FontSize',7);
end
zTop = max(600, p.Rmax*tand(hi));
xlabel(ax3,'ground range (km)'); ylabel(ax3,'altitude (m)');
ylim(ax3,[0 zTop]);
title(ax3, sprintf('vertical coverage, elevation %.0f-%.0f%s', ...
      W.cover(1), W.cover(2), DEG), 'FontWeight','normal');
% the blind cone: a drone at altitude h is above the top bar inside this range
hRef  = 120;
rHole = hRef / tand(hi);
text(ax3, 0.04*p.Rmax/1000, 0.94*zTop, ...
    sprintf(['above %.0f%s elevation: not illuminated\n' ...
             'a %.0f m drone is inside the beam only\n' ...
             'beyond %.0f m ground range'], hi, DEG, hRef, rHole), ...
    'FontSize',8,'Color',[.70 .15 .10],'VerticalAlignment','top');

% ---- (4) dwell budget --------------------------------------------------
ax4 = nexttile; axis(ax4,'off');
L = {
 '\bf beam\rm'
 sprintf('  3-dB beamwidth     %.2f%s az  x  %.2f%s el', W.azBW, DEG, W.elBW, DEG)
 sprintf('  array              %d az x %d el elements at %.2f lambda', p.nAz, p.nEl, p.dspaceWL)
 ''
 '\bf schedule\rm'
 sprintf('  beam positions     %d az x %d el = %d dwells', W.Na, W.Ne, W.nDwells)
 sprintf('  beam spacing       %.2f x 3-dB beamwidth', W.spacing)
 sprintf('  dwell time         %.1f ms  (cpi %d @ prf %.0f kHz)', W.dwellTime*1000, p.cpi, p.prf/1e3)
 sprintf('  revisit period     %.2f s', W.revisit)
 ''
 '\bf consequences\rm'
 sprintf('  earliest confirm   %.2f s   (%d-of-%d looks)', W.tConfirm, p.MofN(1), p.MofN(2))
 sprintf('  chain latency      %.0f s', p.latency)
 sprintf('  requirement        %.0f s warning', p.Treq)
 ''
};
if W.revisit <= p.frameDt
    L{end+1} = sprintf('  \\color{green}revisit %.2f s <= frameDt %.1f s: assumption holds', ...
                       W.revisit, p.frameDt);
else
    L{end+1} = sprintf('  \\color{red}revisit %.2f s > frameDt %.1f s: sim is OPTIMISTIC', ...
                       W.revisit, p.frameDt);
end
L{end+1} = '';
L{end+1} = sprintf('  a full scan is %.1f%% of the %.0f s requirement', ...
                   100*W.revisit/p.Treq, p.Treq);
L{end+1} = '  -> dwell scheduling is NOT the binding constraint;';
L{end+1} = '     sensitivity and placement are.';
text(ax4, 0.02, 0.98, L, 'VerticalAlignment','top', ...
     'FontName','FixedWidth','FontSize',9.5,'Interpreter','tex');
title(ax4,'dwell budget','FontWeight','normal');

sgtitle(fig, sprintf('AERIS-Nexus beams & dwells  |  %.1f GHz  |  %d-element URA', ...
        p.freq/1e9, p.nAz*p.nEl), 'FontSize', 12);

% ---- optional animation ------------------------------------------------
if o.animate
    hl = plot3(ax2, nan, nan, nan, '-', 'Color',[.90 .25 .15], 'LineWidth',2.5);
    hp = patch(ax2,'XData',nan,'YData',nan,'ZData',nan, ...
               'FaceColor',[.95 .35 .20],'EdgeColor',[.70 .15 .10], ...
               'FaceAlpha',.75,'LineWidth',1.2);
    for je = 1:W.Ne
        for ia = 1:W.Na
            a0 = W.azBeams(ia); e0 = W.elBeams(je);
            [cx,cy,cz] = sph2cart_deg(a0, e0, Rshell);
            set(hl,'XData',[0 cx],'YData',[0 cy],'ZData',[0 cz]);
            [fx,fy,fz] = sph2cart_deg(a0+(W.azBW/2)*cos(t), ...
                                      e0+(W.elBW/2)*sin(t), Rshell);
            set(hp,'XData',fx,'YData',fy,'ZData',fz);
            k = (je-1)*W.Na + ia;
            ax2.Title.String = sprintf('dwell %d/%d   az %.1f%s  el %.1f%s   t = %.0f ms', ...
                k, W.nDwells, a0, DEG, e0, DEG, k*W.dwellTime*1000);
            drawnow limitrate
        end
    end
    ax2.Title.String = sprintf('%d dwells (%d az x %d el), footprints at %.1f km', ...
        W.nDwells, W.Na, W.Ne, Rshell/1000);
end

if ~isempty(o.save)
    try
        exportgraphics(fig, o.save, 'Resolution', 200);
    catch
        saveas(fig, o.save);
    end
    fprintf('saved %s\n', o.save);
end

if nargout == 0, clear W; end
end

% ========================================================================
function [x,y,z] = sph2cart_deg(azDeg, elDeg, R)
% boresight +x, azimuth about z, elevation up
x = R .* cosd(elDeg) .* cosd(azDeg);
y = R .* cosd(elDeg) .* sind(azDeg);
z = R .* sind(elDeg);
end

function o = opts(args, o)
for i = 1:2:numel(args)
    n = args{i};
    if ~isfield(o,n), error('aeris:beam3d','unknown option "%s"', n); end
    o.(n) = args{i+1};
end
end

function m = turbo_safe()
try, m = turbo(256); catch, m = jet(256); end
end

function m = bar_colors(n)
n = max(n,1);
try, m = parula(max(n,2)); catch, m = winter(max(n,2)); end
m = m(1:n,:);
end
