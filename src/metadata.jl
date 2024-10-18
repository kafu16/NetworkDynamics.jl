####
#### per sym metadata
####
"""
    has_metadata(c::ComponentFunction, sym::Symbol, key::Symbol)

Checks if symbol metadata `key` is present for symbol `sym`.
"""
function has_metadata(c::ComponentFunction, sym::Symbol, key::Symbol)
    md = symmetadata(c)
    haskey(md, sym) && haskey(md[sym], key)
end
"""
    get_metadata(c::ComponentFunction, sym::Symbol, key::Symbol)

Retrievs the metadata `key` for symbol `sym`.
"""
get_metadata(c::ComponentFunction, sym::Symbol, key::Symbol) = symmetadata(c)[sym][key]

"""
    set_metadata!(c::ComponentFunction, sym::Symbol, key::Symbol, value)
    set_metadata!(c::ComponentFunction, sym::Symbol, pair)

Sets the metadata `key` for symbol `sym` to `value`.
"""
function set_metadata!(c::ComponentFunction, sym::Symbol, key::Symbol, value)
    d = get!(symmetadata(c), sym, Dict{Symbol,Any}())
    d[key] = value
end
set_metadata!(c::ComponentFunction, sym::Symbol, pair::Pair) = set_metadata!(c, sym, pair.first, pair.second)

# generate default methods for some per-symbol metadata fields
for md in [:default, :guess, :init, :bounds]
    fname_has = Symbol(:has_, md)
    fname_get = Symbol(:get_, md)
    fname_set = Symbol(:set_, md, :!)
    @eval begin
        """
            has_$($(QuoteNode(md)))(c::ComponentFunction, sym::Symbol)

        Checks if a `$($(QuoteNode(md)))` value is present for symbol `sym`.

        See also [`get_$($(QuoteNode(md)))`](@ref), [`set_$($(QuoteNode(md)))`](@ref).
        """
        $fname_has(c::ComponentFunction, sym::Symbol) = has_metadata(c, sym, $(QuoteNode(md)))

        """
            get_$($(QuoteNode(md)))(c::ComponentFunction, sym::Symbol)

        Returns the `$($(QuoteNode(md)))` value for symbol `sym`.

        See also [`has_$($(QuoteNode(md)))`](@ref), [`set_$($(QuoteNode(md)))`](@ref).
        """
        $fname_get(c::ComponentFunction, sym::Symbol) = get_metadata(c, sym, $(QuoteNode(md)))


        """
            set_$($(QuoteNode(md)))(c::ComponentFunction, sym::Symbol, value)

        Sets the `$($(QuoteNode(md)))` value for symbol `sym` to `value`.

        See also [`has_$($(QuoteNode(md)))`](@ref), [`get_$($(QuoteNode(md)))`](@ref).
        """
        $fname_set(c::ComponentFunction, sym::Symbol, val) = set_metadata!(c, sym, $(QuoteNode(md)), val)
    end
end


#### default or init
"""
    has_default_or_init(c::ComponentFunction, sym::Symbol)

Checks if a `default` or `init` value is present for symbol `sym`.
"""
has_default_or_init(c::ComponentFunction, sym::Symbol) = has_default(c, sym) || has_init(c, sym)
"""
    get_default_or_init(c::ComponentFunction, sym::Symbol)

Returns if a `default` value if available, otherwise returns `init` value for symbol `sym`.
"""
get_default_or_init(c::ComponentFunction, sym::Symbol) = has_default(c, sym) ? get_default(c, sym) : get_init(c, sym)

#### default or guess
"""
    has_default_or_guess(c::ComponentFunction, sym::Symbol)

Checks if a `default` or `guess` value is present for symbol `sym`.
"""
has_default_or_guess(c::ComponentFunction, sym::Symbol) = has_default(c, sym) || has_guess(c, sym)
"""
    get_default_or_guess(c::ComponentFunction, sym::Symbol)

Returns if a `default` value if available, otherwise returns `guess` value for symbol `sym`.
"""
get_default_or_guess(c::ComponentFunction, sym::Symbol) = has_default(c, sym) ? get_default(c, sym) : get_guess(c, sym)


# TODO: legacy, only used within show methods
function def(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.sym) do s
        has_default_or_init(c, s) ? get_default_or_init(c, s) : nothing
    end
end
function guess(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.sym) do s
        has_guess(c, s) ? get_guess(c, s) : nothing
    end
end
function pdef(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.psym) do s
        has_default_or_init(c, s) ? get_default_or_init(c, s) : nothing
    end
end
function pguess(c::ComponentFunction)::Vector{Union{Nothing,Float64}}
    map(c.psym) do s
        has_guess(c, s) ? get_guess(c, s) : nothing
    end
end

####
#### Component metadata
####
"""
    has_metadata(c::ComponentFunction, key::Symbol)

Checks if metadata `key` is present for the component.
"""
function has_metadata(c::ComponentFunction, key)
    haskey(metadata(c), key)
end
"""
    get_metadata(c::ComponentFunction, key::Symbol)

Retrieves the metadata `key` for the component.
"""
get_metadata(c::ComponentFunction, key::Symbol) = metadata(c)[key]
"""
    set_metadata!(c::ComponentFunction, key::Symbol, value)

Sets the metadata `key` for the component to `value`.
"""
set_metadata!(c::ComponentFunction, key::Symbol, val) = setindex!(metadata(c), val, key)

#### graphelement field for edges and vertices
"""
    has_graphelement(c)

Checks if the edge or vetex function function has the `graphelement` metadata.
"""
has_graphelement(c::ComponentFunction) = has_metadata(c, :graphelement)
"""
    get_graphelement(c::EdgeFunction)::@NamedTuple{src::T, dst::T}
    get_graphelement(c::VertexFunction)::Int

Retrieves the `graphelement` metadata for the component function. For edges this
returns a named tupe `(;src, dst)` where both are either integers (vertex index)
or symbols (vertex name).
"""
get_graphelement(c::EdgeFunction) = get_metadata(c, :graphelement)::@NamedTuple{src::T, dst::T} where {T<:Union{Int,Symbol}}
get_graphelement(c::VertexFunction) = get_metadata(c, :graphelement)::Int
"""
    set_graphelement!(c::EdgeFunction, src, dst)
    set_graphelement!(c::VertexFunction, vidx)

Sets the `graphelement` metadata for the edge function. For edges this takes two
arguments `src` and `dst` which are either integer (vertex index) or symbol
(vertex name). For vertices it takes a single integer `vidx`.
"""
set_graphelement!(c::EdgeFunction, nt::@NamedTuple{src::T, dst::T}) where {T<:Union{Int,Symbol}} = set_metadata!(c, :graphelement, nt)
set_graphelement!(c::VertexFunction, vidx::Int) = set_metadata!(c, :graphelement, vidx)


function get_defaults(c::ComponentFunction, syms)
    [has_default(c, sym) ? get_default(c, sym) : nothing for sym in syms]
end
function get_guesses(c::ComponentFunction, syms)
    [has_guess(c, sym) ? get_guess(c, sym) : nothing for sym in syms]
end
function get_defaults_or_inits(c::ComponentFunction, syms)
    [has_default_or_init(c, sym) ? get_default_or_init(c, sym) : nothing for sym in syms]
end
