" *************************************************
" * Globals
" *************************************************

let s:down_chars = ['j', "\<down>"]
let s:up_chars = ['k', "\<up>"]
let s:back_chars = ['h', "\<left>"]
let s:select_chars = ['l', "\<right>", "\<cr>", "\<space>"]
let s:quit_chars = ["\<esc>", 'Z', 'q']
let s:shortcut_char = 'g'

let s:code0 = char2nr('0')
let s:code1 = char2nr('1')
let s:code9 = char2nr('9')

let s:nvim_lua = has('nvim-0.4')
let s:vim9script = has('vim9script') && has('patch-8.2.4053')

" Action types for PromptLoop()
let s:exit_action = 1
let s:select_action = 2
let s:back_action = 3

" Exclude ToolBar, PopUp, and TouchBar from the root menu.
let s:root_exclusions = ['ToolBar', 'PopUp', 'TouchBar']

" The same buffer is reused to prevent the buffer list numbers from getting
" high from usage of vim-menu. This is not a constant.
let s:bufnr = 0

" *************************************************
" * Utils
" *************************************************

" Returns true if Vim is running on Windows Subsystem for Linux. This is not
" script-local since it's called from plugin/menu.vim.
function! menu#OnWsl()
  " Recent versions of neovim provide a 'wsl' pseudo-feature.
  if has('wsl') | return 1 | endif
  if !has('unix') | return 0 | endif
  " Read /proc/version instead of using `uname` because 1) it's faster and 2)
  " so that this works in restricted mode.
  try
    if filereadable('/proc/version')
      let l:version = readfile('/proc/version', '', 1)
      if len(l:version) ># 0 && stridx(l:version[0], 'Microsoft') ># -1
        return 1
      endif
    endif
  catch
  endtry
  return 0
endfunction

function! s:NumberToFloat(number) abort
  return a:number + 0.0
endfunction

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

function! s:ParseMenuLua(mode) abort
  return luaeval('require("menu").parse_menu(_A)', a:mode)
endfunction

function! s:ParseMenuVimScript(mode) abort
  let l:lines = split(execute(a:mode . 'menu'), '\n')[1:]
  call map(l:lines, '"  " . v:val')
  let l:lines = ['0 '] + l:lines
  let l:depth = -1
  let l:output = {}
  let l:stack = [{'children': []}]
  " Maps menu paths to the shortcuts for that menu. This is for detecting
  " whether a shortcut is a duplicate.
  let l:shortcut_lookup = {}
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
      let l:tab_idx = match(l:full_name, '\^I')
      if l:tab_idx !=# -1
        let l:name = ''
        if l:tab_idx ># 0
          let l:name = l:full_name[:l:tab_idx - 1]
        endif
        let l:subname = l:full_name[l:tab_idx + 2:]
      else
        let [l:name, l:subname] = [l:full_name, '']
      endif
      " Temporarily replace double ampersands with DEL.
      let l:special_char = 127  " <DEL>
      if match(l:name, nr2char(l:special_char)) !=# -1
        throw 'Unsupported menu'
      endif
      let l:name = substitute(l:name, '&&', nr2char(l:special_char), 'g')
      let l:amp_idx = match(l:name, '&')
      let l:name = substitute(l:name, '&', '', 'g')
      let l:shortcut = ''
      if l:amp_idx !=# -1
        if l:amp_idx <# len(l:name)
          let l:shortcut_code = strgetchar(l:name[l:amp_idx:], 0)
          let l:shortcut = tolower(nr2char(l:shortcut_code))
        else
          let l:amp_idx = -1
        endif
      endif
      " Restore double ampersands as single ampersands.
      let l:name = substitute(l:name, nr2char(l:special_char), '\&', 'g')
      let l:is_separator = l:name =~# '^-.*-$'
      let l:parents = []
      for l:parent in l:stack[2:]
        call add(l:parents, l:parent.name)
      endfor
      let l:is_leaf = l:idx + 1 < len(l:lines)
            \ && l:lines[l:idx + 1] !~# '^ *\d'
      let l:path = s:Qualify(l:parents + [l:name])
      let l:parents_path = s:Qualify(l:parents)
      if !has_key(l:shortcut_lookup, l:parents_path)
        let l:shortcut_lookup[l:parents_path] = {}
      endif
      let l:shortcuts = l:shortcut_lookup[l:parents_path]
      let l:existing_shortcut = has_key(l:shortcuts, l:shortcut)
      let l:shortcuts[l:shortcut] = 1
      let l:item = {
            \   'name': l:name,
            \   'subname': l:subname,
            \   'path': l:path,
            \   'amp_idx': l:amp_idx,
            \   'shortcut': l:shortcut,
            \   'existing_shortcut': l:existing_shortcut,
            \   'children': [],
            \   'is_separator': l:is_separator,
            \   'is_root': len(l:parents) ==# 0,
            \   'is_leaf': l:is_leaf
            \ }
      call add(l:stack[-1]['children'], l:item)
      call add(l:stack, l:item)
      let l:output[l:path] = l:item
      let l:depth = l:depth2
    elseif l:line =~# '^ \+' . a:mode
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

