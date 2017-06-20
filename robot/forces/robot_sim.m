%--------------------------------------------------------------------------
% NOTE: This example shows how to define a nonlinear programming problem,
% where all derivative information is automatically generated by
% using the AD tool CasADi.
% 
% You may want to directly pass C functions to FORCES, for example when you 
% are using other AD tools, or have custom C functions for derivate 
% evaluation etc. See the example file "NLPexample_ownFevals.m" for how to
% pass custom C functions to FORCES.
%--------------------------------------------------------------------------
%
% This example solves an optimization problem for a robotic manipulator
% with the following continuous-time, nonlinear dynamics
%
%    ddtheta1/dt    = FILL IN
%    ddtheta2/dt    = FILL IN
%    dtheta1/dt     = dtheta1
%    dtheta2/dt     = dtheta2
%    dtau1/dt       = dtau1
%    dtau2/dt       = dtau2
%
% where (theta1,theta2) are the angles describing the configuration of the 
% manipulator, (dtau1,dtau2) are input torque rates, and a and b are constants
% depending on geometric parameters.
%
% The robotic manipulator must track a reference for the angles and their
% velocities while minimizing the input torques.
%
% There are bounds on all variables.
%
% Variables are collected stage-wise into z = [dtau1 dtau2 theta1 dtheta1 theta2 dtheta2 tau1 tau2].
%
% See also FORCES_NLP
%
% (c) embotech GmbH, Zurich, Switzerland, 2013-16.

close all;
clear all; 
clc;

%% Problem dimensions
model.N     = 21;   % horizon length
model.nvar  = 8;    % number of variables
model.neq   = 6;    % number of equality constraints
model.nh    = 0;    % number of inequality constraint functions
model.npar  = 1;    % reference for state 1

nx = 6;
nu = 2;
Tf = 2;

Tsim = 20;
Ns = Tsim/(Tf/(model.N-1));   % simulation length?

GENERATE = 0;
timing_iter = 1;
%% Objective function

