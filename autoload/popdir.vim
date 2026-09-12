vim9script

# File: popdir.vim
# Description: Display a list of directory entries in the popup window
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
    SetInfo(winid, {
        winid: winid,
        dirpath: dirpath,
        names: names,
        show_hidden: options.show_hidden,
    })
enddef

def NewInfo(): dict<any>
    return {
        winid: 0,
        dirpath: '',
        names: [],
        name: '',
        path: '',
        isdir: false,
        char_stack: [],
        show_hidden: false,
    }
enddef

def SetInfo(winid: number, data: dict<any>): void
    final info = getwinvar(winid, 'info') ?? NewInfo()
    for [key, value] in items(data)
        if !has_key(info, key)
            throw $'unexpected info key: {key}'
        endif
        info[key] = value
    endfor
    setwinvar(winid, 'info', info)
enddef

def GetInfo(winid: number): dict<any>
    final info = getwinvar(winid, 'info') ?? NewInfo()
    win_execute(winid, 'vim9cmd w:name = getline(".")')
    const name = getwinvar(winid, 'name')
    info.name = TrimSlash(name)
    info.isdir = name[-1 :] == '/'
    info.path = $'{info.dirpath}/{info.name}'
    return info
enddef

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
    const info = GetInfo(winid)
    execute "silent edit " .. info.path
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
    const info = GetInfo(winid)
    const names = ListDir(dirpath, info.show_hidden)
    SetInfo(winid, { dirpath: dirpath, names: names })
    popup_settext(winid, names)
    popup_setoptions(winid, { title: Title(dirpath) })
enddef

def Filter(winid: number, key: string): bool
    const info = GetInfo(winid)

    # サブディレクトリを表示
    if key == "\<Enter>" && info.isdir
        DoSubDir(info)
        return true
    endif

    # 一つ上のディレクトリに移動
    if key == '-'
        const prev_name = fnamemodify(info.dirpath, ':t')
        const parent = Parent(info.dirpath)
        Update(info.winid, parent)
        # TODO: escape
        win_execute(info.winid, $":normal! /{prev_name}\<Enter>")
        return true
    endif

    # <Home>: Move to first line
    if key == "\<Home>"
        win_execute(info.winid, ':1')
        return true
    endif

    # gg: Move to first line
    if key == 'g' && info.char_stack[: -1] == ['g']
        info.char_stack = []
        win_execute(info.winid, ':1')
        return true
    endif

    # <End>: Move to last line
    if key == "\<End>"
        win_execute(info.winid, ':normal! G')
        return true
    endif

    # G: Goto line <count>, default last line
    if key == 'G'
        const num_arg = str2nr(join(info.char_stack, ''))
        if num_arg > 0
            win_execute(info.winid, $':normal! {num_arg}G')
        else
            win_execute(info.winid, ':normal! G')
        endif
        info.char_stack = []
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
        var num_arg = str2nr(join(info.char_stack, ''))
        if num_arg < 1
            num_arg = 1
        endif
        win_execute(info.winid, $':normal! {num_arg}{key}')
        info.char_stack = []
        return true
    endif

    # For `gg` and <count> arg
    if key =~ '[gz0-9]'
        add(info.char_stack, key)
        return true
    endif

    # zz: Cursor line to center of window
    # zt: Cursor line to top of window
    # zb: Cursor line to bottom of window
    const command_scroll_cursor = ['z', 't', 'b']
    if index(command_scroll_cursor, key) >= 0 && get(info.char_stack, -1, '') ==# 'z'
        info.char_stack = []
        win_execute(info.winid, $':normal! z{key}')
        return true
    endif

    # h: Toggle display hidden files
    if key == 'h'
        info.show_hidden = !info.show_hidden
        Update(info.winid, info.dirpath)
        return true
    endif

    # %: Create new file and edit
    if key == '%'
        DoNewFile(info)
        return true
    endif

    # D: Delete file
    # TODO: directory
    if key == 'D'
        const choice = confirm($'Delete file?: {info.name}', "&Yes\n&No", 2)
        if choice == 1
            const path = $'{info.dirpath}/{info.name}'
            const result = delete(path)
            if result != 0
                echoerr $'Failed to delete file: {path}'
            endif
            Update(info.winid, info.dirpath)
        endif
        return true
    endif

    # ~: Go to home directory
    if key == '~'
        Update(info.winid, expand('~'))
        return true
    endif

    # /: Forward search
    if key == '/'
        const value = input('/')
        win_execute(info.winid, $":normal! /{value}\<Enter>", 'silent!')
        return true
    endif

    # ?: Backword search
    if key == '?'
        const value = input('?')
        win_execute(info.winid, $":normal! ?{value}\<Enter>", 'silent!')
        return true
    endif

    if key == 'r'
        # TODO: リロード
        return true
    endif

    return popup_filter_menu(info.winid, key)
enddef

def DoSubDir(info: dict<any>): void
    Update(info.winid, info.path)
    win_execute(info.winid, 'vim9cmd cursor(1, 1)')
enddef

def DoNewFile(info: dict<any>): void
    const name = trim(input('New file: '))
    if empty(name)
        return
    endif
    const path = $'{info.dirpath}/{name}'
    if !empty(glob(path))
        :echoerr $'faild to create file: "{path}" is already exists'
        return
    endif
    popup_close(info.winid, -1)
    :execute 'silent edit ' .. path
enddef
