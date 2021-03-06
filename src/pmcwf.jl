"""
    pmcwf(tspan, psi0, H, J; Ntrajectories, <keyword arguments>)

Integrate parallely `Ntrajectories` MCWF trajectories.
Arguments are passed internally to `QuantumOptics.timeevolution.mcwf`.

# Arguments
* `tspan`: Vector specifying the points of time for which output should
be displayed.
* `psi0`: Initial state vector.
* `H`: Arbitrary Operator specifying the Hamiltonian.
* `J`: Vector containing all jump operators which can be of any arbitrary
operator type.
* `Ntrajectories=1`: Number of MCWF trajectories.
* `parallel_type=:none`: The type of parallelism to employ. The types of
parallelism included are: `:none`, `:threads`, `:split_threads`, `:parfor` and
`:pmap`.
* `progressbar=true`: If `true`, a progression bar is displayed.
* `return_data=true`: If `true`, the solution is returned as a `Tuple`.
* `save_data=true`: If `true`, the solution is saved to disk.
If `return_data=false`, less RAM is used (except for `parallel_type=:threads`).
* `fpath=missing`: savefile path (e.g. `some/valid/path/filename.jld2`).
Directory must pre-exist, the savefile is created.
* `additional_data=missing`: If given a `Dict`, entries are added to the
savefile.
* `seed=rand(UInt)`: seed for each trajectory's random number generator.
* `rates=ones()`: Vector of decay rates.
* `fout`: If given, this function `fout(t, psi)` is called every time an
output should be displayed. ATTENTION: The state `psi` is neither
normalized nor permanent! It is still in use by the ode solve
and therefore must not be changed.
* `Jdagger=dagger.(J)`: Vector containing the hermitian conjugates of the jump
operators. If they are not given they are calculated automatically.
* `display_beforeevent=false`: `fout` is called before every jump.
* `display_afterevent=false`: `fout` is called after every jump.
* `kwargs...`: Further arguments are passed on to the ode solver.

See also: [`timeevolution.mcwf`](@ref)

# Examples
```julia-repl
julia> tspan = collect(t0:dt:t_max);
julia> fb = FockBasis(10); ψ0 = fockstate(fb,0); a = destroy(fb);
julia> H = randoperator(fb); H = H + dagger(H); γ = 1.;
julia> # 100 MCWF trajectories
julia> t, trajs = pmcwf(tspan, ψ0, H, [sqrt(γ)*a];
                        Ntrajectories=100, parallel_type=:pmap);
```
"""
function pmcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, parallel_type::Symbol = :none,
        progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = false,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}
    @assert return_data || save_data "pmcwf outputs nothing"
    save_data && @assert !ismissing(fpath) "ERROR: savefile path is missing"
    save_data && @assert isdir(splitdir(fpath)[1]) "ERROR: accessing "*splitdir(fpath)[1]*": No such directory"
    save_data && @assert !isfile(fpath) "ERROR: "*fpath*" already a file: Choose a free savefile name"

    if parallel_type == :none || Ntrajectories == 1
        return serial_mcwf(tspan,psi0,H,J;Ntrajectories=Ntrajectories,
            progressbar=progressbar,
            return_data=return_data,save_data=save_data,
            fpath=fpath,additional_data=additional_data,
            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
            display_beforeevent=display_beforeevent,
            display_afterevent=display_afterevent,
            alg=alg,
            kwargs...);
    elseif parallel_type == :threads
        # TO DO: save_data-only not totally supported. Could use less RAM by
        # writting trajectories directly to disk but would probably require
        # some locking or some parallel process.
        return multithreaded_mcwf(tspan,psi0,H,J;Ntrajectories=Ntrajectories,
            progressbar=progressbar,
            return_data=return_data,save_data=save_data,
            fpath=fpath,additional_data=additional_data,
            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
            display_beforeevent=display_beforeevent,
            display_afterevent=display_afterevent,
            alg=alg,
            kwargs...);
    elseif parallel_type == :pmap
        # TO DO: add batch_size as an option
        return pmap_mcwf(tspan,psi0,H,J;Ntrajectories=Ntrajectories,
            progressbar=progressbar,
            return_data=return_data,save_data=save_data,
            fpath=fpath,additional_data=additional_data,
            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
            display_beforeevent=display_beforeevent,
            display_afterevent=display_afterevent,
            alg=alg,
            kwargs...);
    elseif parallel_type == :parfor
        return distributed_mcwf(tspan,psi0,H,J;Ntrajectories=Ntrajectories,
            progressbar=progressbar,
            return_data=return_data,save_data=save_data,
            fpath=fpath,additional_data=additional_data,
            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
            display_beforeevent=display_beforeevent,
            display_afterevent=display_afterevent,
            alg=alg,
            kwargs...);
    elseif parallel_type == :split_threads
        # TO DO: add batch_size as an option
        return split_threads_mcwf(tspan,psi0,H,J;Ntrajectories=Ntrajectories,
            progressbar=progressbar,
            return_data=return_data,save_data=save_data,
            fpath=fpath,additional_data=additional_data,
            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
            display_beforeevent=display_beforeevent,
            display_afterevent=display_afterevent,
            alg=alg,
            kwargs...);
    else
        valptypes = [:none, :threads, :pmap, :parfor, :split_threads];
        error("Invalid parallel type. Type :$parallel_type not available.\n"*
              "Available types are: "*reduce(*,[":$t " for t in valptypes]))
    end
