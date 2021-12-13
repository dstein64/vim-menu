" Test that menu parsing is consistent across VimScript and Lua.

" Load the default menu, which would ordinarily be done when menu#Menu is
" called, but that's not called here.
silent! source $VIMRUNTIME/menu.vim
let s:menu_vimscript = funcref(menu#Sid() . 'ParseMenuVimScript')('n')
let s:menu_lua = funcref(menu#Sid() . 'ParseMenuLua')('n')
call assert_equal(s:menu_vimscript, s:menu_lua)
