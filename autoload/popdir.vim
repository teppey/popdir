vim9script

# File: popdir.vim
# Description: Directory browser in popup window.
# Author: Teppei Hamada <temada@gmail.com>
# Version: 0.1

const POPDIR_DEFAULT_OPTIONS = {
    show_hidden: false,
}

export def Open(path: string = ''): void
    var dirpath = path
    if empty(dirpath)
        const curpath = expand('%:p')
        if empty(curpath)
            dirpath = getcwd()
        else
            dirpath = Parent(curpath)
        endif
    endif

    if !isdirectory(dirpath)
        ShowError($'"{dirpath}" is not a directory')
        return
    endif

    final options: dict<any> = copy(POPDIR_DEFAULT_OPTIONS)
    if exists('g:popdir_options')
        extend(options, g:popdir_options)
    endif

    const finfos = ListDir2(dirpath, options.show_hidden)
    const display_names = mapnew(finfos, (_, info) => info.DisplayName())
    const winid = popup_menu(display_names, {
        maxheight: 40,
        minheight: 30,
        minwidth: 26,
        pos: 'topleft',
        line: 'cursor+1',
        col: 'cursor+1',
        title: Title(dirpath),
        callback: Callback,
        filter: Filter,
    })

    const state2 = State.new(winid, dirpath, finfos, options.show_hidden)
    SetState2(winid, state2)
enddef

enum Direction
    Forward(''),
    Backward('b')

    var search_flag: string

    def Opposite(): Direction
        if this is Direction.Forward
            return Direction.Backward
        else
            return Direction.Forward
        endif
    enddef
endenum

class FileInfo
    var parent: string
    var name: string
    var ftype: string

    def Path(): string
        return $'{this.parent}/{this.name}'
    enddef

    def DisplayName(): string
        return this.name .. this.Suffix()
    enddef

    def Suffix(): string
        if this.ftype == 'dir'
            return '/'
        elseif this.ftype == 'link'
            return $'@ -> {resolve(this.Path())}'
        elseif this.ftype == 'socket'
            return '='
        elseif this.ftype == 'fifo'
            return '|'
        else
            return ''
        endif
    enddef
endclass

class State
    var winid: number
    var dirpath: string
    var prev_dirpath: string
    var file_infos: list<FileInfo>
    var current: FileInfo
    var key_stack: list<string>
    var show_hidden: bool
    var search: tuple<string, Direction>

    def new(this.winid, this.dirpath, this.file_infos, this.show_hidden)
    enddef

    def SetDirPath(dirpath: string): void
        this.prev_dirpath = this.dirpath
        this.dirpath = dirpath
    enddef

    def SetFileInfos(file_infos: list<FileInfo>): void
        this.file_infos = file_infos
    enddef

    def SetCurrent(index: number): void
        this.current = this.file_infos[index]
    enddef

    def UnsetCurrent(): void
        this.current = null_object
    enddef

    def HasCurrent(): bool
        return this.current != null_object
    enddef

    def ClearKeyStack(): void
        this.key_stack = []
    enddef

    def PeekKeyStack(): string
        return get(this.key_stack, -1, '')
    enddef

    def NumArg(): number
        return str2nr(join(this.key_stack, ''))
    enddef

    def SetShowHidden(show_hidden: bool): void
        this.show_hidden = show_hidden
    enddef

    def SetSearch(pattern: string, direction: Direction): void
        this.search = (pattern, direction)
    enddef
endclass

def SetState2(winid: number, state2: State): void
    setwinvar(winid, 'state2', state2)
enddef

def GetState2(winid: number): State
    final state2 = getwinvar(winid, 'state2', null)
    if state2 == null
        throw $'failed to get state2: winid={winid}'
    endif

    const lnum = line('.', winid)
    if lnum == 0
        throw $'failed to get line number from the popup: winid={winid}'
    endif

    if len(state2.file_infos) > 0
        state2.SetCurrent(lnum - 1)
    else
        state2.UnsetCurrent()
    endif

    return state2
enddef

def Parent(path: string): string
    return fnamemodify(path, ':h')
enddef

def Callback(winid: number, result: number): void
    ClearCommandLine()
enddef

def Title(path: string): string
    const path_tilde = fnamemodify(path, ':~')
    return $'  {path_tilde}  '
enddef

def TrimSlash(s: string): string
    return trim(s, '/', 2)
enddef

def Suffix(dirpath: string, name: string): string
    const path = $'{dirpath}/{name}'
    const ftype = getftype(path)
    if ftype == 'dir'
        return '/'
    elseif ftype == 'link'
        return $'@ -> {resolve(path)}'
    elseif ftype == 'socket'
        return '='
    elseif ftype == 'fifo'
        return '|'
    else
        return ''
    endif
enddef

