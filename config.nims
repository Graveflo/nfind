import std/[strformat, strutils, os, compilesettings]

switch("path", "src")

let projectPath = when defined(mingw):
    getCurrentDir().parentDir().replace("\\", "/")
  else:
    getCurrentDir().parentDir()

proc getCommandlineOptions(): seq[string] =
  result = @[]
  for part in querySetting(SingleValueSetting.commandLine).split(" "):
    if part == querySetting(SingleValueSetting.command):
      break
    else:
      result.add part

proc doBuild(src: string, cmdln: seq[string] = @[]) =
  if not dirExists("bin"):
    mkDir("bin")
  var
    fn = src.splitFile[1]
    outp = &"bin/{fn}"
  when defined(mingw):
    outp &= ".exe"
  var extra = getCommandlineOptions()
  for opt in cmdln:
    extra.add opt
  let expan = extra.join(" ")
  echo expan
  selfExec(&"{expan} -o:{outp} c {src}")


task buildNFind, "builds nfind":
  doBuild("nfind.nim", @["--stacktrace:off", "--mm:arc", "--threads:off"])