end

function serial_mcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = false,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}
    if save_data
        file = jldopen(fpath, "a+");
        file["t"] = tspan;
        if !ismissing(additional_data)
            for (key, val) in additional_data
                file[key] = val;
            end
        end
    end
    if return_data
        # Pre-allocate an array for holding each MC simulation
        out_type = fout == nothing ? typeof(psi0) : pure_inference(fout, Tuple{eltype(tspan),typeof(psi0)});
        sols::Array{Vector{out_type},1} = fill(Vector{out_type}(),Ntrajectories);
    end
    if progressbar
        # A progress bar is set up to be updated by the master thread
        progress = Progress(Ntrajectories);
        ProgressMeter.update!(progress, 0);
    end
    for i in 1:Ntrajectories
        if isnothing(seed)
            sol = timeevolution.mcwf(tspan,psi0,H,J;
                rates=rates,fout=fout,Jdagger=Jdagger,
                display_beforeevent=display_beforeevent,
                display_afterevent=display_afterevent,
                alg=alg,kwargs...);
        else
            sol = timeevolution.mcwf(tspan,psi0,H,J;
                seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
                display_beforeevent=display_beforeevent,
                display_afterevent=display_afterevent,
                alg=alg,kwargs...);
        end
        save_data ? file["trajs/"*string(i)] = sol[2] : nothing;
        return_data ? sols[i] = sol[2] : nothing;
        progressbar ? ProgressMeter.next!(progress) : nothing;
    end
    save_data && close(file);
    return return_data ? (tspan, sols) : nothing;
end

function multithreaded_mcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = true,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}

    if progressbar
        # A progress bar is set up to be updated by the master thread
        progress = Progress(Ntrajectories);
        ProgressMeter.update!(progress, 0);
        function update_progressbar(n::Threads.Atomic{Int64})
            if Threads.threadid() == 1  # If first thread: update progress bar
                for i in 1:(n[]+1) ProgressMeter.next!(progress); end
                Threads.atomic_xchg!(n,0);
            else                    # Else: increment the number of pending updates.
                Threads.atomic_add!(n,1);
            end
        end
        nupdates = Threads.Atomic{Int}(0);
    end
    if save_data
        file = jldopen(fpath, "a+");
        file["t"] = tspan;
        if !ismissing(additional_data)
            for (key, val) in additional_data
                file[key] = val;
            end
        end
        return_data = true; # Some duct tape
    end
    if return_data
        # Pre-allocate an array for holding each MC simulation
        out_type = fout == nothing ? typeof(psi0) : pure_inference(fout, Tuple{eltype(tspan),typeof(psi0)});
        sols::Array{Vector{out_type},1} = [Vector{out_type}() for i in 1:Ntrajectories];
    end
    seed = isnothing(seed) ? [rand(UInt) for i in 1:Threads.nthreads()] : [seed for i in 1:Threads.nthreads()];
    # Multi-threaded for-loop over all MC trajectories.
    Threads.@threads for i in 1:Ntrajectories
        sol = timeevolution.mcwf(tspan,psi0,H,J;
                seed=seed[Threads.threadid()],rates=rates,fout=fout,Jdagger=Jdagger,
                display_beforeevent=display_beforeevent,
                display_afterevent=display_afterevent,
                alg=alg, kwargs...);
        #save_data ? file["trajs/"*string(i)] = sol[2] : nothing;
        return_data ? sols[i] = sol[2] : nothing;
        # Updates progress bar if called from the main thread or adds a pending update otherwise
        progressbar ? update_progressbar(nupdates) : nothing;
    end
    progressbar ? update_progressbar(nupdates) : nothing;
    # Sets the progress bar to 100%
    if progressbar && (progress.counter < Ntrajectories) ProgressMeter.update!(progress, Ntrajectories); end;

    # Some additional duct tape
    if save_data
        for i in 1:length(sols)
            file["trajs/"*string(i)] = sols[i];
        end
    end

    save_data && close(file);
    return return_data ? (tspan, sols) : nothing;
