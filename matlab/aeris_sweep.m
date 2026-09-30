function S = aeris_sweep(N, varargin)
% AERIS_SWEEP  Headless Monte Carlo across drone classes and environments.
%
%   aeris_sweep(15000)
%   aeris_sweep(15000,'parallel',true)
%   aeris_sweep(2000,'envs',{'best','worst'},'classes',{'micro','fixedwing'})
%   S = aeris_sweep(500,'file','matlab_out/pilot.csv');
%
% Runs N randomised engagements with NO graphics and NO GUI, sampling a drone
% class and an environment for each, and writes one row per DRONE to CSV.
% This is the data-generation path - use aeris_analyze_sweep to read it back.
%
% Name/value options
%   'parallel'  false   use parfor (needs Parallel Computing Toolbox)
%   'file'      ''      output CSV; default matlab_out/aeris_sweep.csv
%   'envs'      {}      restrict to these environments (default: all, weighted)
%   'classes'   {}      restrict to these drone classes (default: all, weighted)
%   'append'    false   add to an existing file instead of overwriting
%   'params'    []      base parameter struct (default aeris_params)
%   'altMode'   ''      'class' (default, realistic but RCS-correlated),
%                       'independent' (altitude decoupled from class - use
%                       this to attribute altitude effects), or 'fixed'
%   'alts'      []      altitude range [lo hi] for altMode 'independent'
%   'mat'       true    also save a .mat alongside the CSV
%   'nNodes'    1       nodes in the sensing network (>1 uses aeris_engage)
%   'nodeLayout' 'single'  'single'|'line'|'depth'|'ring'
%   'nodeSpacing' 1500   m, node spacing / ring radius
%
% SAMPLING. Environments and drone classes are drawn by the 'weight' fields in
% aeris.environments and aeris.drone_catalog, so ordinary conditions dominate
% and the extremes stay rare. An unweighted sweep would badly overstate how
% often the node works in a downpour. Pass 'envs' explicitly to force a flat
% comparison between named conditions.
%
% RUNTIME. Roughly 0.1-0.4 s per engagement single-threaded, so 15000 runs is
% about 30-90 minutes. With 'parallel',true on 8 cores expect 5-15 minutes.
% Progress prints every 2%.
%
% See also AERIS_ANALYZE_SWEEP, AERIS.ENVIRONMENTS, AERIS.DRONE_CATALOG.

if nargin < 1 || isempty(N), N = 1000; end

o = parse_opts(varargin, struct('parallel',false,'file','','envs',{{}}, ...
                                'classes',{{}},'append',false,'params',[], ...
                                'altMode','','alts',[],'mat',true, ...
                                'nNodes',1,'nodeLayout','single','nodeSpacing',1500, ...
                                'nodeForward',0));

base = o.params;
if isempty(base), base = aeris_params(); end
base.randomThreats = true;
base.headless      = true;      % no graphics
base.quiet         = true;      % no per-run printout
base.saveVideo     = false;
base.logData       = false;     % we collect in memory and bulk-write
if ~isempty(o.altMode), base.altMode = o.altMode; end
if ~isempty(o.alts),    base.randAlt = o.alts;    end
base.nNodes = o.nNodes; base.nodeLayout = o.nodeLayout; base.nodeSpacing = o.nodeSpacing;
base.nodeForward = o.nodeForward;

% ---- sampling tables ----------------------------------------------------
E = aeris.environments();
D = aeris.drone_catalog();
if ~isempty(o.envs)
    E = E(ismember(lower({E.name}), lower(o.envs)));
    if isempty(E), error('aeris:sweep','no environments matched.'); end
    [E.weight] = deal(1);                       % flat when explicitly named
end
if ~isempty(o.classes)
    D = D(ismember(lower({D.name}), lower(o.classes)));
    if isempty(D), error('aeris:sweep','no drone classes matched.'); end
    [D.weight] = deal(1);
end
eCum = cumsum([E.weight]) / sum([E.weight]);
dCum = cumsum([D.weight]) / sum([D.weight]);

% ---- output -------------------------------------------------------------
file = o.file;
if isempty(file)
    file = fullfile(fileparts(mfilename('fullpath')),'matlab_out','aeris_sweep.csv');
