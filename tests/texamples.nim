import nfind/diriter

let filters = @[
  GlobFilter(incl: false, glob: "*/*/**"),
  GlobFilter(incl: true, glob: "*.{nim,nims}", inverted: true)
]

for path in find(".", {fsoFile}, filters):
  echo path
