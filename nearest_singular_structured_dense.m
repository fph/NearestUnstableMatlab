function problem = nearest_singular_structured_dense(P, A, use_hessian)
% Create a Manopt problem structure for the nearest singular structured
% matrix.
% Uses a dense mxnxp array P as storage for the perturbation basis
% We assume (without checking) that this basis is orthogonal.

n = size(A, 2);
if isreal(A)
    problem.M = spherefactory(n);
else
    problem.M = spherecomplexfactory(n);
end

% populate the struct with generic functions that include the regularization as parameters
problem.gencost  = @(epsilon, y, v, store) cost(P, A, epsilon, y, v, store);
problem.genegrad = @(epsilon, y, v, store) egrad(P, A, epsilon, y, v, store);
if use_hessian
    problem.genehess = @(epsilon, y, v, w, store) ehess(P, A, epsilon, y, v, w, store);
end
problem.genminimizer = @(epsilon, y, v, store) minimizer(P, A, epsilon, y, v, store);

% compute the value of the constraint (A+E)v + epsilon*y.
% We need this for the extended Lagrangian update
% Note that this constraint is not zero when epsilon is nonzero
problem.genconstraint = @(epsilon, y, v, store) constraint(P, A, epsilon, y, v, store);

% populate functions from the Manopt interface with zero regularization
problem = apply_regularization(problem, 0, 0);

% additional function outside of the main interface to recover
% a more exact solution in the case of rank drops, enforcing exact
% zeros in U'*r
problem.recover_exact = @(v, tol) recover_exact(P, A, v, tol);

end

% create M(v)
function M = make_M(P, v)
    M = reshape(pagemtimes(P, v), [size(P,1) size(P,3)]);
end

% create Delta = \sum P(i)delta(i)
function Delta = make_Delta(P, delta)
    Delta = tensorprod(P, delta, 3, 1);
end

% fill values in the 'store', a caching structure used by Manopt
% with precomputed fields that we need in other functions as well
function store = populate_store(P, A, epsilon, y, v, store)
    if ~isfield(store, 'r')
        M = make_M(P, v);
        [W, S, U] = svd(M', 0); %this form ensures U is always square
        Av = A * v;
        store.M = M;
        store.U = U;
        store.WS = W .* diag(S)';
        store.Av = Av;
        Utr = -U' * (Av + epsilon * y);
        store.Utr = Utr;
        s = diag(S);
        store.s = s;
        s(end+1:length(U)) = 0;
        d = 1 ./ (s.^2 + epsilon);
        store.d = d;
        aux = d .* Utr;
        aux(isnan(aux)) = 0;
        store.aux = aux;
    end
end

function [cf, store] = cost(P, A, epsilon, y, v, store)
    store = populate_store(P, A, epsilon, y, v, store);
    d = store.d;
    Utr = store.Utr;
    cf = sum(conj(Utr) .* Utr .* d, 'omitnan'); % in this order we preserve realness, so we don't use aux
end

function [eg, store] = egrad(P, A, epsilon, y, v, store)
    store = populate_store(P, A, epsilon, y, v, store);
    aux = store.aux;
    z = store.U * aux;
    WS = store.WS;
    delta =  WS * aux(1:size(WS,2));
    Delta = make_Delta(P, delta);
    eg = (A+Delta)' * z * (-2);
end

function [Delta, store] = minimizer(P, A, epsilon, y, v, store)
    store = populate_store(P, A, epsilon, y, v, store);
    aux = store.aux;
    WS = store.WS;
    delta =  WS * aux(1:size(WS,2));
    Delta = make_Delta(P, delta);
end

function [ehw, store] = ehess(P, A, epsilon, y, v, w, store)
    store = populate_store(P, A, epsilon, y, v, store);
    aux = store.aux;
    U = store.U;
    z = U * aux;
    WS = store.WS;
    delta =  WS * aux(1:size(WS,2));
    Delta = make_Delta(P, delta); % TODO: could cache more here
    dM = make_M(P, w);
    d = store.d;
    M = store.M;
    daux = -d .* (U' * (M*(dM'*z) + (A+Delta)*w)); % TODO: fix case of M tall-thin
    dz = U * daux;
    ddelta = dM' * z + M' * dz;
    dDelta = make_Delta(P, ddelta);
    ehw = (dDelta' * z + (A+Delta)' * dz) * (-2);
end

function [prod, store] = constraint(P, A, epsilon, y, v, store)
    [Delta, store] = minimizer(P, A, epsilon, y, v, store);
    prod = store.Av + Delta * v;
end

function v_reg = recover_exact(P, A, v, tol)
    TODO %: trickier since U is not constant anymore
    store = struct();
    store = populate_store(P, A, 0, 0, v, store);
    r = store.r;
    d = store.d;
    r_reg = r;
    r_reg(abs(d) > tol) = 0;
    v_reg = - A \ r_reg;
end