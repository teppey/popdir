" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

let s:cpo_save = &cpo
set cpo&vim

if !exists('g:popdir_maxheight')
    let g:popdir_maxheight = 40
endif

" func! popdir#open(dirpath = getcwd())
func! popdir#open(dirpath = '')
    " dirpathが与えられなければ現在のファイルの親ディレクトリをdirpathとする
    " 現在のファイルが存在しなければカレントディレクトリをdirpathとする
    let dirpath = a:dirpath
    if empty(dirpath)
        let curpath = expand('%:p')
        if empty(curpath)
            let dirpath = getcwd()
        else
            let dirpath = s:parent(curpath)
        endif
    endif

    let names = s:sort(s:listdir(dirpath))

    let winid = popup_menu(names, #{
                \ maxheight: g:popdir_maxheight,
                \ minheight: min([len(names), g:popdir_maxheight]),
                \ title: s:title(dirpath),
                \ callback: function('s:callback'),
                \ filter: function('s:filter'),
                \})
    call setwinvar(winid, 'dirpath', dirpath)
    call setwinvar(winid, 'names', names)
endfunc

func! s:setinfo(dirpath, names)
    " TODO
endfunc

func! s:getinfo(dirpath, names)
    " TODO
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

func! s:callback(id, result)
    if a:result == -1
        return
    endif
    let dirpath = getwinvar(a:id, 'dirpath')
    let names = getwinvar(a:id, 'names')
    let name = names[a:result - 1]
    " TODO: safe path construction
    let path = dirpath . '/' . name
    echohl path
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
    return paths
endfunc

func! s:filter(id, key)
    let dirpath = getwinvar(a:id, 'dirpath')
    let names = getwinvar(a:id, 'names')

    " サブディレクトリを表示
    if a:key is# "\<Enter>"
        call win_execute(a:id, 'let w:name = getline(".")')
        let name = getwinvar(a:id, 'name')
        let name_is_dir = name[-1:] == '/'
        if name_is_dir
            let subdir = $'{dirpath}/{s:trimslash(name)}'
            call setwinvar(a:id, 'dirpath', subdir)
            let names = s:listdir(subdir)
            call setwinvar(a:id, 'names', names)
            call popup_settext(a:id, names)
            call popup_setoptions(a:id, #{title: s:title(subdir)})
            return 1
        else
            return popup_filter_menu(a:id, a:key)
        endif
    endif

    if a:key is# '-'
        " TODO: 一つ上のディレクトリに移動
        let parent = fnamemodify(dirpath, ':h')
        call setwinvar(a:id, 'dirpath', parent)
        let names = s:listdir(parent)
        call setwinvar(a:id, 'names', names)
        call popup_settext(a:id, names)
        call popup_setoptions(a:id, #{title: s:title(parent)})
        return 1
    endif

    if a:key is# 'r'
        " TODO: リロード
    endif

    if a:key is# 'h'
        " TODO: 隠しファイルの表示をトグル
    endif

    return popup_filter_menu(a:id, a:key)
endfunc
