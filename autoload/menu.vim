" TODO: top-level menus to ignore: ToolBar, PopUp, TouchBar
" TODO: have to ignore GUI-only menu items (non-seps that have all <NOP>)
" (e..g, File.New Window)
" TODO: popup menu that shows menu items. Maybe use built-in popup
" functionality.
" TODO: make sure you're always using the right :menu (e.g., :nmenu)
" TODO: Vim's popup_menu() probably won't be sufficient, but it's a good idea
" for styling, etc.
" TODO: Add titles to the menu (e.g., File, Edit, Edit > Find)

" Given a menu item name and its parents, return a fully qualified menu name.
function! s:GetQualifiedName(name, parents)
  let l:items = a:parents + [a:name]
  call map(l:items, 'substitute(v:val, ''\.'', ''\\.'', "g")')
  call map(l:items, 'substitute(v:val, " ", ''\\ '', "g")')
  return join(l:items, '.')
endfunction

" TODO: Documentation
function! s:GetMenuTree() abort
  " TODO: support other modes, not just 'n'
  let l:text = execute('nmenu')
  let l:lines = split(l:text, '\n')
  call filter(l:lines, 'v:val =~# "^ *\\d"')
  let l:items = []
  let l:parents = []
  let l:depth = 0
  for l:line in l:lines
    let l:indent = len(matchstr(l:line, '^ *'))
    let l:depth2 = l:indent / 2
    let l:diff = l:depth2 - l:depth
    if l:diff ># 0 && len(l:items) ># 0
      call add(l:parents, l:items[-1].name)
    elseif l:diff <# 0 && len(l:parents) ># 0
      call remove(l:parents, l:diff, -1)
    endif
    let l:depth = l:depth2
    let l:full_name = l:line[matchstrpos(l:line, ' *\d\+ ')[2]:]
    let [l:name, l:subname; l:_] = split(l:full_name, '\^I\|$', 1)
    let l:amp_idx = stridx(l:name, '&')
    if l:amp_idx !=# -1
      let l:name = substitute(l:name, '&', '', '')
    endif
    let l:item = {
          \   'name': l:name,
          \   'subname': l:subname,
          \   'qualified': s:GetQualifiedName(l:name, l:parents),
          \   'amp_idx': l:amp_idx,
          \   'parents': l:parents[:],
          \ }
    call add(l:items, l:item)
  endfor
  return l:items
endfunction

function! s:Beep()
  execute "normal \<esc>"
endfunction

function! menu#Menu() abort
  if mode() !=# 'n'
    call s:Beep()
    return
  endif
  silent! source $VIMRUNTIME/menu.vim
  let l:parsed = s:GetMenuTree()
  for l:item in l:parsed
    echo l:item
  endfor
  echo 'hello, world'
endfunction
