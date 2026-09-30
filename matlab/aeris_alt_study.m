function S = aeris_alt_study(varargin)
% AERIS_ALT_STUDY  Is altitude really a driver, or is it confounded with RCS?
%
%   aeris_alt_study                                  % 40 runs per cell
%   aeris_alt_study('reps',150)                      % tighter error bars
%   aeris_alt_study('classes',{'small_quad'})        % one airframe only
%
% WHY THIS EXISTS
%   In aeris.drone_catalog altitude and RCS are CORRELATED by design, because
%   real airframes are:
%       micro       0.005-0.015 m^2   20-120 m    small and low
%       small_quad  0.01 -0.03        40-250 m
%       heavy_quad  0.03 -0.08        50-300 m
%       fixedwing   0.08 -0.20       150-900 m    big and high
%       fpv_attack  0.005-0.02        15-100 m    small and low
%   So a plain "confirmation rate vs altitude" plot from a mixed sweep mixes
%   two effects and can point either way for the wrong reason. Any altitude
%   claim has to hold RCS fixed.
%
%   This study sweeps altitude on a fixed grid WITHIN each drone class, with
%   RCS drawn from that class only, and runs it twice - elevation beam off and
%   on - so the geometric effect and the beam-scheduling effect are separated.
%
% Name/value options
%   'alts'     [50 100 150 200 250 300 400 500]   altitude grid, m
%   'classes'  all catalogue classes
%   'reps'     40      engagements per (class, altitude, beam) cell
%   'env'      'grass' environment to hold fixed
%   'file'     ''      also write the raw rows to CSV
%
% Reads out: confirmation rate and median warning time vs altitude, per class,
% with and without the elevation beam. If the curves are flat with the beam
% off but fall with it on, the effect is beam SCHEDULING (fixable by covering
% more elevation). If they fall both ways, it is geometry.
%
% See also AERIS.ELEV_GAIN, AERIS.DWELL_PLAN, AERIS_SWEEP.

o = opts(varargin, struct( ...
    'alts',   [50 100 150 200 250 300 400 500], ...
    'classes', {{}}, 'reps', 40, 'env','grass', 'file',''));

D = aeris.drone_catalog();
if ~isempty(o.classes)
    D = D(ismember(lower({D.name}), lower(o.classes)));
    if isempty(D), error('aeris:alt','no classes matched.'); end
end
e = aeris.environments(o.env);

base = aeris_params();
base.randomThreats = true;
base.headless = true;  base.quiet = true;
base.saveVideo = false; base.logData = false;
base.nDrones = 1;                       % one drone: no formation confound
base.rainRate = e.rainRate; base.fogDensity = e.fogDensity;
base.humidity = e.humidity; base.gammaDB = e.gammaDB;
base.mtiImpDB = e.mtiImpDB; base.grazingDeg = e.grazingDeg;

nA = numel(o.alts); nC = numel(D); nB = 2;
conf = nan(nC, nA, nB);
warn = nan(nC, nA, nB);
rows = {};

W = aeris.dwell_plan(base, aeris.derive(base));
fprintf('\n--- altitude study ---\n');
fprintf('environment %s | %d classes x %d altitudes x %d reps x 2 = %d runs\n', ...
        o.env, nC, nA, o.reps, nC*nA*o.reps*2);
fprintf('elevation bars at %s deg (coverage %.0f-%.0f)\n\n', ...
        num2str(W.elBeams,'%.1f '), W.cover(1), W.cover(2));

t0 = tic;
for ib = 1:nB
    beamOn = (ib == 2);
    for ic = 1:nC
        for ia = 1:nA
            p = base;
            p.droneClass  = D(ic).name;
            p.elevBeamOn  = beamOn;
            % FIX the altitude: override the class band
            p.randAlt       = [o.alts(ia) o.alts(ia)];
            p.randAltJitter = [0 0];
            p.targetAlt     = o.alts(ia);

            c = 0; w = [];
            for r = 1:o.reps
                p.rngSeed = 100000*ib + 1000*ic + 37*ia + r;
                res = aeris_scope_sim3d(p);
                ok  = res.per(1).confirmed;
                c   = c + double(ok);
                if ok, w(end+1) = res.per(1).warnTime; end %#ok<AGROW>
                rows{end+1} = {D(ic).name, o.alts(ia), beamOn, ...
                               res.threats(1).rcs, double(ok), ...
                               res.per(1).warnTime}; %#ok<AGROW>
            end
            conf(ic,ia,ib) = c / o.reps;
            if ~isempty(w), warn(ic,ia,ib) = median(w); end
        end
        fprintf('  %s beam=%d  %-11s done (%s)\n', ...
                datestr(now,'HH:MM:SS'), beamOn, D(ic).name, hms(toc(t0))); %#ok<TNOW1,DATST>
    end
