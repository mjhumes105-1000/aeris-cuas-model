function aeris_gui()
% AERIS_GUI  Control panel for the AERIS-Nexus scope simulation.
%
%   aeris_gui
%
% Opens a small always-available control window. Pick the raid type, drone
% count, formation and environment, then hit Run — no command line needed.
% The panel stays open between runs so you can tweak and re-run, and the scope
% reuses one figure instead of piling up windows.
%
% Controls
%   Mode        Random raid / Swarm / Deterministic single target
%   Drones      Auto (random within range) or an exact count 1-8
%   Formation   Auto (random) or a specific one
%   Environment Baseline grass / worst-case trees
%   Seed        blank = shuffle (new raid each run); an integer replays exactly
%   Altitude    lead altitude in metres
%   Elev beam   opt-in elevation pattern (exposes the close-in coverage hole)
%   Log to CSV  append every run to matlab_out/aeris_runs.csv
%   Save video  record the animation (slow — leave off while experimenting)
%
% Buttons
%   Run         one animated engagement
%   Run x N     N engagements headless (no graphics, ~100x faster) for data
%   Stop        interrupt the animation at the next frame
%   Analyze     plot the accumulated log (aeris_analyze_runs)
%
% See also AERIS_SCOPE_SIM3D, AERIS_PARAMS, AERIS_ANALYZE_RUNS.

tag = 'AERIS_GUI';
old = findobj(0,'Type','figure','Tag',tag);
if ~isempty(old), figure(old(1)); return; end

f = figure('Tag',tag,'Name','AERIS control','NumberTitle','off', ...
           'MenuBar','none','ToolBar','none','Color',[.96 .96 .97], ...
           'Position',[80 420 330 430],'Resize','off');

W = 150; Lx = 14; Rx = 165; y = 385; dy = 34;

lbl(f, Lx, y, 'Mode');
uiMode = pop(f, Rx, y, {'Random raid','Swarm','Deterministic'});  y = y-dy;

lbl(f, Lx, y, 'Drones');
uiN = pop(f, Rx, y, [{'Auto'}, arrayfun(@(k)sprintf('%d',k),1:8,'uni',0)]); y = y-dy;

lbl(f, Lx, y, 'Formation');
uiForm = pop(f, Rx, y, {'Auto','line','trail','wedge','echelon','swarm'}); y = y-dy;

lbl(f, Lx, y, 'Environment');
uiEnv = pop(f, Rx, y, {'Baseline (grass)','Worst case (trees)'});  y = y-dy;

lbl(f, Lx, y, 'Seed');
uiSeed = uicontrol(f,'Style','edit','String','','Position',[Rx y W 22], ...
    'BackgroundColor','w','HorizontalAlignment','left', ...
    'TooltipString','blank = shuffle (new raid each run); integer = replay'); y = y-dy;

lbl(f, Lx, y, 'Altitude (m)');
uiAlt = uicontrol(f,'Style','edit','String','150','Position',[Rx y W 22], ...
    'BackgroundColor','w','HorizontalAlignment','left');  y = y-dy-4;

uiElev = chk(f, Lx, y, 'Elevation beam (coverage hole)', 0); y = y-26;
uiLog  = chk(f, Lx, y, 'Log every run to CSV', 1);          y = y-26;
uiVid  = chk(f, Lx, y, 'Save video', 0);                    y = y-34;

uicontrol(f,'Style','pushbutton','String','Run','FontWeight','bold', ...
    'Position',[Lx y 96 30],'BackgroundColor',[.82 .90 .82], ...
    'Callback',@(~,~) doRun(1));
uicontrol(f,'Style','pushbutton','String','Stop', ...
    'Position',[Lx+104 y 96 30],'BackgroundColor',[.95 .85 .85], ...
    'Callback',@(~,~) setappdata(0,'AERIS_STOP',true));
uicontrol(f,'Style','pushbutton','String','Analyze', ...
    'Position',[Lx+208 y 96 30], 'Callback',@(~,~) doAnalyze());
y = y-40;

