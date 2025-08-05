--- lsp-lens.log
--- This module provides logging utilities for the lsp-lens.nvim plugin.
--- It allows logging messages to a file with different severity levels.

local M = {}

local config = require("lsp-lens.config")

--- Path to the log file, located in Neovim's cache directory.
local log_file = vim.fn.stdpath("cache") .. "/lsp-lens.log"

--- Defines the hierarchy of log levels.
--- Messages with a level lower than the configured `log_level` in `config.lua` will be ignored.
local log_level = {
  DEBUG = 1,
  INFO = 2,
  WARN = 3,
  ERROR = 4,
}

--- Writes a log message to the log file.
--- @param level string The severity level of the log message (e.g., "DEBUG", "INFO").
--- @param ... any The messages to be logged. Can be multiple arguments of any type.
local function write_log(level, ...)
  -- Check if the current message's level is sufficient for the configured log level.
  if log_level[level] < log_level[config.config.log_level] then
    return
  end

  -- Collect all arguments into a table and convert tables to inspectable strings.
  local messages = {}
  for i = 1, select("#", ...) do
    local arg = select(i, ...)
    if type(arg) == "table" then
      table.insert(messages, vim.inspect(arg))
    else
      table.insert(messages, tostring(arg))
    end
  end

  -- Format the log message with a timestamp, level, and concatenated messages.
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_message = string.format("[%s] [%s] %s\n", timestamp, level, table.concat(messages, " "))

  -- Open the log file in append mode and write the message.
  local file = io.open(log_file, "a")
  if file then
    file:write(log_message)
    io.close(file)
  end
end

--- Logs a debug message.
--- These messages are typically verbose and used for detailed debugging.
--- @param ... any Messages to log.
function M.debug(...)
  write_log("DEBUG", ...)
end

--- Logs an informational message.
--- These messages provide general insights into the plugin's operation.
--- @param ... any Messages to log.
function M.info(...)
  write_log("INFO", ...)
end

--- Logs a warning message.
--- These messages indicate potential issues that are not critical but should be noted.
--- @param ... any Messages to log.
function M.warn(...)
  write_log("WARN", ...)
end

--- Logs an error message.
--- These messages indicate critical failures or unexpected behavior.
--- @param ... any Messages to log.
function M.error(...)
  write_log("ERROR", ...)
end

return M
