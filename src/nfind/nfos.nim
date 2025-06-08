import std/oserrors

when defined(windows):
  proc maybeOsError*() =
    if osLastError() != OSErrorCode(0):
      raise newOsError(osLastError())

when defined(posix):
  import std/posix

  proc maybeOsError*() =
    if errno != 0:
      raise newOsError(osLastError())
