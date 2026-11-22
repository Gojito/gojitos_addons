addon.name     = 'quester'
addon.author   = 'gojito'
addon.version  = '1.3.1'
addon.desc     = 'Tells you the next step of a quest or mission.'
addon.link     = 'https://github.com/Gojito/gojitos_addons'
addon.commands = { 'quester', 'qr' }

local index = require('data.index')
local packets = require('packets')
local model = require('model')
local journal = require('journal')
local resolve = require('resolve')
local text = require('text')
local rows = require('rows')
local window = require('window')
local starts = require('data.starts')

local M = {
    log = { qcur = {}, qdone = {}, mcur = {}, mdone = {}, mx = {}, cop = nil, nation = nil, seen = false },
    keys = {},
    zone = nil,
    pending = nil,
    name = nil,
    buffer = {},
    since_check = 0,
    replay = nil,
    ready = false,
    log_path = nil,
    log_file = nil,
    items = nil,
}

M.HELP = '/qr opens the window; /qr <name>; /qr go <name>'
M.CHECK_EVERY = 50
M.REPLAY_SLICE = 5000

M.model = model.new(index, function(name)
    local ok, g = pcall(require, 'data.' .. name)
    return ok and g or nil
end, starts, function(name) package.loaded['data.' .. name] = nil end)
M.journal = journal.new(M.model)

-- ---------------------------------------------------------------- files and log

function M.dir()
    return ('%sconfig\\addons\\quester\\'):format(AshitaCore:GetInstallPath())
end

function M.ensure_dir()
    local dir = M.dir()
    if not ashita.fs.exists(dir) then ashita.fs.create_directory(dir) end
    return dir
end

