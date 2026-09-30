function Y = boxfilt(X, n)
%AERIS.BOXFILT  Separable (2n+1)x(2n+1) box sum, 'same' size.
%   Y = aeris.boxfilt(X, n)
%
%   Equivalent to conv2(X, ones(2*n+1), 'same') but O(2k) per pixel instead of
%   O(k^2) - for the 13x13 CFAR window that is ~6x fewer operations.

v = ones(2*n+1, 1);
Y = conv2(v, v.', X, 'same');
end
