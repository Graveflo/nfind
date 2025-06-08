import std/os
let srcDir = currentSourcePath.parentDir() / "../src"
# switch("path", srcDir) # <--- Commenting this out
echo "Executing tests/config.nims (srcDir path switch commented out, import std/os is present)."
