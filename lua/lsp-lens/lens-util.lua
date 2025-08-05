local lsplens = {}
local config = require("lsp-lens.config")
local utils = require("lsp-lens.utils")
local log = require("lsp-lens.log")

local lsp = vim.lsp
local lsp_get_clients_method
if vim.version().minor >= 10 then
  lsp_get_clients_method = lsp.get_clients
else
  lsp_get_clients_method = lsp.get_active_clients
end

local methods = {
  "textDocument/implementation",
  "textDocument/definition",
  "textDocument/references",
  "textDocument/codeLens",
}

local function result_count(results)
  local ret = 0
  for _, res in pairs(results or {}) do
    for _, _ in pairs(res.result or {}) do
      ret = ret + 1
    end
  end
  return ret
end

local function requests_done(finished)
  for _, p in pairs(finished) do
    -- Check all flags, including the new codeLens flag (index 5)
    if not (p[1] == true and p[2] == true and p[3] == true and p[4] == true and p[5] == true) then
      return false
    end
  end
  return true
end

local function get_functions(result)
  local ret = {}
  for _, v in pairs(result or {}) do
    if vim.tbl_contains(config.config.target_symbol_kinds, v.kind) then
      if v.range and v.range.start then
        table.insert(ret, {
          name = v.name,
          rangeStart = v.range.start,
          rangeEnd = v.range["end"],
          selectionRangeStart = v.selectionRange.start,
          selectionRangeEnd = v.selectionRange["end"],
        })
      end
    end

    if v.children then -- Check if children exist before recursing
      ret = utils:merge_table(ret, get_functions(v.children)) -- Recursively find methods
    end
  end
  return ret
end

local function get_cur_document_functions(results)
  local ret = {}
  for _, res in pairs(results or {}) do
    ret = utils:merge_table(ret, get_functions(res.result))
  end
  return ret
end

local function client_supports_method(client, method)
  if vim.fn.has("nvim-0.11") then
    return client:supports_method(method)
  else
    return client.supports_method(method)
  end
end

local function lsp_support_method(buf, method)
  log.debug("Checking LSP support for method: ", method, " on buffer: ", buf)
  for _, client in pairs(lsp_get_clients_method({ bufnr = buf })) do
    local supports = client_supports_method(client, method)
    log.debug("  Client: ", client.name, ", Supports ", method, ": ", supports)
    if supports then
      return true
    end
  end
  return false
end

local function create_string(counting)
  local cfg = config.config
  local text = ""

  local function append_with(value, fn)
    if fn == nil or (cfg.hide_zero_counts and (type(value) == "number" and value == 0)) then
      return
    end

    local formatted = fn(value)
    if formatted == nil or formatted == "" then
      return
    end

    text = text == "" and formatted or text .. cfg.separator .. formatted
  end

  if counting.reference then
    append_with(counting.reference, cfg.sections.references)
  end

  if counting.definition then
    append_with(counting.definition, cfg.sections.definition)
  end

  if counting.implementation then
    append_with(counting.implementation, cfg.sections.implements)
  end

  if counting.code_lens and #counting.code_lens > 0 then
    for _, lens_title in ipairs(counting.code_lens) do
      append_with(lens_title, cfg.sections.code_lens)
    end
  end

  if counting.git_authors then
    if not (cfg.sections.git_authors == nil or (cfg.hide_zero_counts and counting.git_authors.count == 0)) then
      local formatted = cfg.sections.git_authors(counting.git_authors.latest_author, counting.git_authors.count)
      text = text == "" and formatted or text .. cfg.separator .. formatted
    end
  end

  return text == "" and "" or cfg.decorator(text)
end

local function generate_function_id(function_info)
  return function_info.name
    .. "uri="
    .. function_info.query_params.textDocument.uri
    .. "character="
    .. function_info.selectionRangeStart.character
    .. "line="
    .. function_info.selectionRangeStart.line
end

local function delete_existing_lines(bufnr, ns_id)
  local existing_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns_id, 0, -1, {})
  for _, v in pairs(existing_marks) do
    vim.api.nvim_buf_del_extmark(bufnr, ns_id, v[1])
  end
end

local function normalize_rangeStart_character(bufnr, query)
  local filetype = vim.api.nvim_buf_get_option(bufnr, "filetype")
  log.debug(
    "normalize_rangeStart_character: bufnr=",
    bufnr,
    ", filetype=",
    filetype,
    ", original_char=",
    query.character,
    ", line=",
    query.line
  )

  if filetype == "lua" then
    local clients = lsp_get_clients_method({ bufnr = bufnr, name = "lua_ls" })

    if vim.tbl_isempty(clients) then
      log.debug("normalize_rangeStart_character: No lua_ls client found. Skipping normalization.")
      return
    end

    local str = "local "

    local lines = vim.api.nvim_buf_get_lines(bufnr, query.line, query.line + 1, true)
    if #lines == 0 then
      log.debug("normalize_rangeStart_character: Line is empty. Skipping normalization.")
      return
    end
    local line = lines[1]

    local indent = line:match("^%s+")
    indent = indent and indent:len() or 0
    local trimmed = vim.trim(line)

    if trimmed:sub(1, str:len()) == str then
      query.character = indent + query.character - str:len()
      log.debug("normalize_rangeStart_character: Adjusted character to ", query.character)
    else
      log.debug("normalize_rangeStart_character: 'local ' not found. No adjustment.")
    end
  else
    log.debug("normalize_rangeStart_character: Not a Lua file. Skipping normalization.")
  end
