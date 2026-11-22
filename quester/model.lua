-- The step table: entries parsed on first use, the visible part of the world, candidates and steps.
local M = {}
M.__index = M

M.NONE = 65535

local function split(s, sep)
    local out = {}
    if s == nil or s == '' then return out end
    for part in (s .. sep):gmatch('(.-)' .. sep:gsub('%p', '%%%0')) do out[#out + 1] = part end
    return out
end
M.split = split

local function num(v)
    if v == 'T' then return 'T' end
    return tonumber(v)
end

local function pairs_of(s)
    local out = {}
    for _, kv in ipairs(split(s, ',')) do
        local k, v = kv:match('^(%d+)=(.+)$')
        if k then out[tonumber(k)] = num(v) end
    end
    return out
end
M.pairs_of = pairs_of

-- loader(name) returns a group file's table.
-- starts: data/starts.lua. loader(name) returns a group file's table; unload(name) lets it go.
function M.new(index, loader, starts, unload)
    return setmetatable({ index = index, loader = loader, unload = unload, starts_of = starts or {}, groups = {},
        parsed = {}, keys = {} }, M)
end

function M:group(name)
    local g = self.groups[name]
    if g == nil then
        g = self.loader(name) or false
        self.groups[name] = g
        if g and not self.keys[name] then
            local ks = {}
            for k in pairs(g) do ks[#ks + 1] = k end
            table.sort(ks)
            self.keys[name] = ks
        end
    end
    return g or nil
end

function M:group_keys(name)
    if not self.keys[name] then self:group(name) end
    return self.keys[name] or {}
end

-- The starts of a key, from starts.lua: each the step record with its requirement list.
function M:starts(key)
    local out = {}
    for _, rec in ipairs(self.starts_of[key] or {}) do
        out[#out + 1] = { s = rec, n = rec.n or {}, v = rec.v, off = rec.off }
    end
    return out
end

-- Keep the parsed entries in keep, drop the rest, and let every raw group table go.
function M:release(keep)
    for key in pairs(self.parsed) do
        if not (keep and keep[key]) then self.parsed[key] = nil end
    end
    for name in pairs(self.groups) do
        self.groups[name] = nil
        if self.unload then self.unload(name) end
    end
end

function M:entry(key)
    local e = self.parsed[key]
    if e ~= nil then return e or nil end
    local c = self.index.c[key]
    local raw = c and c.f and self:group(c.f)
    raw = raw and raw[key]
    if not raw then
        self.parsed[key] = false
        return nil
    end
    e = { key = key, c = c, a = raw.a, nv = raw.nv, p = raw.p, rm = raw.rm == 1, last = raw.last == 1 }
    e.own = c.k == 'q' and ('qs:' .. c.l .. ':' .. c.i) or ('cm:' .. c.l)
    for i, a in ipairs(e.a) do if a == e.own then e.owni = i end end
    e.rules = {}
    for _, r in ipairs(split(raw.r, ';')) do
        local f = split(r, '|')
        e.rules[#e.rules + 1] = { key = f[1], c = pairs_of(f[2]), w = pairs_of(f[3]), p = tonumber(f[4]),
            o = f[5] ~= '' and tonumber(f[5]) or nil, t = tonumber(f[6] or '') }
    end
    e.starts = self:starts(key)
    if e.rm then
        e.seeds = {}
        for _, s in ipairs(split(raw.sd, ';')) do e.seeds[#e.seeds + 1] = pairs_of(s) end
    else
        e.states, e.vis, e.steps, e.bystr = {}, {}, {}, {}
        local ts = split(raw.t, ';')
        for i, s in ipairs(split(raw.s, ';')) do
            local v, h = s:match('^(.-)|(.*)$')
            local vals = {}
            for _, x in ipairs(split(v, ',')) do vals[#vals + 1] = num(x) end
            for _, x in ipairs(split(h, ',')) do vals[#vals + 1] = num(x) end
            e.states[i], e.vis[i], e.bystr[s] = vals, v, i
            local st = {}
            for _, x in ipairs(split(ts[i] or '', ',')) do st[#st + 1] = tonumber(x) end
            e.steps[i] = st
        end
        e.prelog, e.after = {}, {}
        for _, x in ipairs(split(raw.pl, ',')) do e.prelog[#e.prelog + 1] = tonumber(x) end
        for _, x in ipairs(split(raw.as, ',')) do e.after[#e.after + 1] = tonumber(x) end
    end
    self.parsed[key] = e
    return e
end

-- The value of one visible atom, from the world the addon reads.
function M.read(atom, w)
    local p, a, b = atom:match('^(%a+):([^:]+):?(.*)$')
    if p == 'qs' then return w.quest(tonumber(a), tonumber(b)) end
    if p == 'cm' then return w.mission(tonumber(a)) end
    if p == 'mc' then return w.mission_done(tonumber(a), tonumber(b)) and 1 or 0 end
    if p == 'ki' then return w.ki(tonumber(a)) and 1 or 0 end
    if p == 'it' then return w.item(tonumber(a)) and 1 or 0 end
    if p == 'ms' then
        local st = w.cop_status() or 0
        if b ~= '' then return math.floor(st / 16 ^ tonumber(b)) % 16 end
        return st
    end
    return 0
end

function M.visible(e, w)
    local v = {}
    for i = 1, e.nv do v[i] = M.read(e.a[i], w) end
    return v
end

function M.state_string(e, vals)
    local v, h = {}, {}
    for i = 1, #e.a do
        local x = vals[i]
        if x == nil then x = 0 end
        if x == true then x = 1 elseif x == false then x = 0 end
        if i <= e.nv then v[#v + 1] = tostring(x) else h[#h + 1] = tostring(x) end
    end
    return table.concat(v, ',') .. '|' .. table.concat(h, ',')
end

local function holds(cond, vals, upto)
    for i, want in pairs(cond) do
        if not upto or i <= upto then
            local have = vals[i]
            if have == nil then have = 0 end
            if have ~= 'T' and have ~= want then return false end
        end
    end
    return true
end
M.holds = holds

-- State mode: the stored states whose visible part equals V. Rule mode: the rules whose visible conditions hold.
function M.candidates(e, V)
    local vs = {}
    for i = 1, e.nv do vs[i] = tostring(V[i]) end
    local key = table.concat(vs, ',')
    local out = {}
    if e.rm then
        for ri, r in ipairs(e.rules) do
            if holds(r.c, V, e.nv) then out[#out + 1] = ri end
        end
        return out
    end
    for i, v in ipairs(e.vis) do
        if v == key then out[#out + 1] = i end
    end
    return out
end

-- States whose own status matches V's, for the fallback when nothing matches exactly.
function M.approx(e, V)
    local out = {}
    if e.rm or not e.owni or e.owni > e.nv then return out end
    for i, s in ipairs(e.states) do
        if s[e.owni] == V[e.owni] then out[#out + 1] = i end
    end
    return out
end

function M.steps_of(e, states)
    local set, out = {}, {}
    for _, si in ipairs(states) do
        for _, p in ipairs(e.steps[si] or {}) do set[p] = true end
    end
    for p in pairs(set) do out[#out + 1] = p end
    table.sort(out)
    return out
end

function M.rule_steps(e, rules)
    local set, out = {}, {}
    for _, ri in ipairs(rules) do set[e.rules[ri].p] = true end
    for p in pairs(set) do out[#out + 1] = p end
    table.sort(out)
    return out
end

-- Requirements of a start rule, split into met and unmet by what the addon can check; fame is never checkable.
function M.needs(reqs, w)
    local out = {}
    for _, r in ipairs(reqs) do
        local atom, op, val = r:match('^(.-)([>=]=?)(%-?%d+)$')
        val = tonumber(val)
        local met
        if atom then
            local p = atom:match('^(%a+)')
            if atom:match('^m:lvl') then met = (w.level() or 0) >= val
            elseif atom:match('^m:job') then met = w.job() == val
            elseif atom:match('^m:rankpts') then met = (w.rank_points() or 0) >= val
            elseif atom:match('^m:rank') then met = op == '>=' and (w.rank() or 0) >= val or w.rank() == val
            elseif atom:match('^m:nation') then met = w.nation() == val
            elseif p == 'qs' or p == 'cm' or p == 'mc' or p == 'ki' or p == 'it' then
                local have = M.read(atom, w)
                met = op == '>=' and have >= val or have == val
            elseif p == 'trade' then
                met = true
                for id in atom:sub(7):gmatch('(%d+)') do
                    if not w.item(tonumber(id)) then met = false end
                    break
                end
            end
            if not met then out[#out + 1] = { atom = atom, op = op, val = val, checked = met == false } end
        end
    end
    return out
end

return M
