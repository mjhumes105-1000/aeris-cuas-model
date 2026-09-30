function [detOnTgt, detMask, thresh] = look(snrv, ri, di, nR, nD, cf, Cridge)
%AERIS.LOOK  One radar look: synthesise the range-Doppler map and detect.
%   [detOnTgt, detMask, thresh] = aeris.look(snrv, ri, di, nR, nD, cf, Cridge)
%
%   The per-look detection mechanism, factored out so the single-node scope
%   sim and the multi-node engine share ONE copy (physics cannot drift).
%
%   Inputs (all per-target vectors over the targets visible THIS look):
%     snrv   integrated SNR, linear (>0). Targets with snr<=0 must be omitted.
%     ri     range-bin index of each target
%     di     Doppler-bin index of each target
%     nR,nD  map size
%     cf     CFAR struct from aeris.cfar_init
%     Cridge clutter ridge (nR x nD) or scalar 0
%
%   Outputs:
%     detOnTgt  logical, per target: a CFAR detection within +/-2 range and
%               +/-3 Doppler cells of the true cell (the association gate)
%     detMask   full CFAR detection mask (for display)
%     thresh    CFAR threshold (for the A-scope)
%
%   The map is exponential thermal noise (mean 1) plus clutter, with each
%   target deposited at Swerling-1 amplitude. This mirrors what
%   aeris_scope_sim3d did inline; keep the two in step if either changes.

P = -log(rand(nR, nD)) + Cridge;               % thermal noise + clutter
nT = numel(snrv);
for k = 1:nT
    P = aeris.add_target(P, ri(k), di(k), snrv(k) * -log(rand));   % Swerling-1
end

[detMask, thresh] = aeris.cfar(P, cf);

detOnTgt = false(1, nT);
for k = 1:nT
    rW = abs((1:nR)' - ri(k)) <= 2;
    dW = abs((1:nD)  - di(k)) <= 3;
    detOnTgt(k) = any(any(detMask(rW, dW)));
end
end
