function s = snr(p, g, R, gain)
%AERIS.SNR  Integrated SNR from the matched-filter radar equation.
%   s = aeris.snr(p, g, R)        integrated SNR (linear) at slant range R (m)
%   s = aeris.snr(p, g, R, gain)  additionally weighted by two-way beam gain
%
%   Energy form:  Pt*tau*G^2*lambda^2*sigma / ((4pi)^3 R^4 k Ts L), times the
%   coherent integration gain (= cpi). Vectorised in R.
%
%   THIS IS THE LINK BUDGET. It is the single MATLAB definition of the radar
%   equation, and it mirrors cuas_l3/radar.py. If you change it, change the
%   Python. aeris_nexus_linkbudget.m deliberately does NOT call this - it is an
%   independent reimplementation used to cross-check both.
%
%   gain is linear two-way beam weighting (1 = boresight, 0 = outside sector).

if nargin < 4, gain = 1; end

s = (p.Ptpeak * p.tau * g.Glin.^2 * g.lambda.^2 * p.targetRCS) ./ ...
    ((4*pi)^3 * R.^4 * p.k * g.Ts * g.Lsys) * g.intGain .* gain;

% signal-processing loss (window + straddle), measured by aeris_iq_check.
% ~2.5 dB, and it nearly cancels the RF-chain NF gain - so the conservative
% baseline holds. Default 0; set p.procLossDB to fold it in.
if isfield(p,'procLossDB') && ~isempty(p.procLossDB) && p.procLossDB ~= 0
    s = s / 10^(p.procLossDB/10);
end

% ---- two-way atmospheric attenuation (rain / fog / humidity / O2) -------
% Skipped entirely in clear dry air so the legacy baseline is bit-identical.
if has_weather(p)
    gamma = aeris.atmos_atten(p);                 % dB/km, one way
    s = s .* 10.^(-(2 * gamma * R/1000) / 10);    % two-way, there and back
end
end

function tf = has_weather(p)
tf = nz(p,'rainRate') || nz(p,'fogDensity') || ...
     (isfield(p,'humidity') && ~isempty(p.humidity) && p.humidity > 0);
end

function tf = nz(p, f)
tf = isfield(p,f) && ~isempty(p.(f)) && p.(f) > 0;
end