def Compare(a: string, b: string): number
    const a_is_dir = a[-1 :] == '/'
    const b_is_dir = b[-1 :] == '/'

    const a_trimmed = TrimSlash(a)
    const b_trimmed = TrimSlash(b)

    if a_is_dir && !b_is_dir
        return -1
    elseif !a_is_dir && b_is_dir
        return 1
    endif

    if a_trimmed == b_trimmed
        return 0
    elseif a_trimmed < b_trimmed
        return -1
    else
        return 1
    endif
enddef

def Compare2(a: FileInfo, b: FileInfo): number
    const a_is_dir = a.ftype == 'dir'
    const b_is_dir = b.ftype == 'dir'

    if a_is_dir && !b_is_dir
        return -1
    elseif !a_is_dir && b_is_dir
        return 1
    endif

    if a.name == b.name
        return 0
    elseif a.name < b.name
        return -1
    else
        return 1
    endif
enddef

def ListDir(dirpath: string, hidden: bool = false): list<string>
    final names = map(readdir(dirpath), (_, name) => name .. Suffix(dirpath, name))
    return sort(filter(names, (_, name) => hidden || name[0] != '.'), Compare)
enddef

def ListDir2(dirpath: string, hidden: bool = false): list<FileInfo>
    final finfos: list<FileInfo> = []
    for [i, name] in items(readdir(dirpath))
        const ftype = getftype($'{dirpath}/{name}')
        const finfo = FileInfo.new(dirpath, name, ftype)
        if hidden || name[0] != '.'
            add(finfos, finfo)
        endif
    endfor

    return sort(finfos, Compare2)
enddef

def Update2(winid: number, dirpath: string): void
    if !isdirectory(dirpath)
        ShowError($'"{dirpath}" is not a directory')
        return
    endif

    const state2 = GetState2(winid)
    const finfos = ListDir2(dirpath, state2.show_hidden)
    state2.SetDirPath(dirpath)
    state2.SetFileInfos(finfos)
    SetState2(winid, state2)

    const display_names = mapnew(finfos, (_, info) => info.DisplayName())
    popup_settext(winid, display_names)
    popup_setoptions(winid, { title: Title(dirpath) })
    win_execute(winid, 'vim9 cursor(1, 1)')
enddef

def ClearCommandLine(): void
    echo ''
enddef

const COMMAND_AS_IS = ['j', 'k', 'H', 'L', 'M', "\<C-F>", "\<C-B>"]
const COMMAND_SCROLL_CURSOR = ['z', 't', 'b']

def Filter(winid: number, key: string): bool
    if strtrans(key) == '<80><fd>`'
        return true
    endif

    ClearCommandLine()

    const state2 = GetState2(winid)
    var keep_key_stack = false

    if key == "\<Enter>" || key == "\<Space>"
        DoOpen(state2)
    elseif key == '-'
         DoParentDir2(state2)
    elseif key == "\<Home>"
        # <Home>: Move to first line
        DoFirstLine2(state2)
    elseif key == 'g' && state2.PeekKeyStack() == 'g'
        # gg: Move to first line
        DoFirstLine2(state2)
    elseif key == 'j' && state2.PeekKeyStack() == 'g'
        # gj: 10 lines downward
        DoManyLines2(state2, 10, Direction.Forward)
    elseif key == 'k' && state2.PeekKeyStack() == 'g'
        # gk: 10 lines upward
        DoManyLines2(state2, 10, Direction.Backward)
    elseif key == "\<End>"
        # <End>: Move to last line
        DoLastLine2(state2)
    elseif key == 'G'
        # G: Move to last line if no <count>, or move to <count> line
        const num_arg = state2.NumArg()
        if num_arg > 0
            DoLine2(state2, num_arg)
        else
            DoLastLine2(state2)
        endif
    elseif index(COMMAND_AS_IS, key) >= 0
        # j: <count> lines downward
        # k: <count lines upward
        # H: Line <count> from top of window
        # M: Middle line of window
        # L: Line <count> from bottom of window
        # <C-F>: Page down
        # <C-B>: Page up
        DoCommandAsIs2(state2, key)
    elseif index(COMMAND_SCROLL_CURSOR, key) >= 0 && state2.PeekKeyStack() ==# 'z'
        # zz: Cursor line to center of window
        # zt: Cursor line to top of window
        # zb: Cursor line to bottom of window
        DoCursorRelativeScroll2(state2, key)
    elseif key == 'h'
        # h: Toggle display hidden files
        DoToggleHidden2(state2)
    elseif key == '%'
        # %: Create a new file and edit it
        DoNewFile2(state2)
    elseif key == 'D'
        DoDelete2(state2)
    elseif key == '~'
        # ~: Go to home directory
        DoHome2(state2)
    elseif key == '/'
        DoSearchForward2(state2)
    elseif key == '?'
        DoSearchBackward2(state2)
    elseif key == 'n'
        DoRepeatSearch2(state2)
    elseif key == 'N'
        DoRepeatSearchOpposite2(state2)
    elseif key == "\<C-L>"
        DoRefresh2(state2)
    elseif key == 'c'
        DoChangeDirectory2(state2)
    elseif key == 'p'
        DoPrevDir2(state2)
    elseif key == 'd'
        DoNewDir2(state2)
    elseif key == 'R'
        DoRename2(state2)
    elseif key == 'C'
        DoCopyFile2(state2)
    elseif key == 'r'
        DoView(state2)
    elseif key =~ '[gz0-9]'
        add(state2.key_stack, key)
        keep_key_stack = true
    else
        popup_filter_menu(state2.winid, key)
    endif

    if !keep_key_stack
        state2.ClearKeyStack()
    endif

    return true
