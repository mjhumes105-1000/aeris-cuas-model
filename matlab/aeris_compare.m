function S = aeris_compare(N)
% AERIS_COMPARE  AERIS-10N (Nexus) vs AERIS-10X (Extended), head to head.
%
%   aeris_compare            % 4000 raids each
%   aeris_compare(15000)
%
% Runs the SAME random raid population through both variants and tabulates the
% four dimensions that actually differ: sensing (reliable range, warning),
% coverage/revisit (fixed 90 deg stare vs 360 deg rotation), power/endurance,
% and SWaP-C. This is the contribution comparison - not "is the node good" but
% "which architecture, and what do you give up".
%
% The variants (aeris_params presets 'nexus' / 'extended'):
%   10N  8x16 patch,  16 W, fixed 90 deg sector
%   10X  32x16 wg,   160 W, 360 deg rotating (revisit = rotation period)
% Both at 10.5 GHz, with the modeled RF chain on.

if nargin < 1 || isempty(N), N = 4000; end

E = aeris.environments(); D = aeris.drone_catalog();
eCum = cumsum([E.weight])/sum([E.weight]);
dCum = cumsum([D.weight])/sum([D.weight]);

variants = {'nexus','extended'};
res = struct('name',{},'conf',{},'met',{},'medWarn',{},'relRange',{}, ...
             'revisit',{},'powerW',{},'runtimeH',{},'nodeLb',{},'nodeUsd',{});

for v = 1:numel(variants)
    base = aeris_params(variants{v});
    base.randomThreats = true; base.headless = true; base.quiet = true;
    base.saveVideo = false; base.logData = false; base.useRfChain = true;
    base.battCapacityAh = 40;                 % same 960 Wh pack for both (label-consistent)
    g = aeris.derive(base);

    conf=0; met=0; wv=[];
    for i = 1:N
        p = base;
        e = E(find(rand<=eCum,1)); d = D(find(rand<=dCum,1));
        p.rainRate=e.rainRate; p.fogDensity=e.fogDensity; p.humidity=e.humidity;
        p.gammaDB=e.gammaDB; p.mtiImpDB=e.mtiImpDB; p.grazingDeg=e.grazingDeg;
        p.droneClass=d.name; p.Dforward=3000+rand*6000; p.rngSeed=9e6+1e3*v+i;
        r = aeris_engage(p);
        conf = conf + mean([r.per.confirmed]);
        met  = met  + double(r.requirementMet);
        if ~isnan(r.warnTime), wv(end+1)=r.warnTime; end %#ok<AGROW>
    end

    W  = aeris.dwell_plan(base, g);
    pw = aeris.power_budget(base);
    bm = aeris.bom(1, variant_bom(variants{v}));   % variant-specific SWaP-C
    revisit = W.revisit;
    if base.rotating, revisit = base.rotationPeriod; end

    res(v) = struct('name',variants{v}, 'conf',100*conf/N, 'met',100*met/N, ...
        'medWarn',median(wv), 'relRange',aeris.reliable_range(base,g)/1000, ...
        'revisit',revisit, 'powerW',pw.total_W, 'runtimeH',pw.runtime_h, ...
        'nodeLb',bm.nodeLb, 'nodeUsd',bm.nodeUsd);
end

% ---- table -------------------------------------------------------------
n = res(1); x = res(2);
fprintf('\n================  AERIS-10N vs 10X  (%d raids each)  ================\n', N);
fprintf('%-26s %14s %14s\n','', 'Nexus (10N)', 'Extended (10X)');
row('reliable range (km, 0.03m^2)', n.relRange,  x.relRange,  '%.2f');
row('revisit (s)',                  n.revisit,   x.revisit,   '%.2f');
row('confirmation rate (%)',        n.conf,      x.conf,      '%.1f');
row('warning met 300 s (%)',        n.met,       x.met,       '%.1f');
row('median warning (s)',           n.medWarn,   x.medWarn,   '%.0f');
row('avg power (W)',                n.powerW,    x.powerW,    '%.0f');
row('battery runtime (h, 960Wh)',   n.runtimeH,  x.runtimeH,  '%.1f');
row('node weight (lb)',             n.nodeLb,    x.nodeLb,    '%.0f');
row('node cost ($)',                n.nodeUsd,   x.nodeUsd,   '%.0f');
fprintf('====================================================================\n');
fprintf(['\nRead: 10X sees ~%.1fx farther, covers 360 deg, and warns +%.0f pts\n' ...
         'more - but draws %.0fx the power (%.1f h vs %.1f h on the same pack),\n' ...
         'weighs %.0fx and costs %.1fx more. Matching Nexus endurance would need\n' ...
         '~%.0fx the battery (~%.0f lb, ~$%.0f more) - it is the better sensor but\n' ...
         'the worse *attritable node*.\n'], ...
         x.relRange/max(n.relRange,eps), x.met-n.met, ...
         x.powerW/max(n.powerW,eps), x.runtimeH, n.runtimeH, ...
         x.nodeLb/max(n.nodeLb,eps), x.nodeUsd/max(n.nodeUsd,eps), ...
         ceil(n.runtimeH/max(x.runtimeH,eps)), ...
         (ceil(n.runtimeH/max(x.runtimeH,eps))-1)*20.9, ...
         (ceil(n.runtimeH/max(x.runtimeH,eps))-1)*580);

S = res;
if nargout==0, clear S; end
end

function row(label, a, b, fmt)
fprintf('%-26s %14s %14s\n', label, sprintf(fmt,a), sprintf(fmt,b));
end

function parts = variant_bom(name)
% variant-specific bill of materials (weight lb, cost $). The 10X is not a
% CN0566-class node: a 32x16 slotted-waveguide array with 16 GaN channels, a
% 360 deg rotator pedestal, and (at 411 W) a far bigger battery to hold a watch.
mk = @(nm,cat,q,lb,usd,cf) struct('name',nm,'cat',cat,'qty',q,'lb',lb,'usd',usd,'conf',cf);
if strcmpi(name,'extended') || strcmpi(name,'aeris10x')
    parts = mk('32x16 waveguide + GaN','radar',1, 6.0, 15000,'est');
    parts(end+1) = mk('ADAR1000 beamformers','radar',1, 0.5, 1200,'est');
    parts(end+1) = mk('360 rotator pedestal','struct',1, 12.0, 2500,'est');
    parts(end+1) = mk('Jetson Orin Nano','compute',1, 0.5, 250,'list');
    parts(end+1) = mk('Mesh Rider Mini','comms',1, 0.08, 1750,'quote');
    parts(end+1) = mk('antennas','comms',2, 0.25, 50,'est');
    parts(end+1) = mk('battery 24V 40Ah','power',1, 20.9, 580,'confirmed');
    parts(end+1) = mk('enclosure / mast / cabling','struct',1, 6.0, 500,'est');
else
    parts = [];                               % [] -> aeris.bom default (10N)
end
end
