function w = wrap180(a)
%AERIS.WRAP180  Wrap an angle in degrees to (-180, 180].
%   w = aeris.wrap180(a)

w = mod(a + 180, 360) - 180;
end
