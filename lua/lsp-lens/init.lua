local lens = require("lsp-lens.lens-util")
local config = require("lsp-lens.config")
local highlight = require("lsp-lens.highlight")
local handlers = require("lsp-lens.handlers")
local log = require("lsp-lens.log")

local M = {}

local augroup = vim.api.nvim_create_augroup("lsp_lens", { clear = true })

function M.setup(opts)
  config.setup(opts)
  highlight.setup()

  vim.api.nvim_create_user_command("LspLensOn", lens.lsp_lens_on, {})
  vim.api.nvim_create_user_command("LspLensOff", lens.lsp_lens_off, {})
  vim.api.nvim_create_user_command("LspLensToggle", lens.lsp_lens_toggle, {})

  vim.api.nvim_create_autocmd({ "LspAttach" }, {
    group = augroup,
    callback = function(args)
      local client = vim.lsp.get_client_by_id(args.data.client_id)
      if client and client.name == "metals" then
        log.debug("Registering metals/status handler for client: ", client.name)
        client.handlers["metals/status"] = handlers.metals_status_handler
        vim.defer_fn(function()
          lens.procedure()
        end, 1000)
      else
        lens.procedure()
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "TextChanged", "BufEnter" }, {
    group = augroup,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      local clients = vim.lsp.get_clients({ bufnr = bufnr })
      local is_metals_client = false
      for _, client in pairs(clients) do
        if client.name == "metals" then
          is_metals_client = true
          break
        end
      end

      if is_metals_client then
        vim.defer_fn(function()
          lens.procedure()
        end, 500)
      else
        lens.procedure()
      end
    end,
  })
end

return M
