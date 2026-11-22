-- The window's rows, built from the table, the log, the world reads and the journal. No Ashita call here.
local model = require('model')
local text = require('text')

local R = { MUT = {} }

R.AREAS = { [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst', [3] = 'Jeuno', [4] = 'Other Areas', [5] = 'Outlands',
    [6] = 'Aht Urhgan', [7] = 'Crystal War', [8] = 'Abyssea', [9] = 'Adoulin', [10] = 'Coalition' }
R.NONE = 65535
R.LOGS = { 0, 1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13 }

-- The Available tabs hide what CEXI's own settings switch off; the Active tabs show whatever the log holds.
R.HIDE_SWITCHED_OFF = true

local function cur_bit(ctx, l, i)
    local b = ctx.log.qcur[l]
    if not b then return false end
    return math.floor((b:byte(math.floor(i / 8) + 1) or 0) / 2 ^ (i % 8)) % 2 == 1
end

local function done_bit(ctx, l, i)
    local b = ctx.log.qdone[l]
    if not b then return false end
    return math.floor((b:byte(math.floor(i / 8) + 1) or 0) / 2 ^ (i % 8)) % 2 == 1
end

function R.quest_status(ctx, l, i)
    local c, d = cur_bit(ctx, l, i), done_bit(ctx, l, i)
    if c and d then return 'repeat' end
    if d then return 'done' end
    return c and 'active' or 'none'
end

local function mdone(ctx, l, i)
    return ctx.world.mission_done(l, i)
end

-- The last mission id of a log, from the index's last flags.
local function last_id(ctx, log)
    local best
    for key, c in pairs(ctx.index.c) do
        if c.k == 'm' and c.l == log and c.last and (not best or c.i > best) then best = c.i end
    end
    return best
end

-- One storyline's state: hidden, not_started, between, in_progress, finished or declined, and its mission key.
function R.storyline(ctx, log)
    local L = ctx.log
    local cur = L.mcur[log]
    local key = cur ~= nil and ('m' .. log .. ':' .. cur) or nil
    if R.MUT.emptyvalue then
        if cur ~= nil and ctx.index.c[key] then return { state = 'in_progress', mission = key } end
        return { state = 'hidden' }
    end
    if log == 7 or log == 8 or cur == nil then return { state = 'hidden' } end
    if log <= 2 then
        if log ~= L.nation then return { state = 'hidden' } end
        if cur == R.NONE then
            if mdone(ctx, log, 23) then return { state = 'finished', mission = 'm' .. log .. ':23' } end
            for i = 0, 22 do
                if mdone(ctx, log, i) then return { state = 'between' } end
            end
            return { state = 'not_started' }
        end
        return { state = 'in_progress', mission = key }
    end
    if log == 3 then
        if cur == R.NONE then return { state = 'not_started' } end
        if cur == 0 and mdone(ctx, 3, 0) then return { state = 'between' } end
        return { state = 'in_progress', mission = key }
    end
    if log == 4 or log == 5 then
        if log == 4 and cur == 47 then return { state = 'finished', mission = key } end
        if cur == 0 then
            if log == 5 and mdone(ctx, 5, 53) then return { state = 'finished', mission = 'm5:53' } end
            if mdone(ctx, log, 0) then return { state = 'between' } end
            return { state = 'not_started' }
        end
        return { state = 'in_progress', mission = key }
    end
    if log == 6 then
        if cur == 0 then return { state = 'declined' } end
        if cur == 101 then return { state = 'not_started' } end
        return { state = 'in_progress', mission = key }
    end
    if cur == 0 then
        local mx = L.mx and L.mx[log] or 0
        if mx == 0 then return { state = 'not_started' } end
        local last = last_id(ctx, log)
        if last and mx >= last then return { state = 'finished', mission = 'm' .. log .. ':' .. last } end
        return { state = 'between' }
    end
    return { state = 'in_progress', mission = key }
end

-- ---------------------------------------------------------------- steps and their text

local MERGE_KINDS = { talk = true, trade = true, ki = true, kill = true }

local function nozone(s)
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    c.z, c.x0, c.z0 = nil, nil, nil
    return c
end

-- Steps whose text reads the same merge; the same kind, NPC and items in several zones merge into `N places`.
function R.merge(steps, names)
    local out, by_text, by_place = {}, {}, {}
    for _, s in ipairs(steps) do
        local t = text.step(s, names)
        if not by_text[t] then
            local pk = (MERGE_KINDS[s.k] and not R.MUT.nomerge) and table.concat({ s.k, tostring(s.e), tostring(s.i),
                tostring(s.q), tostring(s.d), tostring(s.w) }, '|') or nil
            local m = pk and by_place[pk]
            if m then
                m.places[#m.places + 1] = { s = s, text = t }
            else
                m = { s = s, text = t, places = { { s = s, text = t } } }
                out[#out + 1] = m
                if pk then by_place[pk] = m end
            end
            by_text[t] = true
        end
    end
    for _, m in ipairs(out) do
        if #m.places > 1 then
            m.text = ('%s, %d places'):format(text.step(nozone(m.s), names), #m.places)
        end
    end
    return out
end

function R.next_text(steps, names)
    local merged = R.merge(steps, names)
    if #merged == 0 then return nil, merged end
    if #merged == 1 then return merged[1].text, merged end
    return ('%d possible'):format(#merged), merged
end

local step_list

-- Inference for one key: the visible part of the world, the stored candidates, the journal's belief.
function R.infer(ctx, key)
    local e = ctx.model:entry(key)
    if not e then return nil end
    local V = model.visible(e, ctx.world)
    local cands = model.candidates(e, V)
    local belief = ctx.beliefs and ctx.beliefs[key]
    if e.rm then
        local keep = cands
        if belief and belief.known and not R.MUT.noknown then
            keep = {}
            for _, ri in ipairs(cands) do
                local ok = true
                for i, want in pairs(e.rules[ri].c) do
                    local have = belief.known[i]
                    if i > e.nv and have ~= nil and have ~= 'T' and want ~= 'T' and have ~= want then ok = false; break end
                end
                if ok then keep[#keep + 1] = ri end
            end
            if #keep == 0 then keep = cands end
        end
        return e, model.rule_steps(e, keep), { known = (not R.MUT.noknown) and belief and belief.known or {} }
    end
    local states = cands
    if belief then
        local keep = {}
        for _, si in ipairs(cands) do if belief[si] then keep[#keep + 1] = si end end
        if #keep > 0 then states = keep end
    end
    if #states == 0 then states = model.approx(e, V) end
    return e, model.steps_of(e, states), { states = states }
end

-- ---------------------------------------------------------------- to do lists

-- A mask whose steps each set one of its bits from 0 to 1, each on that bit at 0, is a to do list: every step is
-- needed, in any order. A rule whose condition needs every bit of it at 1 is the list's final step.
function R.todo_lists(e)
    if e.todo then return e.todo end
    local lists = {}
    e.todo = lists
    if R.MUT.notodo then return lists end
    local masks, order = {}, {}
    for i, a in ipairs(e.a) do
        local name = a:match('^(var:.+)#%d+$')
        if name then
            if not masks[name] then masks[name] = {}; order[#order + 1] = name end
            masks[name][#masks[name] + 1] = i
        end
    end
    table.sort(order)
    for _, name in ipairs(order) do
        local bits, items, finals, n = masks[name], {}, {}, 0
        local used = {}
        for _, r in ipairs(e.rules) do
            local one, count = nil, 0
            for _, i in ipairs(bits) do
                if r.w[i] == 1 then one, count = i, count + 1 end
            end
            if count == 1 and r.c[one] == 0 then
                used[one] = true
                if not items[r.p] then
                    items[r.p] = one
                    n = n + 1
                end
            end
        end
        for _, r in ipairs(e.rules) do
            local all = next(used) ~= nil
            for i in pairs(used) do if r.c[i] ~= 1 then all = false; break end end
            if all then finals[r.p] = true end
        end
        if n >= 2 then lists[#lists + 1] = { name = name, bits = bits, items = items, finals = finals } end
    end
    return lists
end

local function bit_value(e, info, i)
    if info.known then return info.known[i] end
    local v
    for _, si in ipairs(info.states or {}) do
        local x = e.states[si][i]
        if v == nil then v = x elseif v ~= x then return nil end
    end
    return v
end

-- When every candidate is an item of one list or its final step: the pending items, the final step, the done items.
function R.todo_view(e, idx, info, names)
    if not info or #idx < 2 then return nil end
    for _, L in ipairs(R.todo_lists(e)) do
        local fits = true
        for _, p in ipairs(idx) do
            if not L.items[p] and not L.finals[p] then fits = false; break end
        end
        if fits then
            local pending, final, done, allknown = {}, {}, {}, true
            local seen = {}
            for _, p in ipairs(idx) do seen[p] = true end
            local ps = {}
            for p in pairs(L.items) do ps[#ps + 1] = p end
            table.sort(ps)
            for _, p in ipairs(ps) do
                local v = bit_value(e, info, L.items[p])
                if v == nil then allknown = false end
                if v == 1 then
                    done[#done + 1] = e.p[p]
                elseif seen[p] then
                    pending[#pending + 1] = e.p[p]
                end
            end
            for _, p in ipairs(idx) do if L.finals[p] and not L.items[p] then final[#final + 1] = e.p[p] end end
            local text = (allknown and '%d left' or 'Up to %d left'):format(#pending)
            return { text = text, pending = R.merge(pending, names), final = R.merge(final, names),
                done = R.merge(done, names), steps = pending, finals = final }
        end
    end
    return nil
end

-- A row's Next and detail from its candidate steps: a to do list when it is one, else the merged steps.
function R.fill(row, e, idx, info, ctx, key)
    row.steps = step_list(e, idx, ctx, key)
    local td = R.todo_view(e, idx, info, ctx.names)
    if td then
        row.todo = td
        row.next = td.text
        local all = {}
        for _, s in ipairs(td.steps) do all[#all + 1] = s end
        for _, s in ipairs(td.finals) do all[#all + 1] = s end
        row.merged = R.merge(all, ctx.names)
        return
    end
    row.next, row.merged = R.next_text(row.steps, ctx.names)
end

step_list = function(e, idx, ctx, key)
    local out = {}
    for _, p in ipairs(idx) do
        local s = e.p[p]
        local ready = s.w and ctx.timers and ctx.timers[key]
        if ready and ctx.now and ready > ctx.now and ctx.clock then
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            c.until_text = ctx.clock(ready)
            s = c
        end
        out[#out + 1] = s
    end
    return out
end

-- ---------------------------------------------------------------- pre log proof

local function held(ctx, atom)
    local p, id = atom:match('^(%a+):(%d+)$')
    if p == 'ki' then return ctx.world.ki(tonumber(id)) end
    if p == 'it' then return ctx.world.item(tonumber(id)) end
    return false
end

function R.proven(ctx, key)
    local c = ctx.index.c[key]
    if not c or c.k ~= 'q' or not c.pl then return false end
    if R.MUT.anyprelog then
        local e = ctx.model:entry(key)
        if not e or e.rm then return false end
        local pre = {}
        for _, i in ipairs(e.prelog) do pre[i] = true end
        for _, si in ipairs(model.candidates(e, model.visible(e, ctx.world))) do
            if pre[si] then return true end
        end
        return false
    end
    local st = ctx.starts[key]
    for _, a in ipairs(st and (R.MUT.shared and st.pa or st.pf) or {}) do
        if held(ctx, a) then return true end
    end
    local b = ctx.beliefs and ctx.beliefs[key]
    if b and next(b) then
        local e = ctx.model:entry(key)
        if not e or e.rm then return false end
        local pre = {}
        for _, i in ipairs(e.prelog) do pre[i] = true end
        for si in pairs(b) do
            if not pre[si] then return false end
        end
        return true
    end
    return false
end

local function prelog_steps(ctx, key)
    local e = ctx.model:entry(key)
    if not e or e.rm then return e, {} end
    local pre = {}
    for _, i in ipairs(e.prelog) do pre[i] = true end
    local b = ctx.beliefs and ctx.beliefs[key]
    local states = {}
    for _, si in ipairs(model.candidates(e, model.visible(e, ctx.world))) do
        if pre[si] and (not b or b[si]) then states[#states + 1] = si end
    end
    if #states == 0 and b then
        for si in pairs(b) do if pre[si] then states[#states + 1] = si end end
        table.sort(states)
    end
    return e, model.steps_of(e, states)
end

-- ---------------------------------------------------------------- requirements

local UNCHECKED = {
    { '^m:fame', function(v) return 'Fame ' .. v end },
    { '^m:gil', function(v) return v .. ' gil' end },
    { '^m:skill', function(v) return 'Skill ' .. v end },
    { '^m:levelcap', function(v) return 'Level cap ' .. v end },
    { '^m:hastitle', function() return 'A title' end },
    { '^m:canequip', function() return 'Can equip' end },
    { '^m:inmh', function() return 'Mog house' end },
}

-- A start's unmet requirements: checkable ones hide it; the rest are names for the Needs column.
function R.needs(ctx, reqs)
    local unmet = model.needs(reqs, ctx.world)
    local blocked, labels = false, {}
    for _, u in ipairs(unmet) do
        if u.checked then
            blocked = true
        else
            for _, row in ipairs(UNCHECKED) do
                if u.atom:match(row[1]) then
                    labels[#labels + 1] = row[2](u.val)
                    break
                end
            end
        end
    end
    return blocked, labels
end

local function first_start(ctx, list)
    local best, best_labels
    for pass = 1, 2 do
        for _, st in ipairs(list) do
            local early = st.s.k == 'talk' or st.s.k == 'trade' or st.s.k == 'ki'
            if (pass == 1) == early then
                local blocked, labels = R.needs(ctx, st.n)
                if not blocked then return st, labels end
            end
        end
    end
    return best, best_labels
end

local function switched_off(ctx, st)
    if not R.HIDE_SWITCHED_OFF then return false end
    local sw = ctx.index.meta.switches or {}
    return st.off == 'abyssea' and sw.ENABLE_ABYSSEA == 0
end

-- ---------------------------------------------------------------- the four tabs

function R.active_quests(ctx)
    local groups = {}
    for l = 0, 10 do
        local rows = {}
        for key, c in pairs(ctx.index.c) do
            if c.k == 'q' and c.l == l then
                local st = R.quest_status(ctx, l, c.i)
                local row
                if st == 'active' then
                    row = { key = key, name = c.n, i = c.i }
                    if not c.f then
                        row.next = 'No step data'
                    else
                        local e, idx, info = R.infer(ctx, key)
                        if not e then
                            row.next = 'No step data'
                        else
                            R.fill(row, e, idx, info, ctx, key)
                            row.next = row.next or 'No step known'
                            row.comment = #idx == 1 and e.p[idx[1]].x or nil
                        end
                    end
                elseif st == 'repeat' then
                    row = { key = key, name = c.n, i = c.i, next = 'Repeat' }
                elseif st == 'none' and R.proven(ctx, key) then
                    local e, idx = prelog_steps(ctx, key)
                    row = { key = key, name = c.n, i = c.i, marker = 'Not in log' }
                    if e then
                        row.steps = step_list(e, idx, ctx, key)
                        row.next, row.merged = R.next_text(row.steps, ctx.names)
                    end
                    row.next = row.next or 'No step known'
                end
                if row then rows[#rows + 1] = row end
            end
        end
        table.sort(rows, function(a, b) return a.i < b.i end)
        if #rows > 0 then groups[#groups + 1] = { label = R.AREAS[l], area = l, rows = rows } end
    end
    return groups
end

local function mission_row(ctx, log, sl)
    local c = ctx.index.c[sl.mission or '']
    local row = { key = sl.mission, log = log, storyline = ctx.index.meta.storyline[log] or tostring(log),
        name = c and c.n or '', state = sl.state }
    if sl.state == 'finished' then
        row.next, row.grey = 'Finished', true
    elseif sl.state == 'declined' then
        row.next = 'Declined'
    elseif not c or not c.f then
        row.next = 'No step data'
    else
        local e, idx, info = R.infer(ctx, sl.mission)
        if not e then
            row.next = 'No step data'
        else
            R.fill(row, e, idx, info, ctx, sl.mission)
            row.next = row.next or (c.last and 'Finished' or 'No step known')
            row.comment = #idx == 1 and e.p[idx[1]].x or nil
        end
    end
    return row
end

function R.active_missions(ctx)
    local live, done = {}, {}
    for _, log in ipairs(R.LOGS) do
        local sl = R.storyline(ctx, log)
        if sl.state == 'in_progress' then
            live[#live + 1] = mission_row(ctx, log, sl)
        elseif sl.state == 'finished' then
            done[#done + 1] = mission_row(ctx, log, sl)
        end
    end
    for _, r in ipairs(done) do live[#live + 1] = r end
    if #live == 0 then return {} end
    return { { label = '', rows = live } }
end

local function start_row(ctx, key, c, list)
    local st, labels = first_start(ctx, list)
    if not st then return nil end
    local same = { st.s }
    for _, o in ipairs(list) do
        if o ~= st and o.s.k == st.s.k and o.s.e == st.s.e and o.s.i == st.s.i and not R.needs(ctx, o.n) then
            same[#same + 1] = o.s
        end
    end
    local row = { key = key, name = c.n, i = c.i, steps = same, needs = table.concat(labels, ', ') }
    row.merged = R.merge(same, ctx.names)
    row.starts = row.merged[1] and row.merged[1].text or text.step(st.s, ctx.names)
    if st.v then
        local w = ctx.index.c[st.v]
        row.after = w and w.n or nil
    end
    return row
end

function R.available_quests(ctx)
    local groups = {}
    local sw = ctx.index.meta.switches or {}
    for l = 0, 10 do
        local hide_area = R.HIDE_SWITCHED_OFF and (l == 9 or l == 10) and sw.ENABLE_SOA == 0
        local rows, grey = {}, {}
        if not hide_area then
            for key, c in pairs(ctx.index.c) do
                if c.k == 'q' and c.l == l and c.b ~= 'none' and R.quest_status(ctx, l, c.i) == 'none'
                    and not R.proven(ctx, key) then
                    local list = {}
                    for _, st in ipairs(ctx.model:starts(key)) do
                        if not switched_off(ctx, st) then list[#list + 1] = st end
                    end
                    local all = ctx.starts[key]
                    local had = all and all[1] ~= nil
                    if #list > 0 then
                        local row = start_row(ctx, key, c, list)
                        if row then rows[#rows + 1] = row end
                    elseif not had then
                        grey[#grey + 1] = { key = key, name = c.n, i = c.i, starts = 'Start unknown', grey = true,
                            giver = c.g }
                    end
                end
            end
        end
        table.sort(rows, function(a, b) return a.i < b.i end)
        table.sort(grey, function(a, b) return a.i < b.i end)
        for _, r in ipairs(grey) do rows[#rows + 1] = r end
        if #rows > 0 then groups[#groups + 1] = { label = R.AREAS[l], area = l, rows = rows } end
    end
    return groups
end

-- The next mission of a storyline not started, between missions or declined.
function R.next_mission(ctx, log, sl)
    local ids = {}
    for key, c in pairs(ctx.index.c) do
        if c.k == 'm' and c.l == log and c.f and not mdone(ctx, log, c.i) then ids[#ids + 1] = c.i end
    end
    table.sort(ids)
    if sl.state == 'not_started' or sl.state == 'declined' then
        for _, id in ipairs(ids) do
            local key = 'm' .. log .. ':' .. id
            local own = {}
            for _, st in ipairs(ctx.model:starts(key)) do
                if not st.v then own[#own + 1] = st end
            end
            if #own > 0 then
                local st = first_start(ctx, own)
                if st then return key, own end
                return nil
            end
        end
        return nil
    end
    for _, id in ipairs(ids) do
        local key = 'm' .. log .. ':' .. id
        local list = ctx.model:starts(key)
        if #list > 0 and first_start(ctx, list) then return key, list end
    end
    if log <= 2 and ctx.index.guard and ctx.index.guard[log] then
        for pair in tostring(ctx.index.guard[log]):gmatch('[^,]+') do
            local id, rank = pair:match('^(%d+):(%d+)$')
            id, rank = tonumber(id), tonumber(rank)
            if not mdone(ctx, log, id) and (ctx.world.rank() or 0) >= rank then
                return 'm' .. log .. ':' .. id, nil
            end
        end
    end
    return nil
end

function R.available_missions(ctx)
    local rows = {}
    local sw = ctx.index.meta.switches or {}
    for _, log in ipairs(R.LOGS) do
        local sl = R.storyline(ctx, log)
        local hidden = R.HIDE_SWITCHED_OFF and log == 12 and sw.ENABLE_SOA == 0
        if not hidden and (sl.state == 'not_started' or sl.state == 'between' or sl.state == 'declined') then
            local key, list = R.next_mission(ctx, log, sl)
            local c = key and ctx.index.c[key]
            if c then
                local row
                if list then
                    row = start_row(ctx, key, c, list)
                else
                    row = { key = key, name = c.n, starts = ('Take %s from a gate guard'):format(c.n) }
                end
                if row then
                    row.storyline = ctx.index.meta.storyline[log] or tostring(log)
                    row.log = log
                    rows[#rows + 1] = row
                end
            end
        end
    end
    if #rows == 0 then return {} end
    return { { label = '', rows = rows } }
end

function R.filter(groups, needle)
    needle = tostring(needle or ''):lower()
    if needle == '' then return groups end
    local out = {}
    for _, g in ipairs(groups) do
        local rows = {}
        for _, r in ipairs(g.rows) do
            if tostring(r.name):lower():find(needle, 1, true) then rows[#rows + 1] = r end
        end
        if #rows > 0 then out[#out + 1] = { label = g.label, area = g.area, rows = rows } end
    end
    return out
end

function R.build(ctx)
    return { R.active_quests(ctx), R.active_missions(ctx), R.available_quests(ctx), R.available_missions(ctx) }
end

-- The keys whose parsed entries the window keeps: every row on screen and the selected one.
function R.keys_in(tabs, selected)
    local keep = {}
    for _, groups in ipairs(tabs) do
        for _, g in ipairs(groups) do
            for _, r in ipairs(g.rows) do if r.key and r.steps and not r.starts then keep[r.key] = true end end
        end
    end
    if selected then keep[selected] = true end
    return keep
end

return R
