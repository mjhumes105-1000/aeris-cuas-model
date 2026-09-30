function P = add_target(P, ri, di, power)
%AERIS.ADD_TARGET  Add a target return to a range-Doppler map.
%   P = aeris.add_target(P, ri, di, power)
%
%   Deposits `power` at cell (ri, di) spread over a small Gaussian
%   point-spread (+/-1 range bin, +/-2 Doppler bins) representing the
%   matched-filter and window response. Clipped at the map edges.
%
%   Pass power already multiplied by the Swerling fluctuation, e.g.
%     P = aeris.add_target(P, ri, di, snr * -log(rand));   % Swerling-1

[nR, nD] = size(P);
for a = -1:1
    for b = -2:2
        r = ri + a;  c = di + b;
        if r >= 1 && r <= nR && c >= 1 && c <= nD
            P(r,c) = P(r,c) + power * exp(-(a^2/1 + b^2/4));
        end
    end
end
end
