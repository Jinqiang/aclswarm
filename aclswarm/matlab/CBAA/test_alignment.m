%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Alignment and Assignment Inspection
%
% Loads a binary file generated by the C++ implementation for viewing and
% comparison with the MATLAB implementation.
%
% Parker Lusk
% 1 Dec 2019
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Using logged data
vehid = 1;
vehid = vehid + 1; % matlab 1-based indexing
assignment = 2;

% Load data from C++ implementation
fname = ['~/.ros/veh' num2str(vehid-1) '_assignment' num2str(assignment) '.bin'];
[n,q,adjmat,sigma1,p,aligned,sigma2] = read_alignment(fname);
c = struct();
c.sigma = sigma1;
c.aligned = aligned;
c.sigma2 = sigma2

% Load data from MATLAB implementation
Q1 = rowrep(sigma1);
[sigma2inc, aligned_ps] = CBAA_aclswarm(adjmat, p(:,1:2)', (Q1*q(:,1:2))');
% sigma2inc is an incremental permutation from Q1*q to p. Since we want the
% permutation from q to p, we need to compose the permutation matrices.
sigma2 = rowperm(rowrep(sigma2inc)*Q1);
pa = [aligned_ps{vehid}; zeros(1,n)]';
m = struct();
m.sigma = sigma1;
m.aligned = pa;
m.sigma2 = sigma2

% MATLAB Arun implementation of C++
pa = align(vehid, adjmat, q, p, sigma1);

figure(1), clf;
subplot(3,3,[1 2 3 4 5 6]); grid on; hold on;
plotPts(q, 'name','State','labels','alpha');
plotPts(c.aligned, 'name','C++ Aligned', 'labels','show', 'permvec',c.sigma2);
plotPts(m.aligned, 'name','MATLAB aligned', 'labels','show', 'permvec',m.sigma2);
% plotPts(pa, 'name','Arun aligned', 'labels','show', 'permvec',m.sigma2);
axissq([q;c.aligned;m.aligned], 2);
axis square;
xlabel('X'); ylabel('Y'); zlabel('Z');
view(0,90);
% view(-20,30);

%%%%%%%% Original desired formation (no assignment)
subplot(3,3,7); grid on; hold on; axis square; title('From Operator');
plotPts(p);
axissq(p, 2);

%%%%%%%% Desired formation (after assignment)
subplot(3,3,8); grid on; hold on; title('C++ Assigned');
plotPts(c.aligned, 'permvec', c.sigma2);
axissq(c.aligned, 2);

%%%%%%%% Desired formation (after assignment)
subplot(3,3,9); grid on; hold on; axis square; title('MATLAB Assigned');
plotPts(m.aligned, 'permvec', m.sigma2);
axissq(m.aligned, 2);
%% Select neighbors
% use only local information for alignment

function [qnbrs, pnbrs] = nbrsof(vehid, adjmat, q, p, sigma)
% add myself
adjmat = adjmat + eye(size(adjmat));

% work in "formation space" --- which formation pt am i?
i = sigma(vehid);

% figure out who my neighbors are
mynbrs = adjmat(i,:);

% index of each formation pt that is my nbr
jvec = mynbrs.*(1:size(adjmat,1));
jvec(jvec==0) = [];

% create inverse perm vec: formpt to vehid
jinv(sigma) = 1:length(sigma);

% map from formpt to vehidx
nbrvec = jinv(jvec);

pnbrs = p(jvec,:);
qnbrs = q(nbrvec,:);
end

%% Formation Alignment

function aligned = align(vehid, adjmat, q, p, sigma)

[qnbrs, pnbrs] = nbrsof(vehid, adjmat, q, p, sigma);

% ASSUME: q, p are nxd but need to be dxn
qq = qnbrs';
pp = pnbrs';

use2D = false;

[~,sQ,~] = svd(qq' - mean(qq'));
[~,sP,~] = svd(pp' - mean(pp'));
sQ = diag(sQ);
sP = diag(sP);
rQ = sum(sQ>0.05*sQ(1));
rP = sum(sP>0.05*sP(1));

