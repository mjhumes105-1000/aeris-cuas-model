function w = gauss_beam(offDeg, bw3dB)
%AERIS.GAUSS_BEAM  One-way Gaussian power-pattern approximation.
%   w = aeris.gauss_beam(offDeg, bw3dB)
%
%   Unity at boresight, -3 dB at +/- bw3dB/2. Used for the elevation cut,
%   where the full URA pattern is overkill. Square for two-way.
%
%   NOTE: the Python model has no elevation term. Anything that calls this is
%   adding physics beyond cuas_l3 - keep it opt-in.

w = exp(-2.773 * (offDeg ./ bw3dB).^2);
end
