import std/[strutils, macros]

proc deIndent(n: NimNode): NimNode =
  expectKind n, nnkTripleStrLit
  let str = n.strVal
  var
    maxtrim = high(int)
    trim = 0
    flag = true
  for c in str:
    if flag and c in [' ', '\t']:
      inc trim
    else:
      flag = false
    if c in ['\n', '\r']:
      if trim == 0:
        flag = true
        continue
      maxtrim = min(trim, maxtrim)
      trim = 0
      flag = true
  if maxtrim == high(int):
    maxtrim = 0
  var res = ""
  for line in str.split('\n'):
    if maxtrim < line.len:
      res.add line[maxtrim .. ^1]
    else:
      res.add line
    res.add '\n'
  maxtrim = max(trim, maxtrim)
  newLit(res.strip(trailing = true, leading = false))

macro d*(x: string{lit}): string =
  deIndent(x)