function M.char_name()
    if M.name then return M.name end
    local ok, name = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberName(0) end)
    if not ok or type(name) ~= 'string' then return nil end
    name = name:gsub('%z.*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
    if name == '' then return nil end
    M.name = name
    return name
end

function M.diag(line)
    pcall(function()
        local path = ('%s%s_%s.log'):format(M.ensure_dir(), M.char_name() or 'unknown', os.date('%Y-%m-%d'))
        if path ~= M.log_path then
            if M.log_file then M.log_file:close() end
            M.log_file = io.open(path, 'a')
            M.log_path = path
        end
        if M.log_file then
            M.log_file:write(os.date('%H:%M:%S '), line, '\n')
            M.log_file:flush()
        end
    end)
end

function M.say(s)
    AshitaCore:GetChatManager():AddChatMessage(206, false, '[quester] ' .. s)
end

function M.path(suffix)
    local name = M.char_name()
    return name and ('%s%s_%s'):format(M.ensure_dir(), name, suffix) or nil
end

function M.read_file(path)
    local f = path and io.open(path, 'rb')
    if not f then return nil end
    local s = f:read('*a')
    f:close()
    return s
end

function M.write_atomic(path, body)
    local tmp = path .. '.tmp'
    local f = io.open(tmp, 'wb')
    if not f then return false end
    f:write(body)
    f:close()
    os.remove(path)
    return os.rename(tmp, path)
end

-- ---------------------------------------------------------------- journal

function M.record(kind, ...)
    local line = journal.format(os.time(), kind, ...)
    if kind == 'FIN' or kind == 'TALK' or kind == 'TRADE' or kind == 'KILL' then M.diag(line) end
    local path = M.path('journal.txt')
    if not path then
        M.buffer[#M.buffer + 1] = line
        return
    end
    M.flush_buffer(path)
    local f = io.open(path, 'a')
    if f then
        f:write(line, '\n')
        f:close()
    end
    if M.ready then
        M.journal:feed_line(line)
        M.mark()
        M.since_check = M.since_check + 1
        if M.since_check >= M.CHECK_EVERY then M.checkpoint() end
    end
end

function M.flush_buffer(path)
    if #M.buffer == 0 then return end
    local f = io.open(path, 'a')
    if not f then return end
    for _, line in ipairs(M.buffer) do
        f:write(line, '\n')
        if M.ready then M.journal:feed_line(line) end
    end
    f:close()
    M.buffer = {}
end

function M.journal_size()
    local f = io.open(M.path('journal.txt') or '', 'rb')
    if not f then return 0 end
    local n = f:seek('end')
    f:close()
    return n or 0
end

-- The table and the addon version: a new version replays the whole journal once.
function M.table_hash()
    return tostring(index.meta.inputs) .. ':' .. addon.version
end

function M.checkpoint()
    local path = M.path('check.txt')
    if not path or not M.ready then return end
    local offset = M.journal_size()
    M.write_atomic(path, M.journal:checkpoint(M.table_hash(), offset))
    local n = 0
    for _ in pairs(M.journal.beliefs) do n = n + 1 end
    M.diag(('CHECK written %d beliefs at %d'):format(n, offset))
    M.since_check = 0
end

-- Load the checkpoint and replay the tail, or replay the whole journal as a coroutine resumed each frame.
function M.start_replay()
    local jpath, cpath = M.path('journal.txt'), M.path('check.txt')
    if not jpath or M.replay or M.ready then return end
    local body = M.read_file(jpath) or ''
    local hash, offset = M.journal:load_checkpoint(M.read_file(cpath))
    if hash == M.table_hash() and offset and offset <= #body then
        local t0, n = os.clock(), 0
        for line in body:sub(offset + 1):gmatch('[^\n]+') do
            M.journal:feed_line(line)
            n = n + 1
        end
        M.ready = true
        M.diag(('JOURNAL replay %d lines %.2fs from offset %d'):format(n, os.clock() - t0, offset))
        return
    end
    M.journal = journal.new(M.model)
    M.replay = coroutine.create(function()
        local t0, n = os.clock(), 0
        for line in body:gmatch('[^\n]+') do
            M.journal:feed_line(line)
            n = n + 1
            if n % M.REPLAY_SLICE == 0 then coroutine.yield() end
        end
        M.diag(('JOURNAL replay %d lines %.2fs from offset 0'):format(n, os.clock() - t0))
    end)
end

function M.tick()
    if M.replay then
        local ok, err = coroutine.resume(M.replay)
        if not ok then M.diag('ERROR in replay: ' .. tostring(err)) end
        if coroutine.status(M.replay) == 'dead' then
            M.replay = nil
            M.ready = true
            M.checkpoint()
        end
    elseif not M.ready and M.char_name() then
        M.start_replay()
    end
    M.frame(os.clock())
end

-- ---------------------------------------------------------------- the quest and mission log

function M.log_line()
    local parts = {}
    for l = 0, 10 do
        if M.log.qcur[l] then parts[#parts + 1] = ('qc %d %s'):format(l, M.hex(M.log.qcur[l])) end
        if M.log.qdone[l] then parts[#parts + 1] = ('qd %d %s'):format(l, M.hex(M.log.qdone[l])) end
    end
    for l = 0, 13 do
        if M.log.mcur[l] then parts[#parts + 1] = ('mc %d %d'):format(l, M.log.mcur[l]) end
        if M.log.mdone[l] then parts[#parts + 1] = ('md %d %s'):format(l, M.hex(M.log.mdone[l])) end
    end
    for l = 9, 13 do
        if M.log.mx[l] then parts[#parts + 1] = ('mx %d %d'):format(l, M.log.mx[l]) end
    end
    if M.log.cop then parts[#parts + 1] = 'cop ' .. M.log.cop end
    if M.log.nation then parts[#parts + 1] = 'nation ' .. M.log.nation end
    return table.concat(parts, '\n') .. '\n'
end

function M.hex(s)
    return (s:gsub('.', function(c) return ('%02x'):format(c:byte()) end))
end

function M.unhex(h)
    return (h:gsub('%x%x', function(x) return string.char(tonumber(x, 16)) end))
end

function M.read_log_cache()
    local body = M.read_file(M.path('log.txt'))
    if not body then return end
    for line in body:gmatch('[^\n]+') do
        local tag, a, b = line:match('^(%a+) (%S+) ?(%S*)$')
        if tag == 'qc' then M.log.qcur[tonumber(a)] = M.unhex(b)
        elseif tag == 'qd' then M.log.qdone[tonumber(a)] = M.unhex(b)
        elseif tag == 'mc' then M.log.mcur[tonumber(a)] = tonumber(b)
        elseif tag == 'md' then M.log.mdone[tonumber(a)] = M.unhex(b)
        elseif tag == 'mx' then M.log.mx[tonumber(a)] = tonumber(b)
        elseif tag == 'cop' then M.log.cop = tonumber(a)
        elseif tag == 'nation' then M.log.nation = tonumber(a) end
    end
    M.log.seen = true
end

function M.on_log(data)
    local r = packets.mission(data)
    local L = M.log
    if r.qlog then
        local l = r.qlog
        local before_cur, before_done = L.qcur[l], L.qdone[l]
        if r.cur then L.qcur[l] = r.cur end
        if r.done then L.qdone[l] = r.done end
        for q = 0, 255 do
            local oc = before_cur and packets.bit(before_cur, q) or false
            local od = before_done and packets.bit(before_done, q) or false
            local nc = L.qcur[l] and packets.bit(L.qcur[l], q) or false
            local nd = L.qdone[l] and packets.bit(L.qdone[l], q) or false
            if (oc ~= nc and (r.cur ~= nil)) or (od ~= nd and (r.done ~= nil)) then
                M.record('Q', l, q, nc and 1 or 0, nd and 1 or 0)
                M.mark()
            end
        end
    end
    if r.m then
        for log, id in pairs(r.m) do
            if L.mcur[log] ~= id then
                L.mcur[log] = id
                M.record('M', log, id)
                M.mark()
            end
            if log >= 9 and log <= 13 and id > (L.mx[log] or 0) then L.mx[log] = id end
        end
    end
    if r.mdone then
        for log, bits in pairs(r.mdone) do L.mdone[log] = bits end
    end
    if r.cop_status then L.cop = r.cop_status end
    if r.nation then L.nation = r.nation end
    L.seen = true
    local path = M.path('log.txt')
    if path then M.write_atomic(path, M.log_line()) end
    M.diag(('LOG port 0x%X'):format(r.port))
end

function M.on_keyitems(data)
    local tab, bits = packets.keyitems(data)
    local old = M.keys[tab]
    M.keys[tab] = bits
    if not old then return end
    for i = 0, 511 do
        local a, b = packets.bit(old, i), packets.bit(bits, i)
        if a ~= b then
            M.record('KI', b and 'add' or 'del', tab * 512 + i)
            M.mark()
        end
    end
end

-- ---------------------------------------------------------------- the world the model reads

function M.quest(l, i)
    local cur = M.log.qcur[l] and packets.bit(M.log.qcur[l], i)
    local done = M.log.qdone[l] and packets.bit(M.log.qdone[l], i)
    if done then return 2 end
    return cur and 1 or 0
end

function M.mission(l)
    local v = M.log.mcur[l]
    if v == nil then return l <= 2 and model.NONE or 0 end
    return v
end

function M.mission_done(l, i)
    if l <= 5 and i < 64 then
        local bits = M.log.mdone[l]
        return bits ~= nil and packets.bit(bits, i)
    end
    local cur = M.log.mcur[l]
    return cur ~= nil and cur ~= model.NONE and i < cur
end

function M.held_items()
    if M.items then return M.items end
    local out = {}
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory()
        for bag = 0, 16 do
            for slot = 0, inv:GetContainerCountMax(bag) do
                local it = inv:GetContainerItem(bag, slot)
                if it and it.Id ~= 0 and it.Id ~= 65535 then out[it.Id] = true end
            end
        end
    end)
    M.items = out
    return out
end

M.world = {
    quest = function(l, i) return M.quest(l, i) end,
    mission = function(l) return M.mission(l) end,
    mission_done = function(l, i) return M.mission_done(l, i) end,
    cop_status = function() return M.log.cop end,
    ki = function(id)
        local ok, has = pcall(function() return AshitaCore:GetMemoryManager():GetPlayer():HasKeyItem(id) end)
        return ok and has or false
    end,
    item = function(id) return M.held_items()[id] or false end,
    level = function() return AshitaCore:GetMemoryManager():GetPlayer():GetMainJobLevel() end,
    job = function() return AshitaCore:GetMemoryManager():GetPlayer():GetMainJob() end,
    rank = function() return AshitaCore:GetMemoryManager():GetPlayer():GetRank() end,
    rank_points = function() return AshitaCore:GetMemoryManager():GetPlayer():GetRankPoints() end,
    nation = function() return AshitaCore:GetMemoryManager():GetPlayer():GetNation() end,
}

M.names = {
    zone = function(id)
        local ok, s = pcall(function() return AshitaCore:GetResourceManager():GetString('zones.names', id) end)
        return ok and s and s ~= '' and s or ('zone ' .. tostring(id))
    end,
    item = function(id)
        local ok, s = pcall(function() return AshitaCore:GetResourceManager():GetItemById(id).Name[1] end)
        return ok and s or nil
    end,
    keyitem = function(id)
        local ok, s = pcall(function() return AshitaCore:GetResourceManager():GetString('keyitems.names', id) end)
        return ok and s and s ~= '' and s or nil
    end,
    quest = function(l, i)
        local c = index.c['q' .. l .. ':' .. i]
        return c and c.n
    end,
    mission = function(l, i)
        local c = index.c['m' .. l .. ':' .. i]
        return c and c.n
    end,
}

-- ---------------------------------------------------------------- answers and the window

function M.ctx()
    return { index = index, starts = starts, model = M.model, log = M.log, world = M.world,
        beliefs = M.journal.beliefs, timers = M.journal.timers, names = M.names, zone = M.zone, now = os.time(),
        clock = function(t) return os.date('%m-%d %H:%M', t) end }
end

-- The player's x and z, the way gps reads them: party slot 0's target index, then the local position (y is world z).
function M.my_pos()
    local ok, x, z = pcall(function()
        local mm = AshitaCore:GetMemoryManager()
        local idx = mm:GetParty():GetMemberTargetIndex(0)
        local em = mm:GetEntity()
        return em:GetLocalPositionX(idx), em:GetLocalPositionY(idx)
    end)
    if ok and type(x) == 'number' and type(z) == 'number' then return x, z end
    return nil
end

M.NO_TARGET = { zone = true, zoneonce = true, out = true, area = true }

-- The point Go hands gps for one step: in the player's zone the nearest of its positions, in another zone the first.
function M.go_target(s, here, px, pz)
    if not s or M.NO_TARGET[s.k] or not s.xyz or not s.z then return nil end
    local pts = {}
    for x, y, z in tostring(s.xyz):gmatch('(%-?[%d.]+),(%-?[%d.]+),(%-?[%d.]+)') do
        pts[#pts + 1] = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
    end
    if #pts == 0 then return nil end
    local best = pts[1]
    if s.z == here and px and pz then
        local bd
        for _, p in ipairs(pts) do
            local d = (p.x - px) ^ 2 + (p.z - pz) ^ 2
            if not bd or d < bd then best, bd = p, d end
        end
    end
    local label = (s.e or text.step(s, M.names)):gsub('[^\32-\126]', ''):gsub('["|]', '')
    return { zone = s.z, x = best.x, y = best.y, z = best.z, label = label }
end

-- The one way a command is typed: /gps waypoint, from /qr go or the window's Go button.
function M.route(t)
    if type(t) ~= 'table' or not t.zone then return end
    local cmd = ('/gps waypoint %d %.1f %.1f %.1f "%s"'):format(t.zone, t.x, t.y, t.z, t.label)
    M.diag('GO ' .. cmd)
    AshitaCore:GetChatManager():QueueCommand(1, cmd)
    if t.zone ~= M.zone then M.view.queued = M.place_key(t) end
end

function M.place_key(t)
    return t and (t.zone .. '|' .. t.label .. '|' .. t.x .. '|' .. t.z) or nil
end

-- What the detail shows for a place: 'here' or 'away' for a Go button, 'queued', or nil for no Go.
function M.go_state(s)
    local px, pz = M.my_pos()
    local t = M.go_target(s, M.zone, px, pz)
    if not t then return nil end
    if M.view.queued and M.view.queued == M.place_key(t) then return 'queued' end
    return t.zone == M.zone and 'here' or 'away'
end

function M.go_click(s)
    local px, pz = M.my_pos()
    M.route(M.go_target(s, M.zone, px, pz))
end

local function step_line(name, steps, tag)
    local t, merged = rows.next_text(steps, M.names)
    if not t then return name .. ': no step known.' end
    if #merged == 1 then return name .. (tag or '') .. ': ' .. t .. '.' end
    return ('%s%s: %s. /qr shows them.'):format(name, tag or '', t)
end

-- An active quest's or mission's line: a to do list reads its count, anything else its steps.
function M.active_line(name, e, idx, info)
    local td = rows.todo_view(e, idx, info, M.names)
    if td then return ('%s: %s. /qr shows them.'):format(name, td.text:sub(1, 1):lower() .. td.text:sub(2)) end
    local steps = {}
    for _, p in ipairs(idx) do steps[#steps + 1] = e.p[p] end
    return step_line(name, steps)
end

function M.start_line(ctx, key)
    local c = index.c[key]
    local list = M.model:starts(key)
    if #list == 0 then return c.n .. ': no step data.' end
    local st = list[1]
    for _, s in ipairs(list) do
        local blocked = rows.needs(ctx, s.n)
        if not blocked then st = s; break end
    end
    local after = ''
    if st.v and index.c[st.v] then after = 'After ' .. index.c[st.v].n .. ': ' end
    local unmet = {}
    for _, u in ipairs(model.needs(st.n, M.world)) do if u.checked then unmet[#unmet + 1] = u end end
    local needs = text.needs(unmet, M.names)
    return 'Not started: ' .. c.n .. '. ' .. after .. text.step(st.s, M.names) .. '.' .. (needs and (' ' .. needs) or '')
end

-- The one chat line for /qr <name>.
function M.answer(key)
    local ctx = M.ctx()
    local c = index.c[key]
    if c.k == 'q' then
        local st = rows.quest_status(ctx, c.l, c.i)
        if st == 'repeat' then return c.n .. ': repeat, no step data.' end
        if st == 'done' then return 'Done: ' .. c.n .. '.' end
        if st == 'active' then
            local e, idx, info = rows.infer(ctx, key)
            if not c.f or not e then return c.n .. ': no step data.' end
            return M.active_line(c.n, e, idx, info)
        end
        if rows.proven(ctx, key) then
            local row
            for _, g in ipairs(rows.active_quests(ctx)) do
                for _, r in ipairs(g.rows) do if r.key == key then row = r end end
            end
            return step_line(c.n, row and row.steps or {}, ' (not in log)')
        end
        return M.start_line(ctx, key)
    end
    local sl = rows.storyline(ctx, c.l)
    if sl.mission == key and sl.state == 'finished' then return c.n .. ': storyline finished.' end
    if sl.mission == key and sl.state == 'in_progress' then
        local e, idx, info = rows.infer(ctx, key)
        if not c.f or not e then return c.n .. ': no step data.' end
        return M.active_line(c.n, e, idx, info)
    end
    if M.mission_done(c.l, c.i) then return 'Done: ' .. c.n .. '.' end
    return M.start_line(ctx, key)
end

function M.find(words)
    local ctx = M.ctx()
    local preferred = {}
    for key, c in pairs(index.c) do
        if c.k == 'q' and (rows.quest_status(ctx, c.l, c.i) == 'active' or rows.proven(ctx, key)) then
            preferred[#preferred + 1] = key
        end
    end
    for _, log in ipairs(rows.LOGS) do
        local sl = rows.storyline(ctx, log)
        if sl.mission then preferred[#preferred + 1] = sl.mission end
    end
    table.sort(preferred)
    return resolve.pick(index, words, preferred)
end

function M.lookup(words)
    if not M.log.seen then return M.say('Zone once.') end
    M.items = nil
    local hits = M.find(words)
    if #hits == 0 then return M.say('No match: ' .. words .. '.') end
    if #hits > 1 then
        local names = {}
        for i = 1, math.min(3, #hits) do names[#names + 1] = index.c[hits[i]].n end
        return M.say(('%d match: %s%s.'):format(#hits, table.concat(names, ', '), #hits > 3 and (', +' .. (#hits - 3) .. ' more') or ''))
    end
    M.diag('CMD ' .. words)
    M.say(M.answer(hits[1]))
end

function M.go(words)
    if not M.log.seen then return M.say('Zone once.') end
    M.items = nil
    local hits = words ~= '' and M.find(words) or {}
    if #hits ~= 1 then return M.say(#hits > 1 and (#hits .. ' match: /qr go <name> needs one.') or 'No match: give a name.') end
    local key, c, ctx = hits[1], index.c[hits[1]], M.ctx()
    local e, idx = rows.infer(ctx, key)
    if not e then return M.say(c.n .. ': no step data.') end
    if #idx ~= 1 then return M.say(('%s: %d possible. /qr shows them.'):format(c.n, #idx)) end
    local s = e.p[idx[1]]
    local px, pz = M.my_pos()
    local t = M.go_target(s, M.zone, px, pz)
    if not t then return M.say(c.n .. ': ' .. text.step(s, M.names) .. '.') end
    M.route(t)
end

M.view = { open = { false }, filter = { '' }, tabs = { {}, {}, {}, {} }, selected = nil, queued = nil }
M.dirty, M.builds, M.last_build, M.last_poll, M.placed_read = true, 0, -10, 0, false

function M.mark() M.dirty = true end

function M.read_place()
    local p = M.path('window.lua')
    local f = p and loadfile(p)
    local ok, t = pcall(function() return f and f() end)
    if ok and type(t) == 'table' and tonumber(t.x) and tonumber(t.w) then
        M.view.place = t
        M.view.detail_h = tonumber(t.d)
    end
end

function M.save_place()
    local p, t = M.path('window.lua'), M.view.moved
    if not p or not t then return end
    M.write_atomic(p, ('return { x = %d, y = %d, w = %d, h = %d, d = %d }\n'):format(t.x, t.y, t.w, t.h,
        tonumber(M.view.detail_h) or window.DETAIL))
    M.view.saved = t
end

function M.toggle()
    if M.view.open[1] then
        M.view.open[1] = false
        M.save_place()
        return
    end
    if not M.placed_read then
        M.read_place()
        M.placed_read = true
    end
    M.view.open[1] = true
    M.view.go_state = M.go_state
    M.mark()
end

function M.rebuild()
    M.items = nil
    M.view.tabs = rows.build(M.ctx())
    M.model:release(rows.keys_in(M.view.tabs, M.view.selected and M.view.selected.key))
    M.builds = M.builds + 1
    M.dirty = false
end

-- One frame: rebuild at most once a second while dirty, poll every 5 s for item changes, draw.
function M.frame(now)
    if not M.view.open[1] then return end
    if now - M.last_poll >= 5 then
        M.last_poll = now
        M.dirty = true
    end
    if M.dirty and now - M.last_build >= 1 then
        M.last_build = now
        M.rebuild()
    end
    M.imgui = M.imgui or require('imgui')
    local ok, click = pcall(window.draw, M.imgui, M.view)
    if not ok then
        M.diag('ERROR in window: ' .. tostring(click))
        M.view.open[1] = false
        return
    end
    if not click then return end
    if click.select then
        M.view.selected = click.select
        M.mark()
    elseif click.go then
        M.go_click(click.go)
    elseif click.close then
        M.view.open[1] = false
        M.save_place()
    elseif click.resized then
        M.view.detail_h = click.resized
        M.view.moved_at, M.view.saved = now, nil
    elseif click.moved then
        local m, s = click.moved, M.view.moved
        if not s or s.x ~= m.x or s.y ~= m.y or s.w ~= m.w or s.h ~= m.h then
            M.view.moved, M.view.moved_at = m, now
        elseif M.view.moved_at and now - M.view.moved_at >= 1 and M.view.saved ~= s then
            M.save_place()
        end
    end
end

function M.command(rest)
    rest = rest:gsub('^%s+', ''):gsub('%s+$', '')
    local first = (rest:match('^(%S+)') or ''):lower()
    if rest == '' or first == 'list' then return M.toggle() end
    if first == 'help' then return M.say(M.HELP) end
    if first == 'go' then return M.go((rest:sub(3):gsub('^%s+', ''))) end
    return M.lookup(rest)
end

-- The whole first word, lower cased, must be the command; /quest and the like reach the game.
function M.is_command(line)
    local verb = (tostring(line):match('^(%S+)') or ''):lower()
    return verb == '/quester' or verb == '/qr', verb
end

-- ---------------------------------------------------------------- packets

function M.party_ids()
    local ids = {}
    pcall(function()
        local party = AshitaCore:GetMemoryManager():GetParty()
        for i = 0, 17 do
            local id = party:GetMemberServerId(i)
            if id and id ~= 0 then ids[id] = true end
        end
    end)
    return ids
end

function M.entity_name(index_no)
    local ok, name = pcall(function() return AshitaCore:GetMemoryManager():GetEntity():GetName(index_no) end)
    return ok and name or nil
end

function M.trade_items(t)
    local parts = {}
    pcall(function()
        local inv = AshitaCore:GetMemoryManager():GetInventory()
        for _, s in ipairs(t.slots) do
            if s.count > 0 and s.slot > 0 then
                local it = inv:GetContainerItem(0, s.slot)
                if it and it.Id ~= 0 then parts[#parts + 1] = it.Id .. ':' .. s.count end
            end
        end
    end)
    return #parts > 0 and table.concat(parts, ',') or '-'
end

function M.on_in(e)
    if e.id == 0x056 then
        M.on_log(e.data)
    elseif e.id == 0x055 then
        M.on_keyitems(e.data)
    elseif e.id == 0x032 or e.id == 0x033 or e.id == 0x034 then
        local npc, zone, csid = packets.event(e.id, e.data)
        M.pending = { npc = npc, zone = zone, csid = csid }
        M.record('EV', zone, csid, npc)
    elseif e.id == 0x029 then
        local actor, target, tindex, msg = packets.battle(e.data)
        if (msg == 6 or msg == 20) and M.party_ids()[actor] then
            local name = M.entity_name(tindex)
            if name and name ~= '' then M.record('KILL', M.zone or 0, name) end
        end
    elseif e.id == 0x00A then
        M.zone = packets.zone(e.data)
        M.pending = nil
        if M.view.queued and tonumber(M.view.queued:match('^(%d+)|')) == M.zone then M.view.queued = nil end
        M.mark()
        M.record('ZONE', M.zone)
    elseif e.id == 0x00B then
        M.record('OUT', M.zone or 0)
        M.pending = nil
        M.checkpoint()
    end
end

function M.on_out(e)
    if e.injected then return end
    if e.id == 0x05B then
        local r = packets.eventend(e.data)
        if r.mode == 0 then
            M.record('FIN', r.zone, r.csid, r.option, r.npc)
            M.pending = nil
        else
            M.record('UPD', r.zone, r.csid, r.option)
        end
    elseif e.id == 0x01A then
        local target, action = packets.action(e.data)
        if action == 0 then M.record('TALK', M.zone or 0, target) end
    elseif e.id == 0x036 then
        local t = packets.trade(e.data)
        M.record('TRADE', M.zone or 0, t.npc, M.trade_items(t))
    end
end

-- ---------------------------------------------------------------- events

function M.on_error(where, err)
    M.diag(('ERROR in %s: %s'):format(where, tostring(err)))
end

M.traceback = type(package.loaded.debug) == 'table' and type(package.loaded.debug.traceback) == 'function'
    and package.loaded.debug.traceback or nil

function M.guard(where, fn)
    return function(...)
        local args = { ... }
        local ok, err
        if M.traceback then
            ok, err = xpcall(function() return fn(unpack(args)) end, M.traceback)
        else
            ok, err = pcall(fn, unpack(args))
        end
        if not ok then M.on_error(where, err) end
    end
end

function M.on_command(e)
    local is, verb = M.is_command(e.command)
    if not is then return end
    e.blocked = true
    if not M.ready then M.diag('JOURNAL busy') end
    M.command(tostring(e.command):sub(#verb + 1))
end

ashita.events.register('load', 'quester_load', M.guard('load', function()
    local meta = index.meta
    M.zone = select(2, pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0) end))
    if M.char_name() then M.read_log_cache() end
    M.record('LOAD', addon.version, meta.server)
    M.diag(('== quester %s table %s, %d quests, %d missions =='):format(addon.version, meta.server,
        meta.counts.quests or 0, meta.counts.missions or 0))
end))

ashita.events.register('unload', 'quester_unload', M.guard('unload', function()
    M.checkpoint()
    M.save_place()
    if M.log_file then
        M.log_file:close()
        M.log_file = nil
    end
end))

ashita.events.register('command', 'quester_command', M.guard('command', M.on_command))
ashita.events.register('packet_in', 'quester_in', M.guard('packet_in', M.on_in))
ashita.events.register('packet_out', 'quester_out', M.guard('packet_out', M.on_out))
ashita.events.register('d3d_present', 'quester_tick', M.guard('d3d_present', M.tick))

return M
