function m = target_signature(cls, M, PRI, lambda)
%AERIS.TARGET_SIGNATURE  Slow-time micro-Doppler modulation for a target class.
%   m = aeris.target_signature(cls, M, PRI, lambda)
%
%   Returns a length-M complex slow-time modulation (to multiply onto the body
%   Doppler phase) that carries the class's micro-Doppler:
%     rotor  sum of blade-tip FM exp(j*beta*sin(Omega t)), beta=4*pi*R/lambda -
%            broad, fast, periodic (the drone smear)
%     wing   low-rate FM at the wingbeat, small excursion, and INTERMITTENT
%            (gliding birds stop flapping) - narrow, slow, on/off
%     prop   like rotor but slower/larger (moderate lines) on a strong steady
%            body return (planes are mostly rigid)
%
%   cls is one element of aeris.target_classes. Unit-ish amplitude; the caller
%   scales by the body return.

tm = (0:M-1) * PRI;
switch cls.modType
    case 'rotor'
        Om = 2*pi*cls.modRPM/60; beta = 4*pi*cls.tipR/lambda;
        m = zeros(1,M);
        for b = 1:cls.nMod, m = m + exp(1j*beta*sin(Om*tm + 2*pi*rand)); end
        m = m / cls.nMod;
    case 'prop'
        Om = 2*pi*cls.modRPM/60; beta = 4*pi*cls.tipR/lambda;
        pm = zeros(1,M);
        for b = 1:cls.nMod, pm = pm + exp(1j*beta*sin(Om*tm + 2*pi*rand)); end
        m = 0.7 + 0.3*(pm/cls.nMod);            % strong rigid body + prop lines
    case 'wing'
        fw = cls.wingHz; beta = 4*pi*cls.wingExc/lambda;
        flap = exp(1j*beta*sin(2*pi*fw*tm + 2*pi*rand));
        % intermittent: bird glides ~40% of the time (modulation -> steady body)
        gate = double(mod(fw*tm + rand, 1) < 0.6);
        m = (1-0.5*gate) + 0.5*gate.*flap;      % steady with flapping bursts
    otherwise
        m = ones(1,M);                          % rigid
end
end
