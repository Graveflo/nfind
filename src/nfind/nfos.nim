# Placeholder for FsoKind definition
# This file might have originally contained this or similar.

type
  FsoKind* = enum # Export marker on the type itself
    fsoFile, fsoDir, fsoLink, # No '*' on individual members
    fsoBlk, fsoChar, fsoFifo, fsoSock,
    fsoSpecial,
    fsoUnknown

# The maybeOsError procs can remain if they were the original content.
# Adding them back based on previous read_files output.
import std/oserrors

when defined(windows):
  proc maybeOsError*() =
    if osLastError() != OSErrorCode(0):
      raise newOsError(osLastError())

when defined(posix):
  import std/posix # This was missing in one of the reads, ensure it's here for errno

  proc maybeOsError*() =
    if errno != 0: # errno from posix
      raise newOsError(osLastError())
