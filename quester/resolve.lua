-- Names: normalizing, matching typed words against each quest's and mission's variants, and the pick.
local R = {}

R.KEYWORDS = { list = true, go = true, help = true }

function R.norm(s)
    s = tostring(s or ''):lower():gsub("'", ''):gsub('%.', '')
    s = s:gsub('[^%w]+', ' ')
    return (s:gsub('^%s+', ''):gsub('%s+$', ''))
end

function R.words(s)
    local out = {}
    for w in R.norm(s):gmatch('%S+') do out[#out + 1] = w end
    return out
end

-- Each typed word starts a later word of the variant, in order.
function R.match(typed, variant)
    local vw = R.words(variant)
    local j = 1
    for _, w in ipairs(typed) do
        local found = false
        while j <= #vw do
            local v = vw[j]
            j = j + 1
            if v:sub(1, #w) == w then
                found = true
                break
            end
        end
        if not found then return false end
    end
    return #typed > 0
end

local function hits(index, typed, text, keys)
    local out, exact = {}, {}
    for _, key in ipairs(keys) do
        local c = index.c[key]
        for _, v in ipairs(c and c.v or {}) do
            if R.match(typed, v) then
                out[#out + 1] = key
                if v == text then exact[#exact + 1] = key end
                break
            end
        end
    end
    return out, exact
end

-- The keys a text names: those of the preferred set first (active, started before the log); then every known one.
-- Returns the list of hits; one hit, or one exact variant among several, is the answer.
function R.pick(index, text, preferred)
    local typed = R.words(text)
    local norm = R.norm(text)
    if #typed == 0 then return {} end
    local all = {}
    for key in pairs(index.c) do all[#all + 1] = key end
    table.sort(all)
    for _, set in ipairs({ preferred or {}, all }) do
        local h, exact = hits(index, typed, norm, set)
        if #h == 1 then return h end
        if #h > 1 then
            if #exact == 1 then return exact end
            return h
        end
    end
    return {}
end

return R
