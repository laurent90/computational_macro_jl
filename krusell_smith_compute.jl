#=
Program Name: krusell_smith_compute.jl
Runs Krusell-Smith model
=#

using PyPlot
using Interpolations
using GLM

include("krusell_smith_model.jl")

# initialize model primitives

const prim = Primitives()

function k_s_compute(prim::Primitives,operator::Function)

  ## Start in the good state and simulate sequence of T aggregate shocks

  agg_shock_index = zeros(Int64,prim.T)
  agg_shock_vals = zeros(Float64,prim.T)

  agg_shock_index[1] = 1
  agg_shock_vals[1] = prim.z[1]
  for t in 2:prim.T
    if rand() <= prim.transmatagg[agg_shock_index[t-1],1]
      agg_shock_index[t] = 1
      agg_shock_vals[t] = prim.z[1]
    else
      agg_shock_index[t] = 2
      agg_shock_vals[t] = prim.z[2]
    end
  end

  # initialize matrix to store shocks

  idio_shock_vals = zeros(Float64,prim.N,prim.T)

  ## Start all agents employed and simulate sequence of T idiosyncratic shocks

  for i in 1:prim.N
    idio_shock_vals[i,1] = prim.epsilon[1]
  end

  #= calculate sequence of idiosyncratic shocks based on previous
  period aggreate and idiosyncratic shocks =#

  for t in 2:prim.T
    for i in 1:prim.N
      # calculate probability of being employed at time t
      if agg_shock_index[t-1] == 1 # last period good aggregate shock
        if idio_shock_vals[i,t-1] == 1.0 # last period employed
          prob_emp = prim.transmat[1,1]+prim.transmat[1,2]
        else # last period unemployed
          prob_emp = prim.transmat[3,1]+prim.transmat[3,2]
        end
      else  # last period bad aggregate shock
        if idio_shock_vals[i,t-1] == 1.0 # last period employed
          prob_emp = prim.transmat[2,1]+prim.transmat[2,2]
        else # last period unemployed
          prob_emp = prim.transmat[4,1]+prim.transmat[4,2]
        end
      end

      # draw shocks for time t
      if rand() <= prob_emp
        idio_shock_vals[i,t] = prim.epsilon[1]
      else
        idio_shock_vals[i,t] = prim.epsilon[2]
      end
    end
  end

  ## Start all agents with steady state capital holdings from complete mkt economy

  # initialize matrix to store capital holdings

  # policy indices
  k_holdings_index = zeros(Float64,prim.N,prim.T)

  # values
  k_holdings_vals = zeros(Float64,prim.N,prim.T)

  # initialize array to hold average capital holdings (values)

  k_avg = zeros(Float64,prim.T)

  # define K value-to-index function
  val_to_index_K(K_index,target)=abs(prim.itp_K[K_index]-target)

  # find index of steady state capital in complete markets economy (K_ss)
  target = prim.K_ss
  K_ss_index = optimize(K_index->val_to_index_K(K_index,target),1.0,prim.K_size).minimum

  # endow each agent with K_ss

  for i in 1:prim.N
    k_holdings_vals[i,1] = prim.K_ss
    k_holdings_index[i,1] = K_ss_index
  end

  k_avg[1] = (1/prim.N)*sum(k_holdings_vals[:,1])

  ## Calculate decision rules using chosen bellman Operator

  # store decision rules in results object

  res = DecisionRules(operator,prim)

  ## Using decision rules, populate matrices

  # interpolate policy functions

  # policy index

  itp_sigmag0 = interpolate(res.sigmag0,BSpline(Cubic(Line())),OnGrid())
  itp_sigmab0 = interpolate(res.sigmab0,BSpline(Cubic(Line())),OnGrid())
  itp_sigmag1 = interpolate(res.sigmag1,BSpline(Cubic(Line())),OnGrid())
  itp_sigmab1 = interpolate(res.sigmab1,BSpline(Cubic(Line())),OnGrid())

  # values

  itp_sigmag0vals = interpolate(res.sigmag0vals,BSpline(Cubic(Line())),OnGrid())
  itp_sigmab0vals = interpolate(res.sigmab0vals,BSpline(Cubic(Line())),OnGrid())
  itp_sigmag1vals = interpolate(res.sigmag1vals,BSpline(Cubic(Line())),OnGrid())
  itp_sigmab1vals = interpolate(res.sigmab1vals,BSpline(Cubic(Line())),OnGrid())

  tic()
  for t in 1:prim.T-1
    println("t: ", t)
    # find index of avg capital time t
    targetK = k_avg[t]
    k_avg_index = optimize(k_avg_index->val_to_index_K(k_avg_index,targetK),1.0,prim.K_size).minimum
    for i in 1:prim.N
      if agg_shock_index[t] == 1 # good aggregate shock
        if idio_shock_vals[i,t] == 1.0 # employed
          k_holdings_index[i,t+1] = itp_sigmag1[k_holdings_index[i,t],k_avg_index]
          k_holdings_vals[i,t+1] = prim.itp_k[k_holdings_index[i,t+1]]
        else # unemployed
          k_holdings_index[i,t+1] = itp_sigmag0[k_holdings_index[i,t],k_avg_index]
          k_holdings_vals[i,t+1] = prim.itp_k[k_holdings_index[i,t+1]]
        end
      else  # bad aggregate shock
        if idio_shock_vals[i,t] == 1.0 # employed
          k_holdings_index[i,t+1] = itp_sigmab1[k_holdings_index[i,t],k_avg_index]
          k_holdings_vals[i,t+1] = prim.itp_k[k_holdings_index[i,t+1]]
        else # unemployed
          k_holdings_index[i,t+1] = itp_sigmab0[k_holdings_index[i,t],k_avg_index]
          k_holdings_vals[i,t+1] = prim.itp_k[k_holdings_index[i,t+1]]
        end
      end
    end
    k_avg[t+1] = (1/prim.N)*sum(k_holdings_vals[:,t+1])
  end
  toc()

  # drop first 1000 observations

  k_avg_trim = k_avg[1001:prim.T]
  agg_shock_index_trim = agg_shock_index[1001:prim.T]

  ## Regress log K' on log K to estimate forecasting coefficients

  # count number of good and bad periods (ignore last period)

  g_period_count = 0
  b_period_count = 0
  for t in 1:length(agg_shock_index_trim)-1
    if agg_shock_index_trim[t] == 1
      g_period_count += 1
    else
      b_period_count += 1
    end
  end

  # split (avg k,avg k') into two datasets: good and bad periods

  k_avg_g = zeros(Float64,g_period_count,2)
  k_avg_b = zeros(Float64,b_period_count,2)

  # populate (avg k,avg k') in each datasets

  g_index = 1
  b_index = 1
  for t in 1:length(agg_shock_index_trim)-1
    if agg_shock_index_trim[t] == 1
      k_avg_g[g_index,1] = k_avg_trim[t]
      k_avg_g[g_index,2] = k_avg_trim[t+1]
      g_index += 1
    else
      k_avg_b[b_index,1] = k_avg_trim[t]
      k_avg_b[b_index,2] = k_avg_trim[t+1]
      b_index += 1
    end
  end

  # regress log(avg k) on log(avg k')

  k_avg_g_log = log(k_avg_g)
  k_avg_b_log = log(k_avg_b)



end