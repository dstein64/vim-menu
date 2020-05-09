if exists('b:current_syntax')
  finish
endif

let s:cpo_save = &cpo
set cpo&vim

syntax match MenuId /^ *\zs\[\d\+\]\ze/

if has('conceal')
  setlocal concealcursor=nvc
  setlocal conceallevel=3
  execute 'syntax match MenuNonTermIcon /\%x01'
        \ . g:menu_nonterm_char . '/ contains=MenuCtrlA'
  execute 'syntax match MenuLeafIcon /\%x01'
        \ . g:menu_leaf_char . '/ contains=MenuCtrlA'
  syntax match MenuCtrlA /\%x01/ contained conceal
endif

let b:current_syntax = 'menu'

let &cpo = s:cpo_save
unlet s:cpo_save
