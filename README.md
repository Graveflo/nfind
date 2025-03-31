# Nim glob library


example usage:
```nim
import nfind/diriter

let filters =
  @[
    GlobFilter(incl: false, glob: "*/*/**"),
    GlobFilter(incl: true, glob: "*.{nim,nims}", inverted: true),
  ]

for path in find(".", {fsoFile}, filters):
  echo path
```

lists every file in pwd that does not have a nim extension.

that's pretty much it.. The glob logic is designed to be efficient for walking
directories.

## nfind program

With the library is an implementation of a find utility. I made it because I always forget the
syntax for unix find. It's a simple example of how to use the library. Below are the help menus
for the program.

build with:
```bash
nim -d:danger buildNFind
```

```
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

version: 1
```

```
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
```

this idea could use some work, but meh:
```
execution follows this syntax:
  (cmd)->status(,flag ..)
- a simple command does not need to use '()' and '->'
- the default accepted status is 0
- adding the string {} in the command substitutes the found path
  - e.x. '--exec:"stat {}"' will stat each file found
Flags are:
  NoOutput      : Do not display the program's output
  DisplayFailed : Display failed runs
  PathToStdin   : Put the path of the found file on stdin
  DirectIO      : Give the process stdout and stderr from the console for tty behaviors
  EchoCmd       : Echo the command

an example with flags and return value:
  --exec:"(stat {})->1,EchoCmd,NoOutput"
- run stat command on each file passing glob filters
- echo the command and aguments to stat including substitutions of '{}'
- will not display the output of the stat command
- filters out any path where the exit status of the stat command != 1
```

```
flags:
  EchoMatch     (default) print paths that match to stdout
  EchoNonMatch  print paths that do not match to stdout

- flags can be turned off by prepending "no" e.x. "noEchoMatch"
- each flag requires it's own '--' argument e.x. '--noEchoMatch'
```
