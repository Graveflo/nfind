import std/[strutils, os]

type
  FsoKind* = enum
    fsoFile
    fsoDir
    fsoLink
    fsoBlk
    fsoChar
    fsoFifo
    fsoSock
    fsoSpecial
    fsoUnknown

  GlobFilter* = object
    incl*: bool
    inverted* = false
    glob*: string

  MatchKind* = enum
    InDisjoint
    # Below are actual return values
    NoFurtherMatch
    NoMatch
    Match
    AllFurtherMatch

  GlobState* = object
    gt* = 0
    pt* = 0
    match* = NoMatch

proc validateGlob*(glob: string): bool =
  result = true
  var
    gt = 0
    djd = 0
  template adv() =
    inc gt
    if gt >= glob.len:
      return false

  while gt < glob.len:
    case glob[gt]
    of '*':
      inc gt
      if gt < glob.len and glob[gt] == '*':
        inc gt
        if gt < glob.len and glob[gt] != '/':
          return false
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
        return false
    else:
      inc gt
  result = result and djd == 0

proc matchGlob*(path: string; glob: string; state: var GlobState) =
  var
    pt = state.pt
    gt = state.gt
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
    if pt >= pathLen and (state.match != InDisjoint and glob[gt] != '{'):
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
    case glob[gt]
    of '*':
      if gt + 1 < glob.len and glob[gt + 1] == '*': # **
        if gt + 2 >= glob.len: # glob ends with **
          state.match = AllFurtherMatch
          break
        else:
          var flag = true
          while flag:
            # XXX: '**.txt' for example is not supported can ensure **/ here for safety
            var gs = GlobState(gt: gt + 3, pt: pt, match: state.match)
            matchGlob(path, glob, gs)
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
            matchGlob(path, glob, gs)
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
      var
        gs = state
        retc = gt
        retpt = pt
      while true:
        gs = GlobState(gt: gt, pt: pt, match: InDisjoint)
        matchGlob(path, glob, gs)
        if gs.match >= Match:
          pt = gs.pt
          if gs.gt == gt:
            break

        if retc > -1:
          if gs.match < Match:
            gt = retc
            pt = retpt
            retc = -1
          else:
            gt = gs.gt - 1

        var depth = 1
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
            inc gt
          of ',':
            if depth == 1 and retc == -1:
              retc = gt + 1
              retpt = pt
              if gs.match < Match:
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
      if state.match == InDisjoint:
        state.match = Match
        state.gt = gt + 1
        state.pt = pt
        break
      else:
        norm()
    of '}':
      if state.match == InDisjoint:
        state.gt = gt + 1
        state.match = Match
        state.pt = pt
        break
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
  of InDisjoint: Match
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
