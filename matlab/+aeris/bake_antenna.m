function p = bake_antenna(p)
%AERIS.BAKE_ANTENNA  Precompute the modeled antenna into params (parfor-safe).
%   p = aeris.bake_antenna(p)
%
%   The Antenna Toolbox is a client-side license: parfor WORKERS are separate
%   MATLAB processes that often cannot check it out, so a modeled-antenna sweep
%   fails on the workers even though the client has the toolbox. This runs the
%   antenna model ONCE here on the client and stores the result in p, so a
%   parallel sweep reads the numbers instead of rebuilding the antenna on every
%   worker. Also sets p.useModeledAntenna = true.
%
%   Usage:
%     p = aeris.bake_antenna(aeris_params());
%     p.useRfChain = true;
%     aeris_sweep(15000,'parallel',true,'params',p, ...);
%
%   If the toolbox is unavailable here too, it warns and leaves p on the
%   analytic model (which aeris_antenna_check showed agrees to ~0.3 dB anyway).

if nargin < 1 || isempty(p), p = aeris_params(); end

am = aeris.antenna_model(p);
if am.ok
    p.antModelBaked     = am;
    p.useModeledAntenna = true;
    fprintf('baked modeled antenna: gain %.1f dBi, az %.2f deg, el %.2f deg\n', ...
            am.GdB, am.azBW, am.elBW);
else
    p.useModeledAntenna = false;
    warning('aeris:bake', ...
        'modeled antenna unavailable; params left on the analytic model.');
end
end
