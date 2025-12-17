import std/[strutils, os]

type
  GlobFilter* = object
    incl*: bool
    inverted* = false
    glob*: string

  MatchKind* = enum
    NoFurtherMatch
    NoMatch
    Match
    AllFurtherMatch

  GlobState* = object
    gt* = 0
    pt* = 0
    match* = NoMatch

type ValidationVoilation = enum
  vioNone
  vioDoubleStarSegment
  vioDoubleSep
  vioUnclosedDisjoint

proc violationToString(v: ValidationVoilation): string =
  case v
  of vioNone:
    "no error"
  of vioDoubleStarSegment:
    "double star cannot share path segment with other patterns (missing /)"
  of vioDoubleSep:
    "double segment delimiter"
  of vioUnclosedDisjoint:
    "unclosed disjoint"

proc validateGlob*(glob: string; gt: var int): ValidationVoilation =
  result = vioNone
  var djd = 0

  while gt < glob.len:
    case glob[gt]
    of '*':
      inc gt
      if gt < glob.len and glob[gt] == '*':
        inc gt
        var djn = djd
        while gt < glob.len and djn > 0 and glob[gt] == '}':
          dec djn
          djd = max(0, djd - 1)
          inc gt
        if gt < glob.len and glob[gt] != '/':
          return vioDoubleStarSegment
        inc gt
    of '{':
      inc djd
      inc gt
    of '}':
      djd = max(0, djd - 1)
      inc gt
    of '\\':
      inc gt, 2
    of '/':
      inc gt
      if gt < glob.len and glob[gt] == '/':
        return vioDoubleSep
    else:
      inc gt
  if djd != 0:
    result = vioUnclosedDisjoint

proc validateGlob*(glob: string): bool =
  var col = 0
  validateGlob(glob, col) == vioNone

proc globIncl*(glob: sink string): GlobFilter =
  GlobFilter(incl: true, glob: glob)

proc globExcl*(glob: sink string): GlobFilter =
  GlobFilter(incl: false, glob: glob)

proc globPositionMonoFmt(glob: string; gt: int): string =
  result = glob
  result &= '\n'
  for i in 0 ..< gt:
    result &= ' '
  result &= '^'

proc validateGlobCompileTime(glob: static string) {.compileTime.} =
  var gt = 0
  let rt = validateGlob(glob, gt)
  if rt != vioNone:
    echo "invalid glob: " & violationToString(rt)
    quit globPositionMonoFmt(glob, gt)

proc globIncl*(glob: static string): GlobFilter =
  static:
    validateGlobCompileTime(glob)
  GlobFilter(incl: true, glob: glob)

proc globExcl*(glob: static string): GlobFilter =
  static:
    validateGlobCompileTime(glob)
  GlobFilter(incl: false, glob: glob)

template echoGlobDbg(ts: varargs[untyped]): untyped =
  when defined(debugGlob):
    debugEcho ts
  else:
    discard

func skipDepth(glob: string; gt: var int) {.inline.} =
  var depth = 1
  while gt < len(glob) and depth > 0:
    case glob[gt]
    of '{':
      inc depth
    of '}':
      dec depth
    of '\\':
      inc gt # escaped char is skipped at end of loop
    else:
      discard
    inc gt

