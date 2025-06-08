import std/os
import std/osproc
import std/strutils # For replace, though not strictly needed for this simple case

proc createEmptyFile(filePath: string, content: string) =
  # Using osproc to create the file
  let escapedContent = content.replace("\"", "\\\"").replace("'", "'\\''") # Basic escaping for shell
  let createFileCmd = when defined(windows):
    if content.len == 0:
      "cmd /c \"type nul > \"{}\"\"".replace("{}", filePath)
    else:
      "cmd /c \"echo " & escapedContent & " > \"{}\"\"".replace("{}", filePath)
  else: # POSIX
    if content.len == 0:
      "touch \"{}\"".replace("{}", filePath)
    else:
      "sh -c \"printf '%s' '" & escapedContent & "' > \"{}\"\"".replace("{}", filePath)

  echo "Executing file creation: ", createFileCmd
  let (output, exitCode) = execCmdEx(createFileCmd)
  if exitCode != 0:
    echo "Failed to create file: ", filePath
    echo "Command: ", createFileCmd
    echo "Output: ", output
    # quit(1) # Don't quit in a test, let checks handle it

proc main() =
  let dir = getCurrentDir()
  echo "Current directory: ", dir
  let testFile = "temp_test_output.txt"
  createEmptyFile(testFile, "hello from std/os")
  if fileExists(testFile):
    echo "Successfully wrote to ", testFile
    removeFile(testFile)
  else:
    echo "Failed to write to ", testFile
main()
