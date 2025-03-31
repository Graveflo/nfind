import std/[os, strutils, terminal, strformat, sequtils]
when defined(nimPreviewSlimSystem):
  import std/syncio
const nimFindExecDelim* = "{}"

type
  ExecutionFlags* = enum
    NoOutput
    DisplayFailed
    PathToStdin
    DirectIO
    EchoCmd

  ExecutionCheck* = object
    exec*: string
    status* = 0
    flags*: set[ExecutionFlags] = {}
    sections*: seq[string]

  ExecParseState = enum
    Initial
    ExitCode
    Args

proc splitExecSections(e: var ExecutionCheck) =
  let exec = e.exec
  var i = 0
  while i < exec.len:
    var pos = exec.find(nimFindExecDelim, i)
    if pos < 0:
      e.sections.add exec[i .. ^1]
      return
    else:
      e.sections.add exec[i ..< pos]
    i = pos + nimFindExecDelim.len
    if i == exec.len:
      e.sections.add ""

proc parseExecutionCheck*(dst: var ExecutionCheck; val: string): bool =
  result = true
  dst.status = 0
  dst.flags = {}
  dst.exec = newStringOfCap(val.len)

  var i = 0
  template skipSpace(over: untyped) =
    while i < val.len and val[i] == ' ':
      inc i
    if i >= val.len:
      over

  skipSpace:
    dst.exec = val
    return true
  var pCount = 1
  if val[i] == '(':
    inc i

  template syntaxErrorUnexpectedCharacter(pos: int; ch: char) {.dirty.} =
    let character =
      if ch == chr(0):
        "EOF"
      else:
        $ch
    let posf = pos
    stdout.styledWriteLine(
      fgRed,
      "syntax error: ",
      fgDefault,
      &"unexpected character {character} at position {posf} for command {val[0..<posf]}",
      bgRed,
      fgBlack,
      &"{val[posf..^1]}",
    )
    return false

  template syntaxErrorUnexpectedCharacter(pos: int) =
    let ch =
      if pos >= val.len:
        chr(0)
      else:
        val[pos]
    syntaxErrorUnexpectedCharacter(pos, ch)

  template parseFlag() =
    if working.len > 0:
      try:
        dst.flags.incl parseEnum[ExecutionFlags](working)
        working.setLen(0)
      except ValueError:
        stdout.styledWriteLine(
          fgRed,
          "syntax error: ",
          fgDefault,
          &"unexpected flag value {working} at position {i-working.len} for command {val[0..i-working.len-1]}",
          bgRed,
          fgBlack,
          val[i - working.len ..< i],
          fgDefault,
          bgDefault,
          &"{val[i..^1]}",
        )
        echo "Acceptable values are:"
        echo toSeq(ExecutionFlags.items).join(", ")
        return false

  var ps = false
  while pCount > 0:
    if i >= val.len:
      break
    let c = val[i]
    case c
    of '\\':
      ps = true
      dst.exec.add c
    of '(':
      if ps:
        dst.exec[i - 1] = c
        ps = false
      else:
        inc pCount
    of ')':
      if ps:
        dst.exec[i - 1] = c
        ps = false
      else:
        dec pCount
    else:
      dst.exec.add c
    inc i
  splitExecSections(dst)
  skipSpace:
    return true
  var state = Initial
  var status = newStringOfCap(val.len - i)
  var working = ""
  while i < val.len:
    case val[i]
    of '-':
      if state == Initial:
        inc i
        if i >= val.len or val[i] != '>':
          syntaxErrorUnexpectedCharacter(i - 1, '-')
        inc i
        state = ExitCode
        skipSpace:
          syntaxErrorUnexpectedCharacter(i)
        while i < val.len and val[i].ord >= ord('0') and val[i].ord <= ord('9'):
          status.add val[i]
          inc i
        if status.len < 0:
          syntaxErrorUnexpectedCharacter(i)
        dst.status = parseInt(status)
        state = Args
      else:
        syntaxErrorUnexpectedCharacter(i)
    of ',':
      if state == Args:
        parseFlag()
      inc i
    else:
      if state == Args:
        working.add val[i]
      inc i
    skipSpace:
      break
  parseFlag()
