" TODO: make sure you're always using the right :menu (e.g., :nmenu)
" TODO: Add titles to the menu (e.g., File, Edit, Edit > Find)
" TODO: Get the longest name in :nmenu to figure out how wide the text should
" be (for the RHS text).
" TODO: Create a syntax rule so that the :sign highlighting doesn't extend too
" far. See $VIMRUNTIME/syntax/colortest.vim.

" *************************************************
" * Globals
" *************************************************

let s:down_chars = ['j', "\<down>"]
let s:up_chars = ['k', "\<up>"]
let s:back_chars = ['h', "\<left>"]
let s:select_chars = ['l', "\<right>", "\<cr>", "\<space>"]
let s:quit_chars = ["\<esc>", 'Z', 'q']

let s:code0 = char2nr('0')
let s:code1 = char2nr('1')
let s:code9 = char2nr('9')

" Action types for PromptLoop()
let s:exit_action = 1
let s:select_action = 2
let s:back_action = 3

" Exclude ToolBar, PopUp, and TouchBar from the root menu.
let s:root_exclusions = ['ToolBar', 'PopUp', 'TouchBar']

" *************************************************
" * Core
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
        throw 'Mapping already exists.'
      endif
      let l:trimmed = trim(l:line)
      let l:split_idx = match(l:trimmed, ' ')
      let l:lhs = l:trimmed[:l:split_idx - 1]
      let l:rhs = trim(l:trimmed[l:split_idx:])
      let l:stack[-1].mapping = [l:lhs, l:rhs]
    endif
  endfor
  return l:output
endfunction

" Returns true if all leaves under an item are disabled or <Nop>.
function! s:IsDisabled(item) abort
  let l:mappings = []
  let l:stack = [a:item]
  while len(l:stack) ># 0
    let l:candidate = remove(l:stack, -1)
    if l:candidate.is_leaf
      let l:mapping = l:candidate.mapping
      let l:disabled = mapping[0] =~# '-' || mapping[1] ==# '<Nop>'
      if !l:disabled | return 0 | endif
    else
      call extend(l:stack, l:candidate.children)
    endif
  endwhile
  return 1
endfunction

" Remove invalid and/or unsuitable items.
function! s:FilterMenuItems(items, root) abort
  let l:items = a:items[:]
  if a:root
    call filter(l:items, 'index(s:root_exclusions, v:val.name) ==# -1')
  endif
  " Exlude non-separator entries that only have <Nop> subitems.
  call filter(l:items, 'v:val.is_separator || !s:IsDisabled(v:val)')
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
" matchadd and matchaddpos are used for colorization. This is applied
" per-window, as opposed to per-buffer. This is not a problem here since the
" window is only used for a menu (i.e., it's closed as part of usage)
function! s:CreateMenu(parsed, path, id) abort
  " TODO: temporarilty set state (e.g., no hlsearch)
  " TODO: clear any existing menus (or possibly do this when items are
  " selected)
  let l:parts = s:Unqualify(a:path)
  let l:not_avail_err = 'No available menus. See ":help creating-menus".'
  if len(a:parsed) <=# 1 | throw l:not_avail_err | endif
  if !has_key(a:parsed, a:path) || a:parsed[a:path].is_leaf
    throw 'No menu: ' . a:path
  endif
  let l:items = a:parsed[a:path].children
  let l:items = s:FilterMenuItems(l:items, a:parsed[a:path].is_root)
  if len(l:items) ==# 0 | throw l:not_avail_err | endif
  let l:items = s:AttachId(l:items)
  let l:title = join(l:parts, ' > ')
  if has('multi_byte') && &encoding ==# 'utf-8'
    " Hamburger button
    let l:title = nr2char(0x2630) . ' ' . l:title
  endif
  if len(l:title) ==# 0 | let l:title = ' ' | endif
  " TODO: reuse existing buffer so that usage doesn't make the buffer list
  " numbers get high. As part of this, make the buffer read-only and hidden...
  botright split +enew
  setlocal scrolloff=0
  setlocal signcolumn=no
  setlocal nocursorline
  setlocal nonumber
  setlocal norelativenumber
  let &l:statusline = l:title
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
  return l:items
endfunction

" Display leaf item mapping, with special keys properly colored.
function! s:ShowItemInfo(item) abort
  let l:mapping = a:item.mapping[1]
  redraw
  while strchars(l:mapping) ># 0
    let l:match = matchstr(l:mapping, '^<[^ <>]\+>')
    if l:match !=# ''
      echohl SpecialKey
      echon l:match
      echohl None
      let l:mapping = l:mapping[len(l:match):]
    else
      let l:char = strcharpart(l:mapping, 0, 1)
      echon l:char
      let l:mapping = l:mapping[len(l:char):]
    endif
  endwhile
  echohl Question
  echo '[Press any key to continue]'
  call s:GetChar()
  echohl None