" Returns a dictionary that maps each menu path to the corresponding menu
" item.
" XXX: Neovim has a built-in function, menu_get(), that returns a List of
" Dictionaries describing menus. This is not used.
function! s:ParseMenu(mode) abort
  if !g:menu_caching
    if has_key(s:, 'parse_cache_key')
      unlet s:parse_cache_key
    endif
    if has_key(s:, 'parse_cache_val')
      unlet s:parse_cache_val
    endif
  endif
  let l:parse_cache_key = execute(a:mode . 'menu')
  if has_key(s:, 'parse_cache_key') && l:parse_cache_key ==# s:parse_cache_key
    return s:parse_cache_val
  endif
  " For improved speed, a Lua function is used for Neovim and a Vim9 function
  " for Vim, when available.
  if s:nvim_lua
    let l:parsed = s:ParseMenuLua(a:mode)
  elseif s:vim9script
    let l:parsed = menu9#ParseMenu(a:mode)
  else
    let l:parsed = s:ParseMenuVimScript(a:mode)
  endif
  if g:menu_caching
    let s:parse_cache_key = l:parse_cache_key
    let s:parse_cache_val = l:parsed
  endif
  return l:parsed
endfunction

" Returns true if all leaves under an item are disabled.
function! s:IsDisabled(item) abort
  let l:mappings = []
  let l:stack = [a:item]
  while len(l:stack) ># 0
    let l:candidate = remove(l:stack, -1)
    if l:candidate.is_leaf
      let l:mapping = l:candidate.mapping
      let l:disabled = mapping[0] =~# '-'
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
  " Exclude non-separator entries that only have <Nop> subitems.
  call filter(l:items, '!s:IsDisabled(v:val)')
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
" IDs start at -1 and decrement for separators.
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
  " On Cygwin, pressing <c-c> during getchar() does not raise "Vim:Interrupt",
  " so it would still be <c-c> at this point. Convert to <esc>.
  if l:char ==# "\<c-c>"
    let l:char = "\<esc>"
  endif
  return l:char
endfunction

function! s:Contains(list, element) abort
  return index(a:list, a:element) !=# -1
endfunction

" Returns the maximum width of 'name + subname' across the specified items.
function! s:MaxFullNameWidth(items) abort
  let l:max = 0
  for l:item in a:items
    if l:item.is_separator | continue | endif
    if strwidth(l:item.subname) ==# 0 | continue | endif
    let l:width = strwidth(l:item.name) + strwidth(l:item.subname)
    let l:max = max([l:max, l:width])
  endfor
  return l:max
endfunction

function! s:GetIcon() abort
  let l:icon = ' '
  if has('multi_byte') && &encoding ==# 'utf-8'
    " Hamburger button
    let l:icon = nr2char(0x2630)
    " The built-in Windows terminal emulator (used for CMD, Powershell, and
    " WSL) does not properly display the Unicode hamburger button, using the
    " default font, Consolas. The character displays properly on Cygwin using
    " its default font, Lucida Console, and also when using Consolas.
    if has('win32') || menu#OnWsl()
      " Triple bar
      let l:icon = nr2char(0x2261)
    endif
  endif
  return l:icon
