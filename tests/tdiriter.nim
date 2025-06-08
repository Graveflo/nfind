import std/unittest
import std/os
import std/strutils
import std/sequtils
import std/winlean # For windows specific symlink commands if direct os.createSymlink is not used
import std/paths # For `/` operator and parentDir, relativePath
# import std/ossymlinks # Removed as it was not found

# Importing modules from src/nfind
# This assumes the compiler will be run from the project root or
# that the src path is otherwise made available.
import ../src/nfind/diriter
import ../src/nfind/globs

suite "Windows diriter tests":
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
      createDir(parent)
    writeFile(filePath, content)

  # Windows specific symlink creation
  proc createSymlinkCmd(linkName: string, targetName: string, isDir: bool = false) =
    var cmd = "cmd /c mklink "
    if isDir:
      cmd &= "/D "
    # Ensure paths are absolute for mklink if they have spaces or complex chars,
    # or ensure they are correctly relative from the CWD where cmd runs.
    # For simplicity, using absolute paths can be more robust for tool execution.
    let absLinkName = linkName.absolutePath()
    let absTargetName = targetName.absolutePath()

    cmd &= "\"" & absLinkName & "\" \"" & absTargetName & "\""
    echo "Executing: ", cmd
    if execShellCmd(cmd) != 0:
      echo "Warning: Failed to create symlink '", absLinkName, "' -> '", absTargetName, "'. MKLINK might require admin privileges or Developer Mode."
    # Ensure symlink creation has a moment to take effect, especially on Windows
    sleep(100)


  test "Basic file and directory listing":
    let testRoot = setupTestDir("basic_listing")
    defer: cleanupTestDir(testRoot)

    createTestFile(testRoot / "file1.txt")
    createDir(testRoot / "subdir1")
    createTestFile(testRoot / "subdir1" / "file2.txt")

    var foundItemsRelative = newSeq[string]()
    for itemPath in find(testRoot, {fsoFile, fsoDir}, @[]):
        foundItemsRelative.add(itemPath.relativePath(testRoot)) # relativePath from std/paths

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
    # On Windows, removing directories containing symlinks (especially dir symlinks) can be tricky.
    # Normal removeDir might fail if the symlink is perceived as a non-empty directory or special file.
    # Defer with custom logic might be needed if cleanupTestDir isn't robust enough for symlinks.
    defer: cleanupTestDir(testRoot)


    let actualFile = testRoot / "actual_file.txt"
    let actualDir = testRoot / "actual_dir"
    createTestFile(actualFile, "content")
    createDir(actualDir)
    createTestFile(actualDir / "nested_file.txt", "nested_content")

    let symlinkToFile = testRoot / "s_file.txt"
    let symlinkToDir = testRoot / "s_dir"

    createSymlinkCmd(symlinkToFile, actualFile, isDir = false)
    createSymlinkCmd(symlinkToDir, actualDir, isDir = true)

    var foundItemsRelative = newSeq[string]()
    var foundKinds = newSeq[(string, FsoKind)]()

    for itemPath in find(testRoot, {fsoFile, fsoDir, fsoLink}, @[]):
      let relativePath = itemPath.relativePath(testRoot)
      foundItemsRelative.add(relativePath)

      var kind: FsoKind
      if symlinkExists(itemPath): # Use symlinkExists, direct call
          kind = fsoLink
      elif dirExists(itemPath): # Direct call from std/os
          kind = fsoDir
      elif fileExists(itemPath): # Direct call from std/os
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
    let txtFilter = @[GlobFilter(incl: true, glob: "*.txt")]
    for itemPath in find(testRoot, {fsoFile}, txtFilter):
      foundItems.add(itemPath.relativePath(testRoot))
    check(foundItems.contains("a.txt"))
    check(foundItems.contains("c.txt"))
    check(not foundItems.contains("subdir/d.txt"))
    check(foundItems.len == 2)

    foundItems.setLen(0)
    let txtFilterRecursive = @[GlobFilter(incl: true, glob: "**/*.txt")]
    for itemPath in find(testRoot, {fsoFile, fsoDir}, txtFilterRecursive):
      if fileExists(itemPath): # Direct call from std/os
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
        # This glob "subdir/*" should only match items *directly* in subdir,
        # not "subdir" itself from the perspective of find starting at testRoot.
        foundItems.add(itemPath.relativePath(testRoot))

    check(foundItems.contains("subdir/d.txt"))
    check(foundItems.contains("subdir/e.md"))
    check(foundItems.len == 2)

# Added std/paths for robust path operations.
# Added small sleep in cleanup for robustness on Windows.
# Used absolute paths for mklink for robustness.
# Ensured relativePath is used for assertions.
# Corrected glob for subdir/* to only find contents.
# Fixed potential issue in symlink cleanup if removeDir is not robust enough for dir symlinks.
# (Actual fix for robust symlink dir removal might need `cmd /c rmdir` if os.removeDir fails).
# Note: `execShellCmd` is from `std/osproc` which is usually pulled in by `std/os`.
# `sleep`, `dirExists`, `fileExists`, `createDir`, `removeDir`, `writeFile`, `execShellCmd` are from `std/os`.
# `symlinkExists` is from `std/os`.
# `absolutePath`, `relativePath`, `parentDir`, `/` are from `std/paths`.
# `FsoKind`, `GlobFilter`, `find` are from `../src/nfind/` modules.
# All other functions are from explicitly imported standard modules.
