module PkgExtensions

export update

import Pkg, PrettyTables
using  Markdown, UUIDs

#
# # Constants
#
LAST_ACTIVE_PROJECT = Ref{Union{Nothing,String}}(nothing)

#
# # Functions
#

#
# ## Show deps
#
function show_deps(ctx, args::Vector, api_opts)
    _show_deps(;api_opts...)
end

disp(x::String)  = x
disp(x::Nothing) = "-"
disp(x::Bool)    = x ? "*" : " "
disp(x::UUID)    = string(x)[1:8]
disp(x)          = string(x)

hl_odd = PrettyTables.Highlighter(
    f = (data,i,j) -> (i % 2) == 0,
    crayon = PrettyTables.Crayon(foreground = :blue),
)

function _show_deps(;only_direct=true)
    deps   = Pkg.dependencies()
    if only_direct
        deps = Dict(uuid => info for (uuid, info) in deps if uuid in values(Pkg.Types.EnvCache().project.deps))
    end
    uuids  = keys(deps)
    fields = fieldnames(Pkg.Types.PackageInfo)
    table  = collect(uuids)
    for field in fields
        column = collect([getproperty(deps[uuid], field) for uuid in uuids])
        table  = hcat(table, column)
    end
    header = ["UUID", string.(fields)...]
    table = disp.(table)
    PrettyTables.pretty_table(table, header, PrettyTables.unicode;
                              crop=:horizontal, highlighters = hl_odd)
end

#
# ## git
#
function do_git(ctx, args, opts)
    cd(dirname(Base.active_project())) do
        try
            run(`git $args`)
        catch
        end
    end
end

#
# ## activate
#
function do_activate(ctx, args, opts)
    temp_env = Base.active_project()
    if haskey(opts, :temp) && opts[:temp]
        Pkg.activate(mktempdir())
    elseif isempty(args)
        Pkg.activate()
    elseif args[1] == "-"
        Pkg.activate(LAST_ACTIVE_PROJECT[])
    else
        Pkg.activate(args...; opts...)
    end
    LAST_ACTIVE_PROJECT[] = temp_env
end

#
# # REPL Interface
#
const CommandDeclaration   = Vector{Pair{Symbol,Any}}
const CompoundDeclarations = Vector{Pair{String,Vector{CommandDeclaration}}}
const OptionDeclaration    = Vector{Pair{Symbol,Any}}

#
# ## Declarations
#
compound_declarations = [
"package" => CommandDeclaration[
[   :name => "git",
    :short_name => "g",
    :handler => do_git,
    :arg_count => 0 => Inf,
    :description => "Run a git command in the active directory.",
    :help => md"""
    git <args>...

Run a `git` command in the active directory.
"""
],[
    :name => "activate",
    :short_name => "a",
    :handler => do_activate,
    :arg_count => 0 => 1,
    :option_spec => OptionDeclaration[
        [:name => "temp", :api => :temp => true],
    ],
    :description => "Activate.",
    :completions => Pkg.REPLMode.complete_activate,
    :help => md"""
    activate [-|<directory>]
    activate --temp

Make the directory the active project.
"""
]],
"show" => CommandDeclaration[
[   :name => "deps",
    :handler => show_deps,
    :description => "Show depdency information.",
    :option_spec => OptionDeclaration[
        [:name => "all", :api => :only_direct => false],
    ],
    :help => md"""
    show deps

Show dependency information.
""",
],
]]

#
# ## Utils
#
function update(declarations::CompoundDeclarations)
    compound_specs = Pkg.REPLMode.CompoundSpecs(declarations)
    for (super, specs) in compound_specs
        existing = get(Pkg.REPLMode.SPECS[], super, nothing)
        # merge specs, overshadow Pkg commands if conflict
        Pkg.REPLMode.SPECS[][super] = existing === nothing ? specs : merge(existing, specs)
    end
end

function __init__()
    update(compound_declarations)
end

end # module
