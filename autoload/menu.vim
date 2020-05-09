" TODO: add an option to use popup/float windows
" TODO: make sure you're always using the right :menu (e.g., :nmenu)
" TODO: Add titles to the menu (e.g., File, Edit, Edit > Find)
" TODO: Get the longest name in :nmenu to figure out how wide the text should
" be (for the RHS text).
" TODO: Create a syntax rule so that the :sign highlighting doesn't extend too
" far. See $VIMRUNTIME/syntax/colortest.vim.
" TODO: Press K on leaf to show command.

" *************************************************
" * Globals
" *************************************************

let s:down_chars = ['j', "\<down>"]
let s:up_chars = ['k', "\<up>"]
let s:back_chars = ['h', "\<left>"]
let s:select_chars = ['l', "\<right>", "\<cr>", "\<space>"]
let s:quit_chars = ["\<esc>", 'Z', 'q']

" Action types for ShowMenu()
let s:exit_action = 1
let s:select_action = 2
let s:back_action = 3

" Exclude ToolBar, PopUp, and TouchBar from the root menu.
let s:root_exclusions = ['ToolBar', 'PopUp', 'TouchBar']

" *************************************************
" * Utils
" *************************************************

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

" Returns a dictionary that maps each menu path to the corresponding menu
" item.
function! s:ParseMenu(mode) abort
  let l:lines = split(execute(a:mode . 'menu'), '\n')[1:]
  call map(l:lines, '"  " . v:val')
  let l:lines = ['0 '] + l:lines
  let l:depth = -1
  let l:output = {}
  let l:stack = [{'children': []}]
  for l:idx in range(len(l:lines))
    let l:line = l:lines[l:idx]
    if l:line =~# '^ *\d'
      let l:depth2 = len(matchstr(l:line, '^ *')) / 2
      if l:depth2 <=# l:depth
        for l:x in range(l:depth - l:depth2 + 1)
          call remove(l:stack, -1)
        endfor
      endif
      let l:full_name = l:line[matchstrpos(l:line, ' *\d\+ ')[2]:]
      if match(l:full_name, '\^I') !=# -1
        let [l:name, l:subname] = split(l:full_name, '\^I')
      else
        let [l:name, l:subname] = [l:full_name, '']
      endif
      let l:amp_idx = stridx(l:name, '&')
      if l:amp_idx !=# -1
        let l:name = substitute(l:name, '&', '', '')
      endif
      let l:is_separator = l:name =~# '^-.*-$'
      let l:parents = []
      for l:parent in l:stack[2:]
        call add(l:parents, l:parent.name)
      endfor
      let l:is_leaf = l:idx + 1 < len(l:lines)
            \ && l:lines[l:idx + 1] !~# '^ *\d'
      let l:path = s:Qualify(l:parents + [l:name])
      let l:item = {
            \   'name': l:name,
            \   'subname': l:subname,
            \   'path': l:path,
            \   'amp_idx': l:amp_idx,
            \   'children': [],
            \   'is_separator': l:is_separator,
            \   'is_root': len(l:parents) ==# 0,
            \   'is_leaf': l:is_leaf
            \ }
      call add(l:stack[-1]['children'], l:item)
      call add(l:stack, l:item)
      let l:output[l:path] = l:item
      let l:depth = l:depth2
    else
      if has_key(l:stack[-1], 'mapping')
        throw 'Mapping already exists'
      endif
      let l:stack[-1].mapping = trim(l:line)
    endif
  endfor
  return l:output
endfunction

" Returns true if all leaves under the specified item are <Nop>.
function! s:AllNops(item) abort
  " TODO: implement for real
  " TODO: use the .mapping field for leaves.
  return 0
endfunction

" Remove invalid and/or unsuitable items.
function! s:FilterMenuItems(items, root) abort
  let l:items = a:items[:]
  if a:root
    call filter(l:items, 'index(s:root_exclusions, v:val.name) ==# -1')
  endif
  " Exlude non-separator entries that only have <Nop> subitems.
  call filter(l:items, 'v:val.is_separator || !s:AllNops(v:val)')
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

" Attach an ID to menu items. IDs start at 1 and increment for non-separators.
" IDs start at -1 and decrement for non-separators.
function! s:AttachId(items)
  let l:items = deepcopy(a:items[:])
  let l:id = 1
  let l:sep_id = -1
  for l:item in l:items
    let l:is_sep = l:item.is_separator
    let l:item.id = l:is_sep ? l:sep_id : l:id
    if is_sep
      let l:item.id = l:sep_id
      let l:sep_id -= 1
    else
      let l:item.id = l:id
      let l:id += 1
    endif
  endfor
  return l:items
endfunction

function! s:GetChar()
  try
    while 1
      let l:char = getchar()
      if v:mouse_win ># 0 | continue | endif
      if l:char ==# "\<CursorHold>" | continue | endif
      break
    endwhile
  catch
    " E.g., <c-c>
    let l:char = char2nr("\<esc>")
  endtry
  if type(l:char) ==# v:t_number
    let l:char = nr2char(l:char)
  endif
  return l:char
endfunction

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

