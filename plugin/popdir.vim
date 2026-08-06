" File: popdir.vim
" Description: Display a list of directory entries in the popup window
" Author: Teppei Hamada <temada@gmail.com>
" Version: 0.1

if exists('g:loaded_popdir')
  finish
endif
let g:loaded_popdir = 1

let s:cpo_save = &cpo
set cpo&vim

command PopDir call popdir#Open()

let &cpo = s:cpo_save
unlet s:cpo_save

