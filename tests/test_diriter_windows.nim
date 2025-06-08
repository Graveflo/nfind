import std/unittest
import std/os
# import std/ospaths # Explicitly import ospaths - removing as it's deprecated and didn't help
# import std/paths    # Trying std/paths - remove as unused and to clear warning
import std/sequtils
import std/strutils
import ../src/nfind/diriter # Adjusted path to diriter.nim
# If FsoKind and find are not automatically exported, they might need explicit import
# from ../src/nfind/diriter import FsoKind, find # Assuming diriter.nim exports these

const testDataBasePath = "tests" / "test_data_windows" / "diriter_test"

proc normalizePathSeq(paths: seq[string]): seq[string] =
  result = newSeq[string](paths.len)
  for i, p in paths:
    var tempPath = p
    normalizePath(tempPath)
    result[i] = tempPath

suite "Windows Directory Iteration Tests":
  test "Iterate Empty Directory":
    let emptyDirPath = testDataBasePath / "empty_dir"
    var itemsFound = 0
    for item in find(emptyDirPath, {fsoFile, fsoDir}, []):
      itemsFound += 1
    check itemsFound == 0

  test "Iterate Non-Empty Directory":
    let nonEmptyDirPath = testDataBasePath / "non_empty_dir"
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
      check tempItem.splitPath.tail != "."      # Using splitPath.tail
      check tempItem.splitPath.tail != ".."      # Using splitPath.tail

    check foundItems.len == expectedItems.len
    for expected in expectedItems:
      check foundItems.contains(expected)

    # Check basenames explicitly
    let foundBasenames = foundItems.map(proc (p: string): string = p.splitPath.tail) # Using splitPath.tail
    let expectedBasenames = @["file1.txt", "file2.log", "sub_dir1"]
    for bn in expectedBasenames:
      check foundBasenames.contains(bn)

  test "Filter Specific File Types":
    let path = testDataBasePath / "non_empty_dir"

    # Test for fsoFile
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

    # Test for fsoDir
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
    let nonExistentPath = testDataBasePath / "non_existent_dir"

    when defined(windows):
      expect OSError:
        for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
          discard item # Should not reach here

      try:
        for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
          discard item
        check false # Should have raised OSError
      except OSError as e:
        check e.msg.contains(nonExistentPath)
        check e.msg.contains("Windows Error Code") # Specific to Windows error message
    else:
      # On non-Windows, current diriter.nim for POSIX returns nil, find iterator yields nothing.
      var itemsFound = 0
      for item in find(nonExistentPath, {fsoFile, fsoDir}, []):
        itemsFound += 1
      check itemsFound == 0 # Expect no items and no error

# Tests are typically run automatically when the file is the main module
# and contains suite/test blocks.
# If not, specific unittest procs like `runAllTests()` might be needed,
# or configuration through .nimble file.
