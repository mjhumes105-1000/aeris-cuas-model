function S = aeris_discriminate(N)
% AERIS_DISCRIMINATE  Can the radar tell drones, birds and planes apart?
%
%   aeris_discriminate            % 200 samples per class
%   aeris_discriminate(600)
%
% Generates many targets of each class (aeris.target_classes), forms each one's
% slow-time return with its micro-Doppler (aeris.target_signature) plus noise,
% extracts the features a real classifier would use, and plots the class
% separation - INCLUDING the region where drone and bird genuinely overlap.
%
% Features:
%   RCS (log)             - separates planes cleanly (huge vs tiny)
%   micro-Doppler spread  - separates drones (broad rotor smear) from birds
%                           (narrow wingbeat); THE hard-case discriminator
%   body speed            - secondary
%
% Honest takeaway: planes are trivial; drone-vs-bird works on micro-Doppler but
% has a confusion zone (slow/hovering drones vs fast-flapping birds).

if nargin < 1 || isempty(N), N = 200; end

p = aeris_params(); g = aeris.derive(p);
M = p.cpi; PRI = 1/p.prf; lambda = g.lambda; vUn = g.vUnamb;
C = aeris.target_classes();
nc = numel(C);

rcs = cell(1,nc); spd = cell(1,nc); spread = cell(1,nc);
for c = 1:nc
    rc = zeros(1,N); sp = zeros(1,N); sd = zeros(1,N);
    for i = 1:N
        rc(i) = exp(unif(log(C(c).rcs)));
        sp(i) = unif(C(c).spd);
        vr = -sp(i);                                   % inbound
        mod = aeris.target_signature(C(c), M, PRI, lambda);
        body = exp(1j*2*pi*(2*vr/lambda)*(0:M-1)*PRI);
        % SNR scales with RCS; noise floor fixed
        amp = sqrt(max(rc(i)/0.03, 0.05));             % relative to a 0.03 m^2 ref
        sig = amp*(body .* mod) + (randn(1,M)+1j*randn(1,M))/sqrt(2)*0.3;
        sd(i) = doppler_spread(sig, vUn);              % m/s
    end
    rcs{c}=rc; spd{c}=sp; spread{c}=sd;
end

% ---- simple decision + confusion (drone vs bird by spread) --------------
allSpread = [spread{:}]; thrDB = prctile([spread{1} spread{2}], 50);
% classify: plane if RCS>0.3; else drone if spread>thr else bird
correct = 0; tot = 0; conf = zeros(3);
lbl = @(rc,sd) 1*(rc<=0.3 & sd>thrDB) + 2*(rc<=0.3 & sd<=thrDB) + 3*(rc>0.3);
for c=1:nc
    for i=1:N
        pred = lbl(rcs{c}(i), spread{c}(i));
        conf(c,pred)=conf(c,pred)+1; tot=tot+1; correct=correct+(pred==c);
    end
end
fprintf('\n--- 3-way discrimination (spread threshold %.1f m/s) ---\n', thrDB);
fprintf('overall accuracy: %.1f%%\n', 100*correct/tot);
fprintf('confusion (rows=truth, cols=pred: drone bird plane):\n');
for c=1:nc, fprintf('  %-6s %5d %5d %5d\n', C(c).name, conf(c,1),conf(c,2),conf(c,3)); end
dbConf = 100*(conf(1,2)+conf(2,1))/(2*N);
fprintf('drone<->bird confusion: %.1f%%  (the hard pair)\n', dbConf);

% ---- figure ------------------------------------------------------------
figure('Color','w','Position',[80 80 1150 480]);
subplot(1,2,1); hold on; grid on;
for c=1:nc, scatter(rcs{c}, spread{c}, 18, C(c).color,'filled','MarkerFaceAlpha',.5); end
set(gca,'XScale','log'); xline(0.3,'--','Color',[.4 .4 .4],'Label','plane RCS gate');
yline(thrDB,':','Color',[.4 .4 .4],'Label','drone/bird spread gate');
xlabel('RCS (m^2)'); ylabel('micro-Doppler spread (m/s)');
legend({C.name},'Location','northwest','Box','off');
title('feature space: RCS vs micro-Doppler spread','FontWeight','normal');

subplot(1,2,2); hold on; grid on;
for c=1:nc, scatter(spd{c}, spread{c}, 18, C(c).color,'filled','MarkerFaceAlpha',.5); end
xlabel('speed (m/s)'); ylabel('micro-Doppler spread (m/s)');
legend({C.name},'Location','northeast','Box','off');
title('speed vs spread (planes fast; drone smear >> bird)','FontWeight','normal');

S = struct('classes',{{C.name}},'rcs',{rcs},'spd',{spd},'spread',{spread}, ...
           'accuracy',correct/tot,'confusion',conf,'droneBirdConf',dbConf/100);
if nargout==0, clear S; end
end

% ------------------------------------------------------------------------
function sd = doppler_spread(sig, vUn)
% velocity bandwidth holding the central 90% of off-DC Doppler energy
M = numel(sig);
Sp = abs(fftshift(fft(sig .* (0.5-0.5*cos(2*pi*(0:M-1)/(M-1)))))).^2;
Sp = Sp / sum(Sp);
v  = linspace(-vUn, vUn, M);
% energy-weighted std of velocity = spread
mu = sum(v.*Sp); sd = sqrt(max(sum((v-mu).^2 .* Sp), 0));
end

function v = unif(r), v = r(1) + rand*(r(2)-r(1)); end