end;

function pmap_mcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = true,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}

    # Create a remote channel from where trajectories are read out by the saver
    remch = RemoteChannel(()->Channel{Any}(Inf)); # TO DO: add some finite buffer size

    wp = CachingPool(workers());

    # Create a task fetched by the first available worker that retrieves trajs
    # from the remote channel and writes them to disk. A progress bar is set up
    # as well.
    saver = @async launch_saver(remch; Ntrajectories=Ntrajectories,
        progressbar=progressbar, return_data=return_data, save_data=save_data,
        fpath=fpath, additional_data=additional_data);
        batches = nfolds(1:Ntrajectories,length(wp.workers))
    batches = nfolds(1:Ntrajectories,length(wp.workers))
    # Multi-processed map over all batches of MC trajectories. Maps jobs to
    # workers() from the local process. Jobs consist in computing a batch of
    # MC trajectories and pipe them to the remote channel remch.
    pmap(wp,1:length(wp.workers)) do i
        for j in 1:length(batches[i])
            put!(remch,begin
                if isnothing(seed)
                    timeevolution.mcwf(tspan,psi0,H,J;
                        rates=rates,fout=fout,Jdagger=Jdagger,
                        display_beforeevent=display_beforeevent,
                        display_afterevent=display_afterevent,
                        alg=alg, kwargs...);
                else
                    timeevolution.mcwf(tspan,psi0,H,J;
                        seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
                        display_beforeevent=display_beforeevent,
                        display_afterevent=display_afterevent,
                        alg=alg, kwargs...);
                end
            end);
        end
    end
    # Once saver has consumed all queued trajectories produced by all workers, an
    # array of MCWF trajs is returned.
    sols = fetch(saver);
    # Clear caching pool
    clear!(wp);

    if return_data
        out_type = fout == nothing ? typeof(psi0) : pure_inference(fout, Tuple{eltype(tspan),typeof(psi0)});
        return (tspan, convert(Array{Vector{out_type},1},sols));
    else
        nothing;
    end
end;

function distributed_mcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = true,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}

    # Create a remote channel from where trajectories are read out by the saver
    remch = RemoteChannel(()->Channel{Any}(Inf)); # TO DO: add some finite buffer size

    # Create a task fetched by the first available worker that retrieves trajs
    # from the remote channel and writes them to disk. A progress bar is set up
    # as well.
    saver = @async launch_saver(remch; Ntrajectories=Ntrajectories,
        progressbar=progressbar, return_data=return_data, save_data=save_data,
        fpath=fpath, additional_data=additional_data);
    # Multi-processed for-loop over all MC trajectories. @distributed feeds
    # workers() asynchronously with jobs from the local process and is fetched.
    # Jobs consist in computing a trajectory and pipe it to the remote channel remch.
    @sync @distributed for i in 1:Ntrajectories
        put!(remch,begin
                        if isnothing(seed)
                            timeevolution.mcwf(tspan,psi0,H,J;
                            rates=rates,fout=fout,Jdagger=Jdagger,
                            display_beforeevent=display_beforeevent,
                            display_afterevent=display_afterevent,
                            alg=alg, kwargs...);
                        else
                            timeevolution.mcwf(tspan,psi0,H,J;
                            seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
                            display_beforeevent=display_beforeevent,
                            display_afterevent=display_afterevent,
                            alg=alg, kwargs...);
                        end
                    end);
    end
    # Once saver has consumed all queued trajectories produced by all workers, an
    # array of MCWF trajs is returned.
    sols = fetch(saver);

    if return_data
        out_type = fout == nothing ? typeof(psi0) : pure_inference(fout, Tuple{eltype(tspan),typeof(psi0)});
        return (tspan, convert(Array{Vector{out_type},1},sols));
    else
        nothing;
    end
end;

