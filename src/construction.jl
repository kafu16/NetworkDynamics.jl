function Network(g::AbstractGraph,
                 vertexf::Union{VertexFunction,Vector{<:VertexFunction}},
                 edgef::Union{EdgeFunction,Vector{<:EdgeFunction}};
                 execution=SequentialExecution{true}(),
                 edepth=:auto,
                 vdepth=:auto,
                 aggregator=execution isa SequentialExecution ? SequentialAggregator(+) : PolyesterAggregator(+),
                 check_graphelement=true,
                 set_graphelement=false,
                 verbose=false)
    reset_timer!()
    @timeit_debug "Construct Network" begin
        # collect all vertex/edgf to vector
        _vertexf = vertexf isa Vector ? vertexf : [copy(vertexf) for _ in vertices(g)]
        _edgef = edgef isa Vector ? edgef : [copy(edgef) for _ in edges(g)]
        @argcheck _vertexf isa Vector{<:VertexFunction} "Expected VertexFuncions, got $(eltype(_vertexf))"
        @argcheck _edgef isa Vector{<:EdgeFunction} "Expected EdgeFuncions, got $(eltype(_vertexf))"
        @argcheck length(_vertexf) == nv(g)
        @argcheck length(_edgef) == ne(g)

        # check if components alias metadata and copy if necessary
        _dealias!(_vertexf)
        _dealias!(_edgef)

        verbose &&
            println("Create dynamic network with $(nv(g)) vertices and $(ne(g)) edges:")
        @argcheck execution isa ExecutionStyle "Execution type $execution not supported (choose from $(subtypes(ExecutionStyle)))"

        _maxedepth = isempty(_edgef) ? 0 : mapreduce(depth, min, _edgef)
        if edepth === :auto
            edepth = _maxedepth
            verbose && println(" - auto accumulation depth = $edepth")
        end
        @argcheck edepth<=_maxedepth "For this system accumulation depth is limited to $edepth by the edgefunctions"

        _maxvdepth = mapreduce(depth, min, _vertexf)
        if vdepth === :auto
            vdepth = _maxvdepth
            verbose && println(" - auto edge input depth = $vdepth")
        end
        @argcheck vdepth<=_maxvdepth "For this system edge input depth is limited to $edepth by the vertex dimensions"

        dynstates = mapreduce(+, Iterators.flatten((_vertexf,_edgef))) do t
            isdynamic(t) ? dim(t) : 0
        end

        # create index manager
        im = IndexManager(g, dynstates, edepth, vdepth, _vertexf, _edgef)


        # check graph_element metadata and attach if necessary
        for (i, vf) in pairs(_vertexf)
            if check_graphelement && has_graphelement(vf)
                if get_graphelement(vf) != i
                    @warn "Vertex function $(vf.name) is placed at node index $i bus has \
                    `graphelement` $(get_graphelement(vf)) stored in metadata. \
                    The wrong data will be " * (set_graphelement ? "overwritten!" : "ignored!") *
                    " Use `check_graphelement` and `set_graphelement` keywords to alter this behavior."
                end
            end
            set_graphelement && set_graphelement!(vf, i)
        end
        for (iteredge, ef) in zip(im.edgevec, _edgef)
            if check_graphelement && has_graphelement(ef)
                ge = get_graphelement(ef)
                src = get(im.unique_vnames, ge.src, ge.src)
                dst = get(im.unique_vnames, ge.dst, ge.dst)
                if iteredge.src != src || iteredge.dst != dst
                    @warn "Edge function $(ef.name) at $(iteredge.src) => $(iteredge.dst) has wrong `:graphelement` $src => $dst). \
                    The wrong data will be " * (set_graphelement ? "overwritten!" : "ignored!") *
                    " Use `check_graphelement` and `set_graphelement` keywords to alter this behavior."
                end
            end
            set_graphelement && set_graphelement!(ef, (;src=iteredge.src, dst=iteredge.dst))
        end

        # batch identical edge and vertex functions
        @timeit_debug "batch identical vertexes" begin
            vidxs = _find_identical(vertexf, 1:nv(g))
        end
        @timeit_debug "batch identical edges" begin
            eidxs = _find_identical(edgef, 1:ne(g))
        end

        # create vertex batches and initialize with index manager
        @timeit_debug "create vertex batches" begin
            vertexbatches = map(vidxs) do idxs
                VertexBatch(im, idxs; verbose)
            end

            if length(vertexbatches) ≤ 50
                vertexbatches = Tuple(vertexbatches)
            else
                verbose &&
                    println(" $(length(vertexbatches)) > 50 unique indices: don't unroll!")
            end
        end

        # create edge batches and initialize with index manager
        @timeit_debug "create edge batches" begin
            edgebatches = map(eidxs) do idxs
                EdgeBatch(im, idxs; verbose)
            end
            if length(edgebatches) ≤ 50
                edgebatches = Tuple(edgebatches)
            else
                verbose &&
                    println("$(length(edgebatches)) > 50 unique edges: don't unroll!")
            end
        end

        @timeit_debug "initialize aggregator" begin
            _aggregator = aggregator(im, edgebatches)
        end

        nl = NetworkLayer(im.g, edgebatches, _aggregator, im.edepth, im.vdepth)

        @assert isdense(im)
        mass_matrix = construct_mass_matrix(im)
        N = ForwardDiff.pickchunksize(max(im.lastidx_dynamic, im.lastidx_p))
        caches = (;state = DiffCache(zeros(im.lastidx_static), N),
                  aggregation = DiffCache(zeros(im.lastidx_aggr), N))

        gbufprovider = if usebuffer(execution)
            EagerGBufProvider(im, edgebatches)
        else
            LazyGBufProvider(im, edgebatches)
        end

        nw = Network{typeof(execution),typeof(g),typeof(nl), typeof(vertexbatches),
                     typeof(mass_matrix),eltype(caches),typeof(gbufprovider)}(
            vertexbatches,
            nl, im,
            caches,
            mass_matrix,
            gbufprovider
        )

    end
    # print_timer()
    return nw
