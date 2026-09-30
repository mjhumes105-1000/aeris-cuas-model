function D = drone_catalog(name)
%AERIS.DRONE_CATALOG  Threat classes with realistic RCS, speed and altitude.
%   D = aeris.drone_catalog()          the whole catalogue
%   D = aeris.drone_catalog('micro')   one class
%
%   Each class gives a RANGE for each quantity; the sweep draws within it, so
%   two runs of the same class are not identical airframes.
%
%     rcs    m^2   [min max], sampled LOG-uniform (RCS spans decades)
%     spd    m/s   [min max] ground speed
%     alt    m     [min max] typical operating altitude
%     weight -     relative sampling frequency
%
%   Classes:
%     micro       0.005-0.015  toy/FPV quad. The hardest target - this is the
%                 class the node is most likely to lose.
%     small_quad  0.01-0.03    commercial quad (DJI-class). The baseline
%                 0.03 m^2 assumption sits at the top of this band.
%     heavy_quad  0.03-0.08    hexa/octo lifter, payload-carrying.
%     fixedwing   0.08-0.20    Group 2 fixed wing. Easiest to see, fastest.
%     fpv_attack  0.005-0.02   small, FAST, low. One-way attack profile:
%                 the worst combination - hard to see and little time.
%
%   PROVISIONAL. RCS bands are order-of-magnitude estimates for X-band from
%   the open literature, not measurements. Replace with measured values (or
%   a validated set) before citing any per-class result.

D = struct( ...
 'name',  {'micro',        'small_quad',  'heavy_quad',  'fixedwing',   'fpv_attack'}, ...
 'rcs',   {[0.005 0.015],  [0.01 0.03],   [0.03 0.08],   [0.08 0.20],   [0.005 0.02]}, ...
 'spd',   {[8 18],         [12 25],       [15 28],       [25 50],       [35 60]},     ...
 'alt',   {[20 120],       [40 250],      [50 300],      [150 900],     [15 100]},    ...
 'weight',{ 5,              8,             4,             3,             4  } );

if nargin >= 1 && ~isempty(name)
    k = find(strcmpi({D.name}, name), 1);
    if isempty(k)
        error('aeris:drone','unknown drone class "%s". Options: %s', ...
              name, strjoin({D.name}, ', '));
    end
    D = D(k);
end
end
