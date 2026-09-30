function g = derive(p)
%AERIS.DERIVE  Derived radar constants from a parameter struct.
%   g = aeris.derive(p) returns the quantities every AERIS model needs but
%   none of them should recompute: wavelength, element spacing, aperture,
%   boresight gain, system temperature, linear losses, integration gain,
%   beamwidths, unambiguous velocity, and range resolution.
%
%   Mirrors the derived block of cuas_l3/radar.py. Change it here only, and
%   mirror in Python.
%
%   Fields returned:
%     lambda  m      wavelength
%     d       m      element spacing
%     Aap     m^2    physical aperture
%     Glin    -      boresight array gain (linear, aperture formula w/ apEff)
%     Ts      K      system noise temperature
%     Lsys    -      two-way system losses (linear)
%     intGain -      coherent integration gain (= cpi)
%     azBW    deg    azimuth 3-dB beamwidth
%     elBW    deg    elevation 3-dB beamwidth
%     vUnamb  m/s    +/- unambiguous radial velocity
%     dR      m      range resolution / gate width

g.lambda  = p.c / p.freq;
g.d       = p.dspaceWL * g.lambda;
g.Aap     = (p.nAz * g.d) * (p.nEl * g.d);
g.Glin    = 4*pi*g.Aap*p.apEff / g.lambda^2;
g.NFdB    = p.NF;
g.Ts      = p.T0 * 10^(p.NF/10);
g.Lsys    = 10^(p.Lsys/10);

% ---- rung-2: modeled RF cascade sets the system NF ---------------------
% Off by default (p.NF is the fast path and the cross-check). When on, the
% system noise figure - and thus Ts - comes from the receive-chain cascade.
g.rxChain = [];
if isfield(p,'useRfChain') && ~isempty(p.useRfChain) && p.useRfChain
    rc = aeris.rf_chain(p);
    g.NFdB   = rc.NF;
    g.Ts     = p.T0 * 10^(rc.NF/10);
    g.rxChain = rc;
end
g.intGain = p.cpi;
g.azBW    = rad2deg(0.886*g.lambda/(p.nAz*g.d));
g.elBW    = rad2deg(0.886*g.lambda/(p.nEl*g.d));
g.vUnamb  = g.lambda*p.prf/4;
g.dR      = p.c/(2*p.Bchirp);

% ---- rung-1: modeled antenna overrides the analytic gain/beamwidths ----
% Off by default (the analytic model is the fast path and the cross-check).
% When on, gain, beamwidths and the az cut come from the modeled patch array.
g.antenna = [];
if isfield(p,'useModeledAntenna') && ~isempty(p.useModeledAntenna) && p.useModeledAntenna
    if isfield(p,'antModelBaked') && ~isempty(p.antModelBaked) && p.antModelBaked.ok
        am = p.antModelBaked;                 % precomputed on the client (parfor-safe)
    else
        am = aeris.antenna_model(p);           % builds here (needs the toolbox)
    end
    if am.ok
        g.Glin = am.Glin;  g.azBW = am.azBW;  g.elBW = am.elBW;
        g.antenna = am;                       % carried for aeris.beam_pattern
    end
end
end
