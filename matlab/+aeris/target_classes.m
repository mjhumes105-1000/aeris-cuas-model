function C = target_classes(name)
%AERIS.TARGET_CLASSES  Drone / bird / plane: RCS, kinematics, micro-Doppler.
%   C = aeris.target_classes()        all three
%   C = aeris.target_classes('bird')  one
%
%   Shared truth for discrimination (aeris_discriminate) and the live scenario
%   (aeris_vs_live). Each class carries RCS/speed/altitude bands (log-uniform
%   RCS) and the micro-Doppler source that separates them:
%     drone  rotor blades - broad, fast, periodic Doppler smear
%     bird   wingbeat     - narrow, slow (~5 Hz), intermittent (glides)
%     plane  propeller/JEM- moderate lines on a large rigid body
%
%   RCS/kinematics are order-of-magnitude open-literature values - provisional.

C = struct( ...
 'name',   {'drone',       'bird',        'plane'}, ...
 'rcs',    {[0.005 0.15],  [0.001 0.01],  [1 100]}, ...   % m^2, log-uniform
 'spd',    {[8 60],        [5 25],        [60 250]}, ...   % m/s
 'alt',    {[30 400],      [20 300],      [300 3000]}, ... % m
 'modType',{'rotor',       'wing',        'prop'}, ...
 'modRPM', {10000,         NaN,           2400}, ...       % rotor/prop rpm
 'wingHz', {NaN,           5,             NaN}, ...        % wingbeat Hz
 'tipR',   {0.10,          NaN,           0.90}, ...       % rotor/prop tip radius m
 'nMod',   {8,             NaN,           2}, ...          % blades (4 rotors x2) / prop
 'wingExc',{NaN,           0.12,          NaN}, ...        % wingtip excursion m
 'color',  {[.95 .35 .3],  [.4 .8 .95],   [.95 .8 .3]});

if nargin >= 1 && ~isempty(name)
    k = find(strcmpi({C.name}, name), 1);
    if isempty(k), error('aeris:tclass','unknown class "%s"', name); end
    C = C(k);
end
end
