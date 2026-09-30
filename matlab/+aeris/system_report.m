function S = system_report(p, nNodes)
%AERIS.SYSTEM_REPORT  One-page system-model summary of the node/network.
%   aeris.system_report                 % prints the whole system card
%   S = aeris.system_report(p, nNodes)
%
%   Composes every subsystem model into a single system-level picture - this is
%   the system model "at a glance". Each line is computed from the same
%   parameter struct that drives the sensing sim, so sensing, comms, power and
%   SWaP-C can never disagree with each other or with a scenario run.
%
%     SENSING   reliable range, beamwidths, revisit (aeris.reliable_range,
%               aeris.derive, aeris.dwell_plan)
%     COMMS     link range, per-hop latency (aeris.comms_range)
%     POWER     average DC draw, battery runtime (aeris.power_budget)
%     SWaP-C    weight and cost, per node and per network (aeris.bom)
%
%   This is the spine of the model: change one number (say the array size) and
%   the sensing range, the power draw, the weight and the cost all move together
%   the way they would on the real node.

if nargin < 1 || isempty(p), p = aeris_params(); end
if nargin < 2 || isempty(nNodes)
    nNodes = getf(p,'nNodes',1); if nNodes < 1, nNodes = 1; end
end

g   = aeris.derive(p);
rr  = aeris.reliable_range(p, g);
W   = aeris.dwell_plan(p, g);
cr  = aeris.comms_range(p);
pw  = aeris.power_budget(p);
bm  = aeris.bom(nNodes);

S = struct('reliableRange',rr,'azBW',g.azBW,'elBW',g.elBW,'revisit',W.revisit, ...
           'commsRange',cr,'powerW',pw.total_W,'runtimeH',pw.runtime_h, ...
           'nodeLb',bm.nodeLb,'nodeUsd',bm.nodeUsd,'nNodes',nNodes, ...
           'netLb',bm.netLb,'netUsd',bm.netUsd);

if nargout == 0
    line = repmat('=',1,58);
    fprintf('\n%s\n  AERIS-NEXUS SYSTEM MODEL  -  system summary\n%s\n', line, line);

    fprintf(' SENSING\n');
    fprintf('   frequency          %.2f GHz  (lambda %.1f mm)\n', p.freq/1e9, g.lambda*1e3);
    fprintf('   array              %d x %d elements\n', p.nAz, p.nEl);
    fprintf('   beamwidth          %.1f deg az  x  %.1f deg el\n', g.azBW, g.elBW);
    fprintf('   reliable range     %.2f km  (Pd %.2f, RCS %.3g m^2)\n', ...
            rr/1000, p.pdReliable, p.targetRCS);
    fprintf('   revisit            %.2f s  (%d dwells)\n', W.revisit, W.nDwells);

    fprintf(' COMMS\n');
    fprintf('   data link          %.0f MHz, %.0f dBm\n', p.commsFreq/1e6, getf(p,'commsPtx',30));
    fprintf('   link range         %.2f km  (per-hop latency %.1f s)\n', ...
            cr/1000, getf(p,'commsLatency',1.0));

    fprintf(' POWER\n');
    fprintf('   average draw       %.0f W  (%.1f A at %.0f V)\n', ...
            pw.total_W, pw.current_A, pw.battVoltage);
    fprintf('   battery runtime    %.1f h  (%.0f Wh)\n', pw.runtime_h, pw.battWh);

    fprintf(' SWaP-C\n');
    fprintf('   node weight        %.0f lb  (battery %.0f%%)\n', ...
            bm.nodeLb, 100*bm.batteryFrac);
    fprintf('   node cost          $%s\n', commafy(bm.nodeUsd));
    if nNodes > 1
        fprintf('   %d-node network     %.0f lb   $%s\n', ...
                nNodes, bm.netLb, commafy(bm.netUsd));
    end
    fprintf('%s\n', line);
    clear S
end
end

function v = getf(s,f,d), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end, end

function s = commafy(x)
s = sprintf('%.0f', x);
for k = numel(s)-3:-3:1, s = [s(1:k) ',' s(k+1:end)]; end
end
