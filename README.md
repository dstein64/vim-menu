# vim-menu

`vim-menu` is a plugin providing a console interface to Vim's built-in menu.

<img src="screenshot.png?raw=true" width="800"/>

## Requirements

* `vim` or `nvim`

## Installation

Use one of the following package managers:

* [Vim8 packages][vim8pack]:
  - `git clone https://github.com/dstein64/vim-menu ~/.vim/pack/plugins/start/vim-menu`
* [Vundle][vundle]:
  - Add `Plugin 'dstein64/vim-menu'` to `~/.vimrc`
  - `:PluginInstall` or `$ vim +PluginInstall +qall`
* [Pathogen][pathogen]:
  - `git clone --depth=1 https://github.com/dstein64/vim-menu ~/.vim/bundle/vim-menu`
* [vim-plug][vimplug]:
  - Add `Plug 'dstein64/vim-menu'` to `~/.vimrc`
  - `:PlugInstall` or `$ vim +PlugInstall +qall`
* [dein.vim][dein]:
  - Add `call dein#add('dstein64/vim-menu')` to `~/.vimrc`
  - `:call dein#install()`
* [NeoBundle][neobundle]:
  - Add `NeoBundle 'dstein64/vim-menu'` to `~/.vimrc`
  - Re-open vim or execute `:source ~/.vimrc`

## Usage

Vim comes with a default set of menu items. Add menu items using the built-in
`:menu` command.

Enter `vim-menu` with `<leader>m` or `:Menu`.

* Arrows, `hjkl` keys, and `<cr>` are used for movement and selection.
* Number keys can be used to jump to menu items.
* Press `g` followed by a shortcut key to execute the corresponding menu item.
* Press `K` to show more information for the selected menu item.
* Press `?` to show a help message.
* Press `<esc>` to leave `vim-menu`.

See `:help menu-usage` for additional details.

## Documentation

```vim
:help vim-menu
```

The underlying markup is in [menu.txt](doc/menu.txt).

## Demo

<img src="screencast.gif?raw=true" width="735"/>

License
-------

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle