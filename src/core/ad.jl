doc"""
    gradient(vi::VarInfo, model::Function, spl::Union{Void, Sampler})

Function to generate the gradient dictionary, with each prior map to its derivative of the logjoint probibilioty. This function uses chunk-wise forward AD with a chunk of size $(CHUNKSIZE) as default.

Example:

```julia
grad = gradient(vi, model, spl)
end
```
"""
gradient(_vi::VarInfo, model::Function) = gradient(_vi, model, nothing)
gradient(_vi::VarInfo, model::Function, spl::Union{Void, Sampler}) = begin
  # Initialisation
  vi = deepcopy(_vi); grad = Dict{Tuple, Vector{Float64}}()

  # Split keys(vi) into chunks,
  dprintln(4, "making chunks...")
  prior_key_chunks = []; key_chunk = []; prior_dim = 0

  gkeys = keys(vi)
  if spl != nothing && !isempty(spl.alg.space)
    gkeys = filter(k -> getgid(vi, k) == spl.alg.group_id || (getgid(vi, k) == 0 && getsym(vi, k) in spl.alg.space), keys(vi))
  end

  for k in gkeys
    l = length(vi[k])         # dimension for the current variable
    if prior_dim + l > CHUNKSIZE
      push!(prior_key_chunks, # store the previous chunk
            (key_chunk, prior_dim))
      key_chunk = []          # initialise a new chunk
      prior_dim = 0           # reset dimension counter
    end
    push!(key_chunk, k)       # put the current variable into the current chunk
    prior_dim += l            # update dimension counter
  end
  push!(prior_key_chunks,     # push the last chunk
        (key_chunk, prior_dim))

  # Chunk-wise forward AD
  for (key_chunk, prior_dim) in prior_key_chunks
    # Set dual part correspondingly
    dprintln(4, "set dual...")
    dps = zeros(prior_dim)
    prior_count = 1
    for k in gkeys

      duplicate!(vi)    # NOTE: we don't have to call keeplast! in the end
                        #       because we don't return the amended VarInfo

      l = length(vi[k])
      reals = realpart(vi[k])
      range = getrange(vi, k)
      if k in key_chunk         # for each variable to compute gradient in this round
        dprintln(5, "making dual...")
        for i = 1:l
          dps[prior_count] = 1  # set dual part
          vi[range[i]] = Dual(reals[i], dps...)
          dps[prior_count] = 0  # reset dual part
          prior_count += 1      # count
        end
        dprintln(5, "make dual done")
      else                      # for other varilables (no gradient in this round)
        for i = 1:l
          vi[range[i]] = (reals[i])
        end
      end
    end
    vi = runmodel(model, vi, spl, Dual{prior_dim, Float64}(0))
    # Collect gradient
    dprintln(4, "collect gradients from logp...")
    prior_count = 1
    for k in key_chunk
      l = length(vi[k])
      duals = dualpart(-vi.logp)
      g = zeros(l)  # init a container to store the gradient vector
      for i = 1:l
        g[i] = duals[prior_count] # collect current dim
        prior_count += 1          # dim counter
      end
      grad[k] = g
    end
  end

  grad
end

verifygrad(grad::Dict) = begin
  valid = true
  for k in keys(grad)
    if any(isnan(grad[k])) || any(isinf(grad[k]))
      dwarn(0, "NaN/Inf gradients")
      dwarn(1, "grad = $(grad)")
      valid = false
    end
  end
  valid
end
