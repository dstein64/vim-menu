" Test that menu parsing is consistent across VimScript/Lua in Neovim and
" VimScript/Vim9 in Vim.

" Load the default menu, which would ordinarily be done when menu#Menu is
" called, but that's not called here.
silent! source $VIMRUNTIME/menu.vim
" Add additional menus to test.
noremenu &Menu1.I&tem1 :echo<cr>
noremenu Menu1.&Item2 :echo<cr>
noremenu M&&e\.nu1.I&&te&m3 :echo<cr>
noremenu Menu1.Item&4 :echo<cr>
noremenu &&Menu&2.I&tem1&& :echo<cr>
noremenu M&&enu2.I\.tem2\. :echo<cr>
noremenu &&Me\.\.\.nu2\..&&I&&&&tem3&&&& :echo<cr>
noremenu \.Menu2.\.Item&4\. :echo<cr>
noremenu Men&u&3.Item1 :echo<cr>
noremenu Me&nu4&.Item1 :echo<cr>
noremenu Menu5&.Item2 :echo<cr>
noremenu Menu&&&6.Item2 :echo<cr>
noremenu Menu7&&&.Item2 :echo<cr>
noremenu <silent> Menu8.Item1<tab>x<tab> :echo<cr>

let s:menu_vimscript = function(menu#Sid() . 'ParseMenuVimScript')('n')
if has('nvim')
  let s:menu_opt = function(menu#Sid() . 'ParseMenuLua')('n')
else
  let s:menu_opt = menu9#ParseMenu('n')
endif
call assert_equal(s:menu_vimscript, s:menu_opt)
