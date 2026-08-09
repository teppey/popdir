" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

let s:cpo_save = &cpo
set cpo&vim

if !exists('g:popdir_maxheight')
    let g:popdir_maxheight = 40
endif

func! popdir#open()
    func! s:compare(a, b) closure
        let a_path = cwd . '/' . trim(a:a, '/', 2)
        let b_path = cwd . '/' . trim(a:b, '/', 2)

        let a_is_dir = a:a[-1:] == '/'
        let b_is_dir = a:b[-1:] == '/'

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

    func! s:callback(id, result) closure
        if a:result == -1
            return
        endif
        call popup_settext(a:id, ['foo', 'bar', 'baz'])
        return
        let path = paths[a:result - 1]
        execute "silent edit " . path
    endfunc

    let cwd = getcwd()
    let paths = []
    for info in readdirex(cwd)
        let name = info.name
        if info.type == 'dir'
            let name .= '/'
        endif
        call add(paths, name)
    endfor
    call sort(paths, function('s:compare'))
    let cwd_tilde = substitute(cwd, $HOME, '~', '')
    let winid = popup_menu(paths, #{
                \ maxheight: g:popdir_maxheight,
                \ minheight: min([len(paths), g:popdir_maxheight]),
                \ title: printf(' %s: ', cwd_tilde),
                \ callback: function('s:callback'),
                \ filter: function('s:filter'),
                \})
    call setwinvar(winid, 'curdir', cwd)
endfunc

func! s:trimslash(s)
    return trim(a:s, '/', 2)
endfunc

func! s:listdir(dir)
    let paths = []
    for info in readdirex(a:dir)
        let name = info.name
        if info.type == 'dir'
            let name .= '/'
        endif
        call add(paths, name)
    endfor
    return paths
endfunc

func! s:filter(id, key)
    " サブディレクトリを表示
    if a:key is# "\<Enter>"
        call win_execute(a:id, 'let w:name = getline(".")')
        let name = getwinvar(a:id, 'name')
        let curdir = getwinvar(a:id, 'curdir')
        let name_is_dir = name[-1:] == '/'
        if name_is_dir
            let subdir = $'{curdir}/{s:trimslash(name)}'
            call setwinvar(a:id, 'curdir', subdir)
            call popup_settext(a:id, s:listdir(subdir))
            let title = fnamemodify(subdir, ':~')
            call popup_setoptions(a:id, #{title: $' {title} '})
        endif
        return 1
    endif

    if a:key is# '-'
        " TODO: 一つ上のディレクトリに移動
        let curdir = getwinvar(a:id, 'curdir')
        let parent = fnamemodify(curdir, ':h')
        call setwinvar(a:id, 'curdir', parent)
        " TODO: ソート
        call popup_settext(a:id, s:listdir(parent))
        let title = fnamemodify(parent, ':~')
        call popup_setoptions(a:id, #{title: $' {title} '})
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