enddef

def ShowError(message: string): void
    echohl ErrorMsg
    echo message
    echohl None
enddef

def DoOpen(state2: State): void
    if !state2.HasCurrent()
        return
    endif

    const finfo = state2.current
    var path = finfo.Path()
    var ftype = finfo.ftype

    if ftype == 'link'
        path = resolve(path)
        ftype = getftype(path)
    endif

    if ftype == 'file'
        popup_close(state2.winid, -1)
        SafeEdit(path)
    elseif ftype == 'dir'
        Update2(state2.winid, path)
    endif
enddef

def RegexpEscape(s: string): string
    return substitute(s, '[\-\^\\.*$]', '\\&', 'g')
enddef

# Ref: https://thinca.hatenablog.com/entry/20090312/1236792602
# :help `=
def SafePath(path: string): string
    return $'`=''{path}''`'
enddef

def SafeEdit(path: string): void
    const safe = SafePath(path)
    execute $'silent edit {safe}'
enddef

def SafeView(path: string): void
    const safe = SafePath(path)
    execute $'silent view {safe}'
enddef

def DoParentDir2(state2: State): void
    const name = fnamemodify(state2.dirpath, ':t')
    Update2(state2.winid, Parent(state2.dirpath))
    FindAndMove(state2, name)
enddef

def DoFirstLine2(state2: State): void
    win_execute(state2.winid, 'vim9 cursor(1, 1)')
enddef

def DoManyLines2(state2: State, n: number, direction: Direction): void
    const count = state2.NumArg() ?? 1
    const updown = (direction is Direction.Forward) ? 1 : -1
    const cur = line('.', state2.winid)
    const lnum = max([1, cur + (n * count * updown)])
    win_execute(state2.winid, $'vim9 cursor({lnum}, 1)')
enddef

def DoLastLine2(state2: State): void
    win_execute(state2.winid, 'vim9 cursor("$", 1)')
enddef

def DoLine2(state2: State, lnum: number): void
    win_execute(state2.winid, $'vim9 cursor({lnum}, 1)')
enddef

# TODO: j, kにcursor()を使うとパフォーマンスが改善されるか確認
def DoCommandAsIs2(state2: State, key: string): void
    const count = state2.NumArg() ?? 1
    win_execute(state2.winid, $':normal! {count}{key}')
enddef

def DoCursorRelativeScroll2(state2: State, key: string): void
    win_execute(state2.winid, $':normal! z{key}')
enddef

def DoToggleHidden2(state2: State): void
    state2.SetShowHidden(!state2.show_hidden)
    Update2(state2.winid, state2.dirpath)
enddef

def DoNewFile2(state2: State): void
    const name = trim(input('New file: '))
    if empty(name)
        return
    endif
    const path = $'{state2.dirpath}/{name}'
    if !empty(glob(path))
        ShowError($'Failed to create a new file: "{path}" is already exists')
        return
    endif
    popup_close(state2.winid, -1)
    SafeEdit(path)
enddef

def DoDelete2(state2: State): void
    if !state2.HasCurrent()
        return
    endif

    const finfo = state2.current
    const ftype = finfo.ftype
    var kind = ''
    var flags = ''
    if ftype == 'file' || ftype == 'socket' || ftype == 'fifo'
        kind = ftype
    elseif ftype == 'link'
        kind = 'symlink'
    elseif ftype == 'dir'
        kind = 'directory'
        flags = 'd'
    endif

    const path = finfo.Path()
    const choice = confirm($'Delete the {kind}?: {path}', "&Yes\n&No", 2)
    if choice == 1
        const result = delete(path, flags)
        if result != 0
            ShowError($'Failed to delete the {kind}: {path}')
        endif
        Update2(state2.winid, state2.dirpath)
    endif
enddef

def DoHome2(state2: State): void
    Update2(state2.winid, expand('~'))
enddef

