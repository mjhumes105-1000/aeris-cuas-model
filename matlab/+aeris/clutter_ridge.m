function C = clutter_ridge(rangeAxis, velAxis, p, g)
%AERIS.CLUTTER_RIDGE  Residual surface clutter across the range-Doppler map.
%   C = aeris.clutter_ridge(rangeAxis, velAxis, p, g)
%
%   Constant-gamma surface model: sigma0 = gamma*sin(grazing), illuminated
%   patch area = R*azBW*dR/cos(grazing), single-pulse C/N from the same radar
%   equation as the target, then divided by the MTI improvement factor and
%   spread over a few bins either side of zero Doppler.
%
%   Returns nR x nD, in the same noise-normalised power units as the map
%   (thermal noise has mean 1).
%
%   p.mtiImpDB is the dominant Level 3 unknown. If you take clutter to higher
%   fidelity (phased.ConstantGammaClutter, STAP), replace this function and
%   both scope sims inherit it.

nD     = numel(velAxis);
graz   = deg2rad(p.grazingDeg);
sigma0 = 10^(p.gammaDB/10) * sin(graz);
patch  = rangeAxis * deg2rad(g.azBW) * g.dR / max(cos(graz), 1e-3);
sigC   = sigma0 * patch;                       % clutter RCS per range cell
R      = max(rangeAxis, 1);

cn1   = (p.Ptpeak*p.tau*g.Glin^2*g.lambda^2 .* sigC) ./ ...
        ((4*pi)^3 * R.^4 * p.k * g.Ts * g.Lsys);
cnRes = cn1 / 10^(p.mtiImpDB/10);              % after MTI improvement

[~, z] = min(abs(velAxis));                    % zero-Doppler bin
spread = exp(-((1:nD)-z).^2 / (2*2^2));        % a few bins wide
C      = cnRes(:) * spread;

% ---- rain volume backscatter -------------------------------------------
% Rain does not only attenuate (see aeris.atmos_atten) - it reflects, and
% against a 0.01 m^2 drone that can dominate. Marshall-Palmer Z-R with the
% Rayleigh volume-reflectivity form:
%   Z = 200 R^1.6 [mm^6/m^3];  eta = (pi^5/lambda^4)|K|^2 Z 1e-18 [1/m]
%   V = (pi/(8 ln2)) R^2 theta_az theta_el dR      (Gaussian-beam volume)
% Rain is MOVING, so MTI suppresses it far less than ground clutter and it
% spreads across many Doppler bins. Both of those are modelled crudely here.
% PROVISIONAL - the rain-MTI improvement is a guess, not a measurement.
rr = getf(p,'rainRate',0);
if rr > 0
    Zmm  = 200 * rr^1.6;
    Kw2  = 0.93;                                       % |K|^2 for water
    eta  = (pi^5 / g.lambda^4) * Kw2 * Zmm * 1e-18;    % m^-1
    thA  = deg2rad(g.azBW); thE = deg2rad(g.elBW);
    Vres = (pi/(8*log(2))) * R.^2 * thA * thE * g.dR;  % m^3 per cell
    sigR = eta * Vres;                                 % rain RCS per cell

    rn1  = (p.Ptpeak*p.tau*g.Glin^2*g.lambda^2 .* sigR) ./ ...
           ((4*pi)^3 * R.^4 * p.k * g.Ts * g.Lsys);
    rnRes = rn1 / 10^(getf(p,'rainMtiDB',12)/10);      % weak MTI on moving rain

    % rain fills a broad Doppler band (fall speed + wind shear)
    vSpread = getf(p,'rainVelSpread', 4);              % m/s, 1-sigma
    dv      = mean(diff(velAxis));
    sBins   = max(2, vSpread/max(abs(dv),eps));
    rSpread = exp(-((1:nD)-z).^2 / (2*sBins^2));

    C = C + rnRes(:) * rSpread;
end
end

function v = getf(s, f, d)
if isfield(s,f) && ~isempty(s.(f)), v = s.(f); else, v = d; end
end
