if get(g:, 'loaded_menu', 0)
  finish
endif
let g:loaded_menu = 1

let s:save_cpo = &cpo
set cpo&vim

if !exists(':Menu')
  " Save the view and pass it to menu#Menu for immediately restoring, since
  " passing a range to menu#Menu will result in the cursor being moved to the
  " first column of the first line in the range (even with no selection,
  " cursor would be moved to the first column).
  command -range -nargs=? -complete=menu Menu
        \ let s:view = winsaveview()
        \ | <line1>,<line2>:call menu#Menu(<q-args>, <range>, s:view)
  if !hasmapto(':Menu')
    silent! noremap <unique> <leader>m :Menu<cr>
  endif
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
highlight default link MenuSelected Visual
highlight default link MenuId LineNr
highlight default link MenuLeafIcon WarningMsg
highlight default link MenuNonTermIcon Directory
highlight default link MenuShortcut ModeMsg
highlight default link MenuRightAlignedText MoreMsg

" The built-in Windows terminal emulator (used for CMD, Powershell, and WSL)
" does not properly display the Unicode right-pointing triangle and heavy
" asterisk, using the default font, Consolas. The characters display properly
" on Cygwin using its default font, Lucida Console, and also when using
" Consolas.
let s:win_term = has('win32') || menu#OnWsl()
if !s:win_term && has('multi_byte') && &encoding ==# 'utf-8'
  " Right-pointing triangle
  let s:default_nonterm_char = nr2char(0x25B6)
  " Heavy asterisk
  let s:default_leaf_char = nr2char(0x2731)
else
  let s:default_nonterm_char = '>'
  let s:default_leaf_char = '*'
endif
let g:menu_nonterm_char = get(g:, 'menu_nonterm_char', s:default_nonterm_char)
let g:menu_leaf_char = get(g:, 'menu_leaf_char', s:default_leaf_char)
let g:menu_caching = get(g:, 'menu_caching', 1)

let &cpo = s:save_cpo
unlet s:save_cpo