end

local function display_lines(bufnr, query_results)
  if vim.fn.bufexists(bufnr) == 0 then
    log.warn("Buffer ", bufnr, " does not exist. Cannot display lines.")
    return
  end
  local ns_id = vim.api.nvim_create_namespace("lsp-lens")
  delete_existing_lines(bufnr, ns_id)
  for _, query in pairs(query_results or {}) do
    local virt_lines = {}
    local display_str = create_string(query.counting)
    log.debug("Query counting: ", vim.inspect(query.counting))
    log.debug("Display string: ", display_str)

    if not (display_str == "") then
      normalize_rangeStart_character(bufnr, query.rangeStart)

      local vline = { { string.rep(" ", query.rangeStart.character) .. display_str, "LspLens" } }
      table.insert(virt_lines, vline)

      if query.rangeStart.line < vim.api.nvim_buf_line_count(bufnr) then
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, query.rangeStart.line, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })
      end
    end
  end
end

local function get_recent_editor(start_row, end_row, callback)
  local file_path = vim.fn.expand("%:p")

  local stdout = vim.loop.new_pipe()
  if stdout == nil then
    log.error("Failed to create pipe for git blame.")
    return
  end

  local authors = {}
  local most_recent_editor = nil
  vim.loop.spawn("git", {
    args = { "blame", "-L", start_row .. "," .. end_row, "--incremental", file_path },
    stdio = { nil, stdout, nil },
  }, function(exit_code, signal_name)
    if exit_code ~= 0 then
      log.error("Git blame failed with exit code ", exit_code, " and signal ", signal_name)
    end
    local authors_arr = {}
    for author_name, _ in pairs(authors) do
      table.insert(authors_arr, author_name)
    end
    callback(most_recent_editor, authors_arr)
  end)
  vim.loop.read_start(stdout, function(err, data)
    if err then
      log.error("Error reading git blame output: ", err)
      return
    end
    if data == nil then
      return
    end

    for line in string.gmatch(data, "[^\r\n]+") do
      local space_pos = string.find(line, " ")
      if space_pos ~= nil then
        local key = string.sub(line, 1, space_pos - 1)
        local val = string.sub(line, space_pos + 1)
        if key == "author" then
          -- if key == "author" or key == "committer" then
          authors[val] = true
          if most_recent_editor == nil then
            most_recent_editor = val
          end
        end
      end
    end
  end)
  vim.loop.close(stdout)
end

