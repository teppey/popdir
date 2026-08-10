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
    call s:setinfo(winid, dirpath, names)
endfunc

func! s:setinfo(winid, dirpath, names)
    call setwinvar(a:winid, 'dirpath', a:dirpath)
    call setwinvar(a:winid, 'names', a:names)
endfunc

func! s:getinfo(winid)
    let dirpath = getwinvar(a:winid, 'dirpath')
    let names = getwinvar(a:winid, 'names')
    call win_execute(a:winid, 'let w:name = getline(".")')
    let name = getwinvar(a:winid, 'name')
    let isdir = name[-1:] == '/'
    return [dirpath, names, s:trimslash(name), isdir]
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
    let [dirpath, names, name, isdir] = s:getinfo(a:winid)
    let path = $'{dirpath}/{name}'
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
    for info in readdirex(a:dir)
        let name = info.name
        if info.type ==# 'dir'
            let name .= '/'
        endif
        call add(paths, name)
    endfor
    return s:sort(paths)
endfunc

func! s:update(winid, dirpath)
    let names = s:listdir(a:dirpath)
    call s:setinfo(a:winid, a:dirpath, names)
    call popup_settext(a:winid, names)
    call popup_setoptions(a:winid, #{title: s:title(a:dirpath)})
endfunc

func! s:filter(winid, key)
    let [dirpath, names, name, isdir] = s:getinfo(a:winid)

    " サブディレクトリを表示
    if a:key is# "\<Enter>"
        if isdir
            let subdir = $'{dirpath}/{name}'
            call s:update(a:winid, subdir)
            return 1
        else
            return popup_filter_menu(a:winid, a:key)
        endif
    endif

    if a:key is# '-'
        " TODO: 一つ上のディレクトリに移動
        " TODO: 移動する前のディレクトリを検索
        let parent = fnamemodify(dirpath, ':h')
        call s:update(a:winid, parent)
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
