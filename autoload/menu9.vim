vim9script

def s:BoolToInt(x: bool): number
  if x
    return 1
  else
    return 0
  endif
enddef

# (documented in autoload/menu.vim)
def s:Qualify(path: list<string>): string
  final path2 = path[:]
  map(path2, 'substitute(v:val, ''\.'', ''\\.'', "g")')
  map(path2, 'substitute(v:val, " ", ''\\ '', "g")')
  return join(path2, '.')
enddef

# (documented in autoload/menu.vim)
def menu9#ParseMenu(mode: string): dict<dict<any>>
  var lines = split(execute(mode .. 'menu'), '\n')[1 :]
  map(lines, '"  " .. v:val')
  lines = ['0 '] + lines
  var depth = -1
  final output = {}
  final stack: list<dict<any>> = [{'children': []}]
  # Maps menu paths to the shortcuts for that menu. This is for detecting
  # whether a shortcut is a duplicate.
  final shortcut_lookup = {}
  for idx in range(len(lines))
    const line = lines[idx]
    if line =~# '^ *\d'
      const depth2 = len(matchstr(line, '^ *')) / 2
      if depth2 <=# depth
        for x in range(depth - depth2 + 1)
          remove(stack, -1)
        endfor
      endif
      const full_name = line[matchstrpos(line, ' *\d\+ ')[2] :]
      var name: string
      var subname: string
      if match(full_name, '\^I') !=# -1
        [name, subname] = split(full_name, '\^I')
      else
        [name, subname] = [full_name, '']
      endif
      # Temporarily replace double ampersands with DEL.
      const special_char = 127  # <DEL>
      if match(name, nr2char(special_char)) !=# -1
        throw 'Unsupported menu'
      endif
      name = substitute(name, '&&', nr2char(special_char), 'g')
      var amp_idx = match(name, '&')
      name = substitute(name, '&', '', 'g')
      var shortcut = ''
      if amp_idx !=# -1
        if amp_idx <# len(name)
          const shortcut_code = strgetchar(name[amp_idx :], 0)
          shortcut = tolower(nr2char(shortcut_code))
        else
          amp_idx = -1
        endif
      endif
      # Restore double ampersands as single ampersands.
      name = substitute(name, nr2char(special_char), '\&', 'g')
      const is_separator = name =~# '^-.*-$'
      final parents = []
      for parent in stack[2 :]
        add(parents, parent.name)
      endfor
      const is_leaf = idx + 1 < len(lines)
            && lines[idx + 1] !~# '^ *\d'
      const path = s:Qualify(parents + [name])
      const parents_path = s:Qualify(parents)
      if !has_key(shortcut_lookup, parents_path)
        shortcut_lookup[parents_path] = {}
      endif
      const shortcuts = shortcut_lookup[parents_path]
      const existing_shortcut = has_key(shortcuts, shortcut)
      shortcuts[shortcut] = 1
      final item = {
        'name': name,
        'subname': subname,
        'path': path,
        'amp_idx': amp_idx,
        'shortcut': shortcut,
        'existing_shortcut': s:BoolToInt(existing_shortcut),
        'children': [],
        'is_separator': s:BoolToInt(is_separator),
        'is_root': s:BoolToInt(len(parents) ==# 0),
        'is_leaf': s:BoolToInt(is_leaf)
      }
      add(stack[-1]['children'], item)
      add(stack, item)
      output[path] = item
      depth = depth2
    elseif line =~# '^ \+' .. mode
      if has_key(stack[-1], 'mapping')
        throw 'Mapping already exists.'
      endif
      const trimmed = trim(line)
      const split_idx = match(trimmed, ' ')
      const lhs = trimmed[: split_idx - 1]
      const rhs = trim(trimmed[split_idx :])
      stack[-1].mapping = [lhs, rhs]
    endif
  endfor
  return output
enddef
