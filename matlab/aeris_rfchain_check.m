function aeris_rfchain_check(p)
% AERIS_RFCHAIN_CHECK  Receiver noise figure from the RF cascade, and its
% effect on reliable range.
%
%   aeris_rfchain_check
%   aeris_rfchain_check(aeris_params('...'))
%
% Rung-2 report. Prints the receive chain stage by stage, the Friis cascade
% noise figure, and each stage's share of the total - so you can see the LNA
% dominate. Then compares reliable range with the assumed p.NF vs the modeled
% cascade NF, because that is what the NF number actually buys.

if nargin < 1 || isempty(p), p = aeris_params(); end

rc = aeris.rf_chain(p);

fprintf('\n--- RF receive chain (Friis cascade) ---\n');
fprintf('%-24s %7s %7s %10s\n','stage','gain dB','NF dB','contrib %');
fprintf('%s\n', repmat('-',1,52));
for k = 1:numel(rc.stages)
    st = rc.stages(k);
    fprintf('%-24s %7.1f %7.1f %9.1f   (%s)\n', st.name, st.gainDB, st.nfDB, ...
            100*rc.contrib(k), st.conf);
end
fprintf('%s\n', repmat('-',1,52));
fprintf('%-24s %7.1f %7.2f\n','CASCADE', rc.gainDB, rc.NF);

% ---- range impact -------------------------------------------------------
pa = p; pa.useRfChain = false;  ga = aeris.derive(pa);
pm = p; pm.useRfChain = true;   gm = aeris.derive(pm);
rra = aeris.reliable_range(pa, ga);
rrm = aeris.reliable_range(pm, gm);

fprintf('\n--- effect on sensing ---\n');
fprintf('assumed NF        %.2f dB  -> reliable range %.2f km\n', pa.NF, rra/1000);
fprintf('cascade  NF       %.2f dB  -> reliable range %.2f km\n', rc.NF, rrm/1000);
fprintf('delta             %+.2f dB -> %+.2f km  (%+.0f%%)\n', ...
        rc.NF-pa.NF, (rrm-rra)/1000, 100*(rrm-rra)/rra);
if rc.NF < pa.NF
    fprintf('=> the LNA-per-element chain beats the assumed NF; range is\n');
    fprintf('   conservative in the current RadarParams.\n');
end
end
