function rc = rf_chain(p)
%AERIS.RF_CHAIN  Receiver noise figure from the actual RF cascade (rung 2).
%   rc = aeris.rf_chain(p)
%
%   Replaces the single system NF with Friis' cascade over the real receive
%   chain. The lesson the cascade teaches: a low-NF, high-gain LNA in the FIRST
%   stage sets the system NF almost by itself - later stages are divided by the
%   gain ahead of them - so an LNA-per-element architecture (CN0566: ADL8107 at
%   each patch) gives a system NF close to the LNA's own.
%
%     F_sys = F1 + (F2-1)/G1 + (F3-1)/(G1 G2) + ...      (linear F, G)
%
%   Default stages are the CN0566-class chain (LNA -> beamformer -> mixer ->
%   IF/ADC); datasheet values where known, estimates flagged. Override with
%   p.rxStages (struct array: name, gainDB, nfDB) to model a different chain.
%
%   Returns rc with fields:
%     stages    the chain used
%     NF        system noise figure (dB)
%     gainDB    total chain gain (dB)
%     contrib   each stage's share of the total noise factor (fraction)
%
%   NOTE: any loss BEFORE the LNA (radome, T/R switch, cable) adds nearly
%   1:1 to NF. The CN0566 puts the LNA at the element, so pre-LNA loss is
%   small - add a lossy first stage if your build does not.

stages = default_stages();
if isfield(p,'rxStages') && ~isempty(p.rxStages), stages = p.rxStages; end

Fi = 10.^([stages.nfDB]/10);
Gi = 10.^([stages.gainDB]/10);
n  = numel(stages);

Ftot   = Fi(1);
Gcum   = 1;                       % gain ahead of stage k
added  = zeros(1,n);
added(1) = Fi(1);                 % first stage contributes its full F
Gcum   = Gi(1);
for k = 2:n
    added(k) = (Fi(k)-1) / Gcum;
    Ftot     = Ftot + added(k);
    Gcum     = Gcum * Gi(k);
end

rc = struct('stages',stages, 'NF',10*log10(Ftot), ...
            'gainDB',10*log10(Gcum), 'Ftot',Ftot, ...
            'contrib', added / Ftot);
end

% ------------------------------------------------------------------------
function s = default_stages()
% CN0566-class X-band receive chain. conf: 'datasheet' or 'est'.
s = st('ADL8107 LNA',        24, 1.3, 'datasheet');
s(end+1) = st('ADAR1000 beamformer', 10, 5.0, 'est');
s(end+1) = st('downconvert mixer',   -7, 8.0, 'est');
s(end+1) = st('IF amp + Pluto ADC',  20, 12.0,'est');
end

function s = st(name, gainDB, nfDB, conf)
s = struct('name',name,'gainDB',gainDB,'nfDB',nfDB,'conf',conf);
end
