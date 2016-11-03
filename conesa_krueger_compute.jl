#=
Program Name: conesa_krueger_compute.jl
Runs Conesa-Krueger model and performs policy experiments
=#

using PyPlot

include("conesa_krueger_model.jl")

#= Solve model for example years =#

# Initialize Primitives
prim = Primitives(a_size=1000,a_max=100.00)

#= Solve worker problem and return value functions and policy functions
for 50-year old and a 20-year old =#
tic()
res, v_20, v_50, policy_20, policy_50, labor_supply_20 =
  SolveProgram(prim,20,50)
toc()

#= General Equilibrium =#

function compute_GE(;a_size=100,theta=0.11,z_vals=[3.0, 0.5],exo_labor="no",
    epsilon=1e-3,max_iter=100,K0::Float64=2.0363,L0::Float64=0.3249)

  # Initialize primitives
  prim = Primitives(a_size=a_size,theta=theta)

  # Solve problem with default values
  results = SolveProgram(prim,exo_labor=exo_labor)

  # Initialize aggregate capital and labor with Initial guess of capital and labor

  K = K0
  L = L0

  # Calculate initial wages and rental rate
  prim.w = (1-prim.alpha)*K^(prim.alpha)*L^(-prim.alpha)
  prim.r = prim.alpha*K^(prim.alpha-1)*L^(1-prim.alpha) - prim.delta

  max_dist = 100.00

  for i in 1:max_iter

    # Print iteration, wage, rental rate
    println("Iter: ", i, " L: ", L," K: ", K, " Max Dist.: ", max_dist)

    # Calculate benefit
    mass_b = 0.00  # calculate mass receiving benefits
    for age in 1:prim.N-prim.JR+1
      mass_b += sum(results.ss_retired[:,age])
    end

    prim.b = (prim.theta*prim.w*L)/mass_b

    # Solve program given prices and benefit

    results = SolveProgram(prim,exo_labor=exo_labor)

    # Calculate new aggregate capital and labor

    K_new = 0.00
    for working_age in 1:prim.JR-1
      for asset in 1:prim.a_size
        K_new += results.ss_working_hi[asset,working_age]*
          prim.a_vals[results.policy_working_hi[asset,working_age]]
        K_new += results.ss_working_lo[asset,working_age]*
          prim.a_vals[results.policy_working_lo[asset,working_age]]
      end
    end
    for retired_age in 1:prim.N-prim.JR+1
      for asset in 1:prim.a_size
        if results.policy_retired[asset,retired_age] != 0
          K_new += results.ss_retired[asset,retired_age]*
            prim.a_vals[results.policy_retired[asset,retired_age]]
        end
      end
    end

    L_new = 0.00
    for working_age in 1:prim.JR-1
      for asset in 1:prim.a_size
        L_new += results.ss_working_hi[asset,working_age]*
          results.labor_supply_hi[asset,working_age]*prim.ageeff[working_age]
        L_new += results.ss_working_lo[asset,working_age]*
          results.labor_supply_lo[asset,working_age]*prim.ageeff[working_age]
      end
    end

    # Adjust K, L if fails tolerance
    max_dist = max(abs(K-K_new),abs(L-L_new))
    if max_dist < epsilon
        break
    else
      L_new = L*0.99 + L_new*0.01
      K_new = K*0.99 + K_new*0.01
    end

    # Calculate new prices
    w_new = (1-prim.alpha)*K_new^(prim.alpha)*L_new^(-prim.alpha)
    r_new = prim.alpha*K_new^(prim.alpha-1)*L_new^(1-prim.alpha) - prim.delta

    prim.w = w_new
    prim.r = r_new
    L = L_new
    K = K_new

  end

  K, L, prim.w, prim.r, prim.b, results.W, results.cv, results

end

#= Policy Experiments =#

## Baseline: idiosynractic risk and endogenous labor

# with social security
tic()
baseline = compute_GE(a_size=1000,max_iter=100,K0=2.03,L0=0.3)
toc()

# without social security
tic()
baseline_no_ss = compute_GE(a_size=1000,max_iter=100,theta=0.00,K0=2.098,L0=0.325)
toc()

## No idiosyncratic risk

# with social security
tic()
no_idio_risk = compute_GE(a_size=1000,max_iter=100,z_vals=[0.5,0.5])
toc()

# without social security
tic()
no_idio_risk_no_ss = compute_GE(a_size=1000,max_iter=100,z_vals=[0.5,0.5],theta=0.00)
toc()

## Exogenous Labor

# with social security
tic()
exo_labor = compute_GE(a_size=1000,max_iter=100,exo_labor="yes")
toc()

# without social security
tic()
exo_labor_no_ss = compute_GE(a_size=1000,max_iter=100,exo_labor="yes",theta=0.00)
toc()

#= Tables for Output to LaTeX =#

output = Array(Any,(7,6))
titles_vert = ["K","L","w","r","b","W","cv"]
titles_horz = ["Bench","Bench (No SS)", "No Risk", "No Risk (No SS)",
  "Exog. Labor", "Exog. Labor (No SS)"]
K_vals = [baseline[1] baseline_no_ss[1] no_idio_risk[1] no_idio_risk_no_ss[1]
  exo_labor[1] exo_labor_no_ss[1]]

#= Graphs =#

v50fig = figure()
plot(prim.a_vals,v_50,color="blue",linewidth=2.0)
xlabel("a")
ylabel("value")
legend(loc="lower right")
title("Value Function (Age 50)")
ax = PyPlot.gca()
savefig("C:/Users/j0el/Documents/Wisconsin/899/Problem Sets/PS5/Pictures/v50.pgf")

policy20fig = figure()
plot(prim.a_vals,prim.a_vals[policy_20[:,1]],color="blue",linewidth=2.0,label="High Productivity")
plot(prim.a_vals,prim.a_vals[policy_20[:,2]],color="red",linewidth=2.0,linestyle="--",label="Low Productivity")
plot(prim.a_vals,prim.a_vals,color="yellow",linewidth=1.0,label="45 Degree")
xlabel("a")
ylabel("a'(a,z)")
legend(loc="lower right")
title("Policy Function (Age 20)")
ax = PyPlot.gca()
savefig("C:/Users/j0el/Documents/Wisconsin/899/Problem Sets/PS5/Pictures/policy20.pgf")