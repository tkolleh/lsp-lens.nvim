# lsp-lens.nvim

Neovim plugin for displaying reference and definition info upon functions like JB's IDEA.

<img width="376" alt="image" src="https://user-images.githubusercontent.com/16725418/217580076-7064cc80-664c-4ade-8e66-a0c75801cf17.png">

## Installation

### Prerequisite

neovim >= 0.8

lsp server correctly setup

### Lazy

```lua
require("lazy").setup({
  'tkolleh/lsp-lens.nvim'
})
```

### Usage

```lua
require'lsp-lens'.setup({})
```

## Configs

Below is the default config

```lua
local SymbolKind = vim.lsp.protocol.SymbolKind

require'lsp-lens'.setup({
  enable = true,
  include_declaration = false,      -- Reference include declaration
  sections = {                      -- Enable / Disable specific request, formatter example looks 'Format Requests'
    definition = false,
    references = true,
    implements = true,
    git_authors = true,
  },
  ignore_filetype = {
    "prisma",
  },
  -- Target Symbol Kinds to show lens information
  target_symbol_kinds = { SymbolKind.Function, SymbolKind.Method, SymbolKind.Interface },
  -- Symbol Kinds that may have target symbol kinds as children
  wrapper_symbol_kinds = { SymbolKind.Class, SymbolKind.Struct },
})
```

### Format Requests

```lua
require'lsp-lens'.setup({
  sections = {
    definition = function(count)
        return "Definitions: " .. count
    end,
    references = function(count)
        return "References: " .. count
    end,
    implements = function(count)
        return "Implements: " .. count
    end,
    git_authors = function(latest_author, count)
        return " " .. latest_author .. (count - 1 == 0 and "" or (" + " .. count - 1))
    end,
  }
})

```

## Commands

```
:LspLensOn
:LspLensOff
:LspLensToggle
```

## Highlight

```lua
{
  LspLens = { link = "LspCodeLens" },
}
```

## Known Bug

- Due to a [known issue](https://github.com/neovim/neovim/issues/16166) with the neovim `nvim_buf_set_extmark()` api, the function and method defined on the first line of the code may cause the len to display at the -1 index line, which is not visible.


## Contributing

We welcome contributions to this project! Please follow these guidelines when contributing:

- **Issues:** Before submitting a new issue, please search the existing issues to see if your problem has already been reported.
- **Pull Requests:** When submitting a pull request, please make sure that your changes are well-tested and that you have followed the coding standards for this project.
- **Coding Standards:** This project uses `stylua` to format Lua code. Please make sure that your code is formatted with `stylua` before submitting a pull request.
- **Commit Hooks:** This project uses `lefthook` to manage commit hooks. Please make sure that you have `lefthook` installed before committing any changes. You can find installation instructions [here](https://github.com/evilmartians/lefthook/blob/master/docs/install.md).

## Attribution

This project was forked from the work of [VidocqH](https://github.com/VidocqH). We are grateful for their contributions to the open source community.
