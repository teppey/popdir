" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

let s:cpo_save = &cpo
set cpo&vim

if !exists('g:popdir_maxheight')
    let g:popdir_maxheight = 40
endif

func! popdir#open(dirpath = '')
    let dirpath = a:dirpath
    if empty(dirpath)
        let curpath = expand('%:p')
        if empty(curpath)
            let dirpath = getcwd()
        else
            let dirpath = s:parent(curpath)
        endif
    endif

    let names = s:listdir(dirpath)
    let winid = popup_menu(names, #{
                \ maxheight: g:popdir_maxheight,
                \ minheight: min([len(names), g:popdir_maxheight]),
                \ title: s:title(dirpath),
                \ callback: function('s:callback'),
                \ filter: function('s:filter'),
                \})
    call s:setinfo(winid, #{ dirpath: dirpath, names: names })
endfunc

func! s:newinfo()
    return #{ dirpath: '', names: [], name: '', isdir: 0, char_stack: [] }
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

func! s:getinfo(winid)
    let info = getwinvar(a:winid, 'info') ?? s:newinfo()
    call win_execute(a:winid, 'let w:name = getline(".")')
    let name = getwinvar(a:winid, 'name')
    let info.name = s:trimslash(name)
    let info.isdir = name[-1:] == '/'
    return info
endfunc

func! s:parent(path)
    return fnamemodify(a:path, ':h')
endfunc

func! s:sort(names)
    return sort(a:names, function('s:compare'))
endfunc

func! s:compare(a, b)
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

func! s:callback(winid, result)
    if a:result == -1
        return
    endif
    let info = s:getinfo(a:winid)
    let path = $'{info.dirpath}/{info.name}'
    execute "silent edit " . path
endfunc

func! s:title(path)
    let path_tilde = fnamemodify(a:path, ':~')
    return $' {path_tilde}: '
endfunc

func! s:trimslash(s)
    return trim(a:s, '/', 2)
endfunc

func! s:listdir(dir)
    let paths = []
    for d in readdirex(a:dir)
        let name = d.name
        if d.type ==# 'dir'
            let name .= '/'
        endif
        call add(paths, name)
    endfor
    return s:sort(paths)
endfunc

func! s:update(winid, dirpath)
    let names = s:listdir(a:dirpath)
    call s:setinfo(a:winid, #{ dirpath: a:dirpath, names: names })
    call popup_settext(a:winid, names)
    call popup_setoptions(a:winid, #{ title: s:title(a:dirpath) })
endfunc

func! s:filter(winid, key)
    let info = s:getinfo(a:winid)

    " サブディレクトリを表示
    if a:key is# "\<Enter>"
        if info.isdir
            let subdir = $'{info.dirpath}/{info.name}'
            call s:update(a:winid, subdir)
            return 1
        else
            return popup_filter_menu(a:winid, a:key)
        endif
    endif

    if a:key is# '-'
        " TODO: 一つ上のディレクトリに移動
        " TODO: 移動する前のディレクトリを検索
        let parent = fnamemodify(info.dirpath, ':h')
        call s:update(a:winid, parent)
        return 1
    endif

    " j: <count> lines downward
    " k: <count lines upward
    " H: Line <count> from top of window
    " M: Middle line of window
    " L: Line <count> from bottom of window
    " <C-F>: Page down
    " <C-B>: Page up
    " TODO: 数値引数に対応
    let command_as_is = ['j', 'k', 'H', 'L', 'M', "\<C-F>", "\<C-B>"]
    if index(command_as_is, a:key) >= 0
"        let num_arg = str2nr(join(char_stack, ''))
"        if num_arg < 1
"            let num_arg = 1
"        endif
        call win_execute(a:winid, $'normal! 1{a:key}')
        "call setwinvar(a:id, 'char_stack', [])
        return 1
    endif

    if a:key is# 'r'
        " TODO: リロード
    endif

    if a:key is# 'h'
        " TODO: 隠しファイルの表示をトグル
    endif

    return popup_filter_menu(a:winid, a:key)
endfunc