if rQ==1
    disp('Line Swarm');
    use2D = true;
elseif rQ==2
    disp('Flat Swarm');
    use2D = true;
elseif rQ==3
    disp('3D Swarm');
end

if rP==1
    disp('Line Formation');
    use2D = true;
elseif rP==2
    disp('Flat Formation');
    use2D = true;
elseif rP==3
    disp('3D Formation');
end

if use2D
    disp('Using 2D Arun');
    qq = qq(1:2,:);
    pp = pp(1:2,:);
end

[R, t] = arun(qq, pp);

if size(R,1) == 2
    R(3,3) = 1;
    t(3) = 0;
end

aligned = (R*p' + t)';
end

%% Arun's Method
% Minimizes ||q - (Rp + t)||^2
function [R, t] = arun(q, p)

% ASSUME: q, p are dxn (d: 2D or 3D)
d = size(q,1);

% shift point clouds by centroids
mu_q = mean(q,2); % (rowwise)
mu_p = mean(p,2); % (rowwise)
Q = q - mu_q;
P = p - mu_p;

% construct H matrix (dxd)
H = Q * P';

% perform SVD of H
[U,~,V] = svd(H);
D = eye(size(H));
D(d,d) = det(U*V');

% solve rotation-only problem
R = U*D*V';

% solve translation
t = mu_q - R*mu_p;
end

%% Permutation matrix helpers

function Q = rowrep(sigma)
% row representation of permutation matrix.
% see https://en.wikipedia.org/wiki/Permutation_matrix
Q = zeros(length(sigma));
for j = 1:length(sigma)
    Q(sigma(j),j) = 1;
end
end

function P = colrep(sigma)
% col representation of permutation matrix.
% see https://en.wikipedia.org/wiki/Permutation_matrix
P = zeros(length(sigma));
for i = 1:length(sigma)
    P(i,sigma(i)) = 1;
end
end

function perm = rowperm(Q)
% boil the permutation matrix down to a permutation vector
perm = ( Q'*(1:size(Q,1))' )';
end

function perm = colperm(P)
perm = rowperm(P');
end

function isigma = invperm(sigma)
% invert a permutation vector
isigma(sigma) = 1:length(sigma);
end

%% Plotting helpers

function plotPts(p, varargin)
% assume: p is Nx3

ip = inputParser;
ip.addParameter('name','');
ip.addParameter('permvec',[]);
ip.addParameter('labels','show');
ip.parse(varargin{:});

% If a permutation matrix was provided, then relabel pts
if ~isempty(ip.Results.permvec)
    P = ip.Results.permvec;
    p = p(P,:);
end

h = scatter3(p(:,1),p(:,2),p(:,3),400,'filled');

if ~isempty(ip.Results.name)
   set(h,'DisplayName',ip.Results.name);
   legend;
end

if strcmp(ip.Results.labels, 'show') || strcmp(ip.Results.labels, 'alpha')
    % magic number
    magic = 0.1; % make text appear in center of scatter point

    k=1:size(p,1);
    lbl = num2str(k');

    % convert to alphabet if desired and possible
    if strcmp(ip.Results.labels, 'alpha') && size(p,1)<=26
        str = char(k + 65 - 1);
        lbl = cellstr(str(:));
    end

    % label each point
    text(p(:,1)-magic,p(:,2),p(:,3),lbl,...
        'Color','black','FontWeight','bold');
end
end

function axissq(x, m)
axis square;
axis([min(x(:,1))-m max(x(:,1))+m min(x(:,2))-m max(x(:,2))+m -3 3]);

ax = axis;
cx = (ax(1)+ax(2))/2;
cy = (ax(3)+ax(4))/2;
dx = ax(2)-ax(1);
dy = ax(4)-ax(3);

if dx > dy
    axis([ax(1) ax(2) cy-dx/2 cy+dx/2 -3 3]);
else
    axis([cx-dy/2 cx+dy/2 ax(3) ax(4) -3 3]);
end

end