proc matchGlob*(path: string; glob: string; state: var GlobState; sdr = 0) =
  var
    pt = state.pt
    gt = state.gt
    sd = sdr
  let pathLen =
    if (len(path) > 0) and (path[^1] == DirSep):
      len(path) - 1
    else:
      len(path)
  if pt == 0 and pathLen > 0 and path[0] == '.':
    inc pt
    if (pt < path.len) and (path[pt] == DirSep):
      inc pt
      if gt == 0 and glob.len > 1 and glob[0] == '.' and glob[1] == '/':
        inc gt, 2
    else:
      dec pt

  template norm(x) =
    echoGlobDbg "norm(g==p): ", path[pt], " == ", x
    if path[pt] != x:
      state.match = NoFurtherMatch
      break
    inc pt
    inc gt

  template norm() =
    norm(glob[gt])

  while true:
    if gt >= glob.len:
      if pt >= pathLen:
        state.match = Match
      else:
        state.match = NoFurtherMatch
      break
    echoGlobDbg "glob part: ", glob[gt ..^ 1]
    if pt >= pathLen and glob[gt] != '{' and not (sdr > 0 and glob[gt] in [',', '}']):
      echoGlobDbg "path end: ", glob[gt ..^ 1], " : ", state.match
      state.match = NoMatch
      var onSep = glob[gt] == '/'
      if onSep:
        inc gt
      if gt + 2 == glob.len:
        if glob[gt] == '*' and glob[gt + 1] == '*':
          state.match = AllFurtherMatch
        elif glob[gt] == '{' and glob[gt + 1] == '}':
          state.match = Match
      elif gt + 1 == glob.len and not onSep:
        if glob[gt] == '*':
          state.match = Match
      elif gt == glob.len:
        state.match = Match
      break
    echoGlobDbg "path part: ", path[pt ..^ 1]
    case glob[gt]
    of '*':
      if gt + 1 < glob.len and glob[gt + 1] == '*': # **
        echoGlobDbg "starstar"
        inc gt, 2
        if gt >= glob.len: # glob ends with **
          state.match = AllFurtherMatch
          break
        else:
          # this might not be /
          if glob[gt] == '}':
            skipDepth(glob, gt)
          # XXX: '**.txt' for example is not supported can ensure **/ here for safety
          inc gt # this gets rid of '/'
          var flag = true
          while flag:
            var gs = GlobState(gt: gt, pt: pt, match: state.match)
            matchGlob(path, glob, gs, sdr = sd)
            echoGlobDbg "starstar return: ", gs.match, " : ", glob[gs.gt ..^ 1]
            if gs.match >= Match:
              state = gs
              flag = false
            else:
              pt = path.find(DirSep, start = pt, last = pathLen) + 1
              if pt < 1:
                break
          if flag:
            state.match = NoMatch
          break
      else: # single *
        echoGlobDbg "single star"
        if glob[gt] == '}':
          skipDepth(glob, gt)
        inc gt
        if gt >= glob.len:
          var flag = false
          while pt < pathLen:
            if path[pt] == DirSep:
              flag = true
              state.match = NoFurtherMatch
              break
            inc pt
          if flag:
            break
        elif glob[gt] == '/':
          while pt < pathLen and path[pt] != DirSep:
            inc pt
        else:
          var best = NoFurtherMatch
          while pt < pathLen and path[pt] != DirSep:
            var gs = GlobState(gt: gt, pt: pt, match: state.match)
            matchGlob(path, glob, gs, sdr = sd)
            if gs.match >= Match:
              state = gs
              return
            inc pt
            if gs.match > best:
              best = gs.match
          state.match = best
          break
    of '?':
      if path[pt] == DirSep:
        state.match = NoFurtherMatch
        break
      inc pt
      inc gt
    of '[':
      let rest = gt
      inc gt
      if gt >= glob.len:
        dec gt
        norm()
      else:
        let inverted = glob[gt] == '!'
        if inverted:
          inc gt
          if gt >= glob.len:
            gt = rest
            norm()
            continue
        var
          matches = false
          bail = false
        while true:
          if glob[gt] == '\\':
            inc gt
            if gt >= glob.len:
              dec gt
          let w = glob[gt]
          inc gt
          if gt >= glob.len:
            bail = true
            break
          if path[pt] == w:
            matches = true
          case glob[gt]
          of ']':
            break
          of '-':
            inc gt
            if gt >= glob.len:
              bail = true
              break
            if not matches:
              if glob[gt] == ']': # posix glob compat
                matches = path[pt] == '-'
                break
              else:
                matches = path[pt] in w .. glob[gt]
          else:
            discard
        if bail:
          gt = rest
          norm()
        elif matches == inverted:
          state.match = NoFurtherMatch
          break
        else:
          inc gt
          inc pt
    of '{':
      inc gt
      inc sd
      var
        gs = state
        retc = gt # tracks the option position for resets
        retpt = pt
      while true:
        gs = GlobState(gt: gt, pt: pt, match: state.match)
        matchGlob(path, glob, gs, sdr = sd)
        echoGlobDbg "{ returned: ",
          glob[gs.gt .. ^1], " : ", gs.match, " : ", path[gs.pt ..^ 1]
        if gs.match >= Match:
          state.match = gs.match
          return

        if retc > -1:
          # this means the recursion ended with match in this position
          if gs.gt < len(glob) and glob[gs.gt] in [',', '}']:
            gt = gs.gt
            pt = gs.pt
          else:
            # faild. reset the position to trigger advancing to the next one
            gt = retc
            pt = retpt
            retc = -1

        var depth = 1
        # we skip over inner-depths here since they are handled by recursion
        while gt < len(glob):
          case glob[gt]
          of '{':
            inc depth
          of '}':
            dec depth
            if depth <= 0:
              inc gt
              break
          of '\\':
            inc gt # escaped char is skipped at end of loop
          of ',':
            if depth == 1 and retc == -1:
              retc = gt + 1
              retpt = pt
              if gs.match < Match:
                # previous attempt didn't work, so we stop here
                # i.e. not hunting for '}'
                inc gt
                break
          else:
            discard
          inc gt
        if gt >= len(glob):
          if gs.pt < pathLen or gs.match == NoMatch:
            gs.match = NoMatch
            if retc > -1:
              continue
          break

      state.match = gs.match
      return
    of ',':
      if sdr > 0:
        skipDepth(glob, gt)
        echoGlobDbg "special ,"
      else:
        norm()
    of '}':
      if sdr > 0:
        skipDepth(glob, gt)
        echoGlobDbg "special }"
      else:
        norm()
    of '/':
      norm(DirSep)
      state.pt = pt
      state.gt = gt
    of '\\':
      gt = min(gt + 1, len(glob) - 1)
      norm()
    else:
      norm()

proc matchGlob*(path: string; glob: string): GlobState =
  result = GlobState()
  matchGlob(path, glob, result)

proc invert(k: MatchKind): MatchKind =
  case k
  of NoFurtherMatch: AllFurtherMatch
  of NoMatch: Match
  of Match: NoMatch
  of AllFurtherMatch: NoFurtherMatch

proc findFirstGlob*(
    path: string; filters: openArray[GlobFilter]; states: var openArray[GlobState]
): int =
  result = -1
  for i in 0 ..< states.len:
    case states[i].match
    of NoFurtherMatch:
      continue
    of AllFurtherMatch:
      result = i
      break
    else:
      matchGlob(path, filters[i].glob, states[i])
      if filters[i].inverted:
        states[i].match = invert(states[i].match)
      if states[i].match >= Match:
        result = i
        break

proc findFirstGlob*(path: string; filters: openArray[GlobFilter]): int =
  for i in 0 ..< filters.len:
    var state = GlobState()
    matchGlob(path, filters[i].glob, state)
    if state.match >= Match:
      return i
  return -1

proc includes*(path: string; filters: openArray[GlobFilter]): bool =
  result = false
  let pos = findFirstGlob(path, filters)
  if pos > -1:
    result = filters[pos].incl
