function cf = cfar_init(p, nR, nD, nGuard, nTrain)
%AERIS.CFAR_INIT  Precompute everything about the CFAR that never changes.
%   cf = aeris.cfar_init(p, nR, nD)
%   cf = aeris.cfar_init(p, nR, nD, nGuard, nTrain)
%
%   Builds the CA-CFAR scale factor and the per-cell training count for an
%   nR x nD map. The training count depends only on map size, so computing it
%   once per run instead of once per frame is free speed.
%
%   Also constructs a phased.CFARDetector2D when p.useToolboxCFAR is true;
%   cf.tb is [] otherwise (or if the toolbox is unavailable).

if nargin < 4, nGuard = 2; end
if nargin < 5, nTrain = 4; end

cf.ng = nGuard;
cf.nt = nTrain;
cf.k  = nGuard + nTrain;

% CA-CFAR scale factor for the annulus between guard and training bands
Nwin   = (2*cf.k+1)^2;
Nguard = (2*cf.ng+1)^2;
cf.Ntr = Nwin - Nguard;
cf.alpha = cf.Ntr * (p.Pfa^(-1/cf.Ntr) - 1);

% constant across frames
cf.cnt = aeris.boxfilt(ones(nR,nD), cf.k) - aeris.boxfilt(ones(nR,nD), cf.ng);
cf.cnt = max(cf.cnt, 1);

cf.tb = [];
if isfield(p,'useToolboxCFAR') && p.useToolboxCFAR
    try
        cf.tb = phased.CFARDetector2D( ...
            'TrainingBandSize',[nTrain nTrain], ...
            'GuardBandSize',[nGuard nGuard], ...
            'ProbabilityFalseAlarm',p.Pfa, ...
            'Method','CA','ThresholdFactor','Auto', ...
            'OutputFormat','Detection index');
    catch
        warning('aeris:cfar', ...
            'phased.CFARDetector2D unavailable; using built-in CA-CFAR.');
        cf.tb = [];
    end
end
end
