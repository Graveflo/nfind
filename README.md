# Nim glob library


example usage:
```nim
import nfind/diriter

let filters =
  @[
    globExcl"*/*/**",
    GlobFilter(incl: true, glob: "*.{nim,nims}", inverted: true),
  ]

for path in find(".", {fsoFile}, filters):
  echo path
```

lists every file in pwd that does not have a nim extension.
Convoluted for demonstration purposes (first filter excludes sub-dirs, second uses inverted dijoint).
Filters evaluate in order. Globs must always be relative to the seach path for simplicity.

The glob rules are from VSCode's approach.

short synopsis:

> globs sperate path segments with a / character on all platforms
> 
> '*'  matches 0 or more characters in a single segment
>
> '**' matches 0 or more segments
> 
> '?'  matches a single character
> 
> '{}' is an "or"-like expansion with choices seperated by a comma
>
> '[]' specifies a range of characters and may start with '[!' to negate
>
> '\\'  is the escape character - this also means all glob paths use / as dir separator regardless of OS
>
> * case insensitive sections are supported with `(?i)blahblah(?-i)`
> * all patterns are nestable within `{}`


Test for inclusion on arbitrary string:

```nim
echo includes("./file.nims", [globIncl"{*.nim,*.nims}"])
```

Invalid globs will typically bail-out to literal comparisons, however some globs are truely not valid. Test if a glob is valid:

```nim
echo validateGlob("**.nim")
```
The above is invalid because `**` can only match path segments.
`**/*.nim` will work for this instead.

When possible, glob strings are validated at compile time:

```nim
globIncl("{a,")
globIncl("**.txt")
```

```
invalid glob: unclosed disjoint
{a,
   ^

invalid glob: double star cannot share path segment with other patterns (missing /)
**.txt
  ^
```

Expand disjoints:

```nim
for expanded in iterExpansions("{,{a,b}}{1,2}"):
  echo expanded
discard """
  1
  2
  a1
  a2
  b1
  b2
"""
```

This is less of a glob feature and more of an aux feature for configuration files etc.


## why use
* glob logic is designed to be efficient for walking directories
    - `GlobState` objects track progress of each pattern as the path gains depth to avoid re-evaluating sections
* hand rolled - no regex, no non-`std` dependencies
* fairly robust features (eg. nested expressions in groups)
    - see second help menu below for details [or this](https://code.visualstudio.com/docs/editor/glob-patterns) as of writing
    - in addition to above posix-style character sets are also supported
* compatible with windows and posix paths

## why not use
* new - could be missing some test cases
* although tested on windows, the win API code could probably be better

## nfind program

With the library is an implementation of a find utility. I made it because I always forget the
syntax for unix find. It's a simple example of how to use the library. Below are some help menus
from the program.

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
