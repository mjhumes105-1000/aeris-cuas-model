function p = aeris_params(preset)
% AERIS_PARAMS  Single place to change every variable for the radar scope sim.
%   p = aeris_params()            % baseline
%   p = aeris_params('micro')     % 0.01 m^2 micro-quad target
%   p = aeris_params('fixedwing') % 0.1 m^2 Group-2 target
%   p = aeris_params('fast')      % 45 m/s closure
%   p = aeris_params('trees')     % worst-case vegetation clutter
%
% Edit the numbers below, or override any field after calling, e.g.:
%   p = aeris_params(); p.targetRCS = 0.05; p.Vc = 40;
%   aeris_scope_sim(p)
%
% Radar numbers mirror the Python cuas_l3/radar.py RadarParams defaults and
% are AERIS-Nexus PLACEHOLDERS — replace with the frozen repository spec.

if nargin < 1, preset = 'default'; end

% ---- physical constants -------------------------------------------------
p.c        = 299792458;        % m/s
p.k        = 1.380649e-23;     % Boltzmann
p.T0       = 290;              % K

% ---- micro-Doppler (rung 4: rotor blade-flash in aeris.look_iq) ---------
% Rotating rotor blades smear the target across Doppler (+/- 2*v_tip/lambda),
% a signature rigid bodies lack -> drone-vs-clutter discrimination.
p.microDoppler = false;        %      add rotor micro-Doppler to the IQ map
p.rotorRPM     = 10000;        % rpm  rotor speed
p.bladeRadius  = 0.10;         % m    blade tip radius
p.nBlades      = 2;            %      blades per rotor
p.nRotors      = 4;            %      rotors (quad)
p.rotorFrac    = 0.4;          %      rotor return power / body return

% ---- fidelity toggles --------------------------------------------------
% Rung 1: model the real patch array (Antenna + Phased Array Toolbox) for
% gain/beamwidth/pattern and the comms omni for the link budget, instead
% of the analytic aperture formula. OFF by default: analytic is the fast
% path and the cross-check. Set nEl=1 for the CN0566's 1x8 linear array.
p.useModeledAntenna = false;
p.useRfChain        = false;   %      rung 2: system NF from the RF receive-chain
p.procLossDB        = 0;       %      signal-processing loss (dB), window+straddle;
                               %      ~2.5 measured by aeris_iq_check (nearly cancels the RF-chain gain).
                               %      cascade (aeris.rf_chain) instead of p.NF.

% ---- radar / array (placeholders) --------------------------------------
p.freq     = 9.5e9;            % Hz  (X-band)
p.nAz      = 8;                % elements across azimuth
p.nEl      = 16;               % elements in elevation
p.dspaceWL = 0.5;              % element spacing in wavelengths
p.apEff    = 0.6;              % aperture efficiency
p.Ptpeak   = 20;               % W   total peak radiated power
p.tau      = 10e-6;            % s   pulse width (matched-filter energy)
p.Bchirp   = 5e6;              % Hz  LFM bandwidth -> range resolution c/2B
p.prf      = 10e3;             % Hz
p.cpi      = 256;              % coherent pulses integrated per dwell
p.NF       = 4;                % dB  noise figure
p.Lsys     = 6;                % dB  two-way system losses
p.Pfa      = 1e-6;             % design false-alarm probability
p.pdReliable = 0.9;            % Pd defining "reliable range"

% ---- sector / node ------------------------------------------------------
p.sectorWidth = 90;            % deg  field of regard
p.boresight   = 0;             % deg  sector centre (0 = +x, toward threat)
p.Rmax        = 5000;          % m    display / processing max range
p.Dforward    = 6000;          % m    node is this far forward of defended pt

% ---- beam scheduling (aeris_beam3d / aeris.dwell_plan) -----------------
% How much elevation the node is required to cover, and how tightly beams are
% packed. These set the dwell count and therefore the revisit period. The
% scope sims assume revisit << frameDt; aeris_beam3d checks that.
p.elevCoverDeg = [0 20];       % deg  elevation extent to cover [lo hi]
p.beamSpacing  = 0.9;
p.scanLossExp  = 1.5;          %      two-way azimuth scan-loss exponent (cos^q);
                               %      graceful sector edge via aeris.az_gain.          %      beam spacing / 3-dB beamwidth
