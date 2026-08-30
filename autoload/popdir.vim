" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

let s:cpo_save = &cpo
set cpo&vim

let g:popdir_show_hidden = 1

func! popdir#open(dirpath = '') abort
    let dirpath = a:dirpath
    if empty(dirpath)
        let curpath = expand('%:p')
        if empty(curpath)
            let dirpath = getcwd()
        else
            let dirpath = s:parent(curpath)
        endif
    endif

    let names = s:listdir(dirpath, g:popdir_show_hidden)
    let winid = popup_menu(names, #{
                \ maxheight: 40,
                \ minheight: 30,
                \ minwidth: 26,
                \ pos: 'topleft',
                \ line: 'cursor+1',
                \ col: 'cursor+1',
                \ title: s:title(dirpath),
                \ callback: function('s:callback'),
                \ filter: function('s:filter'),
                \ })
    call s:setinfo(winid, #{
                \ winid: winid,
                \ dirpath: dirpath,
                \ names: names,
                \ show_hidden: g:popdir_show_hidden,
                \ })
endfunc

func! s:newinfo() abort
    return #{
                \ winid: 0,
                \ dirpath: '',
                \ names: [],
                \ name: '',
                \ path: '',
                \ isdir: 0,
                \ char_stack: [],
                \ show_hidden: 0,
                \ }
endfunc

func! s:setinfo(winid, data) abort
    let info = getwinvar(a:winid, 'info') ?? s:newinfo()
    for [key, value] in items(a:data)
        if !has_key(info, key)
            throw $'unexpected info key: {key}'
        endif
        let info[key] = value
    endfor
    call setwinvar(a:winid, 'info', info)
endfunc

func! s:getinfo(winid) abort
    let info = getwinvar(a:winid, 'info') ?? s:newinfo()
    call win_execute(a:winid, 'let w:name = getline(".")')
    let name = getwinvar(a:winid, 'name')
    let info.name = s:trimslash(name)
    let info.isdir = name[-1:] == '/'
    let info.path = $'{info.dirpath}/{info.name}'
    return info
endfunc

func! s:parent(path) abort
    return fnamemodify(a:path, ':h')
endfunc

func! s:sort(names) abort
    return sort(a:names, function('s:compare'))
endfunc

func! s:compare(a, b) abort
    let a_is_dir = a:a[-1:] == '/'
    let b_is_dir = a:b[-1:] == '/'

    let a = s:trimslash(a:a)
    let b = s:trimslash(a:b)

    if a_is_dir && !b_is_dir
        return -1
    elseif !a_is_dir && b_is_dir
        return 1
    endif

    if a:a == a:b
        return 0
    elseif a:a < a:b
        return -1
    else
        return 1
endfunc

func! s:callback(winid, result) abort
    if a:result == -1
        return
    endif
    let info = s:getinfo(a:winid)
    let path = $'{info.dirpath}/{info.name}'
    execute "silent edit " . path
endfunc

func! s:title(path) abort
    let path_tilde = fnamemodify(a:path, ':~')
    return $'  {path_tilde}  '
endfunc

func! s:trimslash(s) abort
    return trim(a:s, '/', 2)
endfunc

" TODO: symlink
func! s:suffix(dirpath, name) abort
    return (isdirectory($'{a:dirpath}/{a:name}')) ? '/' : ''
endfunc

func! s:listdir(dirpath, hidden = 0) abort
    let names = map(readdir(a:dirpath), {_, name -> name .. s:suffix(a:dirpath, name)})
    return s:sort(filter(names, {_, name -> a:hidden || name[0] != '.'}))
endfunc

