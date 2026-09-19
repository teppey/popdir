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
    var names: list<string>
    var name: string
    var isdir: bool
    var key_stack: list<string>
    var show_hidden: bool

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
        this.dirpath = dirpath
    enddef

    def SetNames(names: list<string>): void
        this.names = names
    enddef

    def SetShowHidden(show_hidden: bool): void
        this.show_hidden = show_hidden
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

def Sort(names: list<string>): list<string>
    return sort(names, Compare)
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

def ListDir(dirpath: string, hidden: bool = false): list<string>
    final names = map(readdir(dirpath), (_, name) => name .. Suffix(dirpath, name))
    return Sort(filter(names, (_, name) => hidden || name[0] != '.'))
enddef

def Update(winid: number, dirpath: string): void
    const state = State.Get(winid)
    const names = ListDir(dirpath, state.show_hidden)
    state.SetDirPath(dirpath)
    state.SetNames(names)
    state.Set()

    popup_settext(winid, names)
    popup_setoptions(winid, { title: Title(dirpath) })
enddef

def Filter(winid: number, key: string): bool
    if strtrans(key) == '<80><fd>`'
        return true
    endif

    const state = State.Get(winid)

    # サブディレクトリを表示
    if key == "\<Enter>" && state.isdir
        DoSubDir(state)
        return true
    endif

    # 一つ上のディレクトリに移動
    if key == '-'
        DoParentDir(state)
        return true
    endif

    # <Home>: Move to first line
    if key == "\<Home>"
        DoFirstLine(state)
        return true
    endif

    # gg: Move to first line
    if key == 'g' && state.key_stack[: -1] == ['g']
        DoFirstLine(state)
        state.ClearKeyStack()
        return true
    endif

    # <End>: Move to last line
    if key == "\<End>"
        DoLastLine(state)
        return true
    endif

    # G: Move to last line if no <count>, or move to <count> line
    if key == 'G'
        const num_arg = state.NumArg()
        if num_arg > 0
            DoLine(state, num_arg)
        else
            DoLastLine(state)
        endif
        state.ClearKeyStack()
        return true
    endif

    # j: <count> lines downward
    # k: <count lines upward
    # H: Line <count> from top of window
    # M: Middle line of window
    # L: Line <count> from bottom of window
    # <C-F>: Page down
    # <C-B>: Page up
    const command_as_is = ['j', 'k', 'H', 'L', 'M', "\<C-F>", "\<C-B>"]
    if index(command_as_is, key) >= 0
        DoCommandAsIs(state, key)
        return true
    endif

    # Push key stack for `gg` and <count> arg
    if key =~ '[gz0-9]'
        add(state.key_stack, key)
        return true
    endif

    # zz: Cursor line to center of window
    # zt: Cursor line to top of window
    # zb: Cursor line to bottom of window
    const command_scroll_cursor = ['z', 't', 'b']
    if index(command_scroll_cursor, key) >= 0 && get(state.key_stack, -1, '') ==# 'z'
        DoCursorRelativeScroll(state, key)
        return true
    endif

    # h: Toggle display hidden files
    if key == 'h'
        DoToggleHidden(state)
        return true
    endif

    # %: Create a new file and edit it
    if key == '%'
        DoNewFile(state)
        return true
    endif

    # D: Delete a file
    # TODO: directory
    if key == 'D'
        DoDelete(state)
        return true
    endif

    # ~: Go to home directory
    if key == '~'
        DoHome(state)
        return true
    endif

    # /: Forward search
    if key == '/'
        DoForwardSearch(state)
        return true
    endif

    # ?: Backword search
    if key == '?'
        DoBackwardSearch(state)
        return true
    endif

    if key == 'r'
        # TODO: リロード
        DoReload(state)
        return true
    endif

    return popup_filter_menu(state.winid, key)
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
    const value = input('/')
    win_execute(state.winid, $":normal! /{value}\<Enter>", 'silent!')
enddef

def DoBackwardSearch(state: State): void
    const value = input('?')
    win_execute(state.winid, $":normal! ?{value}\<Enter>", 'silent!')
enddef

def DoReload(state: State): void
    Update(state.winid, state.dirpath)
enddef
