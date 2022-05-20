-- Neovim 0.4 doesn't have vim.fn.
local fn = setmetatable({}, {
  __index = function(tbl, key)
    tbl[key] = function(...)
      return vim.api.nvim_call_function(key, {...})
    end
    return tbl[key]
  end
})

-- The table.foreach built-in can run slowly, so implement a version manually.
--   https://github.com/neovim/neovim/issues/18644
--   https://github.com/LuaJIT/LuaJIT/issues/844
local foreach = function(tbl, f)
  for k, v in pairs(tbl) do
    f(k, v)
  end
end

local bool_to_int = function(bool)
  if bool then
    return 1
  else
    return 0
  end
end

-- (documented in autoload/menu.vim)
local qualify = function(path)
  path = vim.deepcopy(path)
  foreach(path, function(k, v)
    path[k] = v:gsub('%.', '\\%.')
  end)
  foreach(path, function(k, v)
    path[k] = v:gsub(' ', '\\ ')
  end)
  return table.concat(path, '.')
end

-- (documented in autoload/menu.vim)
local parse_menu = function(mode)
  local lines = {unpack(fn.split(fn.execute(mode .. 'menu'), '\n'), 2)}
  foreach(lines, function(k, v) lines[k] = '  ' .. v end)
  lines = {'0 ', unpack(lines)}
  local depth = -1
  local output = {}
  local stack = {{children = {}}}
  -- Maps menu paths to the shortcuts for that menu. This is for detecting
  -- whether a shortcut is a duplicate.
  local shortcut_lookup = {}
  for idx = 1, #lines do
    local line = lines[idx]
    if line:find('^ *%d') ~= nil then
      local depth2 = math.floor(({line:find('^ *')})[2] / 2)
      if depth2 <= depth then
        for _ = 1, depth - depth2 + 1 do
          table.remove(stack)
        end
      end
      local _, _, full_name = line:find('^ *%d+ (.*)$')
      local name, subname = unpack({full_name, ''})
      local tab_start, tab_end = full_name:find('%^I')
      if tab_start ~= nil then
        name = full_name:sub(1, tab_start - 1)
        subname = full_name:sub(tab_end + 1)
      end
      -- Temporarily replace double ampersands with DEL.
      local special_char = 127  -- <DEL>
      if name:find(string.char(special_char)) ~= nil then
        error('Unsupported menu')
      end
      name = name:gsub('&&', string.char(special_char))
      local amp_idx = -1
      local amp_idx2 = name:find('&')
      if amp_idx2 ~= nil then
        amp_idx = amp_idx2 - 1
      end
      name = name:gsub('&', '')
      local shortcut = ''
      if amp_idx ~= -1 then
        if amp_idx < #name then
          local shortcut_code = fn.strgetchar(name:sub(amp_idx + 1), 0)
          shortcut = fn.tolower(fn.nr2char(shortcut_code))
        else
          amp_idx = -1
        end
      end
      -- Restore double ampersands as single ampersands.
      name = name:gsub(string.char(special_char), '&')
      local is_separator = name:find('^-.*-$') ~= nil
      local parents = {}
      for _, parent in ipairs({unpack(stack, 3)}) do
        table.insert(parents, parent.name)
      end
      local is_leaf = idx < #lines and lines[idx + 1]:find('^ *%d') == nil
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
    elseif line:find('^ +' .. mode) ~= nil then
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
