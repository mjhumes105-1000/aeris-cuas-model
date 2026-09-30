function E = environments(name)
%AERIS.ENVIRONMENTS  Named environmental conditions, best case to worst.
%   E = aeris.environments()      all of them, as a struct array
%   E = aeris.environments('rain_heavy')   just that one
%
%   Each entry carries the fields the physics consumes:
%     rainRate    mm/hr   0 = dry
%     fogDensity  g/m^3   0.05 light haze, 0.5 dense fog
%     humidity    g/m^3   absolute; 7.5 is the ITU reference atmosphere
%     gammaDB     dB      constant-gamma surface reflectivity
%     mtiImpDB    dB      Doppler/MTI clutter improvement achieved
%     grazingDeg  deg     grazing angle at the clutter patch
%     weight      -       relative sampling frequency in a random sweep
%
%   The two anchors:
%     'best'   best of the best - dry, calm, cold, low-reflectivity ground,
%              excellent MTI, shallow grazing. The optimistic bound.
%     'worst'  worst of the worst - heavy rain AND fog AND dense vegetation
%              AND degraded MTI AND steep grazing, all at once. Deliberately
%              pessimistic; it is a bound, not a forecast.
%
%   Sampling weights are set so that ordinary conditions dominate and the
%   extremes stay rare - an unweighted sweep would badly overstate how often
%   the node operates in a downpour.

E = struct( ...
 'name',      {'best',  'clear', 'grass', 'humid', 'haze',  'fog',   'trees', 'rain_light','rain_mod','rain_heavy','rain_extreme','worst'}, ...
 'rainRate',  { 0,       0,       0,       0,       0,       0,       0,       2,           10,        25,          50,            50   }, ...
 'fogDensity',{ 0,       0,       0,       0,       0.05,    0.5,     0,       0,           0.05,      0.1,         0.2,           0.5  }, ...
 'humidity',  { 2,       7.5,     7.5,     20,      15,      18,      12,      15,          18,        20,          22,            22   }, ...
 'gammaDB',   {-30,     -25,     -22,     -22,     -22,     -22,     -12,     -22,         -20,       -18,         -16,           -10   }, ...
 'mtiImpDB',  { 55,      50,      48,      48,      46,      44,      30,      44,          40,        36,          32,            25   }, ...
 'grazingDeg',{ 0.5,     0.8,     1.0,     1.0,     1.2,     1.5,     3.0,     1.2,         1.5,       2.0,         2.5,           3.5  }, ...
 'weight',    { 1,       6,       10,      6,       4,       2,       5,       4,           3,         2,           1,             1    } );

if nargin >= 1 && ~isempty(name)
    k = find(strcmpi({E.name}, name), 1);
    if isempty(k)
        error('aeris:env','unknown environment "%s". Options: %s', ...
              name, strjoin({E.name}, ', '));
    end
    E = E(k);
end
end
