local M = {}

local config = require("lsp-lens.config")

local log_file = vim.fn.stdpath("cache") .. "/lsp-lens.log"
local log_level = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

local function write_log(level, ...)
  if log_level[level] < log_level[config.config.log_level] then
    return
  end

  local messages = {}
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    if type(arg) == "table" then
      table.insert(messages, vim.inspect(arg))
    else
      table.insert(messages, tostring(arg))
    end
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_message = string.format("[%s] [%s] %s\n", timestamp, level, table.concat(messages, " "))

  local file = io.open(log_file, "a")
  if file then
    file:write(log_message)
    io.close(file)
  end
end

function M.debug(...)
  write_log("DEBUG", ...)
end

function M.info(...)
  write_log("INFO", ...)
end

function M.warn(...)
  write_log("WARN", ...)
end

function M.error(...)
  write_log("ERROR", ...)
end

return M
