import nfind/diriter
import nfind/globs # For GlobFilter, includes
import nfind/nfos  # For FsoKind members like fsoFile

let filters =
  @[
    GlobFilter(incl: false, glob: "*/*/**"),
    GlobFilter(incl: true, glob: "{*.nim,*.nims}", inverted: true),
  ]

for path in find(".", {fsoFile}, filters):
  echo path

echo includes("./file.nims", [GlobFilter(incl: true, glob: "{*.nim,*.nims}")])
