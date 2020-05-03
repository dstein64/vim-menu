" TODO: add handling for -sep-
" TODO: popup menu that shows menu items. Maybe use built-in popup
" functionality.
" TODO: make sure you're always using the right :menu (e.g., :nmenu)
" TODO: Vim's popup_menu() probably won't be sufficient, but it's a good idea
" for styling, etc.
" TODO: Add titles to the menu (e.g., File, Edit, Edit > Find)

" XXX: When preparing and updating menus, there are redundant calls to :nmenu.
" This approach is simpler and more readable than calling and parsing once,
" and there are no noticeable performance implications when used with the
" default menu.

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

" Returns true if the specified path corresponds to a leaf.
function! s:IsLeaf(path) abort
  " Leaf items have 3 lines: "--- Menus ---", parent, command
  return len(split(execute('nmenu ' . a:path), '\n')) ==# 3
endfunction

function! s:IsSeparator(name) abort
  return a:name =~# '^-.*-$'
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
    let l:path2 = s:Qualify([l:name])
    if len(a:path) ># 0
      let l:path2 = a:path . '.' . l:path2
    endif
    let l:item = {
          \   'name': l:name,
          \   'subname': l:subname,
          \   'path': l:path2,
          \   'amp_idx': l:amp_idx,
          \   'is_leaf': s:IsLeaf(l:path2),
          \   'is_separator': s:IsSeparator(l:name),
          \ }
    call add(l:items, l:item)
  endfor
  return l:items
endfunction

" Returns true if all leaves under the specified path are <Nop>.
function! s:AllNops(path) abort
  let l:text = execute('nmenu ' . a:path)
  let l:lines = split(l:text, '\n')
  for l:line in l:lines
    " This pattern matches lines with commands.
    let cmd_pattern = '^ \+n[^-]* \+[^ ]\+'
    if l:line =~# cmd_pattern && l:line !~# '<Nop>$'
      return 0
    endif
  endfor
  return 1
endfunction

" Remove invalid and/or unsuitable items.
function! s:FilterMenuItems(items, root) abort
  let l:items = a:items[:]
  if a:root
    " Exclude ToolBar, PopUp, and TouchBar from the root menu.
    let l:exclusions = ['ToolBar', 'PopUp', 'TouchBar']
    call filter(l:items, 'index(l:exclusions, v:val.name) ==# -1')
  endif
  let l:IsSep = {item -> s:IsSeparator(item.name)}
  " Exlude non-separator entries that only have <Nop> subitems.
  call filter(l:items, 'l:IsSep(v:val) || !s:AllNops(v:val.path)')
  " Drop consecutive separators and separators on the boundary.
  let l:items2 = []
  let l:len = len(l:items)
  for l:idx in range(l:len)
    let l:item = l:items[l:idx]
    let l:is_sep = l:item.is_separator
    " Don't add separators to the beginning of the list
    if len(l:items2) ==# 0 && l:is_sep | continue | endif
    " Don't add a separator if the next element is a separator
    if l:is_sep && l:idx + 1 <# l:len && l:items[l:idx + 1].is_separator
      continue
    endif
    " Don't add a separator to the end
    if l:is_sep && l:idx + 1 ==# l:len | continue | endif
    call add(l:items2, l:item)
  endfor
  return l:items2
endfunction

" Show the specified menu, or if the item is a leaf node, then execute.
function! s:ShowMenu(path) abort
  " TODO: clear any existing menus (or possibly do this when items are
  " selected)
  if s:IsLeaf(a:path)
    throw 'No menu: ' . a:path
  endif
  let l:parts = s:Unqualify(a:path)
  let l:items = s:GetMenuItems(a:path)
  let l:items = s:FilterMenuItems(l:items, len(l:parts) ==# 0)
  let l:title = 'Menu'
  if len(l:parts) ># 0
    let l:title .= ' | ' . join(l:parts, ' > ')
  endif
  " TODO: delete echo below
  echo l:title
  for l:item in l:items
    echo l:item
  endfor
endfunction

function! s:Beep() abort
  execute "normal \<esc>"
endfunction

function! menu#Menu(path) abort
  try
    if mode() !=# 'n'
      throw 'Menu only available in normal mode'
    endif
    silent! source $VIMRUNTIME/menu.vim
    let l:path = a:path
    " Remove trailing dot if present (inserted by -complete=menu)
    if l:path =~# '\.$' && l:path !~# '\\\.$'
      let l:path = l:path[:-2]
    endif
    call s:ShowMenu(l:path)
  catch
    if g:menu_debug_mode
      echohl ErrorMsg | echo v:throwpoint | echohl None
    endif
    echohl ErrorMsg | echo 'vim-menu: ' . v:exception | echohl None
    call s:Beep()
  endtry
endfunction