end
fprintf('\n%d runs in %s\n', nC*nA*o.reps*2, hms(toc(t0)));

% ---- tables ------------------------------------------------------------
for ib = 1:nB
    fprintf('\n--- confirmation rate %%, elevation beam %s ---\n', ...
            ternary(ib==2,'ON','OFF'));
    fprintf('%-12s', 'class');
    fprintf('%7.0f', o.alts); fprintf('   (m)\n');
    for ic = 1:nC
        fprintf('%-12s', D(ic).name);
        fprintf('%7.0f', 100*conf(ic,:,ib)); fprintf('\n');
    end
end

fprintf('\n--- verdict ---\n');
dOff = range_drop(conf(:,:,1));
dOn  = range_drop(conf(:,:,2));
fprintf('largest within-class swing across altitude:\n');
fprintf('  beam OFF %.0f pp   beam ON %.0f pp\n', 100*dOff, 100*dOn);
if dOff < 0.10 && dOn >= 0.20
    fprintf('=> altitude is NOT a geometric driver. The effect is elevation\n');
    fprintf('   BEAM SCHEDULING - widen p.elevCoverDeg and it goes away.\n');
elseif dOff < 0.10 && dOn < 0.10
    fprintf('=> altitude is NOT a driver either way. A "worst altitude" in a\n');
    fprintf('   mixed sweep is CONFOUNDED with drone class (RCS).\n');
else
    fprintf('=> altitude affects results even with the beam off: real geometry\n');
    fprintf('   (slant range). Report it, with the magnitude above.\n');
end

% ========================================================================
figure('Color','w','Position',[70 70 1240 560]);
tiledlayout(1,2,'TileSpacing','compact','Padding','compact');
cols = lines(nC);
for ib = 1:nB
    nexttile; hold on; grid on;
    for ic = 1:nC
        plot(o.alts, 100*conf(ic,:,ib), '-o', 'Color',cols(ic,:), ...
             'MarkerFaceColor',cols(ic,:), 'MarkerSize',4, 'LineWidth',1.4, ...
             'DisplayName',strrep(D(ic).name,'_','\_'));
    end
    xlabel('altitude (m)'); ylabel('confirmation rate (%)');
    ylim([0 105]);
    title(sprintf('elevation beam %s', ternary(ib==2,'ON','OFF')), ...
          'FontWeight','normal');
    if ib==1, legend('Location','southwest','Box','off','FontSize',8); end
end
sgtitle(sprintf(['altitude held FIXED, RCS drawn within class  |  %s  |  ' ...
                 '%d reps/cell'], o.env, o.reps), 'FontSize', 11);

if ~isempty(o.file)
    fid = fopen(o.file,'w');
    fprintf(fid,'class,alt_m,beam_on,rcs_m2,confirmed,warn_time_s\n');
    for i=1:numel(rows)
        r = rows{i};
        fprintf(fid,'%s,%g,%d,%.6g,%d,%.2f\n', r{1},r{2},r{3},r{4},r{5},r{6});
    end
    fclose(fid);
    fprintf('\nraw rows -> %s\n', o.file);
end

S = struct('alts',o.alts,'classes',{{D.name}},'conf',conf,'warn',warn, ...
           'dwell',W,'env',o.env,'reps',o.reps);
if nargout==0, clear S; end
end

% ------------------------------------------------------------------------
function d = range_drop(M)
% largest within-row swing (max - min), ignoring all-NaN rows
d = 0;
for i = 1:size(M,1)
    v = M(i,:); v = v(~isnan(v));
    if numel(v) > 1, d = max(d, max(v) - min(v)); end
end
end

function s = ternary(c,a,b), if c, s=a; else, s=b; end, end

function s = hms(sec)
if sec < 60, s = sprintf('%.0fs', sec);
elseif sec < 3600, s = sprintf('%dm%02ds', floor(sec/60), round(mod(sec,60)));
else, s = sprintf('%dh%02dm', floor(sec/3600), round(mod(sec,3600)/60));
end
end

function o = opts(args, o)
for i = 1:2:numel(args)
    n = args{i};
    if ~isfield(o,n), error('aeris:alt','unknown option "%s"', n); end
    o.(n) = args{i+1};
end
end
