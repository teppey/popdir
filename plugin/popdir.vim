vim9script

# File: popdir.vim
# Description: Directory browser in popup window.
# Author: Teppei Hamada <temada@gmail.com>
# Version: 0.1

import autoload 'popdir.vim'

command -nargs=? -complete=dir PopDir popdir.Open(<q-args>)