% Periodic reference
% x_ref = repmat(ref',1,Ns);     
u_ref = repmat([0 0]',1,Ns);

% model.objective = @(z,p) 1000*(z(3)-p(1)*1.2)^2 + 1000*z(4)^2 + 1000*(z(5)+p(1)*1.2)^2 + 1000*z(6)^2 + 0.001*z(7)^2 + 0.001*z(8)^2 + ...
%                             0.001*z(1)^2 + 0.001*z(2)^2;


Q = diag([1000 0.1 1000 0.1 0.01 0.01]);
R = diag([0.01 0.01]);
model.objective = @(z,p) 1000*(z(3)-p(1)*1.2)^2 + 0.1*z(4)^2 + 1000*(z(5)+p(1)*1.2)^2 + 0.10*z(6)^2 + 0.01*z(7)^2 + 0.01*z(8)^2 + ...
                            0.01*z(1)^2 + 0.01*z(2)^2;
%% Dynamics, i.e. equality constraints 

% We use an explicit RK4 integrator here to discretize continuous dynamics
integrator_stepsize = Tf/(model.N-1);
continuous_dynamics = @(x,u) dynamics(x,u);
model.eq = @(z) RK4( z(3:8), z(1:2), continuous_dynamics, integrator_stepsize, [], 1 );

% Indices on LHS of dynamical constraint - for efficiency reasons, make
% sure the matrix E has structure [0 I] where I is the identity matrix.
model.E = [zeros(6,2), eye(6)];

%% Inequality constraints
% upper/lower variable bounds lb <= x <= ub
%               inputs      |                states
%            dtau1  dtau2    theta1 dtheta1 theta2 dtheta2 tau1   tau2
% model.lb = [ -200,  -200,     -100,  -100,  -100,  -100,   -100,   -100  ];
% model.ub = [  200,   200,      100,   100,   100,   100,    70,    70  ];

model.lb = [ -200,  -200,     -pi,  -100,  -pi,  -100,   -100,   -100  ];
model.ub = [  200,   200,      pi,   100,   pi,   100,    70,    70  ];

%% Initial and final conditions
model.xinit = [-0.4 0 0.4 0 0 0 ]';
model.xinitidx = 3:8;


%% Define solver options
codeoptions = getOptions('FORCESNLPsolver');
codeoptions.maxit = 200;    % Maximum number of iterations
codeoptions.printlevel = 0; % Use printlevel = 2 to print progress (but not for timings)
codeoptions.optlevel = 2;   % 0: no optimization, 1: optimize for size, 2: optimize for speed, 3: optimize for size & speed
codeoptions.server = 'https://forces.embotech.com';

%% Generate forces solver
if GENERATE
    FORCES_NLP(model, codeoptions);
end
%% Call solver
% Set initial guess to start solver from:
x0i=model.lb+(model.ub-model.lb)/2;
x0=repmat(x0i',model.N,1);
problem.x0=x0; 

X = zeros(nx,Ns-model.N+1); X(:,1) = model.xinit;
U = zeros(nu,Ns-model.N);
ITER = zeros(1,Ns-model.N);
SOLVETIME = zeros(1,Ns-model.N);
FEVALSTIME = zeros(1,Ns-model.N);
% Set reference
problem.all_parameters = ones(model.N,1);

% Cost
cost = zeros(Ns,1);
ode45_intermediate_steps = 10;
cost_integration_grid = linspace(0,integrator_stepsize,ode45_intermediate_steps);
cost_integration_step_size = integrator_stepsize/ode45_intermediate_steps;

for i=1:Ns/2
    i

    % Set initial condition
    problem.xinit = X(:,i);
    
    % Time to solve the NLP!
    temp_time = Inf;
    temp_time_fevals = Inf;
    for j = 1:timing_iter
        [output,exitflag,info] = FORCESNLPsolver(problem);
        if  info.solvetime < temp_time
            temp_time =  info.solvetime;
        end
        if  info.fevalstime < temp_time_fevals
            temp_time_fevals =  info.fevalstime;
        end
    end
    assert(exitflag == 1,'Some problem in FORCES solver');
    U(:,i) = output.x01(1:nu);
    ITER(i) = info.it;
    SOLVETIME(i) = temp_time;
    FEVALSTIME(i) = temp_time_fevals;
    
    % Simulate dynamics
    [~,xtemp] = ode45( @(time, states) dynamics(states,U(:,i)), cost_integration_grid, X(:,i) );
    
    % Compute cost
    for j = 1:length(xtemp)
        cost(i) = cost(i) + cost_integration_step_size*(xtemp(j,:)*Q*xtemp(j,:)' + U(:,i)'*R*U(:,i));
    end
    
    X(:,i+1) = xtemp(end,:);
end 

% Set reference
problem.all_parameters = -ones(model.N,1);
for i=Ns/2+1:Ns
    i

    % Set initial condition
    problem.xinit = X(:,i);
    
        % Time to solve the NLP!
    temp_time = Inf;
    temp_time_fevals = Inf;
    for j = 1:timing_iter
        [output,exitflag,info] = FORCESNLPsolver(problem);
        if  info.solvetime < temp_time
            temp_time =  info.solvetime;
        end
        if  info.fevalstime < temp_time_fevals
            temp_time_fevals =  info.fevalstime;
        end
    end
    assert(exitflag == 1,'Some problem in FORCES solver');
    U(:,i) = output.x01(1:nu);
    ITER(i) = info.it;
    SOLVETIME(i) = temp_time;
    FEVALSTIME(i) = temp_time_fevals;
    
    % Simulate dynamics
    [~,xtemp] = ode45( @(time, states) dynamics(states,U(:,i)), cost_integration_grid , X(:,i) );
        % Compute cost
    % Compute cost
    for j = 1:length(xtemp)
        cost(i) = cost(i) + cost_integration_step_size*(xtemp(j,:)*Q*xtemp(j,:)' + U(:,i)'*R*U(:,i));
    end
    X(:,i+1) = xtemp(end,:);
end 
    
%% Plot results
h1=figure();
subplot(4,1,1); grid on; hold on;
plot([0:Ns-1]*integrator_stepsize,X(1,1:end-1)');
plot([0:Ns-1]*integrator_stepsize,X(3,1:end-1)');
ylabel('joint angles [rad]');
% xlabel('time [s]')
ylim([-1.5 1.5])
grid on

subplot(4,1,2); grid on;  hold on;
plot([0:Ns-1]*integrator_stepsize,X(5:6,1:end-1)');
plot([0 Ns-1]*integrator_stepsize, [70 70], 'r--');
% xlabel('time [s]')
ylabel('torques [Nm]')
ylim([-20 80])
grid on

subplot(4,1,3);  grid on; hold on;
plot([0 Ns-1]*integrator_stepsize, [-200 -200]', 'r--'); 
plot([0 Ns-1]*integrator_stepsize, [200 200]', 'r--');
stairs([0:Ns-1]*integrator_stepsize,U(1,:)');
ylabel('\tau_{1r}')
ylim(1.1*[min(-200),max(200)]);
% xlabel('time [s]')

grid on

subplot(4,1,4);  grid on; hold on;
plot([0 Ns-1]*integrator_stepsize, [-200 -200]', 'r--'); plot([0 Ns-1]*integrator_stepsize, [200 200]', 'r--');
ylim(1.1*[min(-200),max(200)]); stairs([0:Ns-1]*integrator_stepsize,U(2,:)');
xlabel('time [s]')
ylabel('\tau_{2r}')
grid on

% savefig(h1,'../plots/robot_forces_sim.fig')

h2= figure(); 
subplot(2,1,1); grid on; hold on;
plot([0:Ns-1]*integrator_stepsize,ITER);
xlabel('time [s]')
ylabel('iterations [s]')
grid on

subplot(2,1,2); grid on; hold on;
semilogy([0:Ns-1]*integrator_stepsize,SOLVETIME,[0:Ns-1]*integrator_stepsize,FEVALSTIME);
xlabel('time [s]')
ylabel('CPU time [s]')
% ylim([0.004,0.06]);
grid on
% savefig(h2,'../plots/robot_forces_stat.fig')

% Compute and plot closed loop cost
h3= figure();
% cost = zeros(Ns,1);
% Q = diag([1000 1000 1000 1000 0.001 0.001]);
% R = diag([0.001 0.001]);
% cost(1,1) = X(:,1)'*Q*X(:,1) + U(:,1)'*R*U(:,1);
% for i=2:Ns
%     cost(i,1) = cost(i-1) + X(:,i)'*Q*X(:,i) + U(:,i)'*R*U(:,i);
% end
grid on;
plot([0:Ns-1]*integrator_stepsize,cost);
xlabel('time [s]')
ylabel('cost')


sum(cost)
% savefig(h3,'../plots/robot_forces_cost.fig')