end

function Network(vertexfs, edgefs; kwargs...)
    @argcheck all(has_graphelement, vertexfs) "All vertex functions must have assigned `graphelement` to implicitly construct graph!"
    @argcheck all(has_graphelement, edgefs) "All edge functions must have assigned `graphelement` to implicitly construct graph!"

    vidxs = get_graphelement.(vertexfs)
    allunique(vidxs) || throw(ArgumentError("All vertex functions must have unique `graphelement`!"))
    sort(vidxs) == 1:length(vidxs) || throw(ArgumentError("Vertex functions must have `graphelement` in range 1:length(vertexfs)!"))

    vdict = Dict(vidxs .=> vertexfs)

    # find unique maapings from name => graphelement
    vnamedict = unique_mappings(getproperty.(vertexfs, :name), get_graphelement.(vertexfs))

    simpleedges = map(edgefs) do e
        ge = get_graphelement(e)
        _resolve_ge_to_edge(ge, vnamedict)
    end
    allunique(simpleedges) || throw(ArgumentError("Some edge functions have the same `graphelement`!"))
    edict = Dict(simpleedges .=> edgefs)

    # if all src < dst then we can use SimpleGraph, else digraph
    g = if all(e -> e.src < e.dst, simpleedges)
        SimpleGraph(length(vertexfs))
    else
        SimpleDiGraph(length(vertexfs))
    end
    for edge in simpleedges
        if g isa SimpleDiGraph && has_edge(g, edge.dst, edge.src)
            @warn "Edges $(edge.src) -> $(edge.dst) and $(edge.dst) -> $(edge.src) are both present in the graph!"
        end
        r = add_edge!(g, edge)
        r || error("Could not add edge $(edge) to graph $(g)!")
    end

    vfs_ordered = [vdict[k] for k in vertices(g)]
    efs_ordered = [edict[k] for k in edges(g)]

    Network(g, vfs_ordered, efs_ordered; check_graphelement=false, set_graphelement=false, kwargs...)
end

