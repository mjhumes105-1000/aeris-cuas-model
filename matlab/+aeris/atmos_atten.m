function [gamma, parts] = atmos_atten(p)
%AERIS.ATMOS_ATTEN  One-way specific atmospheric attenuation, dB/km.
%   [gamma, parts] = aeris.atmos_atten(p)
%
%   Sums the four X-band loss mechanisms. Multiply by 2*R_km for the two-way
%   path loss that aeris.snr applies.
%
%   parts is a struct with the individual dB/km contributions (o2, h2o, rain,
%   fog) so a result can be attributed to a mechanism rather than a total.
%
%   Parameters consumed (all optional; absent = 0 = clear air):
%     p.rainRate   mm/hr  rain rate
%     p.fogDensity g/m^3  liquid water density (0.05 light, 0.5 dense fog)
%     p.humidity   g/m^3  absolute humidity (7.5 = ITU reference, ~20 tropical)
%     p.tempC      deg C  air temperature (default 15)
%
%   MODELS AND THEIR PROVENANCE
%     oxygen  ITU-R P.676 approximate dry-air form, f < 57 GHz, sea level.
%             ~0.007 dB/km at 9.5 GHz.
%     vapour  ITU-R P.676 approximate wet form; 9.5 GHz sits on the low-
%             frequency tail of the 22.235 GHz water line, so this is small.
%     rain    ITU-R P.838  gamma = k * R^alpha. Coefficients k=0.0095,
%             alpha=1.288 are LOG-INTERPOLATED between the tabulated 8 GHz
%             and 10 GHz horizontal-polarisation values to 9.5 GHz.
%     fog     ITU-R P.840 Rayleigh cloud form, gamma = Kl * M, with
%             Kl ~ 0.09 (dB/km)/(g/m^3) at 9.5 GHz / 10 C.
%
%   PROVISIONAL. These are standard published models, not measurements, and
%   the rain coefficients are an interpolation. Cite them as such.
%
%   Sanity check at 9.5 GHz, 5 km two-way:
%     clear air, dry      ~0.08 dB   (negligible)
%     humid 20 g/m^3      ~0.25 dB   (negligible)
%     dense fog 0.5 g/m^3 ~0.70 dB   (minor - X-band is fog-tolerant;
%                                    includes the humid air fog implies)
%     rain 25 mm/hr       ~6.0 dB    (significant)
%     rain 50 mm/hr       ~15 dB     (severe)
%   That asymmetry - rain matters, fog does not - is itself a finding.

fGHz = p.freq / 1e9;

rain = getf(p,'rainRate',   0);
fog  = getf(p,'fogDensity', 0);
rho  = getf(p,'humidity',   7.5);

% ---- oxygen (dry air), ITU-R P.676 approximate ---------------------------
parts.o2 = (7.19e-3 + 6.09/(fGHz^2 + 0.227) + 4.81/((fGHz-57)^2 + 1.50)) ...
           * fGHz^2 * 1e-3;

% ---- water vapour, ITU-R P.676 approximate ------------------------------
parts.h2o = (0.050 + 0.0021*rho + 3.6/((fGHz-22.2)^2 + 8.5)) ...
            * fGHz^2 * rho * 1e-4;

% ---- rain, ITU-R P.838 --------------------------------------------------
kR = getf(p,'rainK',     0.0095);      % interpolated to 9.5 GHz, H-pol
aR = getf(p,'rainAlpha', 1.288);
if rain > 0
    parts.rain = kR * rain^aR;
else
    parts.rain = 0;
end

% ---- fog / cloud, ITU-R P.840 Rayleigh ----------------------------------
Kl = getf(p,'fogKl', 0.09);            % (dB/km)/(g/m^3) at 9.5 GHz, 10 C
parts.fog = Kl * fog;

gamma = parts.o2 + parts.h2o + parts.rain + parts.fog;
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
