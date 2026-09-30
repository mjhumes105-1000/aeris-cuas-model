function [mask, thresh] = cfar(P, cf)
%AERIS.CFAR  Cell-averaging CFAR over a range-Doppler map.
%   [mask, thresh] = aeris.cfar(P, cf)   cf from aeris.cfar_init
%
%   mask   logical detections, same size as P
%   thresh the detection threshold (returned for the A-scope)
%
%   Uses the fast vectorised CA-CFAR by default. If cf.tb holds a
%   phased.CFARDetector2D it is used for the detections instead (decimated CUT
%   grid), with the analytic noise estimate still returned as thresh because
%   the toolbox 'Auto' mode does not expose its threshold.

noise  = (aeris.boxfilt(P, cf.k) - aeris.boxfilt(P, cf.ng)) ./ cf.cnt;
thresh = cf.alpha * noise;

if ~isempty(cf.tb)
    try
        [nR, nD] = size(P);
        k  = cf.k;
        rr = (k+1):2:(nR-k);
        cc = (k+1):2:(nD-k);
        [CC, RR] = meshgrid(cc, rr);
        idx = cf.tb(P, [RR(:).'; CC(:).']);
        mask = false(nR, nD);
        if ~isempty(idx)
            mask(sub2ind([nR nD], idx(1,:), idx(2,:))) = true;
        end
        thresh = noise;
        return;
    catch
        % fall through to the built-in detector
    end
end

mask = P > thresh;

% suppress edges, where the window runs off the map
k = cf.k;
mask(1:k,:) = false;  mask(end-k+1:end,:) = false;
mask(:,1:k) = false;  mask(:,end-k+1:end) = false;
end
