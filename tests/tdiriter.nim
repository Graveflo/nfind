import std/unittest
import std/os
import std/strutils
import std/sequtils
import std/winlean # For windows specific symlink commands if direct os.createSymlink is not used
import std/paths # For `/` operator and parentDir, relativePath
import std/osproc # For execShellCmd, execCmdEx
# Note: std/strutils was imported twice in the version I'm restoring from; will keep one.

# Importing modules from src/nfind
# Path should be resolved by tests/config.nims
import nfind/diriter
import nfind/globs
import nfind/nfos # For FsoKind

suite "Windows diriter tests": # Suite name might be a bit misleading if it's a general diriter test
  const TestDirBase = "test_temp_dir_tdiriter" # Unique name for this test suite

  proc setupTestDir(testName: string): string =
    let testPath = TestDirBase / testName
    if dirExists(testPath):
      removeDir(testPath)
    createDir(testPath)
    return testPath

  proc cleanupTestDir(testPath: string) =
    if dirExists(testPath):
      var retries = 5
      while dirExists(testPath) and retries > 0:
        try:
          removeDir(testPath)
        except OSError as e: # Direct OSError
          echo "Cleanup: removeDir failed for ", testPath, ". Error: ", e.msg
          sleep(100)
        dec retries
      if dirExists(testPath):
        echo "Cleanup: Failed to remove directory after multiple retries: ", testPath

  proc createTestFile(filePath: string, content: string = "") =
    let parent = filePath.parentDir()
    if not dirExists(parent):
      try:
        createDir(parent)
      except:
        let createDirCmdPattern = when defined(windows): "cmd /c mkdir \"{}\"" else: "mkdir -p \"{}\""
        let cmd = createDirCmdPattern.replace("{}", parent)
        if execCmdEx(cmd).exitCode != 0:
          echo "Failed to create parent directory via osproc: ", parent
          quit(1)

    let escapedContent = content.replace("\"", "\\\"").replace("'", "'\\''")
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
      quit(1)

  proc createTestSymlink(linkName: string, targetName: string, isDir: bool = false) =
    var cmd = ""
    when defined(windows):
      cmd = "cmd /c mklink "
      if isDir:
        cmd &= "/D "
      cmd &= "\"" & linkName.absolutePath() & "\" \"" & targetName.absolutePath() & "\""
    else: # POSIX
      cmd = "ln -s \"" & targetName.absolutePath() & "\" \"" & linkName.absolutePath() & "\""

    echo "Executing symlink creation: ", cmd
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      echo "Warning: Failed to create symlink '", linkName, "' -> '", targetName, "'. Output: ", output
    sleep(100)

  test "Basic file and directory listing":
    let testRoot = setupTestDir("basic_listing")
    defer: cleanupTestDir(testRoot)

    createTestFile(testRoot / "file1.txt")
    createDir(testRoot / "subdir1")
    createTestFile(testRoot / "subdir1" / "file2.txt")

    var foundItemsRelative = newSeq[string]()
    for itemPath in find(testRoot, {fsoFile, fsoDir}, @[]):
        foundItemsRelative.add(itemPath.relativePath(testRoot))

    echo "Found items (basic): ", foundItemsRelative

    check(foundItemsRelative.contains("file1.txt"))
    check(foundItemsRelative.contains("subdir1"))
    check(foundItemsRelative.contains("subdir1" / "file2.txt"))
    check(foundItemsRelative.len == 3)

  test "Paths with spaces and Unicode characters":
    let testRoot = setupTestDir("unicode_spaces")
    defer: cleanupTestDir(testRoot)

    let dirWithSpaces = testRoot / "my dir with spaces"
    let fileInDirWithSpaces = dirWithSpaces / "file with spaces.txt"
    createTestFile(fileInDirWithSpaces)

    let dirUnicode = testRoot / "subdir_unicode_éàç"
    let fileInDirUnicode = dirUnicode / "file_unicode_你好.txt"
    createTestFile(fileInDirUnicode)

    var foundItemsRelative = newSeq[string]()
    for itemPath in find(testRoot, {fsoFile, fsoDir}, @[]):
        foundItemsRelative.add(itemPath.relativePath(testRoot))

    echo "Found items (unicode/spaces): ", foundItemsRelative
    check(foundItemsRelative.contains("my dir with spaces"))
    check(foundItemsRelative.contains("my dir with spaces" / "file with spaces.txt"))
    check(foundItemsRelative.contains("subdir_unicode_éàç"))
    check(foundItemsRelative.contains("subdir_unicode_éàç" / "file_unicode_你好.txt"))
    check(foundItemsRelative.len == 4)

  test "Empty directory listing":
    let testRoot = setupTestDir("empty_dir")
    defer: cleanupTestDir(testRoot)

    var count = 0
    for itemPath in find(testRoot, {fsoFile, fsoDir, fsoLink}, @[]):
      inc count

    check(count == 0)

  test "Symbolic link listing (Windows)":
    let testRoot = setupTestDir("symlinks")
    defer: cleanupTestDir(testRoot)

    let actualFile = testRoot / "actual_file.txt"
    let actualDir = testRoot / "actual_dir"
    createTestFile(actualFile, "content")
    createDir(actualDir)
    createTestFile(actualDir / "nested_file.txt", "nested_content")

    let symlinkToFile = testRoot / "s_file.txt"
    let symlinkToDir = testRoot / "s_dir"

    createTestSymlink(symlinkToFile, actualFile, isDir = false)
    createTestSymlink(symlinkToDir, actualDir, isDir = true)

    var foundItemsRelative = newSeq[string]()
    var foundKinds = newSeq[(string, FsoKind)]()

    for itemPath in find(testRoot, {fsoFile, fsoDir, fsoLink}, @[]):
      let relativePath = itemPath.relativePath(testRoot)
      foundItemsRelative.add(relativePath)

      var kind: FsoKind
      # Using std/os procs directly for kind detection in test
      if symlinkExists(itemPath):
          kind = fsoLink
      elif dirExists(itemPath):
          kind = fsoDir
      elif fileExists(itemPath):
          kind = fsoFile
      else:
          kind = fsoUnknown
      foundKinds.add((relativePath, kind))

    echo "Found items (symlinks): ", foundItemsRelative
    echo "Found kinds (symlinks): ", foundKinds

    check(foundItemsRelative.contains("actual_file.txt"))
    check(foundItemsRelative.contains("actual_dir"))
    check(foundItemsRelative.contains("actual_dir" / "nested_file.txt"))
    check(foundItemsRelative.contains("s_file.txt"))
    check(foundItemsRelative.contains("s_dir"))
    check(foundKinds.contains(("s_file.txt", fsoLink)))
    check(foundKinds.contains(("s_dir", fsoLink)))
    check(not foundItemsRelative.contains("s_dir" / "nested_file.txt"))
    check(foundItemsRelative.len == 5)

  test "Interaction with Glob Filters":
    let testRoot = setupTestDir("glob_filters")
    defer: cleanupTestDir(testRoot)

    createTestFile(testRoot / "a.txt")
    createTestFile(testRoot / "b.log")
    createTestFile(testRoot / "c.txt")
    createDir(testRoot / "subdir")
    createTestFile(testRoot / "subdir" / "d.txt")
    createTestFile(testRoot / "subdir" / "e.md")

    var foundItems = newSeq[string]()
    let txtFilter = @[GlobFilter(incl: true, glob: "*.txt")] # GlobFilter from nfind/globs
    for itemPath in find(testRoot, {fsoFile}, txtFilter):
      foundItems.add(itemPath.relativePath(testRoot))
    check(foundItems.contains("a.txt"))
    check(foundItems.contains("c.txt"))
    check(not foundItems.contains("subdir/d.txt")) # *.txt is not recursive by default
    check(foundItems.len == 2)

    foundItems.setLen(0)
    let txtFilterRecursive = @[GlobFilter(incl: true, glob: "**/*.txt")]
    for itemPath in find(testRoot, {fsoFile, fsoDir}, txtFilterRecursive): # Include fsoDir for ** to traverse
      if fileExists(itemPath):
        foundItems.add(itemPath.relativePath(testRoot))
    check(foundItems.contains("a.txt"))
    check(foundItems.contains("c.txt"))
    check(foundItems.contains("subdir/d.txt"))
    check(foundItems.len == 3)

    foundItems.setLen(0)
    let excludeLogFilter = @[
      GlobFilter(incl: true, glob: "**/*"),
      GlobFilter(incl: false, glob: "*.log")
    ]
    for itemPath in find(testRoot, {fsoFile, fsoDir}, excludeLogFilter):
      foundItems.add(itemPath.relativePath(testRoot))
    check(foundItems.contains("a.txt"))
    check(not foundItems.contains("b.log"))
    check(foundItems.contains("c.txt"))
    check(foundItems.contains("subdir"))
    check(foundItems.contains("subdir/d.txt"))
    check(foundItems.contains("subdir/e.md"))
    check(foundItems.len == 5)

    foundItems.setLen(0)
    let subdirFilter = @[GlobFilter(incl: true, glob: "subdir/*")]
    for itemPath in find(testRoot, {fsoFile, fsoDir}, subdirFilter):
        foundItems.add(itemPath.relativePath(testRoot))

    check(foundItems.contains("subdir/d.txt"))
    check(foundItems.contains("subdir/e.md"))
    check(foundItems.len == 2)
