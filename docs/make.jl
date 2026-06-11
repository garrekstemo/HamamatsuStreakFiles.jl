using HamamatsuStreakFiles
using Documenter

DocMeta.setdocmeta!(HamamatsuStreakFiles, :DocTestSetup,
                    :(using HamamatsuStreakFiles); recursive=true)

makedocs(;
    modules=[HamamatsuStreakFiles],
    authors="Garrek Stemo <8449000+garrekstemo@users.noreply.github.com>",
    repo=Remotes.GitHub("garrekstemo", "HamamatsuStreakFiles.jl"),
    sitename="HamamatsuStreakFiles.jl",
    checkdocs=:exports,
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://garrekstemo.github.io/HamamatsuStreakFiles.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Introduction" => "index.md",
        "File format" => "guide/img-format.md",
        "Library" => "lib/public.md",
    ],
)

deploydocs(;
    repo="github.com/garrekstemo/HamamatsuStreakFiles.jl",
    devbranch="main",
)
