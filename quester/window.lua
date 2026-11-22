-- The Quester window: four tabs of built rows and a detail pane. It draws; it never builds rows.
local rows = require('rows')

local window = {}

window.TABS = { 'Active Quests', 'Active Missions', 'Available Quests', 'Available Missions' }
window.EMPTY = { 'No active quests.', 'No active missions.', 'Nothing to start.', 'No mission to take.' }
window.COLUMNS = {
    { 'Quest', 'Next' },
    { 'Storyline', 'Mission', 'Next' },
    { 'Quest', 'Starts', 'Needs' },
    { 'Storyline', 'Mission', 'Starts' },
}
window.GREY = { 0.6, 0.6, 0.6, 1 }
window.AREA = { 0.6, 0.8, 1.0, 1 }
window.TIPS = {
    filter = 'Part of a name.',
    marker = 'Started; the log shows it once accepted.',
    possible = 'Select it to see each step.',
    places = 'Select it to see each place.',
    ['No step known'] = 'The model has no step here.',
    ['No step data'] = "The server's scripts give no step.",
    Repeat = 'Done before; steps follow the first run.',
    Declined = 'You declined its opening scene.',
    ['Start unknown'] = 'No start step in the table.',
    needs = 'Not checked; the client cannot read it.',
    go = 'Routes there with gps.',
    split = 'Drag to resize.',
    go_away = 'Routes once you enter its zone.',
    queued = 'gps routes when you arrive.',
    left = 'Any order; each one is needed.',
    upto = 'Steps done before the journal are unknown.',
}
window.MIN = { 480, 300 }
window.DETAIL, window.DETAIL_MIN, window.LIST_MIN, window.BAR = 140, 80, 100, 6
window.SIZE = { 640, 440 }

function window.tip(imgui, text)
    if text and imgui.IsItemHovered() then imgui.SetTooltip(text) end
end

local function value_tip(v)
    if not v then return nil end
    if v:match('possible$') then return window.TIPS.possible end
    if v:match('places$') then return window.TIPS.places end
    if v:match('^Up to %d+ left$') then return window.TIPS.upto end
    if v:match('^%d+ left$') then return window.TIPS.left end
    return window.TIPS[v]
end

local function cell(imgui, v, grey)
    imgui.TableNextColumn()
    if grey then
        imgui.TextColored(window.GREY, v or '')
    else
        imgui.Text(v or '')
    end
    window.tip(imgui, value_tip(v))
end

