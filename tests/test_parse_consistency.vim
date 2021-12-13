" Test that menu parsing is consistent across VimScript and Lua.

" Load the default menu, which would ordinarily be done when menu#Menu is
" called, but that's not called here.
silent! source $VIMRUNTIME/menu.vim
" Add additional menus to test.
noremenu &Menu1.I&tem1 :echo<cr>
noremenu Menu1.&Item2 :echo<cr>
noremenu M&&e\.nu1.I&&te&m3 :echo<cr>
noremenu Menu1.Item&4 :echo<cr>
noremenu &&Menu&2.I&tem1&& :echo<cr>
noremenu M&&enu2.I\.tem5\. :echo<cr>
noremenu &&Me\.\.\.nu2\..&&I&&&&tem6&&&& :echo<cr>
noremenu \.Menu2.\.Item&7\. :echo<cr>

let s:menu_vimscript = funcref(menu#Sid() . 'ParseMenuVimScript')('n')
let s:menu_lua = funcref(menu#Sid() . 'ParseMenuLua')('n')
call assert_equal(s:menu_vimscript, s:menu_lua)
