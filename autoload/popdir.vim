" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

let s:cpo_save = &cpo
set cpo&vim

if !exists('g:popdir_maxheight')
    let g:popdir_maxheight = 40
endif

func! popdir#Open()
    func! s:compare(a, b) closure
        let a_path = cwd . '/' . a:a
        let b_path = cwd . '/' . a:b
        " echo a_path

        if a:a == a:b
            return 0
        elseif a:a < a:b
            return -1
        else
            return 1
    endfunc

    func! s:Callback(id, result) closure
        if a:result == -1
            return
        endif
        let path = paths[a:result - 1]
        execute "silent edit " . path
    endfunc

    let cwd = getcwd()
    let paths = readdir(cwd)
    call sort(paths, function('s:compare'))
    let cwd_tilde = substitute(cwd, $HOME, '~', '')
    let winid = popup_menu(paths, #{
                \ maxheight: g:popdir_maxheight,
                \ minheight: min([len(paths), g:popdir_maxheight]),
                \ title: printf(' %s: ', cwd_tilde),
                \ callback: function('s:Callback'),
                \})
endfunc

