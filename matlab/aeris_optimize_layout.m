function S = aeris_optimize_layout(N)
% AERIS_OPTIMIZE_LAYOUT  Best warning per node / per dollar across placements.
%
%   aeris_optimize_layout            % 500 raids per configuration
%   aeris_optimize_layout(1500)
%
% Turns the negative result into a design recommendation. Evaluates a set of
% candidate placements (count x layout x forward offset) over the same random
% raid population and reports the warning-satisfaction / cost frontier - i.e.
% the most warning you can buy for a given number of attritable nodes. The
% Pareto-efficient configs are the architecture recommendation.
%
% Comms gating is OFF here (a placement study, not a backhaul study); add it
% back with the backhaul recommendation once the layout is chosen.

if nargin < 1 || isempty(N), N = 500; end

% candidate configurations: {label, nNodes, layout, nodeForward}
C = {
   'single',        1, 'single', 0
   'line-2',        2, 'line',   0
   'line-3',        3, 'line',   0
   'line-4',        4, 'line',   0
   'depth-3',       3, 'depth',  0
   'grid-4',        4, 'grid',   0
   'grid-6',        6, 'grid',   0
   'pairs-4',       4, 'pairs',  0
   'pairs-4-fwd',   4, 'pairs',  0    % pairForward handled below
   'line-3-fwd2k',  3, 'line',   2000
};

base = aeris_params();
base.randomThreats = true; base.headless = true; base.quiet = true;
base.saveVideo = false; base.logData = false;
base.useRfChain = true;

E = aeris.environments(); D = aeris.drone_catalog();
eCum = cumsum([E.weight])/sum([E.weight]);
dCum = cumsum([D.weight])/sum([D.weight]);

nC = size(C,1);
met = zeros(1,nC); cost = zeros(1,nC); wt = zeros(1,nC); nn = zeros(1,nC);
fprintf('\n--- placement optimisation (%d raids each) ---\n', N);
fprintf('%-14s %6s %8s %10s %9s\n','config','nodes','met %','$ cost','med warn');
for c = 1:nC
    lbl = C{c,1};
    p = base; p.nNodes = C{c,2}; p.nodeLayout = C{c,3}; p.nodeForward = C{c,4};
    m = 0; wv = [];
    for i = 1:N
        pp = p;
        e = E(find(rand<=eCum,1)); d = D(find(rand<=dCum,1));
        pp.rainRate=e.rainRate; pp.fogDensity=e.fogDensity; pp.humidity=e.humidity;
        pp.gammaDB=e.gammaDB; pp.mtiImpDB=e.mtiImpDB; pp.grazingDeg=e.grazingDeg;
        pp.droneClass=d.name; pp.Dforward=3000+rand*6000; pp.rngSeed=7e6+1e3*c+i;
        r = aeris_engage(pp);
        m = m + double(r.requirementMet);
        if ~isnan(r.warnTime), wv(end+1)=r.warnTime; end %#ok<AGROW>
    end
    b = aeris.bom(C{c,2});
    met(c)=100*m/N; cost(c)=b.netUsd; nn(c)=C{c,2};
    wt(c)=median(wv);
    fprintf('%-14s %6d %8.1f %10s %8.0fs\n', lbl, C{c,2}, met(c), commafy(cost(c)), wt(c));
end

% Pareto frontier (max met% for min cost)
[cs, si] = sort(cost); ms = met(si); front = false(1,nC);
best = -inf;
for i = 1:nC
    if ms(i) > best, front(si(i)) = true; best = ms(i); end
end

fprintf('\nPareto-efficient (best met%% for the cost):\n');
for c = find(front), fprintf('  %-14s  %2d nodes  %.1f%%  $%s\n', C{c,1}, nn(c), met(c), commafy(cost(c))); end

figure('Color','w','Position',[100 100 780 520]); hold on; grid on;
scatter(cost/1000, met, 70, nn, 'filled');
for c=1:nC, text(cost(c)/1000+0.3, met(c), C{c,1},'FontSize',8,'Interpreter','none'); end
fc = find(front); [~,o]=sort(cost(fc)); fc=fc(o);
plot(cost(fc)/1000, met(fc), 'k--','LineWidth',1.2);
cb=colorbar; cb.Label.String='node count';
xlabel('network cost ($k)'); ylabel('raids meeting requirement (%)');
title('placement frontier: warning per dollar','FontWeight','normal');

S = struct('config',{C(:,1)'},'nNodes',nn,'met',met,'cost',cost,'medWarn',wt,'pareto',front);
if nargout==0, clear S; end
end

function s = commafy(x)
s = sprintf('%.0f', x);
for k = numel(s)-3:-3:1, s = [s(1:k) ',' s(k+1:end)]; end
end
