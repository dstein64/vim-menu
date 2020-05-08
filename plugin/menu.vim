if get(g:, 'loaded_menu', 0)
  finish
endif
let g:loaded_menu = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists(':Menu')
  command -nargs=? -complete=menu Menu :call menu#Menu(<q-args>)
endif

sign define menu_selected linehl=MenuSelected

" ************************************************************
" * User Configuration
" ************************************************************

let g:menu_debug_mode = get(g:, 'menu_debug_mode', 0)

" The default highlight groups (for colors) are specified below.
" Change these default colors by defining or linking the corresponding
" highlight group.
" E.g., the following will use the Error highlight for the selected menu item.
" :highlight link MenuSelected Error
" E.g., the following will use custom highlight colors for the selected menu
" item.
" :highlight WinInactive term=bold ctermfg=12 ctermbg=159 guifg=Blue guibg=LightCyan
highlight default link MenuSelected Search
highlight default link MenuId LineNr

let &cpo = s:save_cpo
unlet s:save_cpo