p.barMode      = 'horizon';    %      'horizon' (lowest bar on the horizon,
                               %      best for low inbound threats) or
                               %      'centered'. Second-order effect; horizon
                               %      is free and strictly better at 0 deg el.

% ---- threat -------------------------------------------------------------
p.Vc          = 30;            % m/s  closure speed
p.bearingDeg  = 10;            % deg  approach bearing rel. boresight
p.targetRCS   = 0.03;          % m^2
p.startRange  = 5000;          % m    slant range at scenario start
p.Treq        = 300;           % s    required warning
p.latency     = 19;            % s    post-confirmation chain latency
p.MofN        = [3 4];         % M-of-N track confirmation

% ---- environment / clutter ---------------------------------------------
p.clutterOn   = true;
p.gammaDB     = -22;           % dB   constant-gamma surface (grass ~ -22)
p.mtiImpDB    = 48;            % dB   Doppler/MTI clutter improvement
p.grazingDeg  = 1.0;           % deg  grazing angle at clutter patch

% ---- terrain masking (rung 4: aeris.terrain_height, aeris.los_clear) ----
% Off = flat earth (all prior results). On = line-of-sight blocked by ground.
p.terrainOn    = false;        %      enable terrain LOS masking
p.terrainPreset= 'ridge';      %      'flat'|'ridge'|'hills'|'dem'
p.mastHeight   = 3;            % m    node antenna height above terrain
p.ridgeX       = 3000;         % m    ridge location (down-threat)
p.ridgeH       = 120;          % m    ridge height
p.ridgeW       = 400;          % m    ridge width
p.multipathOn  = false;        %      rung 4: two-ray ground-bounce lobing
p.groundRefl   = 0.7;          %      ground reflection magnitude (1=smooth/water)

% ---- weather (attenuation + rain backscatter) ---------------------------
% All zero = clear dry air = the legacy baseline, bit-identical. See
% aeris.atmos_atten for the ITU models and aeris.environments for presets.
% At X-band rain dominates and fog barely matters - that asymmetry is a
% finding, not an accident.
p.rainRate    = 0;             % mm/hr  2 light, 10 moderate, 25 heavy, 50 extreme
p.fogDensity  = 0;             % g/m^3  0.05 haze, 0.5 dense fog
p.humidity    = 7.5;           % g/m^3  absolute; 7.5 = ITU reference, ~20 tropical
p.rainMtiDB   = 12;            % dB   MTI improvement against MOVING rain
                               %      (much weaker than against ground). PROVISIONAL.
p.rainVelSpread = 4;           % m/s  Doppler spread of the rain return
p.droneClass  = '';            %      '' = flat RCS range; else a
                               %      aeris.drone_catalog class name

% ---- 3-D / elevation (aeris_scope_sim3d only) --------------------------
p.targetAlt   = 0;             % m    target altitude. 0 = exact 2-D baseline,
                               %      preserving the Level 3 / Python parity.
p.elevBeamOn  = false;         %      weight SNR by the elevation beam. OFF by
                               %      default: the Python model has no
                               %      elevation term. ON exposes the close-in
                               %      coverage hole (elBW ~6 deg for nEl=16).
p.elevBore    = 0;             % deg  elevation boresight