"""
    _dealisas!(cfs::Vector{<:ComponentFunction})

Checks if any component functions reference the same metadtata/symmetada fields and
creates copies of them if necessary.
"""
function _dealias!(cfs::Vector{<:ComponentFunction})
    smd_dict = IdDict{Dict{Symbol,Dict{Symbol, Any}},Vector{Int}}()
    md_dict = IdDict{Dict{Symbol,Any},Vector{Int}}()

    needscopy = false
    for (i, cf) in pairs(cfs)
        if haskey(md_dict, metadata(cf))
            needscopy = true
            push!(md_dict[metadata(cf)], i)
        else
            md_dict[metadata(cf)] = [i]
        end
        if haskey(smd_dict, symmetadata(cf))
            needscopy = true
            push!(smd_dict[symmetadata(cf)], i)
        else
            smd_dict[symmetadata(cf)] = [i]
        end
    end

    if !needscopy
        return cfs
    end

    copyidxs = Int[]
    for v in values(smd_dict)
        length(v) > 1 && append!(copyidxs, v)
    end
    for v in values(md_dict)
        length(v) > 1 && append!(copyidxs, v)
    end
    unique!(copyidxs)

    comp = first(cfs) isa VertexFunction ? "Vertices" : "Edges"

    @warn "$comp $copyidxs reference the same metadata and will be copied. This can happen if \
    the same component reference multiple times. Manually `copy` the component functions to \
    avoid this warning."

    cfs[copyidxs] = copy.(cfs[copyidxs])
end

# resolve the graphelement ge (named tuple) to simple edge with potential lookup in vertex name dict dict
function _resolve_ge_to_edge(ge, vnamedict)
    src = if ge.src isa Symbol
        haskey(vnamedict, ge.src) || throw(ArgumentError("Edge function has unknown or non-unique source vertex name $(ge.src)"))
        vnamedict[ge.src]
    else
        ge.src
    end
    dst = if ge.dst isa Symbol
        haskey(vnamedict, ge.dst) || throw(ArgumentError("Edge function has unknown or non-unique source vertex name $(ge.dst)"))
        vnamedict[ge.dst]
    else
        ge.dst
    end
    SimpleEdge(src, dst)
end

function VertexBatch(im::IndexManager, idxs::Vector{Int}; verbose)
    components = @view im.vertexf[idxs]

    try
        _compT = dispatchT(only(unique(dispatchT, components)))
        _compf = compf(only(unique(compf, components)))
        _statetype = statetype(only(unique(statetype, components)))
        _dim = dim(only(unique(dim, components)))
        _pdim = pdim(only(unique(pdim, components)))

        (statestride, pstride, aggbufstride) = register_vertices!(im, _statetype, _dim, _pdim, idxs)

        verbose &&
        println(" - VertexBatch: dim=$(_dim), pdim=$(_pdim), length=$(length(idxs))")

        VertexBatch{_compT, typeof(_compf), typeof(idxs)}(idxs, _compf, statestride, pstride, aggbufstride)
    catch e
        if e isa ArgumentError && startswith(e.msg, "Collection has multiple elements")
            throw(ArgumentError("Provided vertex functions $idxs use the same function but have different metadata (dim, pdim,type,...)"))
        else
            rethrow(e)
        end
    end
end

function EdgeBatch(im::IndexManager, idxs::Vector{Int}; verbose)
    components = @view im.edgef[idxs]

    try
        _compT = dispatchT(only(unique(dispatchT, components)))
        _compf = compf(only(unique(compf, components)))
        _statetype = statetype(only(unique(statetype, components)))
        _dim = dim(only(unique(dim, components)))
        _pdim = pdim(only(unique(pdim, components)))

        (statestride, pstride, gbufstride) = register_edges!(im, _statetype, _dim, _pdim, idxs)

        verbose &&
        println(" - EdgeBatch: dim=$(_dim), pdim=$(_pdim), length=$(length(idxs))")

        EdgeBatch{_compT, typeof(_compf), typeof(idxs)}(idxs, _compf, statestride, pstride, gbufstride)
    catch e
        if e isa ArgumentError && startswith(e.msg, "Collection has multiple elements")
            throw(ArgumentError("Provided edge functions $idxs use the same function but have different metadata (dim, pdim,type,...)"))
        else
            rethrow(e)
        end
    end
end