endfunction

" Scans user input for a item ID. The first argument specifies the initial
" output, the second argument specified the number of available items, and the
" optional third argument specifies digits that have already been accumulated.
function! s:ScanItemIdDigits(prompt, item_count, ...)
  let l:digits = get(a:, 1, [])[:]
  for l:digit in l:digits
    let l:code = char2nr(l:digit)
    if l:code <# s:code0 || l:code ># s:code9 | return 0 | endif
  endfor
  while 1
    if len(l:digits) ># 0
      if l:digits[0] ==# '0' | return 0 | endif
      if l:digits[-1] ==# "\<cr>"
        call remove(l:digits, -1)
        break
      endif
      let l:code = char2nr(l:digits[-1])
      if l:code <# s:code0 || l:code ># s:code9 | return 0 | endif
      if str2nr(join(l:digits + ['0'], '')) ># a:item_count
        break
      endif
      if len(l:digits) ==# len(string(a:item_count))
        return 0
      endif
    endif
    redraw | echo a:prompt . join(l:digits, '')
    call add(l:digits, s:GetChar())
  endwhile
  let l:item_id = str2nr(join(l:digits, ''))
  return l:item_id <=# a:item_count ? l:item_id : 0
endfunction

" Returns a List that maps item IDs to their corresponding line numbers.
function! s:CreateItemLineLookup(items) abort
  let l:lookup = [-1]
  for l:idx in range(len(a:items))
    let l:item = a:items[l:idx]
    if l:item.is_separator | continue | endif
    if l:item.id !=# len(l:lookup)
      throw 'Assertion failed.'
    endif
    call add(l:lookup, l:idx + 1)
  endfor
  return l:lookup
endfunction

" Gets and processes user menu interactions (movements) and returns when an
" action (exit, select, back) is taken.
function! s:PromptLoop(items) abort
  let l:action = {}
  let l:prompt = 'vim-menu> '
  let l:item_line_lookup = s:CreateItemLineLookup(a:items)
  while 1
    sign unplace 1
    let l:line_before = line('.')
    let l:item = a:items[l:line_before - 1]
    execute printf('sign place 1 line=%s name=menu_selected buffer=%s',
          \ l:line_before, bufnr('%'))
    redraw | echo l:prompt
    let l:char = s:GetChar()
    let l:code = char2nr(l:char)
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
      let l:action.selection = l:item
      break
    elseif l:code >=# s:code1 && l:code <=# s:code9
      let l:item_id = s:ScanItemIdDigits(l:prompt, a:items[-1].id, [l:char])
      if l:item_id !=# 0
        execute 'normal! ' . l:item_line_lookup[l:item_id] . 'G'
      endif
    elseif l:char ==# 'd'
      execute "normal! \<c-d>"
    elseif l:char ==# 'u'
      execute "normal! \<c-u>"
    elseif l:char ==# 'g'
      normal! gg
    elseif s:Contains(['G', 'H', 'M', 'L', '{', '}'], l:char)
      execute 'normal! ' . l:char
    elseif l:char ==# 'K' && l:item.is_leaf
      call s:ShowItemInfo(l:item)
    endif
    let l:line_after = line('.')
    " Skip separators. Running this once assumes no consecutive separators,
    " which is imposed above.
    if a:items[l:line_after - 1].is_separator
      if l:line_after - l:line_before ># 0
        normal! j
      else
        normal! k
      endif
    endif
  endwhile
  return l:action
endfunction

function! s:Beep() abort
  execute "normal \<esc>"
endfunction

function! menu#Menu(path) abort
  try
    echohl None
    if mode() !=# 'n'
      throw 'Menu only available in normal mode.'
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
      let l:items = s:CreateMenu(l:parsed, l:path, l:selection_id)
      let l:action = s:PromptLoop(l:items)
      bdelete!
      if l:action.type ==# s:exit_action
        break
      elseif l:action.type ==# s:select_action
        if l:action.selection.is_leaf 
          let l:execute_pending = 'emenu ' . l:action.selection.path
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
        throw 'Unsupported action.'
      endif
    endwhile
    redraw | echo
  catch
    echohl ErrorMsg
    if g:menu_debug_mode | echo v:throwpoint | endif
    echo 'vim-menu: ' . v:exception
    call s:Beep()
  finally
    echohl None
  endtry
  if exists('l:execute_pending') | execute l:execute_pending | endif
endfunction