local function do_request(symbols)
  log.debug("Starting do_request for buffer: ", symbols.bufnr)
  if not (utils:is_buf_requesting(symbols.bufnr) == -1) then
    log.debug("Buffer ", symbols.bufnr, " is already requesting. Skipping.")
    return
  else
    utils:set_buf_requesting(symbols.bufnr, 0)
  end

  local functions = symbols.document_functions_with_params
  local finished = {}

  for idx, function_info in pairs(functions or {}) do
    -- Initialize all flags to false, including the new codeLens flag
    table.insert(finished, { false, false, false, false, false })

    local params = function_info.query_params
    local counting = {}

    if config.config.sections.implements and lsp_support_method(symbols.bufnr, methods[1]) then
      log.debug("Requesting textDocument/implementation for ", function_info.name)
      lsp.buf_request_all(symbols.bufnr, methods[1], params, function(implements)
        counting["implementation"] = result_count(implements)
        finished[idx][1] = true
        log.debug("Received textDocument/implementation for ", function_info.name, ": ", counting.implementation)
      end)
    else
      finished[idx][1] = true
      log.debug("Skipping textDocument/implementation for ", function_info.name)
    end

    if config.config.sections.definition and lsp_support_method(symbols.bufnr, methods[2]) then
      log.debug("Requesting textDocument/definition for ", function_info.name)
      lsp.buf_request_all(symbols.bufnr, methods[2], params, function(definition)
        counting["definition"] = result_count(definition)
        finished[idx][2] = true
        log.debug("Received textDocument/definition for ", function_info.name, ": ", counting.definition)
      end)
    else
      finished[idx][2] = true
      log.debug("Skipping textDocument/definition for ", function_info.name)
    end

    if config.config.sections.references and lsp_support_method(symbols.bufnr, methods[3]) then
      log.debug("Requesting textDocument/references for ", function_info.name)
      params.context = { includeDeclaration = config.config.include_declaration }
      lsp.buf_request_all(symbols.bufnr, methods[3], params, function(reference)
        counting["reference"] = result_count(reference)
        finished[idx][3] = true
        log.debug("Received textDocument/references for ", function_info.name, ": ", counting.reference)
      end)
    else
      finished[idx][3] = true
      log.debug("Skipping textDocument/references for ", function_info.name)
    end

    if config.config.sections.code_lens and lsp_support_method(symbols.bufnr, methods[4]) then
      log.debug("Requesting textDocument/codeLens for ", function_info.name)
      lsp.buf_request_all(symbols.bufnr, methods[4], params, function(code_lens_results)
        local titles = {}
        for _, res in pairs(code_lens_results or {}) do
          for _, lens in pairs(res.result or {}) do
            if lens.command and lens.command.title then
              table.insert(titles, lens.command.title)
            end
          end
        end
        counting["code_lens"] = titles
        finished[idx][4] = true
        log.debug("Received textDocument/codeLens for ", function_info.name, ": ", titles)
      end)
    else
      finished[idx][4] = true
      log.debug("Skipping textDocument/codeLens for ", function_info.name)
    end

    if config.config.sections.git_authors then
      log.debug("Requesting git_authors for ", function_info.name)
      get_recent_editor(
        function_info.rangeStart.line + 1,
        function_info.rangeEnd.line + 1,
        function(latest_author, authors)
          counting["git_authors"] = { latest_author = latest_author, count = #authors }
          finished[idx][5] = true
          log.debug("Received git_authors for ", function_info.name, ": ", latest_author, " (", #authors, ")")
        end
      )
    else
      finished[idx][5] = true
      log.debug("Skipping git_authors for ", function_info.name)
    end

    function_info["counting"] = counting
  end

  local timer = vim.loop.new_timer()
  timer:start(
    0,
    500,
    vim.schedule_wrap(function()
      if requests_done(finished) then
        if timer ~= nil and timer:is_closing() == false then
          timer:close()
          log.debug("Timer closed for buffer: ", symbols.bufnr)
        end
        display_lines(symbols.bufnr, functions)
        utils:set_buf_requesting(symbols.bufnr, 1)
        log.debug("Requests done and lines displayed for buffer: ", symbols.bufnr)
      end
    end)
  )
end

local function make_params(results)
  for _, query in pairs(results or {}) do
    local params = {
      position = {
        character = query.selectionRangeEnd.character,
        line = query.selectionRangeEnd.line,
      },
      textDocument = lsp.util.make_text_document_params(),
    }
    query.query_params = params
  end
  return results
end

function lsplens:lsp_lens_on()
  config.config.enable = true
  log.info("LspLens enabled.")
  lsplens:procedure()
end

function lsplens:lsp_lens_off()
  config.config.enable = false
  delete_existing_lines(0, vim.api.nvim_create_namespace("lsp-lens"))
  log.info("LspLens disabled.")
end

function lsplens:lsp_lens_toggle()
  if config.config.enable then
    lsplens:lsp_lens_off()
  else
    lsplens:lsp_lens_on()
  end
end

function lsplens:procedure()
  if config.config.enable == false then
    lsplens:lsp_lens_off()
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  log.debug("Procedure started for buffer: ", bufnr)

  -- Ignored Filetype
  if utils:table_find(config.config.ignore_filetype, vim.api.nvim_buf_get_option(bufnr, "filetype")) then
    log.info("Filetype ", vim.api.nvim_buf_get_option(bufnr, "filetype"), " is ignored. Skipping procedure.")
    return
  end

  local method = "textDocument/documentSymbol"
  local max_retries = 5
  local retry_delay_ms = 100

  local function try_document_symbol()
    if lsp_support_method(bufnr, method) then
      log.debug("Requesting textDocument/documentSymbol for buffer: ", bufnr)
      local params = { textDocument = lsp.util.make_text_document_params() }
      lsp.buf_request_all(bufnr, method, params, function(document_symbols)
        log.debug("Received textDocument/documentSymbol for buffer: ", bufnr)
        local symbols = {}
        symbols["bufnr"] = bufnr
        symbols["document_symbols"] = document_symbols
        symbols["document_functions"] = get_cur_document_functions(symbols.document_symbols)
        symbols["document_functions_with_params"] = make_params(symbols.document_functions)
        log.debug("Document functions with params: ", vim.inspect(symbols.document_functions_with_params))
        do_request(symbols)
      end)
      return true -- Request sent, exit retry loop
    end
    return false -- Method not supported yet, continue retrying
  end

  local success = false
  for i = 1, max_retries do
    success = try_document_symbol()
    if success then
      break
    end
    log.debug("Retrying textDocument/documentSymbol check for buffer: ", bufnr, ". Attempt ", i, " of ", max_retries)
    vim.loop.sleep(retry_delay_ms)
  end

  if not success then
    log.info(
      "LSP client does not support textDocument/documentSymbol for buffer: ",
      bufnr,
      " after ",
      max_retries,
      " retries. Skipping procedure."
    )
  end
end

return lsplens
