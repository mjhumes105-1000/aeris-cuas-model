function pd = pd_swerling1(snr, Pfa)
%AERIS.PD_SWERLING1  Detection probability for a Swerling-1 target.
%   pd = aeris.pd_swerling1(snr, Pfa)
%
%   Closed form for a slowly-fluctuating (Swerling case 1) target with a
%   square-law detector:  Pd = Pfa ^ (1 / (1 + SNR)).
%
%   snr is LINEAR (not dB) and may be an array. Mirrors cuas_l3/radar.py.

pd = Pfa .^ (1 ./ (1 + snr));
end
