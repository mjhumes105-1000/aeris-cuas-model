function [z, Rc] = meas_polar(nodePos, pt, snr, g)
%AERIS.MEAS_POLAR  A node's noisy position measurement of a target.
%   [z, Rc] = aeris.meas_polar(nodePos, pt, snr, g)
%
%   A radar measures RANGE well and ANGLE poorly, and both improve with SNR.
%   This returns a 2-D Cartesian position fix z (2x1) and its covariance Rc
%   (2x2) in the common frame, built from:
%     range std    sigR  = dR / sqrt(2*SNR), floored at dR/4
%     bearing std  sigAz = azBW / (1.6*sqrt(2*SNR))   [converted to rad]
%
%   Because bearing error maps to a CROSS-RANGE position error that grows with
%   range, Rc is an ellipse elongated across the line of sight - exactly what a
%   radar track looks like, and why fusing two nodes from different bearings
%   tightens the fix so much.
%
%   snr is linear integrated SNR; g is aeris.derive output (uses g.dR, g.azBW).

rel = pt(1:2) - nodePos(1:2);
R   = max(norm(rel), 1);
az  = atan2(rel(2), rel(1));

s   = max(snr, 1);
sigR  = max(g.dR / sqrt(2*s), g.dR/4);              % m
sigAz = deg2rad(g.azBW) / (1.6 * sqrt(2*s));         % rad

Rm  = R  + sigR  * randn;
azm = az + sigAz * randn;
z   = nodePos(1:2).' + Rm * [cos(azm); sin(azm)];    % 2x1

% polar -> Cartesian covariance via the Jacobian d(x,y)/d(R,az)
J  = [cos(az), -R*sin(az);
      sin(az),  R*cos(az)];
Rc = J * diag([sigR^2, sigAz^2]) * J.';
Rc = (Rc + Rc.') / 2;
end