lbl(f, Lx, y+2, 'Batch runs');
uiBatch = uicontrol(f,'Style','edit','String','25','Position',[Rx y 52 22], ...
    'BackgroundColor','w','HorizontalAlignment','left');
uicontrol(f,'Style','pushbutton','String','Run x N (headless)', ...
    'Position',[Rx+58 y-1 92 25],'Callback',@(~,~) doRun(0));

uiStat = uicontrol(f,'Style','text','String','ready', ...
    'Position',[Lx, 10, 300, 18],'HorizontalAlignment','left', ...
    'BackgroundColor',[.96 .96 .97],'ForegroundColor',[.35 .35 .35]);

% ====================================================================
    function p = buildParams()
        modes = {'random','swarm','default'};
        p = aeris_params(modes{uiMode.Value});

        if uiMode.Value == 3                      % deterministic
            p.randomThreats = false;
        else
            p.randomThreats = true;
        end

        % exact drone count
        if uiN.Value > 1
            p.nDrones = uiN.Value - 1;
        else
            p.nDrones = [];
        end

        % formation
        if uiForm.Value > 1
            p.randFormations = uiForm.String(uiForm.Value);
        end

        % environment
        if uiEnv.Value == 2
            p.gammaDB = -12; p.mtiImpDB = 30; p.grazingDeg = 3;
        end

        % seed
        s = strtrim(uiSeed.String);
        if isempty(s)
            p.rngSeed = 'shuffle';
        else
            v = str2double(s);
            if isnan(v), p.rngSeed = 'shuffle'; else, p.rngSeed = v; end
        end

        a = str2double(uiAlt.String);
        if ~isnan(a), p.targetAlt = a; end

        p.elevBeamOn = logical(uiElev.Value);
        p.logData    = logical(uiLog.Value);
        p.saveVideo  = logical(uiVid.Value);
    end

    function doRun(animated)
        setappdata(0,'AERIS_STOP',false);
        p = buildParams();
        try
            if animated
                say('running...');
                r = aeris_scope_sim3d(p);
                say(sprintf('%d drone(s), %s | warning %s s', ...
                    numel(r.threats), r.formation, fmtw(r.warnTime)));
            else
                n = max(1, round(str2double(uiBatch.String)));
                if isnan(n), n = 25; end
                p.headless = true; p.quiet = true; p.saveVideo = false;
                p.logData  = true;              % batch is pointless unlogged
                met = 0;
                t0 = tic;
                for i = 1:n
                    r = aeris_scope_sim3d(p);
                    met = met + double(r.requirementMet);
                    say(sprintf('batch %d/%d ... %d met', i, n, met));
                    drawnow limitrate
                    if getappdata(0,'AERIS_STOP')
                        say(sprintf('batch stopped at %d/%d', i, n)); break
                    end
                end
                say(sprintf('%d runs in %.1fs — %d met requirement (%.0f%%)', ...
                    i, toc(t0), met, 100*met/i));
            end
        catch ME
            say(['error: ' ME.message]);
            rethrow(ME);
        end
    end

    function doAnalyze()
        try
            say('analyzing...');
            S = aeris_analyze_runs();
            say(sprintf('%d drones / %d raids, %.0f%% met', ...
                S.nDrones, S.nRaids, 100*S.raidMetRate));
        catch ME
            say(ME.message);
        end
    end

    function say(s)
        if isvalid(uiStat), uiStat.String = s; drawnow limitrate; end
    end
end

% ------------------------------------------------------------------------
function lbl(f, x, y, s)
uicontrol(f,'Style','text','String',s,'Position',[x y 140 18], ...
    'HorizontalAlignment','left','BackgroundColor',[.96 .96 .97]);
end

function h = pop(f, x, y, items)
h = uicontrol(f,'Style','popupmenu','String',items,'Position',[x y 150 22], ...
    'BackgroundColor','w');
end

function h = chk(f, x, y, s, v)
h = uicontrol(f,'Style','checkbox','String',s,'Value',v, ...
    'Position',[x y 300 20],'BackgroundColor',[.96 .96 .97]);
end

function s = fmtw(w)
if isnan(w), s = '--'; else, s = sprintf('%.0f', w); end
end
