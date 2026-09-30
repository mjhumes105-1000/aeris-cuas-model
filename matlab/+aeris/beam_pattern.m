function patLin = beam_pattern(azGrid, p, g)
%AERIS.BEAM_PATTERN  One-way normalised azimuth power pattern.
%   patLin = aeris.beam_pattern(azGrid, p, g)
%
%   Uses phased.URA + pattern() when the Phased Array System Toolbox is
%   available (the real element pattern and array factor), and falls back to
%   the uniform-aperture array-factor model otherwise. Normalised to 1 at
%   boresight. Square the result for two-way gain.
%
%   The toolbox path is what MATLAB adds over the Python model, which uses a
%   Gaussian-ish beamwidth approximation.
%
%   When the modeled antenna (rung 1) is active, g.antenna carries its az cut;
%   we interpolate that so beam shape matches the modeled patch array exactly.

if isfield(g,'antenna') && ~isempty(g.antenna) && isstruct(g.antenna) && g.antenna.ok
    patLin = interp1(g.antenna.azGrid, g.antenna.azPatLin, azGrid, 'linear', 0);
    patLin = patLin / max(patLin);
    return
end

try
    arr = phased.URA('Size',[p.nEl p.nAz],'ElementSpacing',[g.d g.d]);
    pdb = pattern(arr, p.freq, azGrid, 0, 'PropagationSpeed', p.c, ...
                  'Type','powerdb','Normalize',true);
    patLin = 10.^(pdb(:).'/10);
catch
    Naz = p.nAz;
    psi = pi*p.dspaceWL*sind(azGrid);
    af  = abs(sin(Naz*psi)./(Naz*sin(psi)));
    af(psi==0) = 1;
    patLin = af.^2;
end
patLin = patLin / max(patLin);
end
