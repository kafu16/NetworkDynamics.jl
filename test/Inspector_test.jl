using NetworkDynamics
using NetworkDynamics: SymbolicIndex
using NetworkDynamicsInspector
using Bonito
using WGLMakie
using WGLMakie.Makie.ColorSchemes
using GraphMakie
using Graphs: SimpleGraph
using OrdinaryDiffEqTsit5
using Graphs: Graphs

sol = let
    include(joinpath(pkgdir(NetworkDynamics), "test", "ComponentLibrary.jl"))

    g = SimpleGraph([0 1 1 0 1;
                        1 0 1 1 0;
                        1 1 0 1 0;
                        0 1 1 0 1;
                        1 0 0 1 0])
    vs = [Lib.swing_mtk() for _ in 1:5];
    set_default!(vs[1], :Pmech, -1)
    set_default!(vs[2], :Pmech, 1.5)
    set_default!(vs[3], :Pmech, -1)
    set_default!(vs[4], :Pmech, -1)
    set_default!(vs[5], :Pmech, 1.5)
    ls = [Lib.line_mtk() for _ in 1:7];
    nw = Network(g, vs, ls)
    sinit = NWState(nw)
    s0 = find_fixpoint(nw)
    set_defaults!(nw, s0)

    # set_position!(vs[1], (0.0, 0.0))
    set_marker!(vs[1], :dtriangle)
    set_marker!(vs[2], :utriangle)
    set_marker!(vs[3], :dtriangle)
    set_marker!(vs[4], :dtriangle)
    set_marker!(vs[5], :utriangle)

    cond = ComponentCondition([:P, :₋P, :srcθ], [:limit, :K]) do u, p, t
        abs(u[:P]) - p[:limit]
    end
    affect = ComponentAffect([],[:active]) do u, p, ctx
        @info "Trip line $(ctx.eidx) between $(ctx.src) and $(ctx.dst) at t=$(ctx.t)"
        p[:active] = 0
    end
    cb = ContinousComponentCallback(cond, affect)
    set_callback!.(ls, Ref(cb))

    tripfirst = PresetTimeComponentCallback(1.0, affect) # reuse the same affect
    add_callback!(nw[EIndex(5)], tripfirst)

    nwcb = NetworkDynamics.get_callbacks(nw);
    s0 = NWState(nw)
    prob = ODEProblem(nw, uflat(s0), (0,6), copy(pflat(s0)), callback=nwcb)
    sol = solve(prob, Tsit5());
end;

# ENV["JULIA_DEBUG"] = NetworkDynamicsInspector
# ENV["JULIA_DEBUG"] = ""

app = (;
    sol = Observable{Any}(sol),
    t = Observable{Float64}(0.0),
    tmin = Observable{Float64}(sol.t[begin]),
    tmax = Observable{Float64}(sol.t[end]),
    active_tsplot = Observable{Int}(1),
    graphplot = (;
        selcomp = Observable{Vector{SymbolicIndex}}(SymbolicIndex[]),
        nstate = Observable{Vector{Symbol}}([:θ]),
        estate = Observable{Vector{Symbol}}([:P]),
        nstate_rel = Observable{Bool}(false),
        estate_rel = Observable{Bool}(false),
        ncolorrange = Observable{Tuple{Float32,Float32}}((-1.0, 1.0)),
        ncolorscheme = Observable{ColorScheme}(ColorSchemes.coolwarm),
        ecolorrange = Observable{Tuple{Float32,Float32}}((-1.0, 1.0)),
        ecolorscheme = Observable{ColorScheme}(ColorSchemes.coolwarm),
    ),
    tsplot = (;
        selcomp = Observable{Vector{SymbolicIndex}}(SymbolicIndex[]),
        states = Observable{Vector{Symbol}}(Symbol[]),
    )
);

let
    _app = App() do session
        @info "start new session"
        WGLMakie.activate!(resize_to=:parent)
        NetworkDynamicsInspector.clear_obs!(app)
        DOM.div(
            DOM.div(
                NetworkDynamicsInspector.graphplot_card(app),
                NetworkDynamicsInspector.gpstate_control_card(app, :vertex),
                NetworkDynamicsInspector.gpstate_control_card(app, :edge),
                class="graphplot-col"
            ),
            DOM.div(
                NetworkDynamicsInspector.timeslider_card(app),
                NetworkDynamicsInspector.timeseries_card(app),
                class="timeseries-col"
            ),
            class="maingrid"
        ) |> wrap_assets
    end;
    serve_app(_app)
end


app.tsplot.states[] = [ :θ, :P]
notify(app.tsplot.states)
app.tsplot.selcomp[]

sol([0, 2], idxs=EIndex.(2:5,:active))

sol = app.sol[]
nw = NetworkDynamics.extract_nw(sol)
sidxs = app.tsplot.selcomp[]
NetworkDynamicsInspector.gen_state_options(nw, sidxs)


idxs = EIndex.(1:7, :active);
rel = false;
NetworkDynamicsInspector._maxrange(sol, idxs, rel)

using WGLMakie.Colors

ColorScheme((colorant"gray",colorant"gray"))
