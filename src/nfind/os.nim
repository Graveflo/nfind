import std/oserrors

type FsoKind* = enum
  fsoFile
  fsoDir
  fsoLink
  fsoBlk
  fsoChar
  fsoFifo
  fsoSock
  fsoSpecial
  fsoUnknown

when defined(windows):
  proc maybeOsError*() =
    if osLastError() != OSErrorCode(0):
      raise newOsError(osLastError())

when defined(posix):
  import std/posix

  proc maybeOsError*() =
    if errno != 0:
      raise newOsError(osLastError())
