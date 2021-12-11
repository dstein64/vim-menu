-- Neovim 0.4 doesn't have vim.fn.
local fn = setmetatable({}, {
  __index = function(tbl, key)
    tbl[key] = function(...)
      return vim.api.nvim_call_function(key, {...})
    end
    return tbl[key]
  end
})

local bool_to_int = function(bool)
  if bool then
    return 1
  else
    return 0
  end
end

-- Given a menu item path (as a list), return its qualified name.
local qualify = function(path)
  path = vim.deepcopy(path)
  table.foreach(path, function(k, v)
    path[k] = fn.substitute(path[k], '\\.', '\\\\.', 'g')
  end)
  table.foreach(path, function(k, v)
    path[k] = fn.substitute(path[k], '\\ ', '\\\\ ', 'g')
  end)
  return table.concat(path, '.')
end

-- Returns a dictionary that maps each menu path to the corresponding menu item.
local parse_menu = function(mode)
  local lines = {unpack(fn.split(fn.execute(mode .. 'menu'), '\n'), 2)}
  table.foreach(lines, function(k, v) lines[k] = '  ' .. v end)
  lines = {'0 ', unpack(lines)}
  local depth = -1
  local output = {}
  local stack = {{children = {}}}
  -- Maps menu paths to the shortcuts for that menu. This is for detecting
  -- whether a shortcut is a duplicate.
  local shortcut_lookup = {}
  for idx = 1, #lines do
    local line = lines[idx]
    if fn.match(line, '^ *\\d') > -1 then
      local depth2 = math.floor(#fn.matchstr(line, '^ *') / 2)
      if depth2 <= depth then
        for x = 1, depth - depth2 + 1 do
          table.remove(stack)
        end
      end
      local full_name = line:sub(fn.matchstrpos(line, ' *\\d\\+ ')[3] + 1)
      local name, subname
      if fn.match(full_name, '\\^I') > -1 then
        name, subname = unpack(fn.split(full_name, '\\^I'))
      else
        name, subname = unpack({full_name, ''})
      end
      -- Find the first ampersand that's 1) not preceded by an ampersand and 2)
      -- followed by a non-ampersand.
      local amp_idx = fn.match(name, '\\([^&]\\|^\\)\\zs&[^&]')
      local shortcut = ''
      if amp_idx ~= -1 then
        name = fn.substitute(name, '&', '', '')
        shortcut_code = fn.strgetchar(name:sub(amp_idx + 1), 0)
        shortcut = fn.tolower(fn.nr2char(shortcut_code))
      end
      name = fn.substitute(name, '&&', '\\&', 'g')
      local is_separator = fn.match(name, '^-.*-$') > -1
      local parents = {}
      for _, parent in ipairs({unpack(stack, 3)}) do
        table.insert(parents, parent.name)
      end
      local is_leaf = idx < #lines and fn.match(lines[idx + 1], '^ *\\d') == -1
      local path_items = vim.deepcopy(parents)
      table.insert(path_items, name)
      local path = qualify(path_items)
      local parents_path = qualify(parents)
      if shortcut_lookup[parents_path] == nil then
        shortcut_lookup[parents_path] = {}
      end
      local shortcuts = shortcut_lookup[parents_path]
      local existing_shortcut = shortcuts[shortcut] ~= nil
      shortcuts[shortcut] = 1
      local item = {
        name = name,
        subname = subname,
        path = path,
        amp_idx = amp_idx,
        shortcut = shortcut,
        existing_shortcut = bool_to_int(existing_shortcut),
        children = {},
        is_separator = bool_to_int(is_separator),
        is_root = bool_to_int(#parents == 0),
        is_leaf = bool_to_int(is_leaf)
      }
      table.insert(stack[#stack].children, item)
      table.insert(stack, item)
      output[path] = item
      depth = depth2
    elseif fn.match(line, '^ \\+' .. mode) > -1 then
      if stack[#stack].mapping ~= nil then
        error('Mapping already exists.')
      end
      local trimmed = fn.trim(line)
      local split_idx = string.find(trimmed, ' ', 1, true)
      local lhs = trimmed:sub(1, split_idx - 1)
      local rhs = fn.trim(trimmed:sub(split_idx))
      stack[#stack].mapping = {lhs, rhs}
    end
  end
  return output
end

return {
  parse_menu = parse_menu
}
