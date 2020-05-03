" TODO: add handling for -sep-
" TODO: popup menu that shows menu items. Maybe use built-in popup
" functionality.
" TODO: make sure you're always using the right :menu (e.g., :nmenu)
" TODO: Vim's popup_menu() probably won't be sufficient, but it's a good idea
" for styling, etc.
" TODO: Add titles to the menu (e.g., File, Edit, Edit > Find)

" Given a menu item path (as a List), return its qualified name.
function! s:Qualify(path) abort
  let l:path = a:path[:]
  call map(l:path, 'substitute(v:val, ''\.'', ''\\.'', "g")')
  call map(l:path, 'substitute(v:val, " ", ''\\ '', "g")')
  return join(l:path, '.')
endfunction

" Given a qualified name, return a menu item path (as a List). Underlying
" parts are not escaped.
function! s:Unqualify(qualified) abort
  " Replace '\.' with a tab char, which will be (partially*) reverted later.
  " This works because unescaped tabs don't work in menu names.
  " * 'partially' since tabs are later converted to '.' (unescaped), not '\.'.
  let l:encoded = substitute(a:qualified, '\\\.', "\t", 'g')
  let l:parts = split(l:encoded, '\.')
  call map(l:parts, 'substitute(v:val, "\t", ''\.'', "g")')
  call map(l:parts, 'substitute(v:val, ''\\ '', " ", "g")')
  return l:parts
endfunction

" Given a menu item path, return the submenu items.
function! s:GetMenuItems(path) abort
  let l:text = execute('nmenu ' . a:path)
  let l:lines = split(l:text, '\n')
  let l:pattern =  'v:val =~# "^\\d"'
  if len(a:path) ># 0
    let l:pattern = 'v:val =~# "^  \\d"'
  endif
  call filter(l:lines, l:pattern)
  let l:items = []
  for l:line in l:lines
    let l:full_name = l:line[matchstrpos(l:line, ' *\d\+ ')[2]:]
    let [l:name, l:subname; l:_] = split(l:full_name, '\^I\|$', 1)
    let l:amp_idx = stridx(l:name, '&')
    if l:amp_idx !=# -1
      let l:name = substitute(l:name, '&', '', '')
    endif
    let l:qualified = s:Qualify([l:name])
    if len(a:path) ># 0
      let l:qualified = a:path . '.' . l:qualified
    endif
    let l:item = {
          \   'name': l:name,
          \   'subname': l:subname,
          \   'qualified': l:qualified,
          \   'amp_idx': l:amp_idx,
          \ }
    call add(l:items, l:item)
  endfor
  return l:items
endfunction

" Show the specified menu, or if this a menu item, then execute.
function! s:ShowMenu(path) abort
  " TODO: clear any existing menus (or possibly do this when items are
  " selected)
  let l:items = s:GetMenuItems(a:path)
  if len(l:items) ==# 0
    if execute('nmenu ' . a:path) =~# '\n *[^ ]\+ \+<Nop>$'
      throw 'Cannot execute menu item: ' . a:path
    endif
    execute 'emenu ' . a:path
    return
  endif
  let l:parts = s:Unqualify(a:path)
  let l:title = 'Menu'
  if len(l:parts) ># 0
    let l:title .= ' | ' . join(l:parts, ' > ')
  endif
  echo l:title
  if len(l:parts) ># 0
    " Exclude ToolBar, PopUp, and TouchBar from the top level menu.
    let l:exclusions = ['ToolBar', 'PopUp', 'TouchBar']
    call filter(l:items, 'index(l:exclusions, v:val.name) ==# -1')
  endif
  for l:item in l:items
    echo l:item
  endfor
endfunction

function! s:Beep() abort
  execute "normal \<esc>"
endfunction

function! menu#Menu(path) abort
  if mode() !=# 'n'
    call s:Beep()
    return
  endif
  silent! source $VIMRUNTIME/menu.vim
  try
    call s:ShowMenu(a:path)
  catch
    if g:menu_debug_mode
      echohl ErrorMsg | echo v:throwpoint | echohl None
    endif
    echohl ErrorMsg | echo v:exception | echohl None
    call s:Beep()
  endtry
endfunction
