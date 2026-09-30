function [file, runId] = log_run(p, g, T, per, summary)
%AERIS.LOG_RUN  Append one engagement to the cumulative results CSV.
%   [file, runId] = aeris.log_run(p, g, T, per, summary)
%
%   Writes ONE ROW PER DRONE, each carrying its run-level context, so the file
%   can be grouped by run_id for raid-level statistics or analysed per drone
%   for detectability-vs-RCS/altitude curves. The file accumulates across runs
%   - that is the point. Every run of the sim adds to your data set.
%
%   Inputs:
%     T       1xN threat struct array from aeris.spawn_threats
%     per     1xN struct: .detFrames .confirmed .tConfirm .warnTime .minRange
%     summary struct: .firstConfirm .warnTime .requirementMet .nFrames .seed
%
%   Output file defaults to matlab_out/aeris_runs.csv (override with p.logFile).
%
%   Load it back with:  Tbl = readtable('matlab_out/aeris_runs.csv');

here   = fileparts(fileparts(mfilename('fullpath')));   % matlab/
outdir = fullfile(here, 'matlab_out');
if ~exist(outdir,'dir'), mkdir(outdir); end

file = fullfile(outdir, 'aeris_runs.csv');
if isfield(p,'logFile') && ~isempty(p.logFile)
    file = p.logFile;
    if ~isfolder(fileparts(file)) && ~isempty(fileparts(file))
        mkdir(fileparts(file));
    end
end

runId = datestr(now, 'yyyymmdd_HHMMSS_FFF'); %#ok<TNOW1,DATST>

cols = {'run_id','timestamp','seed','formation','n_drones','drone', ...
        'rcs_m2','alt_m','speed_mps','bearing_deg','start_range_m', ...
        'Dforward_m','sector_deg','gamma_dB','mti_dB','Treq_s','latency_s', ...
        'reliable_range_m','det_frames','confirmed','t_confirm_s', ...
        'warn_time_s','min_range_m','raid_warn_s','req_met'};

newFile = ~isfile(file);
fid = fopen(file, 'a');
if fid < 0
    warning('aeris:log','could not open %s for append; run not logged.', file);
    return
end
c = onCleanup(@() fclose(fid));

if newFile
    fprintf(fid, '%s\n', strjoin(cols, ','));
end

form = 'single';
if isfield(p,'lastFormation'), form = p.lastFormation; end
ts = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>

for i = 1:numel(T)
    bear = atan2d(T(i).p0(2), T(i).p0(1));
    fprintf(fid, ['%s,%s,%s,%s,%d,%s,' ...
                  '%.5g,%.1f,%.2f,%.2f,%.1f,' ...
                  '%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,' ...
                  '%.1f,%d,%d,%.2f,%.2f,%.1f,%.2f,%d\n'], ...
        runId, ts, num2str(summary.seed), form, numel(T), T(i).label, ...
        T(i).rcs, T(i).alt0, T(i).spd, bear, norm(T(i).p0(1:2)), ...
        p.Dforward, p.sectorWidth, p.gammaDB, p.mtiImpDB, p.Treq, p.latency, ...
        summary.reliableRange(i), per(i).detFrames, per(i).confirmed, ...
        nan2neg(per(i).tConfirm), nan2neg(per(i).warnTime), per(i).minRange, ...
        nan2neg(summary.warnTime), summary.requirementMet);
end
end

function v = nan2neg(x)
% CSV-friendly: NaN (never happened) becomes -1
if isnan(x), v = -1; else, v = x; end
end
