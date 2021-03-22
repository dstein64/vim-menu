[![build][badge_thumbnail]][badge_link]

# vim-menu

`vim-menu` is a plugin providing a console interface to Vim's built-in menu.

<img src="screenshot.png?raw=true" width="300"/>

## Requirements

* `vim` or `nvim`

## Installation

A package manager can be used to install `vim-menu`.
<details><summary>Examples</summary><br>

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

</details>

## Usage

Vim comes with a default set of menu items. `:menu` and `:unmenu` can be used
for adding and removing menu items. See `:help creating-menus` and
`:help delete-menus` for documentation. See `vim-menu`'s documentation for
details on modifying or disabling the default menus.

Enter `vim-menu` with `<leader>m` or `:Menu`.

* Arrows, `hjkl` keys, and `<cr>` are used for selecting and executing menu
  items.
* Number keys can be used to jump to items.
* Press `g` followed by a shortcut key to execute the corresponding item.
* Press `K` to show more information for the selected item.
* Press `?` to show a help message.
* Press `<esc>` to leave `vim-menu`.

See `:help menu-usage` for additional details.

## Documentation

```vim
:help vim-menu
```

The underlying markup is in [menu.txt](doc/menu.txt).

## Demo

<img src="screencast.gif?raw=true" width="825"/>

License
-------

The source code has an [MIT License](https://en.wikipedia.org/wiki/MIT_License).

See [LICENSE](LICENSE).

[badge_link]: https://github.com/dstein64/vim-menu/actions/workflows/build.yml
[badge_thumbnail]: https://github.com/dstein64/vim-menu/actions/workflows/build.yml/badge.svg
[dein]: https://github.com/Shougo/dein.vim
[neobundle]: https://github.com/Shougo/neobundle.vim
[pathogen]: https://github.com/tpope/vim-pathogen
[vim8pack]: http://vimhelp.appspot.com/repeat.txt.html#packages
[vimplug]: https://github.com/junegunn/vim-plug
[vundle]: https://github.com/gmarik/vundle
