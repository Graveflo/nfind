import std/[sequtils, os, strutils]
import os, globs

export FsoKind, globs

when defined(posix):
  import std/posix

  proc convDTypeToFsoKind(dType: cint): FsoKind =
    case dType
    of DT_REG: fsoFile
    of DT_DIR: fsoDir
    of DT_BLK: fsoBlk
    of DT_LNK: fsoLink
    of DT_CHR: fsoChar
    of DT_FIFO: fsoFifo
    of DT_SOCK: fsoSock
    else: fsoUnknown

  proc convStatModeToFsoKind(sMode: Mode): FsoKind =
    case sMode.cint and S_IFMT
    of S_IFREG: fsoFile
    of S_IFDIR: fsoDir
    of S_IFLNK: fsoLink
    of S_IFBLK: fsoBlk
    of S_IFCHR: fsoChar
    of S_IFIFO: fsoFifo
    of S_IFSOCK: fsoSock
    else: fsoUnknown

  type
    DirIter* = ptr DIR
    FstatFlags* = distinct cint
    ItFso* = ptr Dirent

  let
    AT_NO_AUTOMOUNT* {.importc, header: "<fcntl.h>".}: FstatFlags
    AT_SYMLINK_NOFOLLOW* {.importc, header: "<fcntl.h>".}: FstatFlags
  proc fstatat*(
    dirfd: cint; path: pointer; a2: var Stat; flags: FstatFlags
  ): cint {.importc, header: "<sys/stat.h>", sideEffect.}

  proc dirfd*(dirp: ptr DIR): cint {.importc, header: "<dirent.h>".}
elif defined(windows):
  import std/[winlean, strformat, widestrs]
  # god i hate the windows API. This is absolute FILTH! and this is the less efficient, easy way (:
  type
    FINDEX_INFO_LEVELS {.size: sizeof(cint).} = enum
      FindExInfoStandard
      FindExInfoBasic
      FindExInfoMaxInfoLevel

    FINDEX_SEARCH_OPS {.size: sizeof(cint).} = enum
      FindExSearchNameMatch
      FindExSearchLimitToDirectories
      FindExSearchLimitToDevices
      FindExSearchMaxSearchOp

  proc FindFirstFileExW*(
    lpFileName: WideCString;
    fInfoLevelId: FINDEX_INFO_LEVELS;
    lpFindFileData: var WIN32_FIND_DATA;
    fSearchOp: FINDEX_SEARCH_OPS;
    filter: pointer;
    dwAdditionalFlags: int32;
  ): Handle {.stdcall, dynlib: "kernel32", importc: "FindFirstFileExW", sideEffect.}

  type
    DirIter* = object
      handle: Handle
      data: WIN32_FIND_DATA

    ItFso* = ptr WIN32_FIND_DATA

  proc convDwFileAttrToFsoKind(attr: int32): FsoKind =
    if (attr and FILE_ATTRIBUTE_DIRECTORY) == FILE_ATTRIBUTE_DIRECTORY:
      fsoDir
    elif (attr and FILE_ATTRIBUTE_DIRECTORY) == FILE_ATTRIBUTE_REPARSE_POINT:
      fsoLink
    else:
      fsoFile

else:
  {.error: "unsupported platform".}

proc isValid*(it: DirIter): bool =
  when defined(windows):
    return it.handle != INVALID_HANDLE_VALUE
  else:
    return it != nil

proc openDirIter*(path: string): DirIter =
  when defined(posix):
    opendir(path.cstring)
  elif defined(windows):
    let adjust = &"{path}\\*"
    let strconv = newWideCString(adjust.cstring, len(adjust))
    result = DirIter()
    result.handle = FindFirstFileExW(
      strconv, FindExInfoBasic, result.data, FindExSearchNameMatch, nil, 0
    )

proc name*(it: ItFso): string =
  when defined(windows):
    let pt = cast[ptr UncheckedArray[Utf16Char]](it[].cFileName[0].addr)
    $WideCString(pt)
  else:
    $cast[cstring](it.dName[0].addr)

proc next*(it: var DirIter): ItFso =
  when defined(windows):
    if findNextFileW(it.handle, it.data) == 0:
      return nil
    result = it.data.addr
  else:
    readdir(it)

proc entryKind*(it: DirIter; fso: ItFso): FsoKind =
  when defined(windows):
    convDwFileAttrToFsoKind(fso[].dwFileAttributes)
  else:
    {.warning[Uninit]: off.}
    if fso.d_type == DT_UNKNOWN: # file system doesn't support effecient typing
      var st: Stat
      if fstatat(dirfd(it), fso.dName[0].addr, st, AT_SYMLINK_NOFOLLOW) == -1:
        fsoUnknown
      else:
        convStatModeToFsoKind(st.stMode)
    else:
      convDTypeToFsoKind(fso.d_type)

proc close*(it: DirIter) =
  when defined(windows):
    findClose(it.handle)
  else:
    discard closedir(it)

const skips = [".", ".."]
export FsoKind
iterator find*(
    path: string; acceptTypes: set[FsoKind]; filtersl: openArray[GlobFilter]
): string =
  bind skips
  var working = path
  if working.len > 0 and working[^1] == DirSep:
    working.setLen(working.len - 1)
  let addingInclAll = not filtersl.anyIt(it.incl)
  var filters = newSeqOfCap[GlobFilter](filtersl.len + ord(addingInclAll))
  var wgs = newSeqofCap[GlobState](filters.len)
  for filter in filtersl:
    wgs.add GlobState(pt: len(working) + 1)
    filters.add filter
  if addingInclAll:
    filters.add GlobFilter(incl: true, glob: "**")
    wgs.add GlobState(pt: len(working))
  # absolute path so there is no nonsense from the os APIs
  var dirc = @[(openDirIter(path.absolutePath), wgs)]
  try:
    if isValid(dirc[^1][0]):
      while true:
        wgs[0 ..< len(wgs)] = dirc[^1][1]
        var fso = next(dirc[^1][0])
        if fso == nil:
          let pack = dirc.pop()
          close(pack[0])
          if dirc.len <= 0:
            break
          if working[^1] == DirSep:
            working.setLen(working.len - 1)
          working.setLen when defined(danger):
            working.rfind(DirSep)
          else:
            max(working.rfind(DirSep), 0)
        else:
          let thisName = fso.name
          if thisName notin skips:
            let thisPath = working & DirSep & thisName
            let fidx = findFirstGlob(thisPath, filters, wgs)
            let tftype = entryKind(dirc[^1][0], fso)
            var recurse = tftype == fsoDir
            if fidx > -1:
              if filters[fidx].incl:
                if tftype in acceptTypes:
                  yield thisPath
              else:
                # if there is an incl filter before this we have to keep going
                var flag = true
                for i in 0 ..< fidx:
                  if filters[i].incl:
                    flag = false
                    break
                if flag and wgs[fidx].match == AllFurtherMatch:
                  recurse = false
            if recurse:
              let newd = openDirIter(thisPath)
              if isValid(newd):
                dirc.add (newd, wgs)
                working = thisPath
  finally:
    for pack in dirc:
      close(pack[0])
