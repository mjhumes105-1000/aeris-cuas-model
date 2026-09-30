function B = bom(nNodes, parts)
%AERIS.BOM  Bill of materials: weight and cost, per node and per network.
%   B = aeris.bom              % one node, default parts, prints a table
%   B = aeris.bom(4)           % roll up a 4-node network
%   B = aeris.bom(4, parts)    % supply your own parts struct array
%
%   SWaP-C for the node, kept in sync with the model like aeris.power_budget.
%   The default parts are the CN0566-class lab-reference node priced Sep 2026;
%   confidence flags which line items are confirmed vs estimated. Edit the
%   defaults here, or pass your own `parts` (fields: name, cat, qty, lb, usd,
%   conf) to price a different build (e.g. the AERIS-10 production node).
%
%   Returns B with fields: parts (the table), nodeLb, nodeUsd, nNodes,
%   netLb, netUsd, batteryFrac (battery share of node weight).

if nargin < 1 || isempty(nNodes), nNodes = 1; end
if nargin < 2 || isempty(parts),  parts = default_parts(); end

n    = numel(parts);
lb   = zeros(n,1); usd = zeros(n,1);
for i = 1:n
    lb(i)  = parts(i).qty * parts(i).lb;
    usd(i) = parts(i).qty * parts(i).usd;
end
nodeLb  = sum(lb);
nodeUsd = sum(usd);

battLb = sum(lb(strcmp({parts.cat},'power')));
battFrac = battLb / max(nodeLb,eps);

B = struct('parts',{parts}, 'lineLb',lb, 'lineUsd',usd, ...
           'nodeLb',nodeLb, 'nodeUsd',nodeUsd, 'nNodes',nNodes, ...
           'netLb',nodeLb*nNodes, 'netUsd',nodeUsd*nNodes, ...
           'batteryFrac',battFrac);

if nargout == 0
    fprintf('\n--- AERIS node bill of materials ---\n');
    fprintf('%-26s %4s %8s %10s  %s\n','item','qty','wt (lb)','cost ($)','conf');
    fprintf('%s\n', repmat('-',1,62));
    for i = 1:n
        fprintf('%-26s %4d %8.2f %10s  %s\n', parts(i).name, parts(i).qty, ...
                lb(i), commafy(usd(i)), parts(i).conf);
    end
    fprintf('%s\n', repmat('-',1,62));
    fprintf('%-26s %4s %8.1f %10s\n','PER NODE','', nodeLb, commafy(nodeUsd));
    fprintf('battery is %.0f%% of node weight\n', 100*battFrac);
    if nNodes > 1
        fprintf('\n%d-node network:  %.0f lb   $%s\n', ...
                nNodes, nodeLb*nNodes, commafy(nodeUsd*nNodes));
    end
    clear B
end
end

% ------------------------------------------------------------------------
function p = default_parts()
% CN0566-class lab-reference node, prices/weights as of Sep 2026.
% conf: 'confirmed' (distributor/datasheet), 'list', 'quote', 'est'.
p = mk('CN0566 phaser + Pluto','radar', 1, 0.50, 3000, 'confirmed');
p(end+1) = mk('TX illuminator (10.25GHz)','radar', 1, 0.20, 175, 'est');
p(end+1) = mk('Jetson Orin Nano','compute', 1, 0.50, 250, 'list');
p(end+1) = mk('Mesh Rider Mini (900MHz)','comms', 1, 0.08, 1750, 'quote');
p(end+1) = mk('900MHz omni antenna','comms', 2, 0.25, 50, 'est');
p(end+1) = mk('Bioenno 24V 40Ah LiFePO4','power', 1, 20.90, 580, 'confirmed');
p(end+1) = mk('enclosure / mast / cabling','struct', 1, 4.00, 300, 'est');
end

function s = mk(name, cat, qty, lb, usd, conf)
s = struct('name',name,'cat',cat,'qty',qty,'lb',lb,'usd',usd,'conf',conf);
end

function s = commafy(x)
% integer dollars with thousands separators
s = sprintf('%.0f', x);
for k = numel(s)-3:-3:1
    s = [s(1:k) ',' s(k+1:end)];
end
end
