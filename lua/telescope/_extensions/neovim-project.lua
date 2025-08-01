local has_telescope, telescope = pcall(require, "telescope")

if not has_telescope then
  return
end

local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local telescope_config = require("telescope.config").values
local actions = require("telescope.actions")
local state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

local path = require("neovim-project.utils.path")
local history = require("neovim-project.utils.history")
local preview = require("neovim-project.preview")
local project = require("neovim-project.project")

local show_preview = require("neovim-project.config").options.picker.preview.enabled

----------
-- Actions
----------

local function create_finder(discover)
  local results
  if discover then
    results = path.get_all_projects_with_sorting()
  else
    results = history.get_recent_projects()
    results = path.fix_symlinks_for_history(results)
    -- Reverse results
    for i = 1, math.floor(#results / 2) do
      results[i], results[#results - i + 1] = results[#results - i + 1], results[i]
    end
  end

  local displayer = entry_display.create({
    separator = " ",
    items = {
      {
        width = 30,
      },
      {
        remaining = true,
      },
    },
  })

  local function make_display(entry)
    return displayer({ entry.name, { entry.value, "Comment" } })
  end

  return finders.new_table({
    results = results,
    entry_maker = function(entry)
      local name = vim.fn.fnamemodify(entry, ":t")
      return {
        display = make_display,
        name = name,
        value = entry,
        ordinal = name .. " " .. entry,
      }
    end,
  })
end

local function worktree(dir)
  local has_worktree, worktree = pcall(require, "git-worktree")
  if not has_worktree then
    return false
  end

  vim.fn.execute("lcd" .. " " .. dir, "silent")
  local cwd = vim.fn.getcwd()

  vim.fn.system("git rev-parse --is-inside-work-tree")
  local inside_worktree = vim.v.shell_error == 0

  if inside_worktree then
    vim.schedule(function()
       telescope.extensions.git_worktree.git_worktrees()
    end)

    worktree.on_tree_change(function(op, metadata)
      if op == worktree.Operations.Switch then
        project.switch_project(metadata.path)
      end
    end)
  end

  return inside_worktree
end

local function change_working_directory(prompt_bufnr, type)
  local selected_entry = state.get_selected_entry()
  if selected_entry == nil then
    actions.close(prompt_bufnr)
    return
  end
  local dir = selected_entry.value
  actions.close(prompt_bufnr)

  if type ~= "history" then
    local is_worktree = worktree(dir, type)
    if not is_worktree then
      -- session_manager will change session
      project.switch_project(dir)
    end
  end
end

local function delete_project(prompt_bufnr)
  local selectedEntry = state.get_selected_entry()
  if selectedEntry == nil then
    actions.close(prompt_bufnr)
    return
  end
  local dir = selectedEntry.value
  local choice = vim.fn.confirm("Delete '" .. dir .. "' from project list?", "&Yes\n&No", 2)

  if choice == 1 then
    require("neovim-project.picker").delete_confirmed_project(dir)

    local finder = create_finder(false)
    state.get_current_picker(prompt_bufnr):refresh(finder, {
      reset_prompt = true,
    })
  end
end

---Main entrypoint for Telescope.
---@param opts table
local function project_history(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Recent Projects",
      finder = create_finder(false),
      previewer = show_preview and preview.project_previewer,
      sorter = telescope_config.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr, map)
        local config = require("neovim-project.config")
        local forget_project_keys = config.options.forget_project_keys
        if forget_project_keys then
          for mode, key in pairs(forget_project_keys) do
            map(mode, key, delete_project)
          end
        end

        local on_project_selected = function()
          change_working_directory(prompt_bufnr, "history")
        end
        actions.select_default:replace(on_project_selected)
        return true
      end,
    })
    :find()
end

---@param opts table
local function project_discover(opts)
  opts = opts or {}

  pickers
    .new(opts, {
      prompt_title = "Discover Projects",
      finder = create_finder(true),
      previewer = show_preview and preview.project_previewer,
      sorter = telescope_config.generic_sorter(opts),
      attach_mappings = function(prompt_bufnr)
        local on_project_selected = function()
          change_working_directory(prompt_bufnr, "discover")
        end
        actions.select_default:replace(on_project_selected)
        return true
      end,
    })
    :find()
end
return telescope.register_extension({
  exports = {
    ["neovim-project"] = project_history,
    history = project_history,
    discover = project_discover,
  },
})
