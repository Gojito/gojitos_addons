-- Step and requirement text. names: zone(id), item(id), keyitem(id), quest(log, id), mission(log, id).
local T = {}

-- A traded item id 0 is no item; the step reads `the items`.
T.DROP_ITEM0 = true

T.JOBS = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG', 'SAM', 'NIN', 'DRG', 'SMN', 'BLU',
    'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' }
T.NATIONS = { [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst' }
T.FAME = { [0] = "San d'Oria", [1] = 'Bastok', [2] = 'Windurst', [3] = 'Jeuno', [4] = 'Selbina and Rabao', [5] = 'Norg',
    [6] = 'Aht Urhgan', [7] = 'Crystal War', [8] = 'Abyssea', [9] = 'Adoulin' }

local function where(s, names)
    local z = s.z and names.zone(s.z) or nil
    return z and (', ' .. z) or ''
end

local function at(s)
    if s.x0 then return (' at (%d, %d)'):format(s.x0, s.z0) end
    return ''
end

function T.items(s, names)
    if not s.i then return 'the items' end
    local out = {}
    for id, n in tostring(s.i):gmatch('(%d+)x?(%d*)') do
        if id ~= '0' or not T.DROP_ITEM0 then
            local name = names.item(tonumber(id)) or ('item ' .. id)
            n = tonumber(n)
            out[#out + 1] = (n and n > 1) and (name .. ' x' .. n) or name
        end
    end
    if #out == 0 then return 'the items' end
    return table.concat(out, ', ')
end

-- The text of one step, without the trailing period.
function T.step(s, names)
    if s.e == '' then
        local c = {}
        for k, v in pairs(s) do c[k] = v end
        c.e = nil
        s = c
    end
    local k = s.k
    local text
    if k == 'zoneonce' then
        text = 'Zone once'
    elseif s.q then
        text = 'Examine the ???' .. at(s) .. where(s, names)
    elseif s.d then
        text = 'Open the door' .. at(s) .. where(s, names)
    elseif k == 'talk' then
        text = 'Talk to ' .. (s.e or 'the NPC') .. where(s, names)
    elseif k == 'ki' then
        text = 'Talk to ' .. (s.e or 'the NPC') .. where(s, names) .. ' (key item)'
    elseif k == 'trade' then
        text = 'Trade ' .. T.items(s, names) .. ' to ' .. (s.e or 'the NPC') .. where(s, names)
    elseif k == 'kill' then
        text = 'Defeat ' .. (s.e or 'the target') .. where(s, names)
    elseif k == 'zone' then
        text = 'Enter ' .. (s.z and names.zone(s.z) or 'the zone')
        if s.pz then text = text .. ' from ' .. (names.zone(s.pz) or tostring(s.pz)) end
    elseif k == 'out' then
        text = 'Leave ' .. (s.z and names.zone(s.z) or 'the zone')
    elseif k == 'area' then
        text = 'Find the scene spot' .. (s.z and (' in ' .. names.zone(s.z)) or '')
    elseif k == 'fight' then
        text = 'Win ' .. (s.bn and tostring(s.bn):gsub('_', ' ') or 'the battlefield') .. (s.e and (' at ' .. s.e) or '')
            .. where(s, names)
    elseif k == 'take' then
        text = 'Take ' .. (s.e or 'the mission') .. ' from a gate guard'
    else
        text = 'Finish the scene' .. (s.z and (' in ' .. names.zone(s.z)) or '')
    end
    if s.w and k ~= 'zoneonce' then
        if s.until_text then
            text = 'Wait until ' .. s.until_text .. ', then ' .. text:sub(1, 1):lower() .. text:sub(2)
        else
            text = 'Wait, then ' .. text:sub(1, 1):lower() .. text:sub(2)
        end
    end
    return text
end

-- One requirement, or nil when it is not printed.
function T.need(r, names)
    local atom, val = r.atom, r.val
    if atom:match('^m:lvl') then return 'level ' .. val end
    if atom:match('^m:job') then return 'job ' .. (T.JOBS[val] or tostring(val)) end
    if atom:match('^m:rankpts') then return 'rank points ' .. val end
    if atom:match('^m:rank') then return 'rank ' .. val end
    if atom:match('^m:nation') then return T.NATIONS[val] or ('nation ' .. val) end
    if atom:match('^m:famepts') then return nil end
    if atom:match('^m:fame') then
        local area = tonumber(atom:match('^m:fame:(%d+)'))
        return ('fame %d%s'):format(val, area and T.FAME[area] and (' (' .. T.FAME[area] .. ')') or '')
    end
    if atom:match('^m:levelcap') then return 'level cap ' .. val end
    if atom:match('^m:skill') then return 'skill ' .. val end
    if atom:match('^m:hastitle') then return 'a title' end
    if atom:match('^m:gil') then return val .. ' gil' end
    local l, i = atom:match('^qs:(%d+):(%d+)$')
    if l then return (names.quest(tonumber(l), tonumber(i)) or 'a quest') .. (val == 2 and ' done' or ' active') end
    l, i = atom:match('^mc:(%d+):(%d+)$')
    if l then return (names.mission(tonumber(l), tonumber(i)) or 'a mission') .. ' done' end
    l = atom:match('^cm:(%d+)$')
    if l then
        if val == 65535 or val == 0 then return nil end
        return (names.mission(tonumber(l), val) or 'a mission') .. ' current'
    end
    local id = atom:match('^ki:(%d+)$')
    if id then return names.keyitem(tonumber(id)) or ('key item ' .. id) end
    id = atom:match('^it:(%d+)$') or atom:match('^trade:(%d+)')
    if id then return names.item(tonumber(id)) or ('item ' .. id) end
    return nil
end

function T.needs(list, names)
    local out = {}
    for _, r in ipairs(list) do
        local t = T.need(r, names)
        if t then out[#out + 1] = t end
    end
    if #out == 0 then return nil end
    return 'Needs: ' .. table.concat(out, ', ') .. '.'
end

return T
