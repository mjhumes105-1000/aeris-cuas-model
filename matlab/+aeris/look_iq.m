function [P, velAxis] = look_iq(snrv, Rv, vrv, p, g, rangeAxis)
%AERIS.LOOK_IQ  IQ signal-level range-Doppler map (rung-3 fidelity).
%   [P, velAxis] = aeris.look_iq(snrv, Rv, vrv, p, g, rangeAxis)
%
%   Builds a real IQ datacube and processes it, instead of synthesising the
%   range-Doppler map to a target SNR (aeris.look). Per dwell:
%     1. transmit an LFM chirp (phased-array-free, explicit)
%     2. form the fast-time x slow-time cube: each target is a delayed chirp
%        (range) with a per-pulse Doppler phase (velocity), plus complex
%        thermal noise
%     3. matched-filter each pulse (pulse compression -> range)
%     4. windowed FFT across the CPI pulses (Doppler)
%     5. |.|^2 -> power map, normalised so the noise floor is ~1 (same units
%        as aeris.look, so aeris.cfar runs on it unchanged)
%
%   This map carries what the synthesised one cannot: real LFM range sidelobes,
%   Doppler window sidelobes, straddle loss (targets between bins), and window
%   loss - the effects that make the synthesised map mildly optimistic. Per-
%   pulse amplitude is calibrated so the ideal post-processing peak SNR equals
%   snrv; the shortfall the IQ map then shows IS the processing loss.
%
%   Heavy (a full CPI datacube per call) - for validation and interactive use,
%   NOT the 15k sweep. snrv/Rv/vrv may be vectors (multi-target).

nR  = numel(rangeAxis);
M   = p.cpi;
fs  = p.Bchirp;                       % fast-time rate; range bin = c/2fs = g.dR
PRI = 1/p.prf;
Nc  = max(round(p.tau*fs), 4);        % chirp length in samples

tc    = (0:Nc-1).'/fs;
chirp = exp(1j*pi*(p.Bchirp/p.tau)*tc.^2);     % baseband LFM
mf    = conj(flipud(chirp));                    % matched filter
win   = 0.5 - 0.5*cos(2*pi*(0:M-1)/(M-1));      % Hann (slow-time), no toolbox

microDoppler = isfield(p,'microDoppler') && ~isempty(p.microDoppler) && p.microDoppler;
PRIv = 1/p.prf;  tm = (0:M-1)*PRIv;             % slow-time samples

% ---- datacube: thermal noise (unit power per sample) -------------------
X = (randn(nR, M) + 1j*randn(nR, M)) / sqrt(2);

% ---- add each target: delayed chirp x per-pulse Doppler phase ----------
for k = 1:numel(snrv)
    if snrv(k) <= 0, continue; end
    [~, ri] = min(abs(rangeAxis - Rv(k)));
    swer = -log(rand);                         % Swerling-1 power fluctuation
    a    = sqrt(snrv(k) * swer / (Nc * M));    % calibrated per-pulse amplitude
    fd   = 2 * vrv(k) / g.lambda;              % Doppler frequency
    ph   = exp(1j*2*pi*fd*PRI*(0:M-1));        % 1 x M slow-time phase
    idx  = ri:min(ri+Nc-1, nR); L = numel(idx);
    X(idx,:) = X(idx,:) + a * chirp(1:L) * ph;

    % ---- rotor micro-Doppler: blade-tip scatterers phase-modulate the return
    % A tip scatterer at radius Rb rotating at Omega has radial velocity
    % v_tip*cos(Omega t), so its slow-time return is exp(j*beta*sin(Omega t)),
    % beta = 4*pi*Rb/lambda - an FM whose Bessel sidebands smear the target
    % across +/- 2*v_tip/lambda in Doppler. That smear is the drone signature
    % a rigid body (bird, clutter) does not have.
    if microDoppler
        Om   = 2*pi * getf(p,'rotorRPM',10000) / 60;   % rad/s
        beta = 4*pi * getf(p,'bladeRadius',0.10) / g.lambda;
        nb   = getf(p,'nBlades',2) * getf(p,'nRotors',4);
        rot  = zeros(1, M);
        for bl = 1:nb
            rot = rot + exp(1j*beta*sin(Om*tm + 2*pi*rand));   % random blade phase
        end
        rot = rot / nb;
        ar  = a * sqrt(getf(p,'rotorFrac',0.4));               % rotor power fraction
        X(idx,:) = X(idx,:) + ar * chirp(1:L) * (ph .* rot);
    end
end

% ---- pulse compression (matched filter along fast-time) ----------------
Xc = zeros(nR, M);
for m = 1:M
    Xc(:,m) = conv(X(:,m), mf, 'same');
end

% ---- Doppler processing (windowed FFT across pulses) -------------------
RD = fftshift(fft(Xc .* win, M, 2), 2);
P  = abs(RD).^2;
P  = P / median(P(:));                          % noise floor ~1 (match aeris.look)

velAxis = linspace(-g.vUnamb, g.vUnamb, M);
end

function v = getf(s,f,d)
if isfield(s,f) && ~isempty(s.(f)), v=s.(f); else, v=d; end
end