function split_threads_mcwf(tspan, psi0::T, H::AbstractOperator{B,B}, J::Vector;
        Ntrajectories=1, progressbar::Bool = true,
        return_data::Bool = true, save_data::Bool = true,
        fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing,
        seed=nothing, rates::DecayRates=nothing,
        fout=nothing, Jdagger::Vector=dagger.(J),
        display_beforeevent=false, display_afterevent=false,
        alg=OrdinaryDiffEq.AutoTsit5(OrdinaryDiffEq.Rosenbrock23()),
        kwargs...) where {B<:Basis,T<:Ket{B},T2}

    # Create a remote channel from where trajectories are read out by the saver
    remch = RemoteChannel(()->Channel{Any}(Inf)); # TO DO: add some finite buffer size

    # Create a task fetched by the first available worker that retrieves trajs
    # from the remote channel and writes them to disk. A progress bar is set up
    # as well.
    saver = @async launch_saver(remch; Ntrajectories=Ntrajectories,
        progressbar=progressbar, return_data=return_data, save_data=save_data,
        fpath=fpath, additional_data=additional_data);
    wp = CachingPool(workers());

    batches = nfolds(1:Ntrajectories,length(wp.workers))
    # Multi-processed map over all batches of MC trajectories. Maps jobs to
    # workers() from the local process. Jobs consist in computing a batch of
    # MC trajectories and pipe them to the remote channel remch.
    pmap(wp,1:length(wp.workers)) do i
        sol_batch = Array{Any,1}(undef, length(batches[i]))
        Threads.@threads for j in 1:length(batches[i])
            if isnothing(seed)
                sol_batch[j] = timeevolution.mcwf(tspan,psi0,H,J;
                    rates=rates,fout=fout,Jdagger=Jdagger,
                    display_beforeevent=display_beforeevent,
                    display_afterevent=display_afterevent,
                    alg=alg, kwargs...);
            else
                sol_batch[j] = timeevolution.mcwf(tspan,psi0,H,J;
                    seed=seed,rates=rates,fout=fout,Jdagger=Jdagger,
                    display_beforeevent=display_beforeevent,
                    display_afterevent=display_afterevent,
                    alg=alg, kwargs...);
            end
        end
        for sol in sol_batch
            put!(remch,sol);
        end
    end
    # Once saver has consumed all queued trajectories produced by all workers, an
    # array of MCWF trajs is returned.
    sols = fetch(saver);
    # Clear caching pool
    clear!(wp);

    if return_data
        out_type = fout == nothing ? typeof(psi0) : pure_inference(fout, Tuple{eltype(tspan),typeof(psi0)});
        return (tspan, convert(Array{Vector{out_type},1},sols));
    else
        nothing;
    end
end;

function launch_saver(readout_ch::RemoteChannel{Channel{T1}};
        Ntrajectories=1, progressbar::Bool = true, return_data::Bool = true,
        save_data::Bool = true, fpath::Union{String,Missing}=missing,
        additional_data::Union{Dict{String,T2},Missing}=missing) where {T1, T2}
    if progressbar
        # Set up a progress bar
        progress = Progress(Ntrajectories);
        ProgressMeter.update!(progress, 0);
    end
    if save_data
        file = jldopen(fpath, "a+");
        println("Saving data to ",fpath)
        if !ismissing(additional_data)
            for (key, val) in additional_data
                file[key] = val;
            end
        end
    end
    if return_data
        sols::Array{Any,1} = Array{Any,1}(undef,Ntrajectories);
    end

    for i in 1:Ntrajectories
        # Retrieve a queued traj
        sol = take!(readout_ch);
        if save_data && (i == 1) file["t"] = sol[1]; end
        save_data ? file["trajs/" * string(i)] = sol[2] : nothing;
        return_data ? sols[i] = sol[2] : nothing;
        progressbar ? ProgressMeter.next!(progress) : nothing;
    end
    # Set progress bar to 100%
    if progressbar && (progress.counter < Ntrajectories) ProgressMeter.update!(progress, Ntrajectories); end;

    save_data && close(file);
    return return_data ? sols : nothing;
end;

function nfolds(arr,n::Integer)
    foldsize = cld(length(arr),n)
    lastfoldsize = length(arr) - (n-1)*foldsize
    return [[arr[foldsize*(i-1)+1:foldsize*i] for i in 1:n-1]; [arr[end-lastfoldsize+1:end]]]
end;