% ---- randomised raids (aeris_scope_sim3d only) -------------------------
% With randomThreats = true every run draws a fresh raid: size, altitude,
% speed, formation and course. Set p.rngSeed = 'shuffle' so each run differs;
% keep an integer seed to replay a specific raid exactly.
p.randomThreats  = false;      %      master switch
p.nDrones        = [];         %      force an exact count, e.g. 5. [] = random
p.randNDrones    = [2 6];      %      how many drones per raid (min max)
p.randRCS        = [0.005 0.15];   % m^2  LOG-uniform: micro-quad -> Group 2
% ALTITUDE MODE. 'class' takes altitude from the drone class band - realistic,
% but altitude is then correlated with RCS (fixedwing is big AND high), which
% confounds any altitude-vs-performance result. 'independent' draws from
% randAlt regardless of class, breaking that correlation - use it when you want
% to attribute an altitude effect. 'fixed' puts every drone at targetAlt.
p.altMode        = 'class';    %      'class' | 'independent' | 'fixed'
p.randAlt        = [30 400];   % m    lead altitude (altMode 'independent')
p.randAltJitter  = [-60 60];   % m    per-drone offset from the lead
p.randSpeed      = [15 50];    % m/s  group speed
p.randSpeedJitter= [-8 8];     % m/s  per-drone (swarm only)
p.randBearingDeg = [-40 40];   % deg  approach bearing of the lead
p.randStartRange = [4000 5000];% m    initial ground range
p.randSpacing    = [80 300];   % m    formation spacing
p.randCourseJitter=[-12 12];   % deg  per-drone course error (swarm only)
p.randDescent    = [0.1 0.6];  %      fraction of altitude bled off en route
% NOTE: 'single' is deliberately NOT in this list - a one-drone raid already
% happens whenever randNDrones draws 1. Including it here made ~a third of
% runs collapse to a single target.
p.randFormations = {'line','trail','wedge','echelon','swarm'};

% ---- comms / network (aeris.comms) -------------------------------------
% How the radars talk to the fusion cell (C2 = the base by default).
% Centralized fusion with mesh relay: a node delivers directly within
% commsRange, else relays through a connected peer (+1 hop latency each).
% Unreachable or killed nodes drop out of the fused picture.
p.useComms     = false;        %      gate confirmation on comms reachability to
                               %      C2. OFF by default (a comms/attrition STUDY,
                               %      not the default sensing scenario). See aeris.comms.
p.commsRange   = [];           % m    max direct link range; [] = derive from
                               %      the comms link budget (aeris.comms_range)
p.commsLatency = 1.0;
p.commsWaterfall= 2.0;         % dB   link waterfall width: how gradually packet
                               %      delivery falls with range (coded link ~2; smaller = sharper)          % s    latency per relay hop (into warning chain)
p.c2Pos        = [];           % 1x3  fusion cell; [] = defended point
p.nodesDown    = [];           % idx  killed nodes (attrition), e.g. [3]
p.pairForward  = 2500;
% ---- comms RF (the DATA LINK - separate from the X-band radar) ----------
% Baseline: 900 MHz, 1 W, omni COTS mesh carrying low-rate track/plot
% reports (CoT). Out-of-band from the 9.5 GHz sensing radar. See
% aeris.comms_range for the link budget these feed.
p.commsFreq    = 915e6;        % Hz   link carrier (900 MHz ISM)
p.commsPtx     = 30;           % dBm  transmit power (1 W)
p.commsGtx     = 3;            % dBi  Tx antenna gain (omni whip)
p.commsGrx     = 3;            % dBi  Rx antenna gain
p.commsNF      = 6;            % dB   receiver noise figure
p.commsRate    = 100e3;        % bps  data rate (track fusion is low-rate)
p.commsEbN0    = 10;           % dB   required Eb/N0
p.commsMargin  = 12;           % dB   fade / NLOS margin
p.commsPathExp = 3.0;          %      path-loss exponent (2.7 benign, 3.5 foliage)
         % m    'pairs' layout: far pair this far forward

% ---- effector / cueing (aeris.cue_defeat, aeris_cueing_study) -----------
% The node cues an effector; these set the effector timeline the warning
% must beat. The 'right' Treq is really react+engage, not an abstract 300 s.
p.effReact     = 15;           % s   C2 decision / reaction time
p.effEngage    = 60;           % s   effector spin-up + fly-out
p.effPk        = 0.7;          %     single-engagement kill probability
p.effSlop      = 20;           % s   timing softness of the threshold

% ---- data capture -------------------------------------------------------
p.logData     = true;          %      append every run to the results CSV
p.logFile     = '';            %      '' -> matlab/matlab_out/aeris_runs.csv
p.headless    = false;         %      true -> no graphics at all. Use for batch
                               %      Monte Carlo: same physics, same logging,
                               %      ~100x faster because nothing is drawn.
p.quiet       = false;         %      true -> suppress the per-run printout

