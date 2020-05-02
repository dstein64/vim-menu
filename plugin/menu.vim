if get(g:, 'loaded_menu', 0)
  finish
endif
let g:loaded_menu = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists(':Menu')
  command -nargs=? -complete=menu Menu :call menu#Menu(<q-args>)
endif

let &cpo = s:save_cpo
unlet s:save_cpo
