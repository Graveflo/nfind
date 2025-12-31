import nfind/diriter

let filters =
  @[
    globExcl"*/*/**",
    GlobFilter(incl: true, glob: "*.{nim,nims}", inverted: true),
  ]

for path in find(".", {fsoFile}, filters):
  echo path

echo includes("./file.nims", [GlobFilter(incl: true, glob: "{*.nim,*.nims}")])

for expanded in iterExpansions("{,{a,b}}{1,2}"):
  echo expanded