endfunction

" Show the specified menu, with the specified item selected. 'matchadd' and
" 'matchaddpos' are used for colorization. This is applied per-window, as
" opposed to per-buffer. This is not a problem here since the window is only
" used for a menu (i.e., it's closed as part of usage).
function! s:CreateMenu(parsed, path, id) abort
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
  let l:title = s:GetIcon() . ' ' . join(l:parts, ' > ')
  if len(l:title) ==# 0 | let l:title = ' ' | endif
  let &l:statusline = l:title
  " The last item can't be a separator, so don't have to handle the different
  " indexing used for separators.
  let l:id_len = len(string(l:items[-1].id))
  let l:selected_line = 1
  let l:full_name_width = s:MaxFullNameWidth(l:items)
  " All names and subnames will be separated by at least this many spaces.
  let l:min_subname_pad = 3
  for l:item in l:items
    let l:id_pad = l:id_len - len(string(l:item.id))
    " The leading spaces are for the scrollbar.
    let l:line = printf('  %*s[%s] ', l:id_pad, '', l:item.id)
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
    let l:line .= l:symbol . ' '
    if l:item.amp_idx !=# -1 && !l:item.existing_shortcut
      let l:amp_pos = [[line('$'), len(l:line) + 1 + l:item.amp_idx, 1]]
      call matchaddpos('MenuShortcut', l:amp_pos)
    endif
    let l:line .= l:item.name
    if len(l:item.subname) ># 0
      let l:width = strwidth(l:item.subname) + strwidth(l:item.name)
      let l:subname_pad = l:full_name_width - l:width
      let l:line .= printf('%*s', l:subname_pad + l:min_subname_pad, ' ')
      let l:subname_pos = [[line('$'), len(l:line) + 1, len(l:item.subname)]]
      call matchaddpos('MenuRightAlignedText', l:subname_pos)
      let l:line .= l:item.subname
    endif
    if l:item.is_separator
      " Include spaces so the scrollbar is visible, since matchaddpos does not
      " highlight positions with no characters.
      let l:line = ' '
    endif
    if l:item.id ==# a:id | let l:selected_line = line('$') | endif
    call append(line('$') - 1, l:line)
  endfor
  call matchadd('MenuID', '^ *\zs\[\d\+\]\ze')
  $delete _
  normal! gg
  let l:wininfo = getwininfo(win_getid(winnr()))[0]
  let l:height = line('$') + get(l:wininfo, 'winbar', 0)
  execute 'resize ' . l:height
  execute 'normal! ' . l:selected_line . 'G'
  return l:items
endfunction

" Display leaf item mapping, with special keys properly colored.
function! s:ShowItemInfo(item) abort
  redraw
  echohl Title | echon 'shortcut: ' | echohl None
  if a:item.amp_idx !=# -1 && !a:item.existing_shortcut
    echohl SpecialKey | echon a:item.shortcut | echohl None
  else
    echohl WarningMsg | echon 'none' | echohl None
  endif
  echon "\n"
  echohl Title | echon 'mapping:  ' | echohl None
  if a:item.is_leaf
    let l:mapping = a:item.mapping[1]
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
  else
    echohl WarningMsg | echon 'none' | echohl None
  endif
  echon "\n"
  echohl Question
  echon '[Press any key to continue]'
  call s:GetChar() | redraw | echo ''
  echohl None
endfunction

