function [x, P, nis] = kf_update(x, P, z, Rm)
%AERIS.KF_UPDATE  Kalman measurement update with a 2-D position fix.
%   [x,P,nis] = aeris.kf_update(x,P,z,Rm)
%
%   z is a 2x1 Cartesian position measurement, Rm its 2x2 covariance (from
%   aeris.meas_polar). Returns the updated state/covariance and the normalized
%   innovation squared (nis) - a chi-square(2) statistic used for gating.

H = [1 0 0 0;
     0 1 0 0];

y = z - H * x;                 % innovation
S = H * P * H.' + Rm;          % innovation covariance
K = P * H.' / S;               % Kalman gain
x = x + K * y;
P = (eye(4) - K * H) * P;
P = (P + P.') / 2;             % keep it symmetric

nis = y.' / S * y;
end
