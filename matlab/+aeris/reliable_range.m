function [rr, Rg, pd] = reliable_range(p, g)
%AERIS.RELIABLE_RANGE  Range at which Pd first falls below p.pdReliable.
%   rr            = aeris.reliable_range(p, g)
%   [rr, Rg, pd]  = aeris.reliable_range(p, g)   also returns the curve
%
%   This is the number Levels 1-2 otherwise assume. Returns 0 if the required
%   Pd is never achieved at any range in the search grid.

Rg  = 100:10:30000;                       % m
s   = aeris.snr(p, g, Rg);
pd  = aeris.pd_swerling1(s, p.Pfa);
i   = find(pd >= p.pdReliable, 1, 'last');
if isempty(i), rr = 0; else, rr = Rg(i); end
end