function! s:ShowHelp() abort
  let l:lines = [
        \   '* Arrows, `hjkl` keys, and `<cr>` are used for selecting and'
        \   . ' executing menu items.',
        \   '* Number keys can be used to jump to items.',
        \   '* Press `g` followed by a shortcut key to execute the corresponding'
        \   . ' item.',
        \   '* Press `K` to show more information for the selected item.',
        \   '* Press `<esc>` to leave vim-menu.',
        \   '* Documentation can be accessed with the command |:help vim-menu|.',
        \ ]
  redraw
  echohl Title | echo 'vim-menu help'
  echohl None
  echon "\n"
  " The state is 0 for normal text, 1 for text inside backticks, and 2 for
  " text inside vertical bars. All states are assumed mutually exclusive
  " (e.g., no backticks within vertical bars).
  let l:state = 0
  let l:highlight_lookup = ['None', 'SpecialKey', 'WarningMsg']
  for l:char in split(join(l:lines, "\n"), '\zs')
    if l:char ==# '`'
      let l:state = l:state ==# 1 ? 0 : 1
      execute 'echohl ' . l:highlight_lookup[l:state]
      continue
    elseif l:char ==# '|'
      let l:state = l:state ==# 2 ? 0 : 2
      execute 'echohl ' . l:highlight_lookup[l:state]
      continue
    endif
    echon l:char
  endfor
  echon "\n"
  echohl Question
  echon "[Press any key to continue]"
  call s:GetChar() | redraw | echo ''
  echohl None
endfunction

" Scans user input for an item ID. The first argument specifies the initial
" output, the second argument specifies the number of available items, and the
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

" Returns a Dict mapping shortcuts to items.
function! s:CreateShortcutLookup(items) abort
  let l:lookup = {}
  for l:item in a:items
    if l:item.amp_idx ==# -1 || l:item.existing_shortcut
      continue
    endif
    let l:lookup[l:item.shortcut] = l:item
  endfor
  return l:lookup
endfunction

" Returns a list with start line and height for scrollbar. Returns [-1, 0]
" when there is no scrollbar.
function! s:CalcScrollbarPosition() abort
  let l:bufnr = bufnr()
  let l:result = [-1, 0]
  let l:line_count = line('$')
  let l:topline = line('w0')
  let l:botline = line('w$')
  " Don't show the scrollbar when all lines are on screen.
  if l:botline - l:topline + 1 ==# l:line_count
    return l:result
  endif
  let l:winheight = winheight(0)
  " l:top is the position for the top of the scrollbar, relative to the
  " window, and 0-indexed.
  let l:top = (l:topline - 1.0) / (l:line_count - 1)
  let l:top = float2nr(round((l:winheight - 1) * l:top))
  let l:height = s:NumberToFloat(l:winheight) / l:line_count
  let l:height = float2nr(ceil(l:height * l:winheight))
  let l:height = max([1, l:height])
  " Make sure bar properly reflects bottom of document.
  if l:botline ==# l:line_count
    let l:top = l:winheight - l:height
  endif
  " Make sure bar never overlaps status line.
  if l:top + l:height ># l:winheight
    let l:top = l:winheight - l:height
  endif
  let l:result = [l:top + l:topline, l:height]
  return l:result
endfunction

