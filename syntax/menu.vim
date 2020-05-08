if exists('b:current_syntax')
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syntax match MenuId /^ *\zs\[\d\+\]\ze/

let b:current_syntax = 'menu'

let &cpo = s:cpo_save
unlet s:cpo_save
