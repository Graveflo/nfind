import std/[strutils, os]

type
  GlobFilter* = object
    incl*: bool
    inverted* = false
    glob*: string

  # this approach keeps GlobState small for performance
  StateFlags* = enum
    sfMatch
    sfSoft # path additions may change result
    sfCaseInsensitive

  StateKind = enum
    skInsensitive

  GlobState* = object
    gt* = 0
    pt* = 0
    match* = {sfSoft}

template `+=`(a, b: set): untyped =
  a = a + b

type ValidationVoilation* = enum
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

type GlobValidation = object
  gt = 0
  djd = 0
  starstar = -1

iterator disjointSections(glob: string; gt: var int): int =
  var djd = 0
  yield gt
  inc gt
  while gt < glob.len:
    case glob[gt]
    of ',':
      if djd == 0:
        inc gt
        yield gt
    of '{':
      inc djd
    of '}':
      dec djd
      if djd <= 0:
        break
    of '\\':
      inc gt
    else:
      discard
    inc gt

proc validateGlob*(glob: string; v: var GlobValidation): ValidationVoilation =
  result = vioNone
  template gt(): untyped =
    v.gt

  template djd(): untyped =
    v.djd

  while gt < glob.len:
    if v.starstar > -1:
      if glob[gt] notin ['{', '}', ','] and glob[gt] != '/':
        return vioDoubleStarSegment
    else:
      v.starstar = -1
    case glob[gt]
    of '*':
      inc gt
      if gt < glob.len and glob[gt] == '*':
        v.starstar = gt
        inc gt
        return validateGlob(glob, v)
    of '{':
      inc gt
      for start in disjointSections(glob, gt):
        var tmp = GlobValidation(gt: start, djd: djd + 1, starstar: v.starstar)
        let trial = validateGlob(glob, tmp)
        if trial > vioNone:
          v.starstar = tmp.starstar
          v.gt = tmp.gt
          return trial
    of '}':
      djd = max(0, djd - 1)
      inc gt
    of ',':
      if djd > 0:
        skipDepth(glob, gt)
        dec djd
      else:
        inc gt
    of '\\':
      inc gt, 2
    of '/':
      inc gt
      v.starstar = -1
      if gt < glob.len and glob[gt] == '/':
        return vioDoubleSep
    else:
      inc gt
  if djd != 0:
    result = vioUnclosedDisjoint

proc validateGlob*(glob: string): bool =
  var val = GlobValidation()
  validateGlob(glob, val) == vioNone

proc globViolation*(glob: string): ValidationVoilation =
  var val = GlobValidation()
  validateGlob(glob, val)

proc globIncl*(glob: sink string): GlobFilter =
  GlobFilter(incl: true, glob: glob)

proc globExcl*(glob: sink string): GlobFilter =
  GlobFilter(incl: false, glob: glob)

proc globPositionMonoFmt(glob: string; v: GlobValidation): string =
  result = glob
  result &= '\n'
  for i in 0 ..< max(len(glob), v.gt + 1):
    if i == v.gt:
      result &= '^'
    elif i == v.starstar:
      result &= '^'
    else:
      result &= ' '

proc validateGlobCompileTime*(glob: static string) {.compileTime.} =
  var gt = GlobValidation()
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