" Gets and processes user menu interactions (movements) and returns when an
" action (exit, select, back) is taken.
function! s:PromptLoop(items) abort
  let l:action = {}
  let l:prompt = 'vim-menu> '
  let l:item_line_lookup = s:CreateItemLineLookup(a:items)
  let l:shortcut_lookup = s:CreateShortcutLookup(a:items)
  let l:scrollbar_match_ids = []
  while 1
    sign unplace 1
    let l:line_before = line('.')
    let l:item = a:items[l:line_before - 1]
    execute printf('sign place 1 line=%s name=menu_selected buffer=%s',
          \ l:line_before, bufnr('%'))
    for l:match_id in l:scrollbar_match_ids
      call matchdelete(l:match_id)
    endfor
    let l:scrollbar_match_ids = []
    let [l:scrollbar_row, l:scrollbar_height] = s:CalcScrollbarPosition()
    if l:scrollbar_height ># 0
      for l:line in range(l:scrollbar_row,
            \ l:scrollbar_row + l:scrollbar_height - 1)
        let l:match_id = matchaddpos('MenuScrollbar', [[l:line, 1]])
        call add(l:scrollbar_match_ids, l:match_id)
      endfor
    endif
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
    elseif l:char ==# s:shortcut_char
      redraw | echo l:prompt . s:shortcut_char
      let l:shortcut = s:GetChar()
      let l:lower = tolower(l:shortcut)
      if has_key(l:shortcut_lookup, l:lower)
        let l:action.type = s:select_action
        let l:action.selection = l:shortcut_lookup[l:lower]
        break
      endif
    elseif s:Contains(['d', "\<c-d>"], l:char)
      execute "normal! 4\<c-d>"
    elseif s:Contains(['u', "\<c-u>"], l:char)
      execute "normal! 4\<c-u>"
    elseif s:Contains(['f', "\<c-f>"], l:char)
      " Don't use <c-f>, since it can scroll the menu to an invalid section.
      execute "normal! 8\<c-d>"
    elseif s:Contains(['b', "\<c-b>"], l:char)
      " Don't use <c-b>, for consistency with not using <c-f>.
      execute "normal! 8\<c-u>"
    elseif s:Contains(['{', '}'], l:char)
      " Can't execute '{' or '}' keypresses since lines with all whitespace
      " are included for showing scrollbars, but should be treated as if they
      " were empty.
      let l:diff = l:char ==# '{' ? -1 : 1
      let l:key = l:char ==# '{' ? 'k' : 'j'
      while 1
        let l:l = line('.')
        execute 'silent! normal! ' . l:key
        " Break if there was no movement.
        if l:l ==# line('.') | break | endif
        " Break if the line is empty.
        if empty(trim(getline('.'))) | break | endif
      endwhile
    elseif s:Contains(['G', 'H', 'M', 'L', "\<c-e>", "\<c-y>"], l:char)
      " Don't execute <c-e> if the last line is visible, since it would scroll
      " the menu to an invalid section.
      if l:char !=# "\<c-e>" || line('w$') !=# line('$')
        execute 'normal! ' . l:char
      endif
    elseif l:char ==# 'K'
      call s:ShowItemInfo(l:item)
    elseif l:char ==# '?'
      call s:ShowHelp()
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
  execute "normal! \<esc>"
endfunction

" Sets relevant global state and returns information for restoring the
" existing state.
function! s:Init()
  let l:eventignore = &eventignore
  set eventignore=all
  let l:laststatus = &laststatus
  if has('nvim') && l:laststatus ==# 3
    " Keep the existing value
  else
    set laststatus=2
  endif
  let l:cmdheight = &cmdheight
  if l:cmdheight ==# 0
    " Neovim supports cmdheight=0. When used, temporarily change to 1 to avoid
    " 'Press ENTER or type command to continue' after using the plugin.
    set cmdheight=1
  endif
  let l:hlsearch = v:hlsearch
  let v:hlsearch = 0
  let l:winbar = v:null
  if exists('&winbar')
    " Turn off the winbar. This can't be disabled just for the menu window.
    let l:winbar = &winbar
    set winbar=
  endif
  let l:state = {
        \   'eventignore': l:eventignore,
        \   'laststatus': l:laststatus,
        \   'hlsearch': l:hlsearch,
        \   'cmdheight': l:cmdheight,
        \   'winbar': l:winbar,
        \ }
  return l:state
endfunction

function! s:Restore(state)
  let v:hlsearch = a:state['hlsearch']
  let &laststatus = a:state['laststatus']
  let &cmdheight = a:state['cmdheight']
  if a:state['winbar'] isnot# v:null
    let &winbar = a:state['winbar']
  endif
  let &eventignore = a:state['eventignore']
endfunction

function! s:ClearBuffer() abort
  %delete _
  call clearmatches()
endfunction

" Create a buffer if a vim-menu buffer doesn't exist. Load the vim-menu buffer
" in a new window.
function! s:PrepMenuBufAndWin() abort
  if s:bufnr ==# 0 || !buffer_exists(s:bufnr)
    let s:bufnr = bufadd('')
  endif
  let l:pos = 'botright'
  if get(g:, 'menu_position') ==# 'top'
    let l:pos = 'topleft'
  endif
  execute 'silent! ' . l:pos . ' split +' . s:bufnr . 'buffer'
  setlocal buftype=nofile
  setlocal noswapfile
  setlocal nofoldenable
  setlocal foldcolumn=0
  setlocal nobuflisted
  setlocal scrolloff=0
  setlocal signcolumn=no
  setlocal nocursorline
  setlocal nonumber
  setlocal norelativenumber
  setlocal bufhidden=hide
  setlocal nospell
  setlocal nolist
  setlocal nowrap
  setlocal colorcolumn=
endfunction

" Hide Neovim floating windows or Vim popups overlapping with the specified
" top and bottom screen lines (1-based). Returns a list of windows that were
" hidden. Requires a version of Neovim or Vim with float/popup hiding
" functionality.
function! s:HideFloats(top, bottom) abort
  let l:result = []
  if exists('*nvim_win_get_config')
    " Handle Neovim floating windows.
    for l:winnr in range(1, winnr('$'))
      let l:winid = win_getid(l:winnr)
      let l:config = nvim_win_get_config(l:winid)
      let l:float = l:config.relative !=# '' && !l:config.external
      if l:float && has_key(l:config, 'hide') && !l:config.hide
        let l:wininfo = getwininfo(l:winid)[0]
        let l:float_top = l:wininfo.winrow
        let l:float_bottom = l:float_top
              \ + l:wininfo.height - 1
              \ + get(l:wininfo, 'winbar', 0)
        let l:border = get(l:config, 'border', repeat([''], 8))
        if len(l:border) ==# 8 && l:border[1] !=# ''
          " There is a top border.
          let l:float_bottom += 1
        endif
        if len(l:border) ==# 8 && l:border[5] !=# ''
          " There is a bottom border.
          let l:float_bottom += 1
        endif
        if l:float_bottom >=# a:top && l:float_top <=# a:bottom
          call nvim_win_set_config(l:winid, {'hide': v:true})
          call add(l:result, l:winid)
        endif
      endif
    endfor
  elseif has('popupwin')
    " Handle Vim popup windows.
    for l:winid in popup_list()
      let l:popup_pos = popup_getpos(l:winid)
      let l:popup_top = l:popup_pos.line
      let l:popup_bottom = l:popup_pos.line + l:popup_pos.height - 1
      if l:popup_pos.visible
            \ && l:popup_bottom >=# a:top
            \ && l:popup_top <=# a:bottom
        call popup_hide(l:winid)
        call add(l:result, l:winid)
      endif
    endfor
  endif
  return l:result
endfunction

" Unhides the specified windows.
function! s:UnhideWindows(winids) abort
  for l:winid in a:winids
    if exists('*nvim_win_set_config')
      call nvim_win_set_config(l:winid, {'hide': v:false})
    elseif has('popupwin')
      call popup_show(l:winid)
    else
      let l:msg = 'vim-menu: Unable to show hidden windows.'
      call s:ShowError(l:msg)
    endif
  endfor
endfunction

function! s:ShowError(msg) abort
  call s:Beep()
  echohl ErrorMsg
  echo a:msg
  echohl Question
  echo '[Press any key to continue]'
  call s:GetChar() | redraw | echo ''
endfunction

" Returns the script ID, for testing functions with internal visibility.
function! menu#Sid() abort
  let l:sid = expand('<SID>')
  if !empty(l:sid)
    return l:sid
  endif
  " Older versions of Vim cannot expand "<SID>".
  if !exists('*s:Sid')
    function s:Sid() abort
      return matchstr(expand('<sfile>'), '\zs<SNR>\d\+_\zeSid$')
    endfunction
  endif
  return s:Sid()
endfunction

