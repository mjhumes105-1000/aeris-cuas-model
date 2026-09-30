function F4 = multipath_factor(R, ht, hr, g, p)
%AERIS.MULTIPATH_FACTOR  Two-way pattern-propagation factor (two-ray ground).
%   F4 = aeris.multipath_factor(R, ht, hr, g, p)
%
%   Over a reflecting surface the direct and ground-reflected paths interfere,
%   so the received power is not free-space - it LOBES with range and height.
%   For a low grazing geometry the path difference is ~2*hr*ht/R and, with a
%   near -1 ground reflection (horizontal pol, grazing), the one-way field
%   factor is F = |1 - rho*exp(j*4*pi*hr*ht/(lambda*R))|. Two-way power is F^4.
%
%   Consequence: a low-altitude target fades through deep nulls (F->1-rho) and
%   enhancements (F->1+rho, up to +12 dB) as it crosses the lobing structure -
%   real coverage holes at specific ranges the free-space model cannot show,
%   and they hit exactly the low-flying drones the node most needs to see.
%
%     R   slant range (m), may be a vector
%     ht  target height above the local surface (m)
%     hr  radar phase-centre height above the surface (m)
%     p.groundRefl  reflection magnitude rho (default 0.7; 1 = smooth/water,
%                   lower = rough ground, which fills in the nulls)
%
%   Returns the two-way power multiplier (1 = free space). Off unless the caller
%   applies it - see p.multipathOn in aeris_engage.

rho  = 0.7; if isfield(p,'groundRefl') && ~isempty(p.groundRefl), rho = p.groundRefl; end
dphi = 4*pi * hr .* ht ./ (g.lambda * max(R,1));    % round-trip phase difference
F    = abs(1 - rho*exp(1j*dphi));                    % Gamma ~ -1 at grazing
F4   = F.^4;                                          % two-way power factor
end
