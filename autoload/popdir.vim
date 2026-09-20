vim9script

# File: popdir.vim
# Description: Directory browser in popup window.
# Author: Teppei Hamada <temada@gmail.com>
# Version: 0.1

const POPDIR_DEFAULT_OPTIONS = {
    show_hidden: true,
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

    final options: dict<any> = copy(POPDIR_DEFAULT_OPTIONS)
    if exists('g:popdir_options')
        extend(options, g:popdir_options)
    endif

    const names = ListDir(dirpath, options.show_hidden)
    const winid = popup_menu(names, {
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

    State.new(winid, dirpath, names, options.show_hidden).Set()
enddef

class State
    var winid: number
    var dirpath: string
    var prev_dirpath: string
    var names: list<string>
    var name: string
    var isdir: bool
    var key_stack: list<string>
    var show_hidden: bool
    var pattern: string

    def new(this.winid, this.dirpath, this.names, this.show_hidden)
    enddef

    def Set(): void
        setwinvar(this.winid, 'state', this)
    enddef

    static def Get(winid: number): State
        final state = getwinvar(winid, 'state')
        if !state
            throw $'failed to get state: winid={winid}'
        endif

        win_execute(winid, 'vim9cmd w:name = getline(".")')
        const name = getwinvar(winid, 'name')
        state.name = TrimSlash(name)
        state.isdir = name[-1 :] == '/'
        return state
    enddef

    def SetDirPath(dirpath: string): void
        this.prev_dirpath = this.dirpath
        this.dirpath = dirpath
    enddef

    def SetNames(names: list<string>): void
        this.names = names
    enddef

    def SetShowHidden(show_hidden: bool): void
        this.show_hidden = show_hidden
    enddef

    def SetPattern(pattern: string): void
        this.pattern = pattern
    enddef

    def Path(): string
        return $'{this.dirpath}/{this.name}'
    enddef

    def ClearKeyStack(): void
        this.key_stack = []
    enddef

    def NumArg(): number
        return str2nr(join(this.key_stack, ''))
    enddef
endclass

def Parent(path: string): string
    return fnamemodify(path, ':h')
enddef

def Callback(winid: number, result: number): void
    if result == -1
        return
    endif
    const state = State.Get(winid)
    execute "silent edit " .. state.Path()
enddef

def Title(path: string): string
    const path_tilde = fnamemodify(path, ':~')
    return $'  {path_tilde}  '
enddef

def TrimSlash(s: string): string
    return trim(s, '/', 2)
enddef

# TODO: symlink
def Suffix(dirpath: string, name: string): string
    return (isdirectory($'{dirpath}/{name}')) ? '/' : ''
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

def ListDir(dirpath: string, hidden: bool = false): list<string>
    final names = map(readdir(dirpath), (_, name) => name .. Suffix(dirpath, name))
    return sort(filter(names, (_, name) => hidden || name[0] != '.'), Compare)
enddef

def Update(winid: number, dirpath: string): void
    const trimmed = TrimSlash(dirpath)
    const state = State.Get(winid)
    const names = ListDir(trimmed, state.show_hidden)
    state.SetDirPath(trimmed)
    state.SetNames(names)
    state.Set()

    popup_settext(winid, names)
    popup_setoptions(winid, { title: Title(trimmed) })
enddef

const COMMAND_AS_IS = ['j', 'k', 'H', 'L', 'M', "\<C-F>", "\<C-B>"]
const COMMAND_SCROLL_CURSOR = ['z', 't', 'b']

def Filter(winid: number, key: string): bool
    if strtrans(key) == '<80><fd>`'
        return true
    endif

    const state = State.Get(winid)

    if key == "\<Enter>" && state.isdir
        # サブディレクトリを表示
        DoSubDir(state)
    elseif key == '-'
        # 一つ上のディレクトリに移動
        DoParentDir(state)
    elseif key == "\<Home>"
        # <Home>: Move to first line
        DoFirstLine(state)
    elseif key == 'g' && state.key_stack[: -1] == ['g']
        # gg: Move to first line
        DoFirstLine(state)
        state.ClearKeyStack()
    elseif key == "\<End>"
        # <End>: Move to last line
        DoLastLine(state)
    elseif key == 'G'
        # G: Move to last line if no <count>, or move to <count> line
        const num_arg = state.NumArg()
        if num_arg > 0
            DoLine(state, num_arg)
        else
            DoLastLine(state)
        endif
        state.ClearKeyStack()
    elseif index(COMMAND_AS_IS, key) >= 0
        # j: <count> lines downward
        # k: <count lines upward
        # H: Line <count> from top of window
        # M: Middle line of window
        # L: Line <count> from bottom of window
        # <C-F>: Page down
        # <C-B>: Page up
        DoCommandAsIs(state, key)
    elseif index(COMMAND_SCROLL_CURSOR, key) >= 0 && get(state.key_stack, -1, '') ==# 'z'
        # zz: Cursor line to center of window
        # zt: Cursor line to top of window
        # zb: Cursor line to bottom of window
        DoCursorRelativeScroll(state, key)
    elseif key == 'h'
        # h: Toggle display hidden files
        DoToggleHidden(state)
    elseif key == '%'
        # %: Create a new file and edit it
        DoNewFile(state)
    elseif key == 'D'
        # D: Delete a file
        # TODO: directory
        DoDelete(state)
    elseif key == '~'
        # ~: Go to home directory
        DoHome(state)
    elseif key == '/'
        DoForwardSearch(state)
    elseif key == 'n'
        DoForwardSearchNext(state)
    elseif key == '?'
        # ?: Backword search
        DoBackwardSearch(state)
    elseif key == 'r'
        # `r`: リロード
        DoReload(state)
    elseif key == 'c'
        DoChangeDirectory(state)
    elseif key == 'p'
        DoPrevDir(state)
    elseif key =~ '[gz0-9]'
        # Push key stack for `gg` and <count> arg
        add(state.key_stack, key)
    else
        popup_filter_menu(state.winid, key)
    endif

    return true
enddef

def DoSubDir(state: State): void
    Update(state.winid, state.Path())
    win_execute(state.winid, 'vim9 cursor(1, 1)')
enddef

def DoParentDir(state: State): void
    const prev_name = fnamemodify(state.dirpath, ':t')
    const parent = Parent(state.dirpath)
    Update(state.winid, parent)
    # TODO: escape
    win_execute(state.winid, $":normal! /{prev_name}\<Enter>")
enddef

def DoFirstLine(state: State): void
    win_execute(state.winid, 'vim9 cursor(1, 1)')
enddef

def DoLastLine(state: State): void
    win_execute(state.winid, 'vim9 cursor("$", 1)')
enddef

def DoLine(state: State, lnum: number): void
    win_execute(state.winid, $'vim9 cursor({lnum}, 1)')
enddef

def DoCommandAsIs(state: State, key: string): void
    var count = state.NumArg() ?? 1
    win_execute(state.winid, $':normal! {count}{key}')
    state.ClearKeyStack()
enddef

def DoCursorRelativeScroll(state: State, key: string): void
    win_execute(state.winid, $':normal! z{key}')
    state.ClearKeyStack()
enddef

def DoToggleHidden(state: State): void
    state.SetShowHidden(!state.show_hidden)
    Update(state.winid, state.dirpath)
enddef

def DoNewFile(state: State): void
    const name = trim(input('New file: '))
    if empty(name)
        return
    endif
    const path = $'{state.dirpath}/{name}'
    if !empty(glob(path))
        :echoerr $'faild to create file: "{path}" is already exists'
        return
    endif
    popup_close(state.winid, -1)
    :execute 'silent edit ' .. path
enddef

def DoDelete(state: State): void
    const choice = confirm($'Delete file?: {state.name}', "&Yes\n&No", 2)
    if choice == 1
        const path = state.Path()
        const result = delete(path)
        if result != 0
            echoerr $'Failed to delete file: {path}'
        endif
        Update(state.winid, state.dirpath)
    endif
enddef

def DoHome(state: State): void
    Update(state.winid, expand('~'))
enddef

def DoForwardSearch(state: State): void
    const pattern = input('/')
    state.SetPattern(pattern)
    win_execute(state.winid, $'vim9 search(''{pattern}'')')
enddef

def DoForwardSearchNext(state: State): void
    if !empty(state.pattern)
        win_execute(state.winid, $'vim9 search(''{state.pattern}'')')
    endif
enddef

def DoBackwardSearch(state: State): void
    const value = input('?')
    win_execute(state.winid, $":normal! ?{value}\<Enter>", 'silent!')
enddef

def DoReload(state: State): void
    Update(state.winid, state.dirpath)
enddef

def DoChangeDirectory(state: State): void
    const dirpath = expand(trim(input('Change directory: ', '', 'dir')))
    if empty(dirpath)
        return
    endif
    if !isdirectory(dirpath)
        :echoerr $'no such directory: {dirpath}'
        return
    endif
    Update(state.winid, dirpath)
enddef

def DoPrevDir(state: State): void
    if !empty(state.prev_dirpath)
        Update(state.winid, state.prev_dirpath)
    endif
enddef