end
od = fileparts(file);
if ~isempty(od) && ~exist(od,'dir'), mkdir(od); end

fprintf('AERIS sweep: %d engagements\n', N);
fprintf('  environments : %s\n', strjoin({E.name}, ', '));
fprintf('  drone classes: %s\n', strjoin({D.name}, ', '));
fprintf('  output       : %s\n', file);
fprintf('  altitude mode: %s\n', base.altMode);
fprintf('  network      : %d node(s), %s\n', base.nNodes, base.nodeLayout);
fprintf('  parallel     : %s\n\n', mat2str(o.parallel));

t0 = tic;
rows = cell(N,1);

if o.parallel
    % ensure a pool EXISTS before pctRunOnAll (it errors without one), and
    % fall back to serial if Parallel Computing Toolbox is unavailable
    pool = [];
    try
        pool = gcp('nocreate');
        if isempty(pool), pool = parpool; end
    catch ME
        warning('aeris:noParallel', ...
            'could not start a parallel pool (%s); running serially.', ME.message);
        o.parallel = false;
    end
end

if o.parallel
    try
        pctRunOnAll warning('off','MATLAB:nearlySingularMatrix');
    catch
    end
    q = [];
    try
        q = parallel.pool.DataQueue;
        afterEach(q, @(i) progress(i, N, t0));
    catch
    end
    parfor i = 1:N
        rows{i} = one_run(i, base, E, D, eCum, dCum);
        if ~isempty(q), send(q, i); end
    end
else
    step = max(1, round(N/50));
    for i = 1:N
        rows{i} = one_run(i, base, E, D, eCum, dCum);
        if mod(i, step) == 0, progress(i, N, t0); end
    end
end

% ---- write --------------------------------------------------------------
fprintf('\nwriting %s ...\n', file);
write_csv(file, rows, o.append);

matFile = '';
if o.mat
    matFile = [regexprep(file, '[.]csv$', '') '.mat'];
    if strcmp(matFile, file), matFile = [file '.mat']; end
    fprintf('writing %s ...\n', matFile);
    save_mat(matFile, file, rows, base, E, D, N);
end

el = toc(t0);
fprintf('done: %d engagements in %s (%.3f s each)\n', N, hms(el), el/N);

S = struct('file',file,'mat',matFile,'N',N,'elapsed',el, ...
           'envs',{{E.name}},'classes',{{D.name}});

if nargout == 0
    fprintf('\nNext:  aeris_analyze_sweep(''%s'')\n', file);
    clear S
end
end

% ========================================================================
function row = one_run(i, base, E, D, eCum, dCum)
p = base;

% pick environment and drone class
e = E(find(rand <= eCum, 1));
d = D(find(rand <= dCum, 1));

p.rainRate   = e.rainRate;
p.fogDensity = e.fogDensity;
p.humidity   = e.humidity;
p.gammaDB    = e.gammaDB;
p.mtiImpDB   = e.mtiImpDB;
p.grazingDeg = e.grazingDeg;
p.droneClass = d.name;

% independent stream per run so parallel and serial give the same population
p.rngSeed = mod(i*2654435761 + 12345, 2^31-1);

% placement varies too - it is half the study question
p.Dforward = 3000 + rand*6000;

r = aeris_engage(p);   % N=1 reduces to single node (parity-validated)

T   = r.threats;
per = r.per;
row = struct('env',e.name,'class',d.name,'seed',p.rngSeed, ...
             'formation',r.formation,'Dforward',p.Dforward, ...
             'nNodes',r.nNodes,'layout',base.nodeLayout, ...
             'rain',e.rainRate,'fog',e.fogDensity,'humid',e.humidity, ...
             'gammaDB',e.gammaDB,'mtiDB',e.mtiImpDB, ...
             'raidWarn',r.warnTime,'met',r.requirementMet, ...
             'Treq',p.Treq,'T',{T},'per',{per},'rel',r.reliableRange);
end

