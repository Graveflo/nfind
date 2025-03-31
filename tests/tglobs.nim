import std/[unittest]
import nfind/globs

template testMatches(glob: string; matches: untyped) =
  for x in matches:
    check matchGlob(x, glob).match == Match

template testMatch(glob: string; x: untyped) =
  check matchGlob(x, glob).match == Match

template testGlob(glob: string; x: untyped; mk: MatchKind) =
  check matchGlob(x, glob).match == mk

suite "File searching":
  test "test glob empty":
    let r = matchGlob("", "")
    check r.match >= Match

  test "glob empty starstar":
    let r = matchGlob("", "**")
    check r.match >= Match

  test "norm":
    block:
      let r = matchGlob("a", "b")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("b", "b")
      check r.match == Match
    block:
      let r = matchGlob("bb", "b")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("bb", "bb")
      check r.match == Match

  test "special":
    block:
      let r = matchGlob("./thing", "thing")
      check r.match == Match
    block:
      let r = matchGlob("deps", "deps/**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("./deps", "deps/**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("./ns", "./ns/**")
      check r.match == AllFurtherMatch

  test "star":
    block:
      let r = matchGlob("a", "*")
      check r.match == Match
    block:
      let r = matchGlob("a/b", "*/?")
      check r.match == Match
    block:
      let r = matchGlob("a/b/c", "*/b/*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/c", "a/*/c")
      check r.match == Match
    block:
      let r = matchGlob("a/b/c", "a/*/*/c")
      check r.match == NoMatch
    block:
      let r = matchGlob("a/b/c/d", "a/*/*/c")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("a/b/c/d/eb/fb", "*/*/*/*/*/fb")
      check r.match == Match
    block:
      let r = matchGlob("fb", "*b")
      check r.match == Match
    block:
      let r = matchGlob("hfb", "*b")
      check r.match == Match
    block:
      let r = matchGlob("hfb", "b*")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("bf", "b*")
      check r.match == Match
    block:
      let r = matchGlob("vbf", "b*")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("vbf", "*")
      check r.match == Match
    block:
      let r = matchGlob("vbf", "*a")
      check r.match == NoFurtherMatch

  test "star ext":
    block:
      let r = matchGlob("some.thing", "*.*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/soming", "a/*/so*g")
      check r.match == Match
    block:
      let r = matchGlob("a/b/somingn", "a/*/so*g")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("a/b/aba", "**/*b*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/abba", "**/*b*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/abb", "**/*b*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/acb", "**/*b*")
      check r.match == Match
    block:
      let r = matchGlob("a/b/abc", "**/*abc")
      check r.match == Match
    block:
      let r = matchGlob("a/b/asbbc th.efg", "**/*b*.efg")
      check r.match == Match
    block:
      let r = matchGlob("a/b/asjbc th.efg", "**/*jbc*.e*")
      check r.match == Match

  test "starstar":
    block:
      let r = matchGlob("a", "**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("aa", "**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("aa/aa", "**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("aa/aa/aaab", "**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("aa/som/x/a/som/thing", "**/som/thing")
      check r.match == Match
    block:
      let r = matchGlob("aa/som/x/a/som/thing", "**/som/**/som/thing")
      check r.match == Match
    block:
      let r = matchGlob("aa/som/x/a/som/thin/som/thing", "**/som/**/som/thing")
      check r.match == Match
    block:
      let r = matchGlob("aa/som/x/a/som/thin/som/thin", "**/som/**/som/thing")
      check r.match == NoMatch
    block:
      let r = matchGlob("aa/som/x/a/som/thin/som/thing", "*/som/**/som/thing")
      check r.match == Match
    block:
      let r = matchGlob("./handlers/something.lua", "./handlers/**/*.lua")
      check r.match == Match

  test "incremental **":
    var gs = @[GlobState()]
    let filters = @[GlobFilter(glob: "./handlers/**/*.lua", incl: true)]
    let res = findFirstGlob("./handlers/nested", filters, gs)
    check res == -1
    check gs[0].gt == 11
    check gs[0].pt == 11
    check gs[0].match == NoMatch
    let res2 = findFirstGlob("./handlers/nested/something.lua", filters, gs)
    check res2 == 0
    check gs[0].match == Match

  test "startstar before and after":
    block:
      let r = matchGlob("aa/aa/aaab", "**/aa/**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("aa/ab/aaab", "**/aa/**")
      check r.match == AllFurtherMatch
    block:
      let r = matchGlob("a/ab/aaab", "**/aa/**")
      check r.match == NoMatch

  test "?":
    block:
      let r = matchGlob("a", "?")
      check r.match == Match
    block:
      let r = matchGlob("aa", "?")
      check r.match == NoFurtherMatch
    block:
      let r = matchGlob("abc", "?b?")
      check r.match == Match

  test "combined":
    block:
      let r = matchGlob("aa", "**/?")
      check r.match == NoMatch
    block:
      let r = matchGlob("abc", "?b?/**")
      check r.match >= Match
    block:
      let r = matchGlob("qw/er/rty/ui/op/as/dsf/gh", "qw/er/**/dsf/*")
      check r.match == Match
    block:
      let r = matchGlob("aa/som/x/a/som/thing", "**/som/?/**")
      check r.match >= Match
    block:
      let r = matchGlob("/home/user/something.txt", "**/*.txt")
      check r.match == Match

  test "expand disjoint":
    testMatch "{}", ""
    testMatch "{{}}", ""
    testMatch "{\\{}\\}", "{}"
    testMatch "{\\{}", "{"
    testMatch "{\\{\\}}", "{}"
    testMatch "a{}b", "ab"
    testMatches "a{1,2}b", ["a1b", "a2b"]
    testMatches "a{1,2,3}b", ["a1b", "a2b", "a3b"]
    testMatches "{,2,3}b", ["b", "2b", "3b"]
    testMatch "\\{}", "{}"
    testMatch "{1}", "1"
    testMatch "{{1}}", "1"
    testMatches "{1,2}", ["1", "2"]
    testMatches "{1,2}b{3,4}", ["1b3", "2b4", "2b3", "2b4"]
    testMatches "\\{1,2}b{3,4}", ["{1,2}b3", "{1,2}b4"]
    testGlob "{}", "a", NoMatch
    testMatch "{a,b}", "a"
    testMatch "{a,b}", "b"
    testMatches "{a,{c,b}}", ["a", "b", "c"]
    testMatch "{a,{,b}}d", "bd"
    testMatch "{a,h,b}{{f,}{e,d}}", "bd"
    testMatch "{,a}{ab,bc,b}cde", "abcde"
    testMatch "{,a}{ab,b}cde", "abcde"
    testMatch "{,a}{a{bcd,b{c}}}cde", "abcde"
    testGlob "{}{a{bcd,b{c}}}cde", "abcde", Match
    testMatch "{*.nim,*.nims}", "config.nims"

  test "cmplx disjoint":
    #template testGroups(glob, matches: untyped) =
    #  let r = expandAllGlobGroups(glob)
    #  check r == matches

    testMatches "{1,2}b{3,4}", @["1b3", "1b4", "2b3", "2b4"]
    testMatches "j{1{2,3},4}h", @["j12h", "j13h", "j4h"]
    testMatches "{this,that} {damn ,}{dog,{cat,zebra}} {ran,{f,}{ate,lick}}",
      @[
        "this damn dog ran", "this damn dog fate", "this damn dog flick",
        "this damn dog ate", "this damn dog lick", "this damn cat ran",
        "this damn cat fate", "this damn cat flick", "this damn cat ate",
        "this damn cat lick", "this damn zebra ran", "this damn zebra fate",
        "this damn zebra flick", "this damn zebra ate", "this damn zebra lick",
        "this dog ran", "this dog fate", "this dog flick", "this dog ate",
        "this dog lick", "this cat ran", "this cat fate", "this cat flick",
        "this cat ate", "this cat lick", "this zebra ran", "this zebra fate",
        "this zebra flick", "this zebra ate", "this zebra lick", "that damn dog ran",
        "that damn dog fate", "that damn dog flick", "that damn dog ate",
        "that damn dog lick", "that damn cat ran", "that damn cat fate",
        "that damn cat flick", "that damn cat ate", "that damn cat lick",
        "that damn zebra ran", "that damn zebra fate", "that damn zebra flick",
        "that damn zebra ate", "that damn zebra lick", "that dog ran", "that dog fate",
        "that dog flick", "that dog ate", "that dog lick", "that cat ran",
        "that cat fate", "that cat flick", "that cat ate", "that cat lick",
        "that zebra ran", "that zebra fate", "that zebra flick", "that zebra ate",
        "that zebra lick",
      ]

  test "betwen":
    block:
      let r = matchGlob("abcd", "a[a-b][a-c][a-z]")
      check r.match == Match
    block:
      let r = matchGlob("abcd", "ab[a-b]d")
      check r.match == NoFurtherMatch
