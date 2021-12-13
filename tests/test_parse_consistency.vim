" Test that menu parsing is consistent across VimScript and Lua.

let s:menu_vimscript = funcref(menu#Sid() . 'ParseMenuVimScript')('n')
let s:menu_lua = funcref(menu#Sid() . 'ParseMenuLua')('n')
call assert_equal(s:menu_vimscript, s:menu_lua)
call assert_equal('temporary', 'error1')
call assert_equal('temporary', 'error2')
