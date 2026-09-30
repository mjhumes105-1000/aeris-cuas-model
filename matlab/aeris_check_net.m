function aeris_check_net(reps)
% AERIS_CHECK_NET  Validate the multi-node engine, then show what nodes buy.
%
%   aeris_check_net           % 400 reps
%   aeris_check_net(1500)     % tighter
%
% Part 1 - PARITY. Runs aeris_engage with nNodes = 1 and aeris_scope_sim3d
% headless over the SAME seeds and checks they agree. They share the physics
% (+aeris) but re-implement the surrounding loop, so agreement is expected to a
% few tenths of a percent (Monte Carlo noise from independent RNG streams), not
% bit-for-bit. A large gap means the engine diverged from the reference.
%
% Part 2 - UPLIFT. Runs 1/2/3/4-node layouts on the same raids and reports the
% confirmation rate and warning satisfaction each adds. This is the
% distributed-placement payoff, quantified.
%
% Headless and fast. Run it before trusting any multi-node sweep.

if nargin < 1, reps = 400; end

base = aeris_params();
base.randomThreats = true; base.headless = true; base.quiet = true;
base.saveVideo = false; base.logData = false;

% ---- Part 1: N=1 parity -------------------------------------------------
fprintf('\n=== PART 1: single-node parity (%d reps) ===\n', reps);
c_eng = 0; c_sim = 0; w_eng = []; w_sim = [];
for r = 1:reps
    p = base; p.nNodes = 1; p.rngSeed = 5000 + r;
    re = aeris_engage(p);
    rs = aeris_scope_sim3d(p);            % headless, same seed -> same raid
    c_eng = c_eng + mean([re.per.confirmed]);
    c_sim = c_sim + mean([rs.per.confirmed]);
    if ~isnan(re.warnTime), w_eng(end+1) = re.warnTime; end %#ok<AGROW>
    if ~isnan(rs.warnTime), w_sim(end+1) = rs.warnTime; end %#ok<AGROW>
end
fprintf('per-drone confirmation:  engage %.1f%%   sim3d %.1f%%   (Δ %.2f pp)\n', ...
    100*c_eng/reps, 100*c_sim/reps, 100*abs(c_eng-c_sim)/reps);
fprintf('median warning time:     engage %.0f s    sim3d %.0f s\n', ...
    median(w_eng), median(w_sim));
if abs(c_eng-c_sim)/reps < 0.03
    fprintf('=> PARITY OK (within Monte Carlo noise). Engine matches reference.\n');
else
    fprintf('=> PARITY FAIL (>3 pp). The engine diverged - do not trust multi-node yet.\n');
end

% ---- Part 2: multi-node uplift -----------------------------------------
fprintf('\n=== PART 2: what nodes buy (line layout, %d reps) ===\n', reps);
fprintf('%-8s %10s %10s %10s\n','nodes','conf%','met%','med warn');
Ns = [1 2 3 4];
for k = 1:numel(Ns)
    conf = 0; met = 0; w = [];
    for r = 1:reps
        p = base; p.nNodes = Ns(k); p.nodeLayout = 'line'; p.nodeSpacing = 1500;
        p.rngSeed = 9000 + r;            % same raids across node counts
        re = aeris_engage(p);
        conf = conf + mean([re.per.confirmed]);
        met  = met  + double(re.requirementMet);
        if ~isnan(re.warnTime), w(end+1) = re.warnTime; end %#ok<AGROW>
    end
    fprintf('%-8d %9.1f%% %9.1f%% %9.0f s\n', ...
        Ns(k), 100*conf/reps, 100*met/reps, median(w));
end
fprintf(['\nRead: how much each added node raises confirmation and warning\n' ...
         'satisfaction. Diminishing returns tell you the useful network size.\n']);
end
