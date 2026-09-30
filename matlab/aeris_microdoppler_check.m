function aeris_microdoppler_check(p)
% AERIS_MICRODOPPLER_CHECK  Rotor micro-Doppler: the drone discriminator.
%
%   aeris_microdoppler_check
%   aeris_microdoppler_check(aeris_params())
%
% Shows what rotor blades add to the signal, and why it separates a drone from
% a rigid body (bird / clutter):
%   (1) range-Doppler map WITHOUT rotor (clean point) vs WITH rotor (a Doppler
%       smear across the velocity axis - the micro-Doppler signature);
%   (2) a slow-time spectrogram of the target range bin - the blades trace
%       sinusoidal tracks, the classic micro-Doppler picture;
%   (3) a discriminant: fraction of Doppler energy OFF the body line. A rotor
%       target sits high, a rigid one near zero -> a physics-based class flag
%       instead of the RCS+speed guess.
%
% Heavy (IQ datacubes). Needs no toolbox.

if nargin < 1 || isempty(p), p = aeris_params(); end
g = aeris.derive(p);
rangeAxis = (0:g.dR:p.Rmax).';  nR = numel(rangeAxis);
R = 2000; vr = -20; snr = 10^(22/10);       % bright target, clear signature

pOff = p; pOff.microDoppler = false;
pOn  = p; pOn.microDoppler  = true;
[Poff, vel] = aeris.look_iq(snr, R, vr, pOff, g, rangeAxis);
[Pon,  ~  ] = aeris.look_iq(snr, R, vr, pOn,  g, rangeAxis);

% discriminant: off-body Doppler energy fraction, of SIGNAL (noise removed).
% The matched-filter 'same' conv offsets the range peak by ~Nc/2, so find the
% target's actual range bin from the data rather than assuming it.
[~, di] = min(abs(vel - vr));
band = max(1,di-3):min(numel(vel),di+3);         % "body" Doppler band
nf   = median(Poff(:));                           % noise floor (~1)
thr  = 4*nf;                                       % keep only cells >6 dB over noise
[~, riPk] = max(max(Poff(:,band),[],2));          % actual peak range bin
gate = max(1,riPk-2):min(nR,riPk+2);
fOff = sfrac(Poff, gate, band, thr);
fOn  = sfrac(Pon,  gate, band, thr);

fprintf('\n--- micro-Doppler discriminant (off-body Doppler energy) ---\n');
fprintf('rigid body (rotor off): %.2f\n', fOff);
fprintf('drone (rotor on):       %.2f\n', fOn);
fprintf('=> the rotor smear raises off-body energy from %.0f%% to %.0f%% -\n', 100*fOff, 100*fOn);
fprintf('   a threshold on this flags "drone" from the signal, not from RCS.\n');

% ---- figures -----------------------------------------------------------
figure('Color','w','Position',[60 80 1360 460]);
% floor the colour scale ~6 dB over noise so noise goes dark and the target /
% smear stand out; zoom range to the target gate
rzoom = [rangeAxis(gate(1)) rangeAxis(gate(end))]/1000 + [-0.3 0.3];
subplot(1,3,1);
imagesc(vel, rangeAxis/1000, 10*log10(Poff)); set(gca,'YDir','normal');
colormap(turbo_or_jet()); caxis([6 max(10*log10(Poff(:)))]); ylim(rzoom); %#ok<CAXIS>
xlabel('velocity (m/s)'); ylabel('range (km)'); title('rigid body (no rotor)','FontWeight','normal');

subplot(1,3,2);
imagesc(vel, rangeAxis/1000, 10*log10(Pon)); set(gca,'YDir','normal');
colormap(turbo_or_jet()); caxis([6 max(10*log10(Pon(:)))]); ylim(rzoom); %#ok<CAXIS>
xlabel('velocity (m/s)'); ylabel('range (km)'); title('drone (rotor micro-Doppler smear)','FontWeight','normal');

% (3) micro-Doppler spectrogram of the target range bin (manual STFT) -----
subplot(1,3,3);
M = p.cpi; PRIv = 1/p.prf;
% rebuild the slow-time signal at the target range bin, rotor on, low noise
Om = 2*pi*p.rotorRPM/60; beta = 4*pi*p.bladeRadius/g.lambda;
tm = (0:M-1)*PRIv; nb = p.nBlades*p.nRotors;
rot = zeros(1,M); for bl=1:nb, rot=rot+exp(1j*beta*sin(Om*tm+2*pi*rand)); end
body = exp(1j*2*pi*(2*vr/g.lambda)*tm);
sig = body + 0.6*rot/nb;                          % body + rotor
% STFT: sliding windowed FFT
w = 32; hop = 4; nf = 64;
cols = 1:hop:(M-w);
Sp = zeros(nf, numel(cols));
hann = 0.5-0.5*cos(2*pi*(0:w-1)/(w-1));
for c = 1:numel(cols)
    seg = sig(cols(c):cols(c)+w-1) .* hann;
    F = fftshift(fft(seg, nf));
    Sp(:,c) = abs(F).^2;
end
fax = linspace(-p.prf/2, p.prf/2, nf) * g.lambda/2;   % -> velocity
imagesc((cols+w/2)*PRIv*1e3, fax, 10*log10(Sp+eps)); set(gca,'YDir','normal');
colormap(turbo_or_jet());
xlabel('slow time (ms)'); ylabel('velocity (m/s)');
title('micro-Doppler spectrogram: blade tracks','FontWeight','normal');
end

function f = sfrac(P, gate, band, thr)
% fraction of above-noise signal energy that is OFF the body Doppler band
G = max(P(gate,:) - thr, 0);           % signal in the gate, noise removed
f = 1 - sum(sum(G(:,band))) / max(sum(G(:)), eps);
end

function m = turbo_or_jet(), try, m=turbo(256); catch, m=jet(256); end, end