" Show the specified menu, with the specified item selected.
function! s:ShowMenu(parsed, path, id) abort
  " TODO: temporarilty set state (e.g., no hlsearch)
  " TODO: clear any existing menus (or possibly do this when items are
  " selected)
  let l:parts = s:Unqualify(a:path)
  if len(a:parsed) <=# 1
    throw 'No available menus. See ":help creating-menus."'
  endif
  let l:items = a:parsed[a:path].children
  if a:parsed[a:path].is_leaf | throw 'No menu: ' . a:path | endif
  let l:root = len(l:parts) ==# 0
  let l:items = s:FilterMenuItems(l:items, l:root)
  let l:items = s:AttachId(l:items)
  let l:title = 'Menu'
  if len(l:parts) ># 0
    let l:title .= ' | ' . join(l:parts, ' > ')
  endif
  " TODO: reuse existing buffer so that usage doesn't make the buffer list
  " numbers get high. As part of this, make the buffer read-only and hidden...
  botright split +enew
  setlocal scrolloff=0
  setlocal signcolumn=no
  setlocal nocursorline
  setlocal nonumber
  setlocal norelativenumber
  let &l:statusline = l:title

  " TODO: delete
  " Example l:items
  " Added an 'id' field too. And a 'mapping' field for leaves.
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'File', 'amp_idx': 0, 'subname': '', 'path': 'File'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Edit', 'amp_idx': 0, 'subname': '', 'path': 'Edit'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Tools', 'amp_idx': 0, 'subname': '', 'path': 'Tools'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Syntax', 'amp_idx': 0, 'subname': '', 'path': 'Syntax'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Buffers', 'amp_idx': 0, 'subname': '', 'path': 'Buffers'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Dan', 'amp_idx': -1, 'subname': '', 'path': 'Dan'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Window', 'amp_idx': -1, 'subname': '', 'path': 'Window'}
  "{'is_leaf': 0, 'is_separator': 0, 'name': 'Help', 'amp_idx': 0, 'subname': '', 'path': 'Help'}

  " The last item can't be a separator, so don't have to handle the different
  " indexing used for separators.
  let l:id_len = len(string(l:items[-1].id))
  let l:selected_line = 1
  for l:item in l:items
    let l:id_pad = l:id_len - len(string(l:item.id))
    let l:line = printf('%*s[%s] ', l:id_pad, '', l:item.id)
    if l:item.is_leaf
      let l:symbol = g:menu_leaf_char
      let l:symbol_hl = 'MenuLeafIcon'
    else
      let l:symbol = g:menu_nonterm_char
      let l:symbol_hl = 'MenuNonTermIcon'
    endif
    if strwidth(l:symbol) !=# 1 | let l:symbol = ' ' | endif
    let l:symbol_pos = [[line('$'), len(l:line) + 1, len(l:symbol)]]
    call matchaddpos(l:symbol_hl, l:symbol_pos)
    let l:line .= l:symbol . ' ' . l:item.name
    if l:item.is_separator | let l:line = '' | endif
    if l:item.id ==# a:id | let l:selected_line = line('$') | endif
    call append(line('$') - 1, l:line)
  endfor
  call matchadd('MenuID', '^ *\zs\[\d\+\]\ze')

  normal! Gddgg0
  execute 'resize ' . line('$')
  execute 'normal! ' . l:selected_line . 'G'
  echo '  vim-menu'
  let l:action = {}
  while 1
    sign unplace 1
    let l:line_before = line('.')
    execute printf('sign place 1 line=%s name=menu_selected buffer=%s',
          \ l:line_before, bufnr('%'))
    redraw
    " TODO: more chars: numbers, control chars (q for quit)
    let l:char = s:GetChar()
    if s:Contains(s:quit_chars, l:char)
      let l:action.type = s:exit_action
      break
    elseif s:Contains(s:down_chars, l:char)
      normal! j
    elseif s:Contains(s:up_chars, l:char)
      normal! k
    elseif s:Contains(s:back_chars, l:char)
      let l:action.type = s:back_action
      break
    elseif s:Contains(s:select_chars, l:char)
      let l:action.type = s:select_action
      let l:action.selection = l:items[l:line_before - 1]
      break
    elseif l:char ==# 'd'
      execute "normal! \<c-d>"
    elseif l:char ==# 'u'
      execute "normal! \<c-u>"
    elseif l:char ==# 'g'
      normal! gg
    elseif s:Contains(['G', 'H', 'M', 'L', '{', '}'], l:char)
      execute 'normal! ' . l:char
    endif
    let l:line_after = line('.')
    " Skip separators. Running this once assumes no consecutive separators,
    " which is imposed above.
    if l:items[l:line_after - 1].is_separator
      if l:line_after - l:line_before ># 0
        normal! j
      else
        normal! k
      endif
    endif
  endwhile
  bdelete!
  return l:action
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
    let l:selection_ids = []
    let l:selection_id = 1
    let l:parsed = s:ParseMenu(mode())
    while 1
      let l:action = s:ShowMenu(l:parsed, l:path, l:selection_id)
      if l:action.type ==# s:exit_action
        break
      elseif l:action.type ==# s:select_action
        if l:action.selection.is_leaf 
          execute 'emenu ' . l:action.selection.path
          break
        else
          let l:path = l:action.selection.path
          call add(l:selection_ids, l:action.selection.id)
          let l:selection_id = 1
        endif
      elseif l:action.type ==# s:back_action
        if l:path ==# '' | break | endif
        let l:parts = s:Unqualify(l:path)
        let l:path = s:Qualify(l:parts[:-2])
        if len(l:selection_ids) ># 0
          let l:selection_id = remove(l:selection_ids, -1)
        elseif len(l:parts) ==# 1 && s:Contains(s:root_exclusions, l:parts[0])
          " For items excluded from the root menu, don't go back to the root
          " menu.
          break
        else
          let l:selection_id = 1
        endif
      else
        throw 'Unsupported action'
      endif
    endwhile
  catch
    if g:menu_debug_mode
      echohl ErrorMsg | echo v:throwpoint | echohl None
    endif
    echohl ErrorMsg | echo 'vim-menu: ' . v:exception | echohl None
    call s:Beep()
  endtry
endfunction