" 'path' is the menu path. 'range_count' is the number of items in the command
" range. The range behavior is the same as used for 'emenu':
"   The default is to use the Normal mode menu. If there is a range, the
"   Visual mode menu is used. With a range, if the lines match the '< and '>
"   marks, the menu is executed with the last visual selection.
" 'view' is a dictionary returned by 'winsaveview' that will be immediately
" restored with 'winrestview'.
function! menu#Menu(path, range_count, view) range abort
  call winrestview(a:view)
  if &buftype ==# 'nofile' && bufname('%') ==# '[Command Line]'
    let l:msg = 'vim-menu: Menu not available from the command-line window.'
    call s:ShowError(l:msg)
    return
  endif
  let l:prior_winid = win_getid()
  let l:hidden_winids = []
  let l:state = s:Init()
  call s:PrepMenuBufAndWin()
  " The lines above are intentionally left outside the try block, so that
  " assumptions in the catch and finally blocks are satisfied.
  try
    echohl None
    silent! source $VIMRUNTIME/menu.vim
    let l:path = a:path
    " Remove trailing dot if present (inserted by -complete=menu)
    if l:path =~# '\.$' && l:path !~# '\\\.$'
      let l:path = l:path[:-2]
    endif
    let l:selection_ids = []
    let l:selection_id = 1
    let l:parsed = s:ParseMenu(a:range_count > 0 ? 'v' : 'n')
    while 1
      call s:ClearBuffer()
      let l:items = s:CreateMenu(l:parsed, l:path, l:selection_id)
      call s:UnhideWindows(l:hidden_winids)
      " Hide overlapping floating windows for the duration of processing, to
      " prevent overlapping the menu window.
      let l:wininfo = getwininfo(win_getid(winnr()))[0]
      let l:top = l:wininfo.winrow
      let l:bottom = l:top + l:wininfo.height + get(l:wininfo, 'winbar', 0)
      let l:hidden_winids = s:HideFloats(l:top, l:bottom)
      let l:action = s:PromptLoop(l:items)
      if l:action.type ==# s:exit_action
        break
      elseif l:action.type ==# s:select_action
        if l:action.selection.is_leaf 
          let l:range = ''
          if a:range_count ># 0
            let l:range = a:firstline . ',' . a:lastline
          endif
          let l:pending = l:range . ':emenu ' . l:action.selection.path
          break
        else
          let l:path = l:action.selection.path
          call add(l:selection_ids, l:action.selection.id)
          let l:selection_id = 1
        endif
      elseif l:action.type ==# s:back_action
        if l:path ==# '' | break | endif
        if (len(l:selection_ids) ==# 0) | break | endif
        let l:parts = s:Unqualify(l:path)
        let l:path = s:Qualify(l:parts[:-2])
        let l:selection_id = remove(l:selection_ids, -1)
      else
        throw 'Unsupported action.'
      endif
    endwhile
    redraw | echo ''
  catch
    let l:error = 1
    let l:msg = ''
    if g:menu_debug_mode
      let l:msg .= v:throwpoint . "\n"
    endif
    let l:msg .= 'vim-menu: ' . v:exception
    call s:ShowError(l:msg)
  finally
    call s:ClearBuffer()
    " Close the vim-menu window.
    close
    " Return to the initial window from prior to loading menu.
    call win_gotoid(l:prior_winid)
    echohl None
    redraw | echo ''
    call s:UnhideWindows(l:hidden_winids)
    call s:Restore(l:state)
  endtry
  if !get(l:, 'error', 0)
    if exists('l:pending')
      " Execute the pending command with 'feedkeys', as opposed to 'execute'.
      " This accommodates commands that result in command-line mode (e.g.,
      " ':menu File.Save\ As :saveas ' for loading ':saveas ' with
      " anticipation for a file argument) or operator-pending mode (e.g.,
      " ':menu Edit.Format gw' for formatting the text corresponding to the
      " motion that follows, when there is no visual selection).
      call feedkeys(l:pending . "\n", 'n')
    elseif a:range_count ># 0
      " If no command was executed (i.e., exit action or back action out of
      " menu), and the user had a visual selection (assumed by positive
      " range_count), restore the visual selection. This is intentionally not
      " executed on error (some steps leading up to error may have been
      " executed, whereby visual selection would not ordinarily be restored
      " even in the absence of an error).
      normal! gv
    endif
  endif
endfunction
