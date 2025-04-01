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
    testMatch "b", "b"
    testMatch "bb", "bb"
    testGlob "b", "a", NoFurtherMatch
    testGlob "b", "bb", NoFurtherMatch

  test "special":
    testMatch "thing", "./thing"
    testGlob "deps/**", "deps", AllFurtherMatch
    testGlob "deps/**", "./deps", AllFurtherMatch
    testGlob "./ns/**", "./ns", AllFurtherMatch

  test "star":
    testMatch "*", "a"
    testMatch "*/?", "a/b"
    testMatch "*/b/*", "a/b/c"
    testMatch "a/*/c", "a/b/c"
    testMatch "*/*/*/*/*/fb", "a/b/c/d/eb/fb"
    testMatch "*b", "fb"
    testMatch "*b", "b"
    testMatch "b*", "bf"
    testMatch "*", "vbf"

    testGlob "b*", "hfb", NoFurtherMatch
    testGlob "a/*/*/c", "a/b/c", NoMatch
    testGlob "a/b/*/*/b", "a/b/c", NoMatch
    testGlob "a/b/*/*", "a/b/c", NoMatch
    testGlob "a/b/*/*", "a/b/c/", NoMatch
    testGlob "a/*/*/c", "a/b/c/d", NoFurtherMatch
    testGlob "b*", "vbf", NoFurtherMatch
    testGlob "*a", "vbf", NoFurtherMatch

  test "star ext":
    testMatch "*.*", "some.thing"
    testMatch "a/*/so*g", "a/b/soming"
    testMatch "**/*b*", "a/b/aba"
    testMatch "**/*b*", "a/b/abba"
    testMatch "**/*b*", "a/b/abb"
    testMatch "**/*b*", "a/b/acb"
    testMatch "**/*abc", "a/b/abc"
    testMatch "**/*b*.efg", "a/b/asbbc th.efg"
    testMatch "**/*jbc*.e*", "a/b/asjbc th.efg"
    testGlob "a/b/**/**/b", "a/b/c", NoMatch
    testGlob "a/b/**/c/**/b", "a/b/c", NoMatch
    testMatch "a/b/**/c/**/b", "a/b/c/b"
    testGlob "a/*/so*g", "a/b/somingn", NoFurtherMatch

  test "starstar":
    testMatch "**/som/**/som/thing", "aa/som/x/a/som/thing"
    testMatch "**/som/**/som/thing", "aa/som/x/a/som/thin/som/thing"
    testMatch "**/som/thing", "aa/som/x/a/som/thing"
    testMatch "*/som/**/som/thing", "aa/som/x/a/som/thin/som/thing"
    testMatch "./handlers/**/*.lua", "./handlers/something.lua"
    testGlob "**", "a", AllFurtherMatch
    testGlob "**", "aa", AllFurtherMatch
    testGlob "**", "aa/aa", AllFurtherMatch
    testGlob "**", "aa/aa/aaab", AllFurtherMatch
    testGlob "**/som/**/som/thing", "aa/som/x/a/som/thin/som/thin", NoMatch

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
    testGlob "**/aa/**", "aa/aa/aaab", AllFurtherMatch
    testGlob "**/aa/**", "aa/ab/aaab", AllFurtherMatch
    testGlob "**/aa/**", "ab/aa/aaab", AllFurtherMatch
    testGlob "**/aa/**", "a/ab/aaab", NoMatch

  test "?":
    testMatch "?", "a"
    testMatch "??", "aa"
    testGlob "??", "a", NoMatch
    testGlob "?", "", NoMatch
    testMatch "?b?", "abc"

  test "combined":
    testGlob "**/?", "aa", NoMatch
    testGlob "?b?/**", "abc", AllFurtherMatch
    testMatch "qw/er/**/dsf/*", "qw/er/rty/ui/op/as/dsf/gh"
    testGlob "**/som/?/**", "aa/som/x/a/som/thing", AllFurtherMatch
    testMatch "**/*.txt", "/home/user/something.txt"

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
    testMatch "a[a-b][a-c][a-z]", "abcd"
    testGlob "ab[a-b]d", "abcd", NoFurtherMatch
