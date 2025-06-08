import std/unittest
import std/os
import std/osproc # For execCmd, execCmdEx
# import std/strformat # For fmt - removing, will use strutils.replace
import std/sequtils
import std/strutils # For replace
import nfind/diriter # Changed path

const tempTestBaseDir = "tests" / "temp_test_data"
const tempTestDir = tempTestBaseDir / "windows_diriter"

proc normalizePathSeq(paths: seq[string]): seq[string] =
  result = newSeq[string](paths.len)
  for i, p in paths:
    var tempPath = p
    normalizePath(tempPath)
    result[i] = tempPath

proc runOrFail(cmdPattern: string, pathArg: string): void =
  let cmd = cmdPattern.replace("{}", pathArg)
  echo "Executing: ", cmd
  let (output, exitCode) = execCmdEx(cmd)
  if exitCode != 0:
    echo "Command failed with exit code: ", exitCode
    echo "Output:\n", output
    quit(1) # Fail fast if setup/teardown commands don't work

proc setupTestSuite(): void =
  echo "Setting up test suite..."
  let createDirCmdPattern = when defined(windows): "cmd /c mkdir \"{}\"" else: "mkdir -p \"{}\""
  let createFileCmdPattern = when defined(windows): "cmd /c \"type nul > \"{}\"\"" else: "touch \"{}\""

  # Create directory structure
  runOrFail(createDirCmdPattern, tempTestDir)
  runOrFail(createDirCmdPattern, tempTestDir / "empty_dir")

  let nonEmptyDirPath = tempTestDir / "non_empty_dir"
  runOrFail(createDirCmdPattern, nonEmptyDirPath)
  runOrFail(createDirCmdPattern, nonEmptyDirPath / "sub_dir1")

  # Create empty files
  runOrFail(createFileCmdPattern, nonEmptyDirPath / "file1.txt")
  runOrFail(createFileCmdPattern, nonEmptyDirPath / "file2.log")
  echo "Test suite setup complete."

proc teardownTestSuite(): void =
  echo "Tearing down test suite..."
  let removeDirCmdPattern = when defined(windows): "cmd /c rmdir /s /q \"{}\"" else: "rm -rf \"{}\""
  runOrFail(removeDirCmdPattern, tempTestDir)

  # Attempt to remove the base directory if it's empty.
  # This part is best-effort; primary cleanup is tempTestDir itself.
  # Check if tempTestBaseDir exists and is empty before attempting to remove.
  if dirExists(tempTestBaseDir):
    var isEmpty = true
    for _ in walkDir(tempTestBaseDir, relative = true): # Check if any files/dirs remain
      isEmpty = false
      break
    if isEmpty:
      try:
        runOrFail(removeDirCmdPattern, tempTestBaseDir)
      except: # Ignore if removal of base dir fails (e.g. due to other test suites using it)
        echo "Could not remove base temp dir: ", tempTestBaseDir, " (might be in use or already removed)"

  echo "Test suite teardown complete."

suite "Windows Directory Iteration Tests":
  setupTestSuite()

  try:
    test "Iterate Empty Directory":
      let emptyDirPath = tempTestDir / "empty_dir"
      var itemsFound = 0
      for item in find(emptyDirPath, {fsoFile, fsoDir}, []):
        itemsFound += 1
      check itemsFound == 0

    test "Iterate Non-Empty Directory":
      let nonEmptyDirPath = tempTestDir / "non_empty_dir"
      var expectedItems = @[
        "file1.txt",
        "file2.log",
        "sub_dir1"
      ].mapIt(nonEmptyDirPath / it)
      expectedItems = normalizePathSeq(expectedItems)

      var foundItems: seq[string] = @[]
      for item in find(nonEmptyDirPath, {fsoFile, fsoDir}, []):
        var tempItem = item
        normalizePath(tempItem)
        foundItems.add(tempItem)
        check tempItem.splitPath.tail != "."
        check tempItem.splitPath.tail != ".."

      check foundItems.len == expectedItems.len
      for expected in expectedItems:
        check foundItems.contains(expected)

      let foundBasenames = foundItems.map(proc (p: string): string = p.splitPath.tail)
      let expectedBasenames = @["file1.txt", "file2.log", "sub_dir1"]
      for bn in expectedBasenames:
        check foundBasenames.contains(bn)

    test "Filter Specific File Types":
      let path = tempTestDir / "non_empty_dir"
      var expectedFiles = @[
        "file1.txt",
        "file2.log"
      ].mapIt(path / it)
      expectedFiles = normalizePathSeq(expectedFiles)

      var foundFiles: seq[string] = @[]
      for item in find(path, {fsoFile}, []):
        var tempItem = item
        normalizePath(tempItem)
        foundFiles.add(tempItem)

      check foundFiles.len == expectedFiles.len
      for expected in expectedFiles:
        check foundFiles.contains(expected)

      var expectedDirs = @[
        "sub_dir1"
      ].mapIt(path / it)
      expectedDirs = normalizePathSeq(expectedDirs)

      var foundDirs: seq[string] = @[]
      for item in find(path, {fsoDir}, []):
        var tempItem = item
        normalizePath(tempItem)
        foundDirs.add(tempItem)

      check foundDirs.len == expectedDirs.len
      for expected in expectedDirs:
        check foundDirs.contains(expected)

    test "Iterate Non-Existent Directory":
      let nonExistentPath = tempTestDir / "non_existent_dir"
      when defined(windows):
        expect OSError:
          for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
            discard item

        try:
          for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
            discard item
          check false
        except OSError as e:
          check e.msg.contains(nonExistentPath)
          check e.msg.contains("Windows Error Code")
      else:
        var itemsFound = 0
        for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
          itemsFound += 1
        check itemsFound == 0
  finally:
    teardownTestSuite()
