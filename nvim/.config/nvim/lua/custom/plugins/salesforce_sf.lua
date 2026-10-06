-- Salesforce CLI integration for Neovim
-- Provides org management, deploy, retrieve, and diff via the `sf` CLI
-- All commands under <leader>F (Force/Salesforce) group
--
-- Prerequisites: `sf` CLI must be in PATH
-- Keymaps (only active inside an sfdx-project):
--   <leader>Fa  Execute current .apex file as anonymous Apex (normal: whole file, visual: selection)
--   <leader>Fo  Select & set default org
--   <leader>Fd  Deploy current file to org
--   <leader>FD  Deploy entire project to org
--   <leader>Fr  Retrieve current file from org
--   <leader>FR  Retrieve entire project from org
--   <leader>F=  Diff current file against org (retrieve to tmp + vimdiff)
--   <leader>Fp  Preview deploy (show what would change)
--   <leader>FP  Preview retrieve (show what would change)

---@module 'lazy'
---@type LazySpec
return {
  {
    -- which-key: register the <leader>F group label only (individual descs come from keymap set calls)
    'folke/which-key.nvim',
    optional = true,
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      vim.list_extend(opts.spec, {
        { '<leader>F', group = '[F]orce / Salesforce', icon = '☁' },
        { '<leader>F', group = '[F]orce / Salesforce', icon = '☁', mode = 'v' },
      })
      return opts
    end,
  },
  {
    -- Standalone entry: not coupled to telescope so keymaps always register
    dir = vim.fn.stdpath 'config',
    name = 'salesforce-sf-keymaps',
    lazy = false,
    init = function()
      vim.api.nvim_create_autocmd('User', {
        pattern = 'LazyDone',
        once = true,
        callback = function()
          -- ── helpers ───────────────────────────────────────────────────────────

          local function sf_bin()
            return vim.fn.has 'win32' == 1 and 'sf.cmd' or 'sf'
          end

          local function shell_args(cmd)
            return vim.fn.has 'win32' == 1 and { 'bash', '-lc', cmd } or { 'sh', '-c', cmd }
          end

          --- Open a scratch buffer with the output of `cmd`, press q to close
          local function run_in_buf(cmd, cwd)
            local buf = vim.api.nvim_create_buf(false, true)
            vim.bo[buf].buftype = 'nofile'
            vim.bo[buf].bufhidden = 'wipe'
            vim.bo[buf].swapfile = false
            vim.bo[buf].filetype = 'sf-output'
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '⏳ Running: ' .. cmd, '' })
            vim.keymap.set('n', 'q', '<cmd>bdelete!<cr>', { buffer = buf, noremap = true, silent = true })
            vim.cmd 'botright split'
            vim.api.nvim_win_set_buf(0, buf)
            vim.api.nvim_buf_set_name(buf, '[SF: Apex Output]')
            vim.system(shell_args(cmd), { cwd = cwd or vim.fn.getcwd(), text = true }, function(result)
              vim.schedule(function()
                local lines = {}
                local raw = (result.stdout or '') .. (result.stderr or '')
                for _, line in ipairs(vim.split(raw, '\n')) do
                  table.insert(lines, line)
                end
                while lines[#lines] == '' do
                  table.remove(lines)
                end
                if #lines == 0 then lines = { '(no output)' } end
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false
                vim.notify('[SF] Apex finished. Press q to close.', vim.log.levels.INFO)
              end)
            end)
          end

          --- Open a floating terminal that runs `cmd` with optional cwd, closes on 'q' when done
          local function run_in_term(cmd, cwd)
            local buf = vim.api.nvim_create_buf(false, true)
            local width = math.floor(vim.o.columns * 0.85)
            local height = math.floor(vim.o.lines * 0.75)
            vim.api.nvim_open_win(buf, true, {
              relative = 'editor',
              width = width,
              height = height,
              row = math.floor((vim.o.lines - height) / 2),
              col = math.floor((vim.o.columns - width) / 2),
              style = 'minimal',
              border = 'rounded',
              title = ' Salesforce ',
              title_pos = 'center',
            })
            vim.fn.termopen(shell_args(cmd), {
              cwd = cwd or vim.fn.getcwd(),
              on_exit = function()
                vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>bdelete!<cr>', { noremap = true, silent = true })
                vim.api.nvim_buf_set_keymap(buf, 't', 'q', '<cmd>bdelete!<cr>', { noremap = true, silent = true })
                vim.notify('[SF] Command finished. Press q to close.', vim.log.levels.INFO)
              end,
            })
            vim.cmd 'startinsert'
          end

          --- Find the sfdx project root from the current buffer's path, or cwd
          local function get_project_root()
            local from = vim.fn.expand '%:p:h'
            if from == '' then from = vim.fn.getcwd() end
            local found = vim.fn.findfile('sfdx-project.json', from .. ';')
            if found == '' then return nil end
            return vim.fn.fnamemodify(found, ':h')
          end

          --- Derive a `--metadata Type:Name` spec from a file path, for use with --output-dir.
          --- Returns nil if the type cannot be determined.
          local function get_metadata_spec(filepath)
            local ext = vim.fn.fnamemodify(filepath, ':e')
            local name = vim.fn.fnamemodify(filepath, ':t:r') -- filename without extension
            local parent = vim.fn.fnamemodify(filepath, ':h:t') -- immediate directory
            local grandpa = vim.fn.fnamemodify(filepath, ':h:h:t') -- two levels up

            if ext == 'cls' then return 'ApexClass:' .. name end
            if ext == 'trigger' then return 'ApexTrigger:' .. name end
            if grandpa == 'lwc' then return 'LightningComponentBundle:' .. parent end
            if grandpa == 'aura' then return 'AuraDefinitionBundle:' .. parent end
            if ext == 'page' then return 'ApexPage:' .. name end
            if ext == 'component' then return 'ApexComponent:' .. name end
            return nil
          end

          --- Return the current target-org (alias or username), or nil
          local function get_default_org()
            local result = vim.system({ sf_bin(), 'config', 'get', 'target-org', '--json' }, {
              cwd = get_project_root() or vim.fn.getcwd(),
              text = true,
            }):wait()
            if result.code ~= 0 then return nil end
            local ok, data = pcall(vim.json.decode, result.stdout or '')
            if not ok or not data then return nil end
            local entry = (data.result or {})[1] or {}
            return entry.value
          end

          --- Read the auth file for an org alias or username. Returns the parsed table or nil.
          local function read_auth_file(org)
            local sfdx_dir = vim.fn.expand '~/.sfdx'
            -- Resolve alias → username
            local username = org
            local alias_file = sfdx_dir .. '/alias.json'
            if vim.fn.filereadable(alias_file) == 1 then
              local ok, data = pcall(vim.json.decode, table.concat(vim.fn.readfile(alias_file), ''))
              if ok and data and data.orgs and data.orgs[org] then username = data.orgs[org] end
            end
            local path = sfdx_dir .. '/' .. username .. '.json'
            if vim.fn.filereadable(path) ~= 1 then return nil end
            local ok, auth = pcall(vim.json.decode, table.concat(vim.fn.readfile(path), ''))
            return ok and auth or nil
          end

          --- Check session validity via `sf org display` (handles token refresh automatically).
          --- callback(true) = ok, callback(false, msg) = invalid/error.
          local function check_auth(org, callback)
            vim.system({ sf_bin(), 'org', 'display', '--target-org', org, '--json' }, {
              cwd = get_project_root() or vim.fn.getcwd(),
              text = true,
            }, function(result)
              vim.schedule(function()
                local ok, data = pcall(vim.json.decode, result.stdout or '')
                if result.code == 0 and ok and data and data.status == 0 then
                  callback(true, nil)
                else
                  local msg = (ok and data and data.message) or result.stderr or 'Session check failed'
                  callback(false, '[SF] Session invalid: ' .. msg .. '\nRe-authenticate with <leader>Fl or run:\n  ' .. sf_bin() .. ' org login web --target-org ' .. org)
                end
              end)
            end)
          end

          --- Read authenticated orgs from the native Salesforce CLI so Windows ~/.sf auth works.
          local function list_orgs(callback)
            local default_org = get_default_org()
            vim.system({ sf_bin(), 'org', 'list', '--json' }, { cwd = get_project_root() or vim.fn.getcwd(), text = true }, function(result)
              local orgs, seen = {}, {}
              local function add_org(o)
                if type(o) ~= 'table' or not o.username or seen[o.username] then return end
                seen[o.username] = true
                local alias = o.alias
                if type(alias) == 'table' then alias = alias[1] end
                table.insert(orgs, {
                  username = o.username,
                  alias = alias or vim.NIL,
                  instanceUrl = o.instanceUrl,
                  isSandbox = o.isSandbox,
                  isScratch = o.isScratch,
                  isDefaultUsername = o.isDefaultUsername or default_org == alias or default_org == o.username,
                  isDefaultDevHubUsername = o.isDefaultDevHubUsername or false,
                })
              end

              local ok, data = pcall(vim.json.decode, result.stdout or '')
              if result.code == 0 and ok and data and data.result then
                for _, value in pairs(data.result) do
                  if type(value) == 'table' and value.username then
                    add_org(value)
                  elseif type(value) == 'table' then
                    for _, org in ipairs(value) do
                      add_org(org)
                    end
                  end
                end
              end

              vim.schedule(function() callback(orgs) end)
            end)
          end

          --- Format an org entry for display in the picker
          local function org_label(o)
            local default = (o.isDefaultUsername or o.isDefaultDevHubUsername) and ' ✓' or ''
            local alias = o.alias ~= vim.NIL and o.alias or ''
            if alias ~= '' then return string.format('%s (%s)%s', alias, o.username, default) end
            return o.username .. default
          end

          -- ── commands ──────────────────────────────────────────────────────────

          local M = {}

          --- Pick an org and set it as target-org
          function M.select_org()
            list_orgs(function(orgs)
              if #orgs == 0 then
                vim.notify('[SF] No authenticated orgs found. Run: sf org login web', vim.log.levels.WARN)
                return
              end
              local labels = vim.tbl_map(org_label, orgs)
              vim.ui.select(labels, { prompt = 'Select Salesforce Org' }, function(choice, idx)
                if not choice then return end
                local org = orgs[idx]
                local target = org.alias ~= vim.NIL and org.alias or org.username
                vim.fn.jobstart({ sf_bin(), 'config', 'set', 'target-org=' .. target }, {
                  cwd = get_project_root() or vim.fn.getcwd(),
                  on_exit = function(_, code)
                    if code == 0 then
                      vim.notify('[SF] Default org set to: ' .. target, vim.log.levels.INFO)
                    else
                      vim.notify('[SF] Failed to set org', vim.log.levels.ERROR)
                    end
                  end,
                })
              end)
            end)
          end

          --- Deploy current file (or directory for LWC/Aura bundles)
          function M.deploy_file()
            local path = vim.fn.expand '%:p'
            if path == '' then
              vim.notify('[SF] No file open', vim.log.levels.WARN)
              return
            end
            local root = get_project_root()
            -- For LWC/Aura, deploy the whole bundle directory
            local parent = vim.fn.fnamemodify(path, ':h')
            local grandparent = vim.fn.fnamemodify(parent, ':h')
            local deploy_path = path
            for _, marker in ipairs { 'lwc', 'aura' } do
              if vim.fn.fnamemodify(grandparent, ':t') == marker then
                deploy_path = parent
                break
              end
            end
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            run_in_term(sf_bin() .. ' project deploy start --source-dir ' .. vim.fn.shellescape(deploy_path) .. org_flag, root)
          end

          --- Deploy entire project: uses manifest/package.xml if present, else source dirs from sfdx-project.json
          function M.deploy_project()
            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            local manifest = root and (root .. '/manifest/package.xml') or ''
            local flag
            if manifest ~= '' and vim.fn.filereadable(manifest) == 1 then
              flag = ' --manifest ' .. vim.fn.shellescape(manifest)
            else
              flag = ' --source-dir ' .. vim.fn.shellescape(root .. '/force-app')
            end
            run_in_term(sf_bin() .. ' project deploy start' .. flag .. org_flag, root)
          end

          --- Retrieve current file from org
          function M.retrieve_file()
            local path = vim.fn.expand '%:p'
            if path == '' then
              vim.notify('[SF] No file open', vim.log.levels.WARN)
              return
            end
            local root = get_project_root()
            local parent = vim.fn.fnamemodify(path, ':h')
            local grandparent = vim.fn.fnamemodify(parent, ':h')
            local retrieve_path = path
            for _, marker in ipairs { 'lwc', 'aura' } do
              if vim.fn.fnamemodify(grandparent, ':t') == marker then
                retrieve_path = parent
                break
              end
            end
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            run_in_term(sf_bin() .. ' project retrieve start --source-dir ' .. vim.fn.shellescape(retrieve_path) .. org_flag, root)
          end

          --- Retrieve entire project: uses manifest/package.xml if present, else source dirs from sfdx-project.json
          function M.retrieve_project()
            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            local manifest = root and (root .. '/manifest/package.xml') or ''
            local flag
            if manifest ~= '' and vim.fn.filereadable(manifest) == 1 then
              flag = ' --manifest ' .. vim.fn.shellescape(manifest)
            else
              flag = ' --source-dir ' .. vim.fn.shellescape(root .. '/force-app')
            end
            run_in_term(sf_bin() .. ' project retrieve start' .. flag .. org_flag, root)
          end

          --- Diff current file against org version.
          --- Shells out a single pipeline: backup local → retrieve (overwrites) → copy org to temp → restore local.
          --- Local file is fully restored before the diff opens, so no W12 / buffer conflicts.
          function M.diff_file()
            local path = vim.fn.expand '%:p'
            if path == '' then
              vim.notify('[SF] No file open', vim.log.levels.WARN)
              return
            end
            local org = get_default_org()
            if not org then
              vim.notify('[SF] No default org set. Use <leader>Fo first.', vim.log.levels.WARN)
              return
            end
            local root = get_project_root()
            if not root then
              vim.notify('[SF] sfdx-project.json not found', vim.log.levels.ERROR)
              return
            end

            vim.notify('[SF] Checking session for ' .. org .. '…', vim.log.levels.INFO)
            check_auth(org, function(valid, err)
              if not valid then
                vim.notify(err or '[SF] Auth check failed', vim.log.levels.ERROR)
                return
              end
              vim.schedule(function() M._do_diff(path, org, root) end)
            end)
          end

          --- Internal: run the actual retrieve + diff after auth is confirmed.
          function M._do_diff(path, org, root)
            -- Relative path from project root for sf
            local rel_path = path
            if path:sub(1, #root + 1) == root .. '/' then rel_path = path:sub(#root + 2) end

            local fname = vim.fn.fnamemodify(path, ':t')
            local org_tmp = root .. '/.sf_diff_tmp/' .. fname .. '.org'
            local orig_tabnr = vim.fn.tabpagenr()
            vim.fn.mkdir(root .. '/.sf_diff_tmp', 'p')

            -- Shell pipeline: backup → retrieve (with TTY for progress) → copy org version → restore local
            local script = table.concat({
              'set -e',
              'LOCAL_BAK=' .. vim.fn.shellescape(org_tmp .. '.local'),
              'cp ' .. vim.fn.shellescape(path) .. ' "$LOCAL_BAK"',
              'cd ' .. vim.fn.shellescape(root),
              sf_bin() .. ' project retrieve start --source-dir ' .. vim.fn.shellescape(rel_path) .. ' --target-org ' .. vim.fn.shellescape(org),
              'cp ' .. vim.fn.shellescape(path) .. ' ' .. vim.fn.shellescape(org_tmp),
              'cp "$LOCAL_BAK" ' .. vim.fn.shellescape(path),
              'rm "$LOCAL_BAK"',
            }, '\n')

            -- Open a floating terminal — SF CLI needs a real PTY or it hangs indefinitely
            local term_buf = vim.api.nvim_create_buf(false, true)
            local width = math.floor(vim.o.columns * 0.72)
            local height = 16
            local term_win = vim.api.nvim_open_win(term_buf, true, {
              relative = 'editor',
              width = width,
              height = height,
              row = math.floor((vim.o.lines - height) / 2),
              col = math.floor((vim.o.columns - width) / 2),
              style = 'minimal',
              border = 'rounded',
              title = ' SF: Retrieving ' .. fname .. ' from ' .. org .. ' ',
              title_pos = 'center',
            })

            vim.notify('[SF] Fetching org version of ' .. fname .. '…', vim.log.levels.INFO)
            vim.g.sf_diff_in_progress = 1
            vim.fn.termopen(shell_args(script), {
              cwd = root,
              on_exit = function(_, code)
                vim.g.sf_diff_in_progress = 0
                vim.schedule(function()
                  if vim.api.nvim_win_is_valid(term_win) then vim.api.nvim_win_close(term_win, true) end
                  if code ~= 0 then
                    vim.notify('[SF] Retrieve failed (exit ' .. code .. '). Check the output above.', vim.log.levels.ERROR)
                    vim.fn.delete(root .. '/.sf_diff_tmp', 'rf')
                    return
                  end
                  vim.cmd 'tabnew'
                  local diff_tabnr = vim.fn.tabpagenr()
                  local close_cmd = string.format('<cmd>tabclose | tabnext %d<cr>', orig_tabnr)

                  -- Left: org version (read-only)
                  vim.cmd('edit ' .. vim.fn.fnameescape(org_tmp))
                  vim.bo.readonly = true
                  vim.bo.modifiable = false
                  vim.cmd 'diffthis'
                  vim.api.nvim_buf_set_keymap(0, 'n', 'q', close_cmd, { noremap = true, silent = true, desc = 'Close diff' })

                  -- Right: local version
                  vim.cmd('vsplit ' .. vim.fn.fnameescape(path))
                  vim.cmd 'diffthis'
                  vim.api.nvim_buf_set_keymap(0, 'n', 'q', close_cmd, { noremap = true, silent = true, desc = 'Close diff' })

                  -- Fix diff rendering: disable horizontal scrollbind, wrap, and scrolloff
                  vim.cmd 'diffupdate'
                  vim.cmd 'windo setlocal nowrap scrolloff=0 foldlevel=99 scrollopt=ver,jump'
                  vim.cmd 'syncbind'

                  -- Clean up temp files when diff tab closes
                  local grp = vim.api.nvim_create_augroup('sf_diff_' .. diff_tabnr, { clear = true })
                  vim.api.nvim_create_autocmd('TabClosed', {
                    group = grp,
                    callback = function(ev)
                      if tonumber(ev.file) == diff_tabnr then
                        vim.fn.delete(root .. '/.sf_diff_tmp', 'rf')
                        vim.api.nvim_del_augroup_by_name('sf_diff_' .. diff_tabnr)
                      end
                    end,
                  })
                end)
              end,
            })
          end

          --- Show deploy preview (what would be deployed)
          function M.preview_deploy()
            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            local manifest = root and (root .. '/manifest/package.xml') or ''
            local flag = (manifest ~= '' and vim.fn.filereadable(manifest) == 1) and (' --manifest ' .. vim.fn.shellescape(manifest))
              or (' --source-dir ' .. vim.fn.shellescape(root .. '/force-app'))
            run_in_term(sf_bin() .. ' project deploy preview' .. flag .. org_flag, root)
          end

          --- Execute the current .apex file as anonymous Apex
          function M.exec_apex_file()
            local path = vim.fn.expand '%:p'
            if path == '' then
              vim.notify('[SF] No file open', vim.log.levels.WARN)
              return
            end
            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            run_in_buf(sf_bin() .. ' apex run --file ' .. vim.fn.shellescape(path) .. org_flag, root)
          end

          --- Execute the current visual selection as anonymous Apex (writes to a temp file)
          function M.exec_apex_selection()
            local start_line = vim.fn.line "'<"
            local end_line = vim.fn.line "'>"
            local start_col = vim.fn.col "'<"
            local end_col = vim.fn.col "'>"
            local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)

            if vim.fn.visualmode() == 'v' and #lines > 0 then
              if #lines == 1 then
                lines[1] = lines[1]:sub(start_col, end_col)
              else
                lines[1] = lines[1]:sub(start_col)
                lines[#lines] = lines[#lines]:sub(1, end_col)
              end
            end

            local tmp = vim.fn.tempname() .. '.apex'
            vim.fn.writefile(lines, tmp)

            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            run_in_buf(sf_bin() .. ' apex run --file ' .. vim.fn.shellescape(tmp) .. org_flag .. '; rm -f ' .. vim.fn.shellescape(tmp), root)
          end

          --- Show retrieve preview (what would be retrieved)
          function M.preview_retrieve()
            local root = get_project_root()
            local org = get_default_org()
            local org_flag = org and (' --target-org ' .. vim.fn.shellescape(org)) or ''
            local manifest = root and (root .. '/manifest/package.xml') or ''
            local flag = (manifest ~= '' and vim.fn.filereadable(manifest) == 1) and (' --manifest ' .. vim.fn.shellescape(manifest))
              or (' --source-dir ' .. vim.fn.shellescape(root .. '/force-app'))
            run_in_term(sf_bin() .. ' project retrieve preview' .. flag .. org_flag, root)
          end

          --- Re-authenticate an org via browser login (use when session is expired)
          function M.login_org()
            local org = get_default_org()
            local alias_flag = org and (' --alias ' .. vim.fn.shellescape(org)) or ''
            local login_url_flag = ''
            if org then
              local auth = read_auth_file(org)
              local is_sandbox = auth and auth.isSandbox
              -- Fallback: detect sandbox from loginUrl when isSandbox field is absent
              if not is_sandbox and auth and auth.loginUrl then is_sandbox = auth.loginUrl:find 'test%.salesforce%.com' ~= nil end
              if is_sandbox then login_url_flag = ' --instance-url https://test.salesforce.com' end
            end
            -- Kill anything holding the SF OAuth redirect port before and after
            local cmd = 'fuser -k 1717/tcp 2>/dev/null || true'
              .. '; '
              .. sf_bin()
              .. ' org login web'
              .. login_url_flag
              .. alias_flag
              .. '; fuser -k 1717/tcp 2>/dev/null || true'
            run_in_term(cmd, vim.fn.getcwd())
          end

          -- ── keymaps (only inside sfdx project) ───────────────────────────────
          local function is_sf_project()
            local from = vim.fn.expand '%:p:h'
            if from == '' then from = vim.fn.getcwd() end
            return vim.fn.findfile('sfdx-project.json', from .. ';') ~= ''
          end

          local function map(key, fn, desc)
            vim.keymap.set('n', key, function()
              if not is_sf_project() then
                vim.notify('[SF] Not inside an sfdx-project (no sfdx-project.json found)', vim.log.levels.WARN)
                return
              end
              fn()
            end, { desc = desc })
          end

          map('<leader>Fo', M.select_org, '[F]orce: select [o]rg')
          map('<leader>Fl', M.login_org, '[F]orce: [l]ogin / re-authenticate org')
          map('<leader>Fd', M.deploy_file, '[F]orce: [d]eploy file/bundle')
          map('<leader>FD', M.deploy_project, '[F]orce: [D]eploy project')
          map('<leader>Fr', M.retrieve_file, '[F]orce: [r]etrieve file/bundle')
          map('<leader>FR', M.retrieve_project, '[F]orce: [R]etrieve project')
          map('<leader>F=', M.diff_file, '[F]orce: diff file vs org')
          map('<leader>Fp', M.preview_deploy, '[F]orce: [p]review deploy')
          map('<leader>FP', M.preview_retrieve, '[F]orce: [P]review retrieve')
          map('<leader>Fa', M.exec_apex_file, '[F]orce: run [a]nonymous Apex file')

          vim.keymap.set('v', '<leader>Fa', function()
            if not is_sf_project() then
              vim.notify('[SF] Not inside an sfdx-project (no sfdx-project.json found)', vim.log.levels.WARN)
              return
            end
            M.exec_apex_selection()
          end, { desc = '[F]orce: run [a]nonymous Apex selection' })

          map('<leader>Ft', function()
            local root = vim.fn.findfile('sfdx-project.json', vim.fn.getcwd() .. ';')
            if root == '' then return end
            root = vim.fn.fnamemodify(root, ':h')
            local cmd = 'ctags -R --languages=Java --langmap=Java:.cls.trigger.apex -f ' .. root .. '/tags ' .. root .. '/force-app'
            vim.fn.jobstart(cmd, {
              on_exit = function(_, code)
                if code == 0 then
                  vim.opt.tags:prepend(root .. '/tags')
                  vim.notify('[SF] Tags generated — gd now works across all Apex files', vim.log.levels.INFO)
                else
                  vim.notify('[SF] ctags failed (is universal-ctags installed?)', vim.log.levels.ERROR)
                end
              end,
            })
          end, '[F]orce: generate Apex [t]ags')

          -- gd: try LSP first, fall back to ctags if LSP returns nothing
          vim.keymap.set('n', 'gd', function()
            local params = vim.lsp.util.make_position_params(0, 'utf-16')
            local clients = vim.lsp.get_clients { bufnr = 0 }
            local tried_lsp = false
            for _, client in ipairs(clients) do
              if client:supports_method 'textDocument/definition' then
                tried_lsp = true
                client:request('textDocument/definition', params, function(err, result)
                  if err or not result or vim.tbl_isempty(result) then
                    vim.notify('[SF] LSP found nothing — jumping via tags', vim.log.levels.INFO)
                    local ok, tag_err = pcall(vim.cmd, 'tag ' .. vim.fn.expand '<cword>')
                    if not ok then vim.notify('[SF] Tag not found: ' .. tostring(tag_err), vim.log.levels.WARN) end
                  else
                    local loc = vim.islist(result) and result[1] or result
                    vim.lsp.util.jump_to_location(loc, client.offset_encoding)
                  end
                end, 0)
                return
              end
            end
            if not tried_lsp then pcall(vim.cmd, 'tag ' .. vim.fn.expand '<cword>') end
          end, { desc = 'LSP: Go to Definition (with ctags fallback)' })
        end, -- callback
      }) -- autocmd
    end, -- init
  },
}
