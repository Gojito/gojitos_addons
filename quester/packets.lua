-- Packet parsers. Offsets are zero based from the start of the packet, header included.
local P = {}

function P.u8(data, off)
    return data:byte(off + 1) or 0
end

function P.u16(data, off)
    local a, b = data:byte(off + 1, off + 2)
    return (a or 0) + (b or 0) * 256
end

function P.u32(data, off)
    local a, b, c, d = data:byte(off + 1, off + 4)
    return (a or 0) + (b or 0) * 256 + (c or 0) * 65536 + (d or 0) * 16777216
end

P.QUEST_CUR = { [0x50] = 0, [0x58] = 1, [0x60] = 2, [0x68] = 3, [0x70] = 4, [0x78] = 5, [0x80] = 6, [0x88] = 7,
    [0xE0] = 8, [0xF0] = 9, [0x100] = 10 }
P.QUEST_DONE = { [0x90] = 0, [0x98] = 1, [0xA0] = 2, [0xA8] = 3, [0xB0] = 4, [0xB8] = 5, [0xC0] = 6, [0xC8] = 7,
    [0xE8] = 8, [0xF8] = 9, [0x108] = 10 }
P.AHT_URHGAN = 6

-- Quest q of a log is bit q % 8 of byte q / 8 of the 32 data bytes.
function P.bit(bytes, id)
    local b = bytes:byte(math.floor(id / 8) + 1) or 0
    return math.floor(b / 2 ^ (id % 8)) % 2 == 1
end

-- 0x056: one log. Returns a table: port, and either quest bytes, mission done words or the current missions.
function P.mission(data)
    local port = P.u16(data, 0x24)
    local out = { port = port }
    if P.QUEST_CUR[port] then
        out.qlog, out.cur = P.QUEST_CUR[port], data:sub(5, 36)
        if out.qlog == P.AHT_URHGAN then
            out.cur = data:sub(5, 20) .. string.rep('\0', 16)
            out.m = { [7] = P.u32(data, 0x14), [4] = P.u32(data, 0x18), [5] = P.u32(data, 0x1C), [8] = P.u32(data, 0x20) }
        end
    elseif P.QUEST_DONE[port] then
        out.qlog, out.done = P.QUEST_DONE[port], data:sub(5, 36)
        if out.qlog == P.AHT_URHGAN then
            out.done = data:sub(5, 20) .. string.rep('\0', 16)
        end
    elseif port == 0xD0 then
        out.mdone = {}
        for log = 0, 3 do out.mdone[log] = data:sub(5 + log * 8, 12 + log * 8) end
    elseif port == 0xD8 then
        out.mdone = { [4] = data:sub(5, 12), [5] = data:sub(13, 20) }
    elseif port == 0xFFFF then
        local nation = P.u32(data, 0x04)
        local addons = P.u16(data, 0x18)
        out.nation = nation
        out.m = { [nation] = P.u32(data, 0x08), [3] = P.u32(data, 0x0C), [6] = P.u32(data, 0x10),
            [9] = addons % 16, [10] = math.floor(addons / 16) % 16, [11] = math.floor(addons / 256) % 16 }
        local soa, rov = P.u32(data, 0x1C), P.u32(data, 0x20)
        if soa >= 0x6E then out.m[12] = (soa - 0x6E) / 2 end
        if rov >= 0x6C then out.m[13] = rov - 0x6C end
        out.cop_status = P.u32(data, 0x14)
    end
    return out
end

-- 0x055: one table of 512 key items.
function P.keyitems(data)
    return P.u16(data, 0x84), data:sub(5, 68)
end

-- 0x032, 0x033, 0x034: the NPC (or the player), zone and csid of an event the server starts.
function P.event(id, data)
    if id == 0x032 then
        return P.u32(data, 0x04), P.u16(data, 0x0A), P.u16(data, 0x0C)
    elseif id == 0x034 then
        return P.u32(data, 0x04), P.u16(data, 0x2A), P.u16(data, 0x2C)
    elseif id == 0x033 then
        return P.u32(data, 0x04), P.u16(data, 0x0A), P.u16(data, 0x0C)
    end
end

-- 0x05B out: the event end or update the client sends.
function P.eventend(data)
    return { npc = P.u32(data, 0x04), option = P.u32(data, 0x08), index = P.u16(data, 0x0C), mode = P.u16(data, 0x0E),
        zone = P.u16(data, 0x10), csid = P.u16(data, 0x12) }
end

-- 0x01A out: target and ActionID; 0 is a talk.
function P.action(data)
    return P.u32(data, 0x04), P.u16(data, 0x0A)
end

-- 0x036 out: the NPC traded to, and each slot with its count.
function P.trade(data)
    local out = { npc = P.u32(data, 0x04), count = P.u8(data, 0x3C), slots = {} }
    for i = 0, 9 do
        out.slots[i + 1] = { count = P.u32(data, 0x08 + 4 * i), slot = P.u8(data, 0x30 + i) }
    end
    return out
end

-- 0x029: actor, target, target index, message.
function P.battle(data)
    return P.u32(data, 0x04), P.u32(data, 0x08), P.u16(data, 0x16), P.u16(data, 0x18)
end

function P.zone(data)
    return P.u32(data, 0x30)
end

return P