proc matchGlob*(
    path: string; glob: string; state: var GlobState; sdr = 0
) {.raises: [].} =
  var
    pt = state.pt
    gt = state.gt
    sd = sdr

  template comitState() =
    if sdr == 0:
      state.pt = pt
      state.gt = gt

  template st(): untyped =
    state.st

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
      if sfCaseInsensitive notin state.match or x.toLowerAscii != path[pt].toLowerAscii:
        state.match = {}
        break
    inc pt
    inc gt

  template norm() =
    norm(glob[gt])

  while true:
    if gt >= glob.len:
      if pt >= pathLen:
        state.match += {sfMatch, sfSoft}
      else:
        state.match = {}
      break
    echoGlobDbg "glob part: ", glob[gt ..^ 1]
    if pt >= pathLen and glob[gt] notin {'{', '*', '('} and
        (sdr <= 0 or glob[gt] notin {',', '}'}):
      echoGlobDbg "path end: ", glob[gt ..^ 1], " : ", state.match
      state.match = {sfSoft}
      let onSep = glob[gt] == '/'
      if onSep:
        inc gt
      if gt + 2 == glob.len:
        if glob[gt] == '*' and glob[gt + 1] == '*':
          state.match = {sfMatch}
        elif glob[gt] == '{' and glob[gt + 1] == '}':
          state.match.incl sfMatch
      elif gt + 1 == glob.len and not onSep:
        if glob[gt] == '*':
          state.match.incl sfMatch
      elif gt == glob.len:
        state.match.incl sfMatch
      break
    echoGlobDbg "path part: ", path[pt ..^ 1]
    case glob[gt]
    of '/':
      norm(DirSep)
      comitState()
    of '*':
      inc gt
      # single * (special cases)
      while gt < glob.len and glob[gt] == '}' and sd > 0:
        inc gt
        dec sd
      if gt >= glob.len:
        while pt < pathLen:
          if path[pt] == DirSep:
            state.match = {}
            break
          inc pt
      elif glob[gt] == '/':
        while pt < pathLen and path[pt] != DirSep:
          inc pt
      elif glob[gt] == '*': # **
        echoGlobDbg "starstar"
        while true:
          inc gt
          if gt >= glob.len: # glob ends with **
            state.match = {sfMatch}
            return
          elif glob[gt] == '}' and sd > 0:
            dec sd
          else:
            break
        # XXX: '**.txt' for example is not supported can ensure **/ here for safety
        inc gt # this gets rid of '/'
        while true:
          var gs = GlobState(gt: gt, pt: pt, match: state.match)
          matchGlob(path, glob, gs, sdr = sd)
          echoGlobDbg "starstar return: ", gs.match, " : ", glob[gs.gt ..^ 1]
          if sfMatch in gs.match:
            state.match = gs.match
            return
          else:
            pt = path.find(DirSep, start = pt, last = pathLen) + 1
            if pt < 1:
              break
        state.match = {sfSoft}
        break
      else: # single *
        echoGlobDbg "single star"
        var
          best: set[StateFlags] = {}
          startPt = pt
        while true:
          var gs = GlobState(gt: gt, pt: startPt, match: state.match)
          matchGlob(path, glob, gs, sdr = sd)
          if sfMatch in gs.match:
            state.match = gs.match
            return
          if sfSoft in gs.match:
            best.incl sfSoft
          if startPt >= pathLen or path[startPt] == DirSep:
            break
          inc startPt
        if startPt >= pathLen:
          best = {}
        state.match = best
        break
    of '?':
      if path[pt] == DirSep:
        state.match = {}
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
          state.match = {}
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
        bestState = GlobState(match: {})
        hasBest = false
      while true:
        gs = GlobState(gt: gt, pt: pt, match: state.match)
        echoGlobDbg "{ recurse"
        matchGlob(path, glob, gs, sdr = sd)
        echoGlobDbg "{ returned: ",
          glob[gs.gt .. ^1], " : ", gs.match, " : ", path[gs.pt ..^ 1]
        if sfMatch in gs.match:
          state = gs
          return
        if not hasBest or gs.match > bestState.match:
          bestState = gs
          hasBest = true

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
              if sfMatch notin gs.match:
                # previous attempt didn't work, so we stop here
                # i.e. not hunting for '}'
                inc gt
                break
          else:
            discard
          inc gt
        if depth <= 0 and retc == -1:
          break

      if hasBest:
        state = bestState
      else:
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
        inc gt
        dec sd
        echoGlobDbg "special }"
      else:
        norm()
    of '(':
      let bu = gt
      inc gt
      if gt < len(glob) and glob[gt] == '?':
        inc gt
        if gt < len(glob):
          var isMinus =
            if glob[gt] == '-':
              inc gt
              true
            else:
              false
          if gt < len(glob) and glob[gt] == 'i':
            inc gt
            if gt < len(glob) and glob[gt] == ')':
              if isMinus:
                state.match.excl sfCaseInsensitive
              else:
                state.match.incl sfCaseInsensitive
              inc gt
              continue
      gt = bu
      norm()
    of '\\':
      gt = min(gt + 1, len(glob) - 1)
      norm()
    else:
      norm()

proc matchGlob*(path: string; glob: string): GlobState =
  result = GlobState()
  matchGlob(path, glob, result)

proc invert(k: var set[StateFlags]) =
  # k = k xor {sfMatch}
  if sfMatch in k:
    k.excl sfMatch
  else:
    k.incl sfMatch

proc findFirstGlob*(
    path: string; filters: openArray[GlobFilter]; states: var openArray[GlobState]
): int =
  result = -1
  for i in 0 ..< states.len:
    if sfSoft in states[i].match:
      matchGlob(path, filters[i].glob, states[i])
      if filters[i].inverted:
        invert(states[i].match)
      if sfMatch in states[i].match:
        result = i
        break
    elif sfMatch in states[i].match:
      result = i
      break

proc findFirstGlob*(path: string; filters: openArray[GlobFilter]): int =
  for i in 0 ..< filters.len:
    var state = GlobState()
    matchGlob(path, filters[i].glob, state)
    if sfMatch in state.match:
      return i
  return -1

proc includes*(path: string; filters: openArray[GlobFilter]): bool =
  result = false
  let pos = findFirstGlob(path, filters)
  if pos > -1:
    result = filters[pos].incl

proc nextSection(glob: string; gt: var int) =
  var depth = 0
  while gt < glob.len:
    case glob[gt]
    of '{':
      inc depth
    of '}':
      if depth > 0:
        dec depth
    of ',':
      if depth == 0:
        return
    of '\\':
      inc gt
      if gt >= glob.len:
        dec gt
    else:
      discard
    inc gt

iterator iterExpansions*(glob: string; gts = 0; depths = 0): string {.closure.} =
  result = ""
  var
    gt = gts
    depth = depths
  while gt < glob.len:
    case glob[gt]
    of '{':
      while gt < glob.len and glob[gt] != '}':
        inc gt
        for np in iterExpansions(glob, gts = gt, depths = depth + 1):
          yield result & np
        nextSection(glob, gt)
      return
    of '}':
      if depth > 0:
        dec depth
      else:
        result.add glob[gt]
    of ',':
      if depth > 0:
        skipDepth(glob, gt)
        continue
      else:
        result.add glob[gt]
    of '\\':
      inc gt
      if gt >= glob.len:
        dec gt
    else:
      result.add glob[gt]
    inc gt
  yield result
