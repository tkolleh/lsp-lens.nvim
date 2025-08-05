local M = {}
local lens = require("lsp-lens.lens-util")
local log = require("lsp-lens.log")

function M.metals_status_handler(err, method, result)
  if err then
    log.error("Error in metals/status handler: ", vim.inspect(err))
    return
  end

  log.debug("Metals status received: ", vim.inspect(result))
end

return M
