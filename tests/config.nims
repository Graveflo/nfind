import std/os
let srcDir = currentSourcePath.parentDir() / "../src"
switch("path", srcDir) # <--- Uncommented
# echo "Executing tests/config.nims (srcDir path switch commented out, import std/os is present)." # Removed echo