batch_by_idxs(v, idxs::Vector{Vector{Int}}) = [v for batch in idxs]
function batch_by_idxs(v::AbstractVector, batches::Vector{Vector{Int}})
    @assert length(v) == sum(length.(batches))
    [v[batch] for batch in batches]
end

_find_identical(v::ComponentFunction, indices) = [collect(indices)]
function _find_identical(v::Vector, indices)
    idxs_per_type = Vector{Int}[]
    unique_compf = []
    for i in eachindex(v)
        found = false
        for j in eachindex(unique_compf)
            if compf(v[i]) == unique_compf[j]
                found = true
                push!(idxs_per_type[j], indices[i])
                break
            end
        end
        if !found
            push!(unique_compf, compf(v[i]))
            push!(idxs_per_type, [indices[i]])
        end
    end
    @assert length(unique_compf) == length(idxs_per_type)
    return idxs_per_type
end

function construct_mass_matrix(im; type=nothing)
    vertexd = filter(pairs(im.vertexf)) do (_, c)
        hasproperty(c,:mass_matrix) && c.mass_matrix != LinearAlgebra.I
    end
    edged = filter(pairs(im.edgef)) do (_, c)
        hasproperty(c,:mass_matrix) && c.mass_matrix != LinearAlgebra.I
    end
    if isempty(vertexd) && isempty(edged)
        return LinearAlgebra.I
    end


    # go through all mass matrices, find type and diagonal structure of massmatrix
    all_diag = true
    _type = Bool
    for comp in Iterators.flatten((values(vertexd), values(edged)))
        _check_massmatrix(comp)
        _type = promote_type(_type, eltype(comp.mass_matrix))
        all_diag = all_diag && LinearAlgebra.isdiag(comp.mass_matrix)
    end
    if type != nothing
        _type = type
    end

    mass_matrix = if all_diag
        UniformScaling{_type}(1)(im.lastidx_dynamic)
    else
        Matrix(UniformScaling{_type}(1)(im.lastidx_dynamic))
    end
    _fill_mass_matrix!(mass_matrix, im, vertexd, edged)
end

function _fill_mass_matrix!(mass_matrix, im, vertexd, edged)
    for (i, c) in vertexd
        range = im.v_data[i]
        # cannot broadcast uniform scaling, collect to diagonal in that case
        mm = c.mass_matrix isa UniformScaling ? c.mass_matrix(length(range)) : c.mass_matrix
        mass_matrix[range, range] .= mm
    end
    for (i, c) in edged
        range = im.e_data[i]
        mm = c.mass_matrix isa UniformScaling ? c.mass_matrix(length(range)) : c.mass_matrix
        mass_matrix[range, range] .= mm
    end
    mass_matrix
end

function _check_massmatrix(c)
    if c.mass_matrix isa UniformScaling
        return
    end
    if length(size(c.mass_matrix)) == 2
        @argcheck size(c.mass_matrix) == (dim(c), dim(c))
        return
    end
    throw(ArgumentError("Mass matrix must be a square matrix,\
                         a uniform scaling, or scalar. Got $(c.mass_matrix) \
                         in component :$(c.name)."))
end

"""
    Network(nw::Network; g, vertexf, edgef, kwargs...)

Rebuild the Network with same graph and vertex/edge functions but possibly different kwargs.
"""
function Network(nw::Network;
                 g = nw.im.g,
                 vertexf = copy.(nw.im.vertexf),
                 edgef = copy.(nw.im.edgef),
                 kwargs...)

    _kwargs = Dict(:execution => executionstyle(nw),
                   :edepth => :auto,
                   :vdepth => :auto,
                   :aggregator => get_aggr_constructor(nw.layer.aggregator),
                   :check_graphelement => true,
                   :set_graphelement => false,
                   :verbose => false)
    for (k, v) in kwargs
        _kwargs[k] = v
    end

    # check, that we actually provide all of the arguments
    # mainly so we don't forget to add it here if we introduce new kw arg to main constructor
    m = only(methods(Network, [typeof(g), typeof(vertexf), typeof(edgef)]))
    @assert keys(_kwargs) == Set(Base.kwarg_decl(m))

    Network(g, vertexf, edgef; _kwargs...)
end