% ---- simulation / display ----------------------------------------------
p.frameDt     = 2.0;           % s    time between displayed looks
p.maxFrames   = 300;           % cap
p.nDoppler    = 128;           % Doppler bins in the range-Doppler map
p.fps         = 15;            % video frame rate
p.saveVideo   = true;
p.videoFile   = 'aeris_scope.mp4';
p.useToolboxCFAR = false;      % true -> phased.CFARDetector2D (slower); false -> fast CA-CFAR
% ---- tracker (aeris_cop / aeris.track_step) ----------------------------
p.trackQ       = 3;            % m/s^2  accel process-noise (maneuver allowance)
p.trackGate    = 11.8;         %        chi-square(2) assoc. gate (~99.7%)
p.trackConfirm = 3;            %        hits to confirm a track
p.trackMaxMiss = 3;            %        misses before dropping a track
p.trackV0      = 40;           % m/s    initial speed uncertainty (new track)

% ---- georeference (aeris.sim2ll) ---------------------------------------
% Operator/site datum so the defended point and every track report real
% coordinates (WGS-84). refLat/refLon = GPS of the sim origin; threatBearing = TRUE
% bearing (deg from north) the sector faces (+x). Empty ref = no lat/lon.
p.refLat       = [];           % deg   site datum, e.g. 33.24 (leave [] for none)
p.refLon       = [];           % deg
p.threatBearing= 0;            % deg   true bearing of +x (sector boresight)

p.units       = 'imperial';   %      OPERATOR display units: 'imperial'
                               %      (feet/miles/mph) or 'si'. Affects
                               %      aeris_cop and warning_text ONLY -
                               %      all physics and data stay SI.
p.rngSeed     = 7;

% ---- presets ------------------------------------------------------------
switch lower(preset)
    case 'default'
        % as above
    case 'micro'
        p.targetRCS = 0.01;
    case 'fixedwing'
        p.targetRCS = 0.10;
    case 'fast'
        p.Vc = 45;
    case 'trees'
        p.gammaDB = -12; p.mtiImpDB = 30; p.grazingDeg = 3;
    case {'nexus','aeris10n'}
        % AERIS-10N: 10.5 GHz, 8x16 patch, 1W x 16 = 16 W, FIXED 90 deg sector.
        p.freq = 10.5e9; p.nAz = 8;  p.nEl = 16; p.Ptpeak = 16;
        p.sectorWidth = 90; p.rotating = false;
    case {'extended','aeris10x','aeris10e'}
        % AERIS-10X: 10.5 GHz, 32x16 slotted waveguide, 10W x 16 = 160 W GaN,
        % 20 km design. 4x azimuth aperture + 10x power, and it ROTATES 360 deg
        % mechanically (revisit = rotation period) instead of a fixed stare.
        p.freq = 10.5e9; p.nAz = 32; p.nEl = 16; p.Ptpeak = 160;
        p.sectorWidth = 360; p.rotating = true; p.rotationPeriod = 4;
        p.perElemW = 0.5;   % active waveguide array draws more per element
    case 'random'
        % fresh randomised raid every run, logged to CSV
        p.randomThreats = true; p.rngSeed = 'shuffle';
        p.targetAlt = 150; p.saveVideo = false;
    case 'swarm'
        % many small drones, low and fast, worst case for the node
        p.randomThreats = true; p.rngSeed = 'shuffle';
        p.randFormations = {'swarm'}; p.randNDrones = [4 8];
        p.randRCS = [0.005 0.03]; p.randAlt = [30 120];
        p.randSpeed = [25 50]; p.targetAlt = 100; p.saveVideo = false;
    case {'best','clear','grass','humid','haze','fog','rain_light', ...
          'rain_mod','rain_heavy','rain_extreme','worst'}
        % environmental presets from aeris.environments
        e = aeris.environments(lower(preset));
        p.rainRate = e.rainRate; p.fogDensity = e.fogDensity;
        p.humidity = e.humidity; p.gammaDB    = e.gammaDB;
        p.mtiImpDB = e.mtiImpDB; p.grazingDeg = e.grazingDeg;
    otherwise
        warning('aeris_params:unknownPreset', 'Unknown preset "%s"; using default.', preset);
end
end
