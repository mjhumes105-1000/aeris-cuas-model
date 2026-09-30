function S = aeris_sensitivity(r, N)
% AERIS_SENSITIVITY  Global sensitivity (Morris elementary effects) of met%
% to the provisional parameters.
%
%   aeris_sensitivity            % r=8 trajectories, N=300 raids/eval
%   aeris_sensitivity(12, 500)
%
% Replaces one-at-a-time knob-wiggling with a proper screening: which of the
% provisional assumptions actually move the warning result, and which are
% along-for-the-ride. Morris elementary effects give, per parameter:
%   mu*   mean absolute influence on met% (rank by this)
%   sigma spread of the effect = nonlinearity / interaction with others
%
% Screened parameters and ranges (edit here):
%   Treq         [180 420] s     the load-bearing requirement
%   rainMtiDB    [8 20] dB       MTI against moving rain (the guess)
%   procLossDB   [0 4] dB        signal-processing loss (rung 3)
%   scanLossExp  [1.0 2.5]       sector-edge sharpness
%   rcsScale     [0.5 2.0]       global RCS multiplier (threat-size uncertainty)
%   sectorWidth  [60 120] deg    field of regard
%
% Cost ~ r*(k+1) sweeps of N engagements. Serial; a few minutes. Uses the
% analytic antenna (fast, parfor-free) with the RF chain + processing loss on.

if nargin < 1 || isempty(r), r = 8;   end
if nargin < 2 || isempty(N), N = 300; end

names  = {'Treq','rainMtiDB','procLossDB','scanLossExp','rcsScale','sectorWidth'};
lo     = [180   8    0    1.0  0.5   60];
hi     = [420   20   4    2.5  2.0  120];
k = numel(names);

base = aeris_params();
base.randomThreats = true; base.headless = true; base.quiet = true;
base.saveVideo = false; base.logData = false;
base.useRfChain = true;                    % modeled receiver
% analytic antenna on purpose: fast and parfor-free for many evaluations

E = aeris.environments(); D = aeris.drone_catalog();
eCum = cumsum([E.weight])/sum([E.weight]);
dCum = cumsum([D.weight])/sum([D.weight]);

L = 4; delta = L/(2*(L-1)); grid = (0:L-1)/(L-1);
EE = nan(r, k);
evalCount = 0; t0 = tic;

fprintf('\nMorris sensitivity: %d trajectories x %d params, %d raids/eval\n', r, k, N);
for tr = 1:r
    x = grid(randi(L, 1, k));               % start point in [0,1]^k
    perm = randperm(k);
    yprev = evalMet(x); evalCount = evalCount + 1;
    for jj = 1:k
        j = perm(jj);
        xn = x;
        if x(j) + delta <= 1, xn(j) = x(j) + delta; d = delta;
        else,                 xn(j) = x(j) - delta; d = -delta; end
        yn = evalMet(xn); evalCount = evalCount + 1;
        EE(tr, j) = (yn - yprev) / d;         % effect per unit normalised step
        x = xn; yprev = yn;
    end
    fprintf('  trajectory %d/%d done (%d evals, %s)\n', tr, r, evalCount, hms(toc(t0)));
end

mustar = mean(abs(EE), 1, 'omitnan');
sigma  = std(EE, 0, 1, 'omitnan');
[~, ord] = sort(mustar, 'descend');

fprintf('\n--- parameter influence on met%% (ranked) ---\n');
fprintf('%-13s %10s %10s\n','param','mu* (infl)','sigma');
for i = ord
    fprintf('%-13s %10.1f %10.1f\n', names{i}, mustar(i), sigma(i));
end
fprintf('\n(mu* = mean absolute change in met%% per full-range step;\n');
fprintf(' sigma large => nonlinear or interacts with other params.)\n');

figure('Color','w','Position',[100 100 700 520]); hold on; grid on;
scatter(mustar, sigma, 70, 'filled');
for i=1:k, text(mustar(i)+0.3, sigma(i), names{i}, 'FontSize',9,'Interpreter','none'); end
xlabel('\mu*  (mean influence on met %)'); ylabel('\sigma  (nonlinearity / interaction)');
title('Morris screening of provisional parameters','FontWeight','normal');

S = struct('names',{names},'mustar',mustar,'sigma',sigma,'EE',EE,'lo',lo,'hi',hi);
if nargout==0, clear S; end

    % ---- nested: map normalised x -> params, run N raids, return met% ----
    function y = evalMet(xn)
        v = lo + xn .* (hi - lo);
        m = 0;
        for i = 1:N
            p = base;
            p.Treq        = v(1);
            p.rainMtiDB   = v(2);
            p.procLossDB  = v(3);
            p.scanLossExp = v(4);
            p.rcsScale    = v(5);
            p.sectorWidth = v(6);
            e = E(find(rand <= eCum, 1));
            d = D(find(rand <= dCum, 1));
            p.rainRate = e.rainRate; p.fogDensity = e.fogDensity;
            p.humidity = e.humidity; p.gammaDB = e.gammaDB;
            p.mtiImpDB = e.mtiImpDB; p.grazingDeg = e.grazingDeg;
            p.droneClass = d.name;
            p.Dforward = 3000 + rand*6000;
            p.rngSeed = 1e6*tr + 1e3*i + jj_safe();
            m = m + double(aeris_engage(p).requirementMet);
        end
        y = 100*m/N;
    end
end

function j = jj_safe(), j = randi(1e6); end

function s = hms(sec)
if sec<60, s=sprintf('%.0fs',sec); else, s=sprintf('%dm%02ds',floor(sec/60),round(mod(sec,60))); end
end
