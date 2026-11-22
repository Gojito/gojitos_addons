-- The journal: evidence lines, replayed into a belief per quest or mission.
local model = require('model')

local J = {}
J.__index = J

local FIELDS = { FIN = 4, UPD = 3, EV = 3, TALK = 2, TRADE = 3, KILL = 2, KI = 2, Q = 4, M = 2, ZONE = 1, OUT = 1, LOAD = 2 }

function J.format(t, kind, ...)
    local parts = { tostring(t), kind }
    for _, v in ipairs({ ... }) do parts[#parts + 1] = tostring(v) end
    return table.concat(parts, ' ')
end

-- A line back to its fields; nil for a truncated or unknown line. KILL keeps the rest of the line as the name.
function J.parse(line)
    if type(line) ~= 'string' then return nil end
    local t, kind, rest = line:match('^(%d+) (%u+) ?(.*)$')
    if not t or not FIELDS[kind] then return nil end
    local f = {}
    if kind == 'KILL' then
        local z, name = rest:match('^(%d+) (.+)$')
        if not z then return nil end
        f = { z, name }
    else
        for x in rest:gmatch('%S+') do f[#f + 1] = x end
    end
    if #f ~= FIELDS[kind] then return nil end
    return { t = tonumber(t), k = kind, f = f }
end

function J.new(m)
    return setmetatable({ m = m, beliefs = {}, qstat = {}, mcur = {}, bykey = {}, timers = {}, lines = 0 }, J)
end

local function defaults(e)
    local v = {}
    for i, a in ipairs(e.a) do v[i] = a:match('^cm:') and model.NONE or 0 end
    return v
end

function J:not_started(e)
    if e.rm then return { defaults(e) } end
    local i = e.bystr[model.state_string(e, defaults(e))]
    return i and { [i] = true } or {}
end

-- The containers and rules an evidence key touches, parsed once.
function J:touched(key)
    local list = self.bykey[key]
    if list then return list end
    list = {}
    local files = self.m.index.keys[key]
    if files then
        for _, f in ipairs(files) do
            for _, ck in ipairs(self.m:group_keys(f)) do
                local e = self.m:entry(ck)
                local rules = {}
                for _, r in ipairs(e and e.rules or {}) do
                    if r.key == key then rules[#rules + 1] = r end
                end
                if #rules > 0 then list[#list + 1] = { e = e, rules = rules } end
            end
        end
    end
    self.bykey[key] = list
    return list
end

function J:start_belief(e)
    local q = e.c.k == 'q' and self.qstat[e.key]
    if q and q.cur == 0 and q.done == 0 then
        if e.rm then local k = {}; for i, v in ipairs(defaults(e)) do k[i] = v end; return { known = k } end
        return self:not_started(e)
    end
    if e.rm then return { known = {} } end
    local all = {}
    for i in ipairs(e.states) do all[i] = true end
    return all
end

local function seed_known(e)
    local k = {}
    local seeds = e.seeds or {}
    if #seeds == 0 then return { known = k } end
    for i, v in pairs(seeds[1]) do
        local same = true
        for _, sd in ipairs(seeds) do if sd[i] ~= v then same = false end end
        if same then k[i] = v end
    end
    return { known = k }
end
J.seed_known = seed_known

local function consistent(c, known)
    for i, want in pairs(c) do
        local have = known[i]
        if have ~= nil and have ~= 'T' and want ~= 'T' and have ~= want then return false end
    end
    return true
end
J.consistent = consistent

local function learn(known, app)
    local k = {}
    for i, v in pairs(known) do k[i] = v end
    local wr = {}
    for _, r in ipairs(app) do
        for i, v in pairs(r.w) do wr[i] = wr[i] or {}; wr[i][#wr[i] + 1] = v end
    end
    for i, list in pairs(wr) do
        local same = #list == #app
        for _, v in ipairs(list) do if v ~= list[1] then same = false end end
        k[i] = same and list[1] or nil
    end
    for i, v in pairs(app[1].c) do
        if not wr[i] then
            local same = true
            for _, r in ipairs(app) do if r.c[i] ~= v then same = false end end
            if same then k[i] = v end
        end
    end
    return k
end

local function apply_rule(e, vals, r)
    local out = {}
    for i, v in ipairs(vals) do out[i] = v end
    for i, v in pairs(r.w) do out[i] = v end
    return out
end

function J:apply_key(key, opt)
    local touched = self:touched(key)
    local exclusive = #touched == 1
    for _, hit in ipairs(touched) do
        local e = hit.e
        local b = self.beliefs[e.key]
        if b == nil then b = self:start_belief(e) end
        if e.rm then
            b = b or { known = {} }
            local app = {}
            for _, r in ipairs(hit.rules) do
                if (r.o == nil or r.o == opt) and consistent(r.c, b.known) then app[#app + 1] = r end
            end
            if exclusive and #app == 0 then
                for _, r in ipairs(hit.rules) do
                    if r.o == nil or r.o == opt then app[#app + 1] = r end
                end
                b = { known = {} }
            end
            if exclusive and #app > 0 then b = { known = learn(b.known, app) } end
            self.beliefs[e.key] = b
        else
            local function step(src)
                local out, any = {}, false
                for si in pairs(src) do
                    local vals = e.states[si]
                    local matched = false
                    for _, r in ipairs(hit.rules) do
                        if (r.o == nil or r.o == opt) and model.holds(r.c, vals) then
                            matched = true
                            if r.t and self.now then self.timers[e.key] = self.now + r.t end
                            local ni = e.bystr[model.state_string(e, apply_rule(e, vals, r))]
                            if ni then out[ni] = true end
                        end
                    end
                    if matched then any = true elseif not exclusive then out[si] = true end
                end
                return out, any
            end
            local out, any = step(b)
            if exclusive and not any then
                local all = {}
                for i in ipairs(e.states) do all[i] = true end
                out, any = step(all)
            end
            if next(out) == nil then out = b end
            self.beliefs[e.key] = out
        end
    end
end

-- Zoning clears local variables in every belief that holds one.
function J:zone_reset()
    for key, b in pairs(self.beliefs) do
        local e = self.m:entry(key)
        if e and e.rm and b and b.known then
            for i, a in ipairs(e.a) do if a:match('^lv:') then b.known[i] = 0 end end
        end
        if e and not e.rm and b then
            local lv = {}
            for i, a in ipairs(e.a) do if a:match('^lv:') then lv[#lv + 1] = i end end
            if #lv > 0 then
                local out = {}
                for si in pairs(b) do
                    local vals = {}
                    for i, v in ipairs(e.states[si]) do vals[i] = v end
                    for _, i in ipairs(lv) do vals[i] = 0 end
                    local ni = e.bystr[model.state_string(e, vals)]
                    out[ni or si] = true
                end
                self.beliefs[key] = out
            end
        end
    end
end

function J:anchor_quest(key, cur, done)
    local prev = self.qstat[key]
    self.qstat[key] = { cur = cur, done = done }
    local e = self.m:entry(key)
    if not e then return end
    if cur == 1 and done == 0 and (not prev or prev.cur ~= 1) then
        if e.rm then
            self.beliefs[key] = seed_known(e)
        else
            local b = {}
            for _, i in ipairs(e.after) do b[i] = true end
            self.beliefs[key] = b
        end
    elseif done == 1 or (cur == 0 and prev and prev.cur == 1) then
        self.beliefs[key] = nil
    end
end

function J:anchor_mission(log, id)
    local prev = self.mcur[log]
    self.mcur[log] = id
    if prev and prev ~= id then self.beliefs['m' .. log .. ':' .. prev] = nil end
    local key = 'm' .. log .. ':' .. id
    local e = self.m:entry(key)
    if e and prev ~= id then
        if e.rm then
            self.beliefs[key] = seed_known(e)
        else
            local b = {}
            for _, i in ipairs(e.after) do b[i] = true end
            self.beliefs[key] = b
        end
    end
end

-- One parsed line applied to the beliefs.
function J:feed(rec)
    if not rec then return end
    self.lines = self.lines + 1
    self.now = rec.t
    local k, f = rec.k, rec.f
    if k == 'FIN' then
        self:apply_key('F' .. f[1] .. ':' .. f[2], tonumber(f[3]))
    elseif k == 'TALK' or k == 'TRADE' then
        local zt = self.m.index.npcs[tonumber(f[1])]
        local name = zt and zt[tonumber(f[2])]
        if name then self:apply_key((k == 'TALK' and 'T' or 'R') .. f[1] .. ':' .. name) end
    elseif k == 'KILL' then
        self:apply_key('K' .. f[1] .. ':' .. f[2])
    elseif k == 'ZONE' then
        self:zone_reset()
        self:apply_key('Z' .. f[1])
    elseif k == 'OUT' then
        self:apply_key('O' .. f[1])
    elseif k == 'Q' then
        self:anchor_quest('q' .. f[1] .. ':' .. f[2], tonumber(f[3]), tonumber(f[4]))
    elseif k == 'M' then
        self:anchor_mission(tonumber(f[1]), tonumber(f[2]))
    end
end

function J:feed_line(line)
    self:feed(J.parse(line))
end

-- The checkpoint: table hash, journal byte offset, quest status, current missions and every belief.
function J:checkpoint(hash, offset)
    local out = { 'hash ' .. tostring(hash), 'offset ' .. tostring(offset) }
    local keys = {}
    for key in pairs(self.qstat) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        out[#out + 1] = ('q %s %d %d'):format(key, self.qstat[key].cur, self.qstat[key].done)
    end
    local logs = {}
    for log in pairs(self.mcur) do logs[#logs + 1] = log end
    table.sort(logs)
    for _, log in ipairs(logs) do out[#out + 1] = ('m %d %d'):format(log, self.mcur[log]) end
    keys = {}
    for key in pairs(self.timers) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do out[#out + 1] = ('t %s %d'):format(key, self.timers[key]) end
    keys = {}
    for key in pairs(self.beliefs) do keys[#keys + 1] = key end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local b = self.beliefs[key]
        local e = self.m:entry(key)
        if e and e.rm then
            local kv, idx = {}, {}
            for i in pairs(b.known or {}) do idx[#idx + 1] = i end
            table.sort(idx)
            for _, i in ipairs(idx) do kv[#kv + 1] = i .. '=' .. tostring(b.known[i]) end
            if #kv > 0 then out[#out + 1] = 'k ' .. key .. ' ' .. table.concat(kv, ',') end
        elseif e then
            local idx = {}
            for si in pairs(b) do idx[#idx + 1] = si end
            table.sort(idx)
            out[#out + 1] = 's ' .. key .. ' ' .. table.concat(idx, ',')
        end
    end
    return table.concat(out, '\n') .. '\n'
end

-- A checkpoint back into this journal; returns its hash and offset, or nil when it does not parse.
function J:load_checkpoint(text)
    if type(text) ~= 'string' then return nil end
    local hash = text:match('^hash (%S+)\n')
    local offset = tonumber(text:match('\noffset (%d+)\n'))
    if not hash or not offset then return nil end
    self.beliefs, self.qstat, self.mcur, self.timers = {}, {}, {}, {}
    for line in text:gmatch('[^\n]+') do
        local tag, a, b, c = line:match('^(%a) (%S+) ?(%S*) ?(%S*)$')
        if tag == 'q' then
            self.qstat[a] = { cur = tonumber(b), done = tonumber(c) }
        elseif tag == 'm' then
            self.mcur[tonumber(a)] = tonumber(b)
        elseif tag == 't' then
            self.timers[a] = tonumber(b)
        elseif tag == 's' then
            local set = {}
            for x in b:gmatch('%d+') do set[tonumber(x)] = true end
            self.beliefs[a] = set
        elseif tag == 'k' then
            self.beliefs[a] = { known = model.pairs_of(b) }
        end
    end
    return hash, offset
end

return J
