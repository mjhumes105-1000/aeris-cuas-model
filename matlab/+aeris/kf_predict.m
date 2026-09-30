function [x, P] = kf_predict(x, P, dt, q)
%AERIS.KF_PREDICT  Constant-velocity Kalman prediction (2-D, state [x y vx vy]).
%   [x,P] = aeris.kf_predict(x,P,dt,q)
%
%   q is the acceleration process-noise standard deviation (m/s^2) - how much
%   the target is allowed to maneuver between updates. Larger q -> the filter
%   trusts the model less and the measurements more (looser, more responsive).

F = [1 0 dt 0;
     0 1 0 dt;
     0 0 1 0;
     0 0 0 1];

q2 = q^2;
Q  = q2 * [dt^4/4, 0,      dt^3/2, 0;
           0,      dt^4/4, 0,      dt^3/2;
           dt^3/2, 0,      dt^2,   0;
           0,      dt^3/2, 0,      dt^2];

x = F * x;
P = F * P * F.' + Q;
end
