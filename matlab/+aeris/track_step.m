function [tr, nextId] = track_step(tr, Z, Rc, meta, dt, cfg, nextId)
%AERIS.TRACK_STEP  One cycle of a multi-target tracker (predict/associate/update).
%   [tr, nextId] = aeris.track_step(tr, Z, Rc, meta, dt, cfg, nextId)
%
%   Runs a constant-velocity Kalman tracker over this frame's measurements:
%     1. predict every existing track forward by dt
%     2. associate each measurement to the nearest track within a chi-square
%        gate (greedy nearest-neighbour); multiple measurements (one per
%        detecting node) can update the same track in sequence - that IS the
%        multi-node fusion
%     3. spawn a tentative track for any unassociated measurement
%     4. age tracks: confirm at cfg.confirmHits, delete after cfg.maxMiss misses
%
%   INPUTS
%     tr      track struct array (pass [] to start); fields x,P,id,hits,misses,
%             confirmed,alt,rcs,contrib
%     Z       2xM measurements (Cartesian), Rc 2x2xM covariances
%     meta    struct with per-measurement metadata: .alt (1xM), .rcs (1xM)
%     dt      s since last step
%     cfg     .q (accel PSD std), .gate (chi2, ~9.21 for 99%/2dof),
%             .confirmHits, .maxMiss, .v0 (initial speed std)
%     nextId  running track-id counter
%
%   OUTPUT tr carries CONFIRMED and tentative tracks; filter on [tr.confirmed].

if isempty(tr)
    tr = empty_tracks();
end

% ---- 1. predict --------------------------------------------------------
for i = 1:numel(tr)
    [tr(i).x, tr(i).P] = aeris.kf_predict(tr(i).x, tr(i).P, dt, cfg.q);
    tr(i).matched = false;
    tr(i).contrib = 0;
end

% ---- 2/3. associate + update or spawn ----------------------------------
H = [1 0 0 0; 0 1 0 0];
M = size(Z, 2);
for m = 1:M
    z = Z(:,m); Rm = Rc(:,:,m);
    best = -1; bestd = inf;
    for i = 1:numel(tr)
        y = z - H*tr(i).x;
        S = H*tr(i).P*H.' + Rm;
        d = y.' / S * y;
        if d < cfg.gate && d < bestd, bestd = d; best = i; end
    end
    if best > 0
        [tr(best).x, tr(best).P] = aeris.kf_update(tr(best).x, tr(best).P, z, Rm);
        tr(best).matched = true;
        tr(best).contrib = tr(best).contrib + 1;
        tr(best).hits    = tr(best).hits + 1;
        tr(best).misses  = 0;
        tr(best).alt     = meta.alt(m);
        tr(best).rcs     = meta.rcs(m);
    else
        tr(end+1) = new_track(z, Rm, meta.alt(m), meta.rcs(m), nextId, cfg); %#ok<AGROW>
        nextId = nextId + 1;
    end
end

% ---- 4. age: confirm / delete ------------------------------------------
keep = true(1, numel(tr));
for i = 1:numel(tr)
    if ~tr(i).matched, tr(i).misses = tr(i).misses + 1; end
    if tr(i).hits >= cfg.confirmHits, tr(i).confirmed = true; end
    if tr(i).misses > cfg.maxMiss, keep(i) = false; end
end
tr = tr(keep);
end

% ------------------------------------------------------------------------
function t = new_track(z, Rm, alt, rcs, id, cfg)
t = struct('x', [z; 0; 0], ...
           'P', blkdiag(Rm, cfg.v0^2*eye(2)), ...
           'id', sprintf('T%d', id), ...
           'hits', 1, 'misses', 0, 'confirmed', false, ...
           'matched', true, 'contrib', 1, 'alt', alt, 'rcs', rcs, 'classCall', '');
end

function tr = empty_tracks()
tr = struct('x',{}, 'P',{}, 'id',{}, 'hits',{}, 'misses',{}, ...
            'confirmed',{}, 'matched',{}, 'contrib',{}, 'alt',{}, 'rcs',{}, 'classCall',{});
end
