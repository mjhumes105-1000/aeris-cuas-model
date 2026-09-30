function P = power_budget(p)
%AERIS.POWER_BUDGET  DC power draw of one node and battery runtime.
%   P = aeris.power_budget(p)         % returns a struct
%   aeris.power_budget(p)             % prints a table
%
%   A field node is radar + data link + compute, and for an ATTRITABLE node the
%   power/SWaP budget is a first-class constraint, not an afterthought. This
%   estimates the average DC draw and the runtime on a battery. The RADAR IS
%   PULSED, so what matters is AVERAGE power (peak transients are handled by
%   bulk capacitance, not the battery), which is why a 20 W-peak radar does not
%   need a 20 W supply.
%
%   NOTE: the MATLAB toolboxes (Antenna/RF/RF Blockset) run on the design
%   laptop, NOT the node - they do not appear here.
%
%   Parameters consumed (all optional; defaults are a modest low-cost node):
%     radar:  p.Ptpeak, p.tau, p.prf (-> duty & average RF), p.nAz*p.nEl,
%             p.paEff (PA efficiency), p.perElemW (per T/R module DC; 0 = passive
%             array with a single PA), p.radarBackendW (exciter/rx/ADC/FPGA)
%     comms:  p.commsRadioW (MANET radio total draw, not just Tx)
%     compute:p.computeW (SBC running CFAR/tracker)
%     misc:   p.miscFactor (cooling/regulator losses, e.g. 1.15)
%     battery:p.battVoltage (V), p.battCapacityAh (Ah)
%
%   Returns per-subsystem watts, total watts, current at the battery voltage,
%   and runtime hours.

Ptpeak = getf(p,'Ptpeak',20);
tau    = getf(p,'tau',10e-6);
prf    = getf(p,'prf',10e3);
nEl    = getf(p,'nAz',8) * getf(p,'nEl',16);

paEff    = getf(p,'paEff',0.30);
perElemW = getf(p,'perElemW',0.25);
backendW = getf(p,'radarBackendW',25);
commsW   = getf(p,'commsRadioW',8);
computeW = getf(p,'computeW',15);
misc     = getf(p,'miscFactor',1.15);

Vb = getf(p,'battVoltage',24);
Ah = getf(p,'battCapacityAh',20);

duty  = tau * prf;                       % fraction of time transmitting
avgRF = Ptpeak * duty;                    % average radiated power, W
paDC  = avgRF / max(paEff,1e-3);          % PA DC draw
arrDC = nEl * perElemW;                   % active array T/R modules
radar = paDC + arrDC + backendW;

subtotal = radar + commsW + computeW;
total    = subtotal * misc;               % losses/cooling

I  = total / Vb;                          % battery current
Wh = Vb * Ah;                             % battery energy
hrs = Wh / total;

P = struct('duty',duty,'avgRF_W',avgRF,'paDC_W',paDC,'array_W',arrDC, ...
           'radarBackend_W',backendW,'radar_W',radar,'comms_W',commsW, ...
           'compute_W',computeW,'total_W',total,'current_A',I, ...
           'battVoltage',Vb,'battWh',Wh,'runtime_h',hrs);

if nargout == 0
    fprintf('\n--- node power budget (avg DC) ---\n');
    fprintf('radar PA        %6.1f W   (%.1f W avg RF @ %.0f%% duty, %.0f%% eff)\n', ...
            paDC, avgRF, 100*duty, 100*paEff);
    fprintf('radar array     %6.1f W   (%d elements x %.2f W)\n', arrDC, nEl, perElemW);
    fprintf('radar backend   %6.1f W\n', backendW);
    fprintf('comms radio     %6.1f W\n', commsW);
    fprintf('compute         %6.1f W\n', computeW);
    fprintf('losses/cooling  %6.1f W   (x%.2f)\n', total-subtotal, misc);
    fprintf('                ------\n');
    fprintf('TOTAL           %6.1f W   = %.1f A at %.0f V\n', total, I, Vb);
    fprintf('battery         %.0f V x %.0f Ah = %.0f Wh  ->  runtime %.1f h\n', ...
            Vb, Ah, Wh, hrs);
    clear P
end
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
