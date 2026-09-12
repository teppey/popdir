vim9script

# File: popdir.vim
# Description: Display a list of directory entries in the popup window
# Author: Teppei Hamada <temada@gmail.com>
# Version: 0.1

import autoload 'popdir.vim'

command PopDir popdir.Open()