% ------------------------------------------------------------------------
function write_csv(file, rows, appendMode)
cols = {'run','env','class','formation','n_nodes','layout','seed','Dforward_m', ...
        'rain_mmhr','fog_gm3','humid_gm3','gamma_dB','mti_dB', ...
        'drone','rcs_m2','alt_m','speed_mps','reliable_range_m', ...
        'det_frames','confirmed','conf_node','n_det_nodes', ...
        't_confirm_s','warn_time_s','min_range_m', ...
        'raid_warn_s','Treq_s','req_met'};

mode = 'w';
if appendMode && isfile(file), mode = 'a'; end
fid = fopen(file, mode);
if fid < 0, error('aeris:sweep','cannot open %s', file); end
c = onCleanup(@() fclose(fid));
if ~strcmp(mode,'a'), fprintf(fid, '%s\n', strjoin(cols, ',')); end

for i = 1:numel(rows)
    r = rows{i};
    if isempty(r), continue; end
    T = r.T; per = r.per;
    for j = 1:numel(T)
        cn = '';
        if isfield(per(j),'confNode'), cn = per(j).confNode; end
        ndn = 1;
        if isfield(per(j),'nDetNodes'), ndn = per(j).nDetNodes; end
        fprintf(fid, ['%d,%s,%s,%s,%d,%s,%d,%.1f,' ...
                      '%.2f,%.3f,%.1f,%.1f,%.1f,' ...
                      '%s,%.6g,%.1f,%.2f,%.1f,' ...
                      '%d,%d,%s,%d,%.2f,%.2f,%.1f,%.2f,%.1f,%d\n'], ...
            i, r.env, r.class, r.formation, r.nNodes, r.layout, r.seed, r.Dforward, ...
            r.rain, r.fog, r.humid, r.gammaDB, r.mtiDB, ...
            T(j).label, T(j).rcs, T(j).alt0, T(j).spd, r.rel(j), ...
            per(j).detFrames, per(j).confirmed, cn, ndn, ...
            nn(per(j).tConfirm), nn(per(j).warnTime), per(j).minRange, ...
            nn(r.raidWarn), r.Treq, r.met);
    end
end
end

function v = nn(x)
if isnan(x), v = -1; else, v = x; end
end

function progress(i, N, t0)
persistent last
if isempty(last), last = 0; end
pct = floor(100*i/N);
if pct >= last + 2 || i == N
    last = pct;
    el = toc(t0); rate = i/el;
    fprintf('  %3d%%  %6d/%d   %.1f runs/s   eta %s\n', ...
            pct, i, N, rate, hms((N-i)/max(rate,eps)));
end
end

function s = hms(sec)
if sec < 60, s = sprintf('%.0fs', sec);
elseif sec < 3600, s = sprintf('%dm%02ds', floor(sec/60), round(mod(sec,60)));
else, s = sprintf('%dh%02dm', floor(sec/3600), round(mod(sec,3600)/60));
end
end

function o = parse_opts(args, o)
for i = 1:2:numel(args)
    n = args{i};
    if ~isfield(o, n), error('aeris:sweep','unknown option "%s"', n); end
    o.(n) = args{i+1};
end
end

% ------------------------------------------------------------------------
function save_mat(matFile, csvFile, rows, base, E, D, N)
% Save the sweep as a .mat: a ready-to-use table plus enough provenance that
% the file can be interpreted years later without this script.
%
% Variables in the file:
%   data        table, one row per drone - same columns as the CSV
%   raids       table, one row per engagement (the raid-level view)
%   meta        struct: when, git-less version info, params, sampling tables
%   params      the base parameter struct actually used
%   envTable    the environment definitions used
%   droneTable  the drone-class definitions used

nRow = 0;
for i = 1:numel(rows)
    if ~isempty(rows{i}), nRow = nRow + numel(rows{i}.T); end
end

run_    = zeros(nRow,1);   env     = cell(nRow,1);   class_  = cell(nRow,1);
form    = cell(nRow,1);    seed    = zeros(nRow,1);  Dfwd    = zeros(nRow,1);
rain    = zeros(nRow,1);   fog     = zeros(nRow,1);  humid   = zeros(nRow,1);
gammaDB = zeros(nRow,1);   mtiDB   = zeros(nRow,1);  drone   = cell(nRow,1);
rcs     = zeros(nRow,1);   alt     = zeros(nRow,1);  spd     = zeros(nRow,1);
relRng  = zeros(nRow,1);   detF    = zeros(nRow,1);  conf    = false(nRow,1);
tConf   = nan(nRow,1);     warnT   = nan(nRow,1);    minR    = zeros(nRow,1);
raidW   = nan(nRow,1);     Treq    = zeros(nRow,1);  met     = false(nRow,1);
nNod    = zeros(nRow,1);   layout  = cell(nRow,1);   confN   = cell(nRow,1);  nDetN = zeros(nRow,1);

