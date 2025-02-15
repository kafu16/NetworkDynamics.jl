using NetworkDynamicsInspector
using NetworkDynamics
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
end

app = (;
    sol = Observable{Any}(sol),
    t = Observable{Float64}(0.0),
    tmin = Observable{Float64}(sol.t[begin]),
    tmax = Observable{Float64}(sol.t[end]),
    sel_nodes = Observable{Vector{Int}}(Int[]),
    sel_edges = Observable{Vector{Int}}(Int[]),
    graphplot = (;
        nstate = Observable{Union{Symbol,Nothing}}(:θ),
        estate = Observable{Union{Symbol,Nothing}}(:P),
        nstate_rel = Observable{Bool}(false),
        estate_rel = Observable{Bool}(false),
        ncolorrange = Observable{Tuple{Float32,Float32}}((-1.0, 1.0)),
        ncolorscheme = Observable{ColorScheme}(ColorSchemes.coolwarm),
        ecolorrange = Observable{Tuple{Float32,Float32}}((-1.0, 1.0)),
        ecolorscheme = Observable{ColorScheme}(ColorSchemes.coolwarm),
    )
);

gpfig = Ref{Any}()
App() do session
    WGLMakie.activate!(resize_to=:parent)
    NetworkDynamicsInspector.clear_obs!(app)
    gpfig[] = fig
    Grid(
        NetworkDynamicsInspector.graphplot_card(app; height="400px"),
        NetworkDynamicsInspector.nodestate_control_card(app),
        NetworkDynamicsInspector.timeslider_card(app),
        columns="100%",
        width="500px"
    )
end

app.t[] = 4.0

app.tmin[] = NaN
app.tmin[] = 1.0

app.tmin[]
app.tmax[]

fig = Figure()
ax = Axis(fig[1,1])
graphplot!(ax, Graphs.smallgraph(:karate))



using Bonito

struct OptionGroup{T}
    label::String
    options::Vector{T}
end

multiselect = (;
    options = Observable([
        # OptionGroup("Programming Languages", ["Julia", "Rust", "Java"]),
        # OptionGroup("Languages", ["French", "Spanish", "German"]),
        (;label="Programming Languages", options=[(; id=1, text="Julia"), (;id=2,text="Rust")]),
        (;label="Languages", options=[(; id=3, text="Spanish"), (;id=4,text="French")]),
    ]),
    selection = Observable{Vector{Int}}([1]),
    placeholder="Select state(s) to plot"
)

SERVER = Ref{Any}()
let
    app = App(;) do session
        jquery = Asset("https://cdn.jsdelivr.net/npm/jquery@3.7.1/dist/jquery.min.js")
        select2_css = Asset("https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/css/select2.min.css")
        select2_js = Asset("https://cdn.jsdelivr.net/npm/select2@4.1.0-rc.0/dist/js/select2.min.js")

        # Create a multi-select element
        id = replace(string(gensym("selectbox")), "#"=>"")
        select = DOM.select(
            DOM.option();
            multiple = true,
            class = "js-example-basic-multiple",
            style = "width: 300px",
            name = "states[]",
            id
        )

        # jqdocument = Bonito.JSString(raw"$(document)")
        jqselect = Bonito.JSString(raw"$('#"* id * raw"')")

        esc = Bonito.JSString(raw"$")

        js_onload = js"""
        (select) => {
            $jqselect.select2({
                placeholder: "select a state"
            });
            $jqselect.bind('change', onSelectChange);

            function onSelectChange(event){
                const new_sel = $jqselect.select2('val')
                const old_sel = $(multiselect.selection).value

                // only push back to julia if different
                if (!(new_sel.length === old_sel.length &&
                        new_sel.every(function(val, i) { return val == old_sel[i]}))){
                    console.log("new", new_sel)
                    console.log("old", old_sel)
                    $(multiselect.selection).notify(new_sel);
                }
                // console.log("Slected ", $jqselect.select2('val') );
                // console.log("Observable ", $(multiselect.options).value);
                //console.log("JS data ", options);
            };

            function updateDisplayedItems(new_options) {
                const jq_select = $jqselect;

                // Clear previous options
                jq_select.empty();

                // Loop through each group and create optgroups
                new_options.forEach(group => {
                    let jq_optgroup = $esc('<optgroup>', { label: group.label });

                    group.options.forEach(option => {
                        let newOption = new Option(option.text, option.id, false, false);
                        jq_optgroup.append(newOption);
                    });

                    jq_select.append(jq_optgroup);
                });
            }
            updateDisplayedItems($(multiselect.options).value);
            $(multiselect.options).on(updateDisplayedItems);

            function updateDisplayedSelection(new_sel) {
                selection = new_sel;
                $jqselect.val(new_sel).trigger('change');
            }
            updateDisplayedSelection($(multiselect.selection).value)
            $(multiselect.selection).on(updateDisplayedSelection)

            // Trigger update for Select2 to recognize new options
            $jqselect.trigger('change');

            // Don't reorder
            // https://github.com/select2/select2/issues/3106#issuecomment-255492815
            /*
            $jqselect.on('select2:select', function(e) {
                var element = $esc(this).find('[value="' + e.params.data.id + '"]');
                $esc(this).append(element);
                $esc(this).trigger('change');
            });
            */
        }
        """
        Bonito.onload(session, select, js_onload)

        return DOM.div(
            jquery,
            select2_css,
            select2_js,
            # styles,
            DOM.h2("Select Programming Languages:"),
            select,
            DOM.br(),
        )
    end;
    try
        println("Close existing")
        close(SERVER[])
    catch
    end
    println("Start server")
    SERVER[] = Bonito.Server(app, "0.0.0.0", 8080)
    # Bonito.update_app!
end

multiselect.selection[] = [4,3]
multiselect.selection[]

close(server)
server




# Start the server
server = Server(app, "0.0.0.0", 8080)
wait(server)


d = DOM.div("foo")
jsrender()


    # jquery = Asset("https://cdn.jsdelivr.net/npm/jquery@3.7.1/dist/jquery.min.js")
        # DOM.head(jquery),

using Bonito
app = App() do session
    return DOM.html(
        DOM.head(
            DOM.meta(name="viewport", content="width=device-width, initial-scale=1.0"),
            DOM.meta(charset="utf-8"),
            Bonito.TailwindCSS,
        ),
        DOM.body(
            DOM.div("Hello")
        )
    )
end;
server = Bonito.Server(app, "0.0.0.0", 8080)

using Bonito
app = App() do session
    return DOM.html(
        DOM.head(),
        DOM.body(
            DOM.div("Hello")
        )
    )
end;
server = Bonito.Server(app, "0.0.0.0", 8080)
close(server)