local function table_rows(imgui, view, t, group, gi)
    local click
    local cols = window.COLUMNS[t]
    local flags = bit.bor(ImGuiTableFlags_RowBg, ImGuiTableFlags_BordersInnerH, ImGuiTableFlags_SizingFixedFit)
    imgui.PushID(gi)
    if imgui.BeginTable('##rows', #cols, flags) then
        for ci, name in ipairs(cols) do
            imgui.TableSetupColumn(name, ci == 1 and ImGuiTableColumnFlags_WidthStretch or ImGuiTableColumnFlags_WidthFixed, 0, 0)
        end
        imgui.TableHeadersRow()
        for n, r in ipairs(group.rows) do
            imgui.PushID(n)
            imgui.TableNextRow()
            imgui.TableNextColumn()
            local first = (t == 2 or t == 4) and r.storyline or r.name
            local sel = view.selected and view.selected.tab == t and view.selected.key == r.key
            if r.grey then imgui.PushStyleColor(ImGuiCol_Text, window.GREY) end
            if imgui.Selectable(first .. (r.marker and ('  ' .. r.marker) or ''), sel, ImGuiSelectableFlags_SpanAllColumns, { 0, 0 }) then
                click = { select = { tab = t, key = r.key } }
            end
            if r.grey then imgui.PopStyleColor(1) end
            if r.marker then window.tip(imgui, window.TIPS.marker) end
            if t == 2 or t == 4 then cell(imgui, r.name, r.grey) end
            if t == 3 then
                cell(imgui, r.starts, r.grey)
                cell(imgui, r.needs, r.grey)
                if r.needs and r.needs ~= '' then window.tip(imgui, window.TIPS.needs) end
            else
                cell(imgui, t == 4 and r.starts or r.next, r.grey)
            end
            imgui.PopID()
        end
        imgui.EndTable()
    end
    imgui.PopID()
    return click
end

local function find_row(view)
    local s = view.selected
    if not s then return nil end
    for _, g in ipairs(view.tabs[s.tab] or {}) do
        for _, r in ipairs(g.rows) do if r.key == s.key then return r end end
    end
    return nil
end

local function detail(imgui, view)
    local click
    local r = find_row(view)
    if not r then
        imgui.TextColored(window.GREY, 'Select a row.')
        return nil
    end
    imgui.Text(r.storyline and (r.storyline .. ': ' .. r.name) or r.name)
    if r.after then imgui.Text('After ' .. r.after) end
    local n = 0
    local function places(list, grey)
        for _, m in ipairs(list or {}) do
            for _, place in ipairs(m.places or { m }) do
                n = n + 1
                local state = (not grey) and view.go_state and view.go_state(place.s) or nil
                imgui.Bullet()
                imgui.SameLine()
                if grey then imgui.TextColored(window.GREY, place.text) else imgui.Text(place.text) end
                if state == 'queued' then
                    imgui.SameLine()
                    imgui.TextColored(window.GREY, 'Queued')
                    window.tip(imgui, window.TIPS.queued)
                elseif state then
                    imgui.SameLine()
                    if imgui.Button('Go##' .. n) then click = { go = place.s } end
                    window.tip(imgui, state == 'here' and window.TIPS.go or window.TIPS.go_away)
                end
            end
        end
    end
    if r.todo then
        imgui.Text('Any order')
        places(r.todo.pending)
        if #r.todo.final > 0 then
            imgui.Text('Then')
            places(r.todo.final)
        end
        if #r.todo.done > 0 then
            imgui.TextColored(window.GREY, 'Done')
            places(r.todo.done, true)
        end
    else
        places(r.merged)
    end
    if not r.merged or #r.merged == 0 then imgui.Text(r.next or r.starts or '') end
    if r.needs and r.needs ~= '' then imgui.Text('Needs: ' .. r.needs) end
    if r.giver then imgui.Text('Client: ' .. r.giver) end
    if r.comment then
        imgui.PushTextWrapPos(0)
        imgui.TextWrapped(r.comment)
        imgui.PopTextWrapPos()
    end
    return click
end

-- The detail's height: the saved one, clamped to the space this frame has; the saved value is left as it is.
function window.detail_height(view, avail)
    local d = tonumber(view.detail_h) or window.DETAIL
    local most = (avail or 0) - window.LIST_MIN - window.BAR
    if d > most then d = most end
    if d < window.DETAIL_MIN then d = window.DETAIL_MIN end
    return math.floor(d)
end

local function tab_body(imgui, view, t)
    local click
    local groups = rows.filter(view.tabs[t] or {}, view.filter[1])
    local aw, avail = imgui.GetContentRegionAvail()
    if type(aw) == 'table' then aw, avail = aw[1], aw[2] end
    local d = window.detail_height(view, avail)
    imgui.BeginChild('##list', { 0, -(d + window.BAR + imgui.GetFrameHeightWithSpacing()) }, true)
    if #groups == 0 then
        imgui.TextColored(window.GREY, window.EMPTY[t])
    end
    local flat = view.filter[1] ~= ''
    for gi, g in ipairs(groups) do
        if t == 3 and not flat then
            if imgui.CollapsingHeader(('%s (%d)###area%d'):format(g.label, #g.rows, g.area or gi)) then
                click = table_rows(imgui, view, t, g, gi) or click
            end
        else
            if g.label ~= '' and not (t == 3 and flat) then imgui.TextColored(window.AREA, g.label) end
            click = table_rows(imgui, view, t, g, gi) or click
        end
    end
    imgui.EndChild()
    imgui.Separator()
    imgui.InvisibleButton('##split', { aw or 0, window.BAR })
    local hovered, active = imgui.IsItemHovered(), imgui.IsItemActive()
    if hovered or active then pcall(imgui.SetMouseCursor, ImGuiMouseCursor_ResizeNS) end
    window.tip(imgui, hovered and window.TIPS.split or nil)
    local resized
    if active then
        local dx, dy = imgui.GetMouseDragDelta(ImGuiMouseButton_Left)
        if type(dx) == 'table' then dy = dx[2] end
        if dy and dy ~= 0 then
            imgui.ResetMouseDragDelta(ImGuiMouseButton_Left)
            view.detail_h = window.detail_height({ detail_h = d - dy }, avail)
            resized = { resized = view.detail_h }
        end
    end
    imgui.BeginChild('##detail', { 0, 0 }, true)
    click = detail(imgui, view) or click
    imgui.EndChild()
    return click or resized
end

-- One frame. Returns { select = { tab, key } }, { go = cmd }, { close = true }, { resized = height },
-- { moved = { x, y, w, h } } or nil.
function window.draw(imgui, view)
    if not view.open[1] then return { close = true } end
    local click
    if view.place and not view.placed then
        imgui.SetNextWindowPos({ view.place.x, view.place.y }, ImGuiCond_Always)
        imgui.SetNextWindowSize({ view.place.w, view.place.h }, ImGuiCond_Always)
        view.placed = true
    else
        imgui.SetNextWindowSize(window.SIZE, ImGuiCond_FirstUseEver)
    end
    imgui.SetNextWindowSizeConstraints(window.MIN, { FLT_MAX, FLT_MAX })
    if imgui.Begin('Quester', view.open, ImGuiWindowFlags_NoSavedSettings) then
        imgui.InputText('Filter', view.filter, 48)
        window.tip(imgui, window.TIPS.filter)
        if imgui.BeginTabBar('##quester_tabs', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            for t, label in ipairs(window.TABS) do
                if imgui.BeginTabItem(label, nil) then
                    view.tab = t
                    click = tab_body(imgui, view, t) or click
                    imgui.EndTabItem()
                end
            end
            imgui.EndTabBar()
        end
        local x, y = imgui.GetWindowPos()
        local w, h = imgui.GetWindowSize()
        click = click or { moved = { x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h) } }
    end
    imgui.End()
    if not view.open[1] then return { close = true } end
    return click
end

return window