def DoSearchForward2(state2: State): void
    const pattern = input('/')
    if !empty(pattern)
        state2.SetSearch(pattern, Direction.Forward)
        const escaped = substitute(pattern, "'", "''", 'g')
        const command = printf("vim9 search('%s')", escaped)
        win_execute(state2.winid, command)
    endif
enddef

def DoSearchBackward2(state2: State): void
    const pattern = input('?')
    if !empty(pattern)
        state2.SetSearch(pattern, Direction.Backward)
        const escaped = substitute(pattern, "'", "''", 'g')
        const command = printf("vim9 search('%s', 'b')", escaped)
        win_execute(state2.winid, command)
    endif
enddef

def DoRepeatSearch2(state2: State): void
    if !empty(state2.search)
        const [pattern, direction] = state2.search
        const flag = direction.search_flag
        const escaped = substitute(pattern, "'", "''", 'g')
        const command = printf("vim9 search('%s', '%s')", escaped, flag)
        win_execute(state2.winid, command)
    endif
enddef

def DoRepeatSearchOpposite2(state2: State): void
    if !empty(state2.search)
        const [pattern, direction] = state2.search
        const flag = direction.Opposite().search_flag
        const escaped = substitute(pattern, "'", "''", 'g')
        const command = printf("vim9 search('%s', '%s')", escaped, flag)
        win_execute(state2.winid, command)
    endif
enddef

def DoRefresh2(state2: State): void
    Update2(state2.winid, state2.dirpath)
enddef

def DoChangeDirectory2(state2: State): void
    const dirpath = expand(trim(input('Change directory: ', '', 'dir')))
    if empty(dirpath)
        return
    endif
    if !isdirectory(dirpath)
        ShowError($'No such directory: {dirpath}')
        return
    endif
    Update2(state2.winid, dirpath)
enddef

def DoPrevDir2(state2: State): void
    const prev_dirpath = state2.prev_dirpath
    if empty(prev_dirpath)
        return
    endif
    if !isdirectory(prev_dirpath)
        ShowError($'No such directory: {prev_dirpath}')
        return
    endif
    Update2(state2.winid, prev_dirpath)
enddef

def DoNewDir2(state2: State): void
    const name = trim(input('New directory: '))
    if empty(name)
        return
    endif

    const path = $'{state2.dirpath}/{name}'
    if !empty(glob(path))
        ShowError($'Failed to create directory: "{path}" is already exists')
        return
    endif

    const success = mkdir(path)
    if !success
        ShowError($'Failed to create directory: "{path}"')
        return
    endif

    Update2(state2.winid, state2.dirpath)
    FindAndMove(state2, name)
enddef

def DoRename2(state2: State): void
    if !state2.HasCurrent()
        return
    endif

    const finfo = state2.current
    const ftype = finfo.ftype
    var kind = ''
    if ftype == 'file' || ftype == 'socket' || ftype == 'fifo'
        kind = ftype
    elseif ftype == 'link'
        kind = 'symlink'
    elseif ftype == 'dir'
        kind = 'directory'
    endif

    const from = finfo.Path()
    const to = trim(input($'Rename the {kind}: {from} -> ', from))
    if empty(to)
        return
    endif

    const result = rename(from, to)
    if result != 0
        ShowError($'Failed to rename {kind}: {from} -> {to}')
        return
    endif

    Update2(state2.winid, state2.dirpath)

    if Parent(from) == Parent(to)
        const to_name = fnamemodify(to, ':t')
        FindAndMove(state2, to_name)
    endif
enddef

def DoCopyFile2(state2: State): void
    if !state2.HasCurrent()
        return
    endif

    const finfo = state2.current
    const ftype = finfo.ftype
    if ftype == 'dir'
        return
    endif

    const from = finfo.Path()
    const to = trim(input($'Copy the file: {from} -> ', from))
    if empty(to)
        return
    endif

    const success = filecopy(from, to)
    if !success
        ShowError($'Failed to copy file: {from} -> {to}')
        return
    endif

    Update2(state2.winid, state2.dirpath)

    if Parent(from) == Parent(to)
        const to_name = fnamemodify(to, ':t')
        FindAndMove(state2, to_name)
    endif
enddef

def FindAndMove(state2: State, name: string)
    const index = indexof(state2.file_infos,  (i, finfo) => finfo.name == name)
    if index != -1
        win_execute(state2.winid, $'vim9 cursor({index + 1}, 1)')
        state2.SetCurrent(index)
    endif
enddef

def DoView(state2: State): void
    if !state2.HasCurrent()
        return
    endif

    const finfo = state2.current
    var path = finfo.Path()
    var ftype = finfo.ftype
    if ftype == 'link'
        path = resolve(path)
        ftype = getftype(path)
    endif

    if ftype == 'file'
        popup_close(state2.winid, -1)
        SafeView(path)
    elseif ftype == 'dir'
        Update2(state2.winid, path)
    endif
enddef
