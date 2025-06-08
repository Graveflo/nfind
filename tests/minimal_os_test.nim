import std/os
proc main() =
  let dir = getCurrentDir()
  echo "Current directory: ", dir
  let testFile = "temp_test_output.txt"
  writeFile(testFile, "hello from std/os")
  if fileExists(testFile):
    echo "Successfully wrote to ", testFile
    removeFile(testFile)
  else:
    echo "Failed to write to ", testFile
main()
