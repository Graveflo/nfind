import std/[terminal, parseopt, os, enumutils, strutils, osproc, strformat]
import nfind/[diriter, globs, os, util]
import cmdparser

when defined(nimPreviewSlimSystem):
  import std/syncio

const version = 1

type
  ConfigFlags = enum
    cfEchoMatch
    cfEchoNonMatch

  Config = object
    paths = newSeq[string]()
    filters = newSeq[GlobFilter]()
    ftypes = {fsoFile, fsoDir}
    execs = newSeq[ExecutionCheck]()
    flags = {cfEchoMatch}
    matchColor = fgDefault
    nomatchColor = fgRed

when defined(debug):
  let defaultCmdOptions = {poStdErrToStdOut, poUsePath, poEchoCmd}
else:
  let defaultCmdOptions = {poUsePath}

proc doExec(exec: ExecutionCheck; path: string): bool =
  let cmd = exec.sections.join(path)
  var options = defaultCmdOptions
  if EchoCmd in exec.flags:
    options.incl poEchoCmd
  let ret = execCmdEx(
    cmd, options = options, input = if PathToStdIn in exec.flags: path else: ""
  )
  result = ret.exitCode == exec.status
  if NoOutput notin exec.flags and result:
    stdout.write(ret.output)
  elif DisplayFailed in exec.flags:
    stdout.styledWriteLine(fgRed, &"[Status={ret.exitCode}]: ", fgDefault, path)

proc appSpringboard(c: var Config): int =
  if c.paths.len == 0:
    c.paths.add "."
  for path in c.paths:
    if not dirExists(path):
      echo &"directory does not exist: {path}"
      maybeOsError()
      quit(1)
  for dir in c.paths:
    for path in find(dir, c.ftypes, c.filters):
      var match = true
      for e in c.execs:
        if not doExec(e, path):
          match = false
          break
      if match:
        if cfEchoMatch in c.flags:
          when defined(windows): # windows cmd hates ANSI evenin 2025
            echo path
          else:
            stdout.styledWriteLine(c.matchColor, path)
      else:
        if cfEchoNonMatch in c.flags:
          when defined(windows):
            echo path
          else:
            stdout.styledWriteLine(c.nomatchColor, path)
  return 0

proc main(): int =
  var c = Config()
  let helpMenu =
    &d"""
    syntax:
      nfind (path ..) (-i:glob ..) (-e:glob ..) (--exec:cmd ..) (-t:filetypes) (--help[:glob,:exec,:flags])
    
    - multiple paths can be specified as bare arguments
    - if no paths are specified '.' is implied
    - if no inclusion filters are specified "**" is implied as the least priority filter
    - glob filters are evaluated in the order they are specified
      -- see '--help:glob'
    - file types are given all in one ex: -t:File,Dir,Link
    - exec specifies a command to run as a filter for each file passing the glob filters
      -- the exit status of the command determines filter's acceptance
      -- see '--help:exec'
    - use '--e!' and '--i!' for inverted filters

    version: {version} 
    """
  let globHelp =
    d"""
  the glob rules are from VSCode's documentation, so you can look that up to maybe get a better explination.
  below is a short synopsis:
  globs sperate path segments with a / character on all platforms
  '*'  matches 0 or more characters in a single segment
  '**' matches 0 or more segments
  '?'  matches a single character
  '{}' is an "or"-like expansion with choices seperated by a comma
  '[]' specifies a range of characters and may start with '[!' to negate
  '\'  is the escape character - this also means all glob paths use / as dir separator regardless of OS
  
  - you may want to wrap glob patterns in "" since some shells like to expand them on their own
  - the order which globs are specified matters as a match immediately terminates the glob filtering stage
    - '-e:"**" -i:"**/*.txt"' will always exclude everything since the catch-all happens first
  """
  let execHelp =
    &d"""
  execution follows this syntax:
    (cmd)->status(,flag ..)
  - a simple command does not need to use '()' and '->'
  - the default accepted status is 0
  - adding the string {nimFindExecDelim} in the command substitutes the found path
    - e.x. '--exec:"stat {nimFindExecDelim}"' will stat each file found
  Flags are:
    NoOutput      : Do not display the program's output
    DisplayFailed : Display failed runs
    PathToStdin   : Put the path of the found file on stdin
    DirectIO      : Give the process stdout and stderr from the console for tty behaviors
    EchoCmd       : Echo the command
  
  an example with flags and return value:
    --exec:"(stat {nimFindExecDelim})->1,EchoCmd,NoOutput"
  - run stat command on each file passing glob filters
  - echo the command and aguments to stat including substitutions of '{nimFindExecDelim}'
  - will not display the output of the stat command
  - filters out any path where the exit status of the stat command != 1
  """
  let flagsHelp =
    d"""
  flags:
    EchoMatch     (default) print paths that match to stdout
    EchoNonMatch  print paths that do not match to stdout
  
  - flags can be turned off by prepending "no" e.x. "noEchoMatch"
  - each flag requires it's own '--' argument e.x. '--noEchoMatch'
  """
  template fail() =
    echo &"unrecognized argument(s): '{key}' '{val}'"
    echo ""
    echo helpMenu
    quit(1)

  for kind, key, val in getopt():
    case kind
    of cmdArgument:
      c.paths.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "i":
        c.filters.add GlobFilter(incl: true, glob: val)
      of "e":
        c.filters.add GlobFilter(incl: false, glob: val)
      of "i!":
        c.filters.add GlobFilter(incl: true, glob: val, inverted: true)
      of "e!":
        c.filters.add GlobFilter(incl: false, glob: val, inverted: true)
      of "exec":
        var exe = default(ExecutionCheck)
        if parseExecutionCheck(exe, val):
          c.execs.add exe
        else:
          echo &"error parsing execution: {val}"
          quit(1)
      of "t":
        c.ftypes = {}
        for part in val.split(','):
          try:
            c.ftypes.incl parseEnum[FsoKind](&"fso{part}")
          except ValueError:
            echo &"bad filetype flag: {part}"
            quit(1)
      of "help":
        case val
        of "glob", "globs":
          echo globHelp
        of "exec":
          echo execHelp
        of "flags":
          echo flagsHelp
        else:
          echo helpMenu
        quit(0)
      else:
        try:
          if val.startsWith("no"):
            c.flags.excl parseEnum[ConfigFlags](&"cf{val[2 .. ^1]}")
          else:
            c.flags.incl parseEnum[ConfigFlags](&"cf{val}")
        except ValueError:
          fail()
    of cmdEnd:
      break
  appSpringboard(c)

when isMainModule:
  quit(main())