func! s:update(winid, dirpath) abort
    let info = s:getinfo(a:winid)
    let names = s:listdir(a:dirpath, info.show_hidden)
    call s:setinfo(a:winid, #{ dirpath: a:dirpath, names: names })
    call popup_settext(a:winid, names)
    call popup_setoptions(a:winid, #{ title: s:title(a:dirpath) })
endfunc

func! s:filter(winid, key) abort
    let info = s:getinfo(a:winid)

    " サブディレクトリを表示
    if a:key is# "\<Enter>" && info.isdir
        call s:doSubdir(info)
        return 1
    endif

    " 一つ上のディレクトリに移動
    if a:key is# '-'
        let prev_name = fnamemodify(info.dirpath, ':t')
        let parent = s:parent(info.dirpath)
        call s:update(info.winid, parent)
        " TODO: escape
        call win_execute(info.winid, $"normal! /{prev_name}\<Enter>")
        return 1
    endif

    " <Home>: Move to first line
    if a:key is# "\<Home>"
        call win_execute(info.winid, '1')
        return 1
    endif

    " gg: Move to first line
    if a:key is# 'g' && info.char_stack[:-1] == ['g']
        let info.char_stack = []
        call win_execute(info.winid, '1')
        return 1
    endif

    " <End>: Move to last line
    if a:key is# "\<End>"
        call win_execute(info.winid, 'normal! G')
        return 1
    endif

    " G: Goto line <count>, default last line
    if a:key is# 'G'
        let num_arg = str2nr(join(info.char_stack, ''))
        if num_arg > 0
            call win_execute(info.winid, $'normal! {num_arg}G')
        else
            call win_execute(info.winid, 'normal! G')
        endif
        let info.char_stack = []
        return 1
    endif

    " j: <count> lines downward
    " k: <count lines upward
    " H: Line <count> from top of window
    " M: Middle line of window
    " L: Line <count> from bottom of window
    " <C-F>: Page down
    " <C-B>: Page up
    let command_as_is = ['j', 'k', 'H', 'L', 'M', "\<C-F>", "\<C-B>"]
    if index(command_as_is, a:key) >= 0
        let num_arg = str2nr(join(info.char_stack, ''))
        if num_arg < 1
            let num_arg = 1
        endif
        call win_execute(info.winid, $'normal! {num_arg}{a:key}')
        let info.char_stack = []
        return 1
    endif

    " For `gg` and <count> arg
    if a:key =~ '[gz0-9]'
        call add(info.char_stack, a:key)
        return 1
    endif

    " zz: Cursor line to center of window
    " zt: Cursor line to top of window
    " zb: Cursor line to bottom of window
    let command_scroll_cursor = ['z', 't', 'b']
    if index(command_scroll_cursor, a:key) >= 0 && get(info.char_stack, -1, '') ==# 'z'
        let info.char_stack = []
        call win_execute(info.winid, 'normal! z' . a:key)
        return 1
    endif

    " h: Toggle display hidden files
    if a:key is# 'h'
        let info.show_hidden = !info.show_hidden
        call s:update(info.winid, info.dirpath)
        return 1
    endif

    " %: Create new file and edit
    if a:key is# '%'
        call s:doNewFile(info)
        return 1
    endif

    " D: Delete file
    " TODO: directory
    if a:key is# 'D'
        let choice = confirm($'Delete file?: {info.name}', "&Yes\n&No", 2)
        if choice == 1
            let path = $'{info.dirpath}/{info.name}'
            let result = delete(path)
            if result != 0
                echoerr $'Failed to delete file: {path}'
            endif
            call s:update(info.winid, info.dirpath)
        endif
        return 1
    endif

    " ~: Go to home directory
    if a:key is# '~'
        call s:update(info.winid, expand('~'))
        return 1
    endif

    " /: Forward search
    if a:key is# '/'
        let value = input('/')
        call win_execute(info.winid, $"normal! /{value}\<Enter>", 'silent!')
        return 1
    endif

    " ?: Backword search
    if a:key is# '?'
        let value = input('?')
        call win_execute(info.winid, $"normal! ?{value}\<Enter>", 'silent!')
        return 1
    endif

    if a:key is# 'r'
        " TODO: リロード
        return 1
    endif

    return popup_filter_menu(info.winid, a:key)
endfunc

func! s:doSubdir(info) abort
    call s:update(a:info.winid, a:info.path)
    call win_execute(a:info.winid, '1')
endfunc

func! s:doNewFile(info) abort
    let name = trim(input('New file: '))
    if empty(name)
        return
    endif
    let path = $'{a:info.dirpath}/{name}'
    if !empty(glob(path))
        echoerr $'faild to create file: "{path}" is already exists'
        return
    endif
    call popup_close(a:info.winid, -1)
    execute "silent edit " . path
endfunc