k = 0;
for i = 1:numel(rows)
    r = rows{i};
    if isempty(r), continue; end
    for j = 1:numel(r.T)
        k = k + 1;
        run_(k)=i;            env{k}=r.env;        class_{k}=r.class;
        form{k}=r.formation;  seed(k)=r.seed;      Dfwd(k)=r.Dforward;
        rain(k)=r.rain;       fog(k)=r.fog;        humid(k)=r.humid;
        gammaDB(k)=r.gammaDB; mtiDB(k)=r.mtiDB;    drone{k}=r.T(j).label;
        rcs(k)=r.T(j).rcs;    alt(k)=r.T(j).alt0;  spd(k)=r.T(j).spd;
        relRng(k)=r.rel(j);   detF(k)=r.per(j).detFrames;
        conf(k)=logical(r.per(j).confirmed);
        tConf(k)=r.per(j).tConfirm;  warnT(k)=r.per(j).warnTime;
        minR(k)=r.per(j).minRange;   raidW(k)=r.raidWarn;
        Treq(k)=r.Treq;              met(k)=logical(r.met);
        nNod(k)=r.nNodes;            layout{k}=r.layout;
        if isfield(r.per(j),'confNode'), confN{k}=r.per(j).confNode; else, confN{k}=''; end
        if isfield(r.per(j),'nDetNodes'), nDetN(k)=r.per(j).nDetNodes; else, nDetN(k)=1; end
    end
end

data = table(run_, string(env), string(class_), string(form), seed, Dfwd, ...
    rain, fog, humid, gammaDB, mtiDB, string(drone), rcs, alt, spd, ...
    relRng, detF, conf, tConf, warnT, minR, raidW, Treq, met, ...
    nNod, string(layout), string(confN), nDetN, ...
    'VariableNames', {'run','env','class','formation','seed','Dforward_m', ...
    'rain_mmhr','fog_gm3','humid_gm3','gamma_dB','mti_dB','drone','rcs_m2', ...
    'alt_m','speed_mps','reliable_range_m','det_frames','confirmed', ...
    't_confirm_s','warn_time_s','min_range_m','raid_warn_s','Treq_s','req_met', ...
    'n_nodes','layout','conf_node','n_det_nodes'});

% raid-level view: first row of each run
[~, ia] = unique(data.run, 'stable');
raids = data(ia, {'run','env','class','formation','seed','Dforward_m', ...
                  'rain_mmhr','fog_gm3','humid_gm3','gamma_dB','mti_dB', ...
                  'raid_warn_s','Treq_s','req_met'});
nPer = accumarray(data.run, 1, [max(data.run) 1]);
raids.n_drones = nPer(raids.run);

meta = struct();
meta.created      = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
meta.csv          = csvFile;
meta.nEngagements = N;
meta.nDrones      = nRow;
meta.altMode      = base.altMode;
meta.network      = sprintf('%d node(s), %s layout, %.0f m spacing', base.nNodes, base.nodeLayout, base.nodeSpacing);
meta.matlab       = version;
meta.elevModel    = 'aeris.elev_gain - nearest elevation bar from aeris.dwell_plan';
meta.weather      = 'aeris.atmos_atten - ITU-R P.676 / P.838 / P.840';
meta.provisional  = { ...
    'p.rainMtiDB (MTI improvement against moving rain) is a GUESS'
    'drone RCS bands are order-of-magnitude literature estimates'
    'p.Treq = 300 s has no established operational basis'
    'all RadarParams values are AERIS-Nexus placeholders'};

params     = base;
envTable   = struct2table(E);
droneTable = struct2table(D);

save(matFile, 'data', 'raids', 'meta', 'params', 'envTable', 'droneTable', '-v7.3');
end
