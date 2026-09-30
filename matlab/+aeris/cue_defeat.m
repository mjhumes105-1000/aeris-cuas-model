function pd = cue_defeat(warnT, p)
%AERIS.CUE_DEFEAT  Probability an effector defeats a threat given the warning.
%   pd = aeris.cue_defeat(warnT, p)
%
%   The node's job in defense-in-depth is not to meet an abstract 300 s - it is
%   to CUE an effector in time to act. This maps delivered warning time to a
%   defeat probability through a simple effector timeline:
%
%     time needed = react + engage (spin-up / fly-out)
%     pd = Pk / (1 + exp(-(warnT - needed)/slop))
%
%   so an effector that only needs ~90 s can still be cued by a warning that
%   "fails" the 300 s requirement - which is exactly why the requirement should
%   follow the effector, not the other way round (see aeris_treq_curve).
%
%   Parameters (aeris_params):
%     p.effReact   s   C2 decision / reaction time (default 15)
%     p.effEngage  s   effector spin-up + fly-out (default 60)
%     p.effPk      -   single-engagement kill probability (default 0.7)
%     p.effSlop    s   timing softness of the threshold (default 20)
%
%   warnT may be a vector; entries < 0 or NaN (never warned) give pd = 0.

tReact = getf(p,'effReact', 15);
tEng   = getf(p,'effEngage',60);
Pk     = getf(p,'effPk',    0.7);
slop   = getf(p,'effSlop',  20);

needed = tReact + tEng;
pd = Pk ./ (1 + exp(-(warnT - needed)/slop));
pd(isnan(warnT) | warnT < 0) = 0;
end

function v = getf(s,f,d), if isfield(s,f)&&~isempty(s.(f)), v=s.(f); else, v=d; end, end
