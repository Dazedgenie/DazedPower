--[[ DazedPower -- the analog charge board, laid out as draw operations plus click regions.
     It makes no draw calls of its own, so the face can be previewed and tested headlessly; DP_Window draws the
     operations and turns a click on a region into the controller action it names.
]]

DazedPower = DazedPower or {}
local Board = {}
DazedPower.BoardLayout = Board

-- The face in base pixels; build() scales everything by S, the ratio of the loaded fonts to the base set.
Board.W, Board.H = 760, 560
Board.TEX = "media/ui/DazedPower/Board/"
Board.SCALES = { 2000, 4000, 8000, 20000, 40000, 80000 }

local C = {
    frame = { 0.235, 0.282, 0.227 }, bar = { 0.212, 0.255, 0.204 }, barText = { 0.925, 0.898, 0.800 },
    board = { 0.906, 0.867, 0.765 }, card = { 0.886, 0.847, 0.749 }, line = { 0.667, 0.620, 0.525 },
    ink = { 0.165, 0.153, 0.133 }, muted = { 0.455, 0.420, 0.361 }, red = { 0.733, 0.169, 0.133 },
    green = { 0.290, 0.560, 0.255 }, amber = { 0.800, 0.540, 0.120 }, dark = { 0.165, 0.165, 0.149 },
    cream = { 0.929, 0.898, 0.816 }, paper = { 0.969, 0.941, 0.882 }, grid = { 0.875, 0.733, 0.710 },
    trace = { 0.169, 0.302, 0.647 }, segOff = { 0.200, 0.196, 0.188 }, segOn = { 0.475, 0.773, 0.420 },
    segLow = { 0.886, 0.643, 0.235 }, white = { 1, 1, 1 },
}
Board.COLORS = C

local COMPRESSOR = { fridge = true, freezer = true, fridgefreezer = true }
local SRC_KIND = { pedal = "IGUI_DazedPower_SrcPedal", windmill = "IGUI_DazedPower_SrcWind", steam = "IGUI_DazedPower_SrcSteam",
    propane = "IGUI_DazedPower_SrcPropane", petrol = "IGUI_DazedPower_SrcPetrol", hydro = "IGUI_DazedPower_SrcHydro",
    car = "IGUI_DazedPower_SrcCar", solar = "IGUI_DazedPower_SrcSolar" }
local GEN_STATE = { running = "IGUI_DazedPower_GenRun", standby = "IGUI_DazedPower_GenStandby", off = "IGUI_DazedPower_GenOff",
    nofuel = "IGUI_DazedPower_GenNoFuel", fault = "IGUI_DazedPower_GenFault", indoors = "IGUI_DazedPower_GenIndoors",
    server = "IGUI_DazedPower_GenServer", cold = "IGUI_DazedPower_GenCold" }
local GEN_BRAND = { propane_makeshift = "IGUI_DazedPower_BrandPropaneMakeshift", propane_salvaged = "IGUI_DazedPower_BrandPropaneSalvaged",
    propane_workshop = "IGUI_DazedPower_BrandPropaneWorkshop", petrol_makeshift = "IGUI_DazedPower_BrandPetrolMakeshift",
    petrol_salvaged = "IGUI_DazedPower_BrandPetrolSalvaged", petrol_workshop = "IGUI_DazedPower_BrandPetrolWorkshop" }

--- "WATER PUMP" as "Water pump"; short words such as TV stay as they are.
function Board.titleCase(str)
    str = tostring(str)
    if #str <= 2 or str:find("%s") == nil and #str <= 3 then return str end
    return string.upper(string.sub(str, 1, 1)) .. string.lower(string.sub(str, 2))
end

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Board.fmtW(w)
    w = w or 0
    if math.abs(w) >= 10000 then return string.format("%.1f kW", w / 1000) end
    return string.format("%d W", math.floor(w + 0.5))
end

function Board.fmtWh(wh)
    wh = wh or 0
    if wh >= 10000 then return string.format("%.1f kWh", wh / 1000) end
    return string.format("%d Wh", math.floor(wh + 0.5))
end

--- The smallest dial range that holds `peak` with a little headroom.
function Board.fullScale(peak)
    for _, v in ipairs(Board.SCALES) do
        if (peak or 0) * 1.1 <= v then return v end
    end
    return Board.SCALES[#Board.SCALES]
end

--- The source rows the board lists: every wired fixture, plus solar, biggest first.
function Board.sources(s)
    local rows = {}
    for _, r in ipairs(type(s.dpmRows) == "table" and s.dpmRows or {}) do rows[#rows + 1] = r end
    local solar = s.solarW
    if solar == nil then
        -- An older controller has no solar figure of its own; solar is what the fixtures don't explain.
        local ours = 0
        for _, r in ipairs(rows) do ours = ours + (r.w or 0) end
        solar = math.max(0, (s.gen or 0) - ours)
    end
    if (solar or 0) >= 1 or #rows == 0 and (s.arrays or 0) > 0 then rows[#rows + 1] = { k = "solar", w = solar or 0, s = "sun" } end
    for i = 1, #rows do rows[i].i = i end
    table.sort(rows, function(a, b)
        if (a.w or 0) ~= (b.w or 0) then return (a.w or 0) > (b.w or 0) end
        return a.i < b.i
    end)
    return rows
end

--- The six lamps along the title bar.
function Board.lamps(s)
    return {
        { lab = "BOOT", lit = s.starting, col = "amber", blink = true },
        { lab = "SOURCE", lit = s.online and (s.gen or 0) > 0, col = "green" },
        { lab = "CHARGE", lit = s.online and s.charging, col = "green" },
        { lab = "LOAD", lit = s.powered and (s.load or 0) > 0, col = "green" },
        { lab = "EQUAL", lit = s.online and s.equalise, col = "amber" },
        { lab = "FAULT", lit = s.trip, col = "red", blink = true },
    }
end

--- Build the face for a snapshot `s`.
--  `o` carries the engine's pieces: S, fontH(name), measure(name, str), getText(key), txt(key, ...), and the window's
--  own state: needles { src, load } (0..1, eased by the window), scales { src, load } (W), genIndex, blink, tier, readOnly.
--  @return { w, h, ops, hits } in screen pixels
function Board.build(s, o)
    local S = o.S or 1
    local ops, hits = {}, {}
    local function fh(f) return o.fontH(f) / S end
    local function mw(f, str) return o.measure(f, tostring(str)) / S end
    local T, TX = o.getText, o.txt

    local function rect(x, y, w, h, c, a) ops[#ops + 1] = { k = "rect", x = x, y = y, w = w, h = h, c = c, a = a or 1 } end
    local function card(x, y, w, h, fill, line, a) ops[#ops + 1] = { k = "card", x = x, y = y, w = w, h = h, c = fill, line = line, a = a or 1 } end
    local function tex(name, x, y, w, h, a, tint) ops[#ops + 1] = { k = "tex", name = Board.TEX .. name, x = x, y = y, w = w, h = h, a = a or 1, c = tint } end
    local function line(x1, y1, x2, y2, th, c, a) ops[#ops + 1] = { k = "line", x = x1, y = y1, x2 = x2, y2 = y2, th = th, c = c, a = a or 1 } end
    local function text(str, x, y, c, font, align, a)
        ops[#ops + 1] = { k = "text", str = tostring(str), x = x, y = y, c = c, font = font or "Small", align = align or "left", a = a or 1 }
    end
    local function hit(x, y, w, h, id) hits[#hits + 1] = { x = x, y = y, w = w, h = h, id = id } end
    local function fit(str, font, w)
        str = tostring(str)
        if mw(font, str) <= w then return str end
        while #str > 1 and mw(font, str .. "..") > w do
            local n = #str
            while n > 1 and string.byte(str, n) >= 128 and string.byte(str, n) < 192 do n = n - 1 end
            str = string.sub(str, 1, n - 1)
        end
        return str .. ".."
    end
    local function wrap(str, font, w)
        local out, cur = {}, ""
        for word in string.gmatch(tostring(str or ""), "%S+") do
            local try = cur == "" and word or (cur .. " " .. word)
            if mw(font, try) > w and cur ~= "" then out[#out + 1] = cur; cur = word else cur = try end
        end
        if cur ~= "" then out[#out + 1] = cur end
        return out
    end
    local function lamp(col, lit, x, y, size, a) tex(lit and ("lamp_" .. col .. ".png") or "lamp_off.png", x, y, size, size, a) end
    local online = s.online == true
    local W, H = Board.W, Board.H

    -- Frame, board and the title bar with its lamps, the clock and the close X.
    rect(0, 0, W, H, C.frame)
    rect(6, 6, W - 12, H - 12, C.board)
    rect(6, 6, W - 12, 34, C.bar)
    local model = T("IGUI_DazedPower_BoardModel_" .. tostring(o.tier or "makeshift"))
    text(TX("IGUI_DazedPower_BoardTitle", model), 18, 23 - fh("Medium") / 2, C.barText, "Medium")
    local hour = (s.env and s.env.hour) or 0
    text(string.format("%02d:%02d", math.floor(hour), math.floor((hour % 1) * 60)), W - 40, 23 - fh("Code") / 2, C.barText, "Code", "right")
    text("X", W - 24, 23 - fh("Small") / 2, C.barText, "Small", "center")
    hit(W - 36, 6, 30, 34, "close")

    -- The two dials: every source in and the load out, on ranges that grow to fit what they have seen.
    local function gauge(x, y, d, f, full, title, red)
        tex("gauge_face.png", x, y, d, d)
        local cx, cy = x + d / 2, y + d / 2
        local ro = d / 2 - 11
        local function at(fr, r)
            local a = math.rad(225 - 270 * fr)
            return cx + r * math.cos(a), cy - r * math.sin(a), a
        end
        if red then
            for i = 0, 15 do
                local x1, y1 = at(red + (1 - red) * i / 16, ro - 3)
                local x2, y2 = at(red + (1 - red) * (i + 1) / 16, ro - 3)
                line(x1, y1, x2, y2, 5, C.red, 0.9)
            end
        end
        for i = 0, 20 do
            local major = i % 5 == 0
            local x1, y1 = at(i / 20, ro)
            local x2, y2 = at(i / 20, ro - (major and 12 or 6))
            line(x1, y1, x2, y2, major and 2.5 or 1.2, C.ink)
            if major then
                local v = full * i / 20 / 1000
                local str = (v == math.floor(v)) and string.format("%d", v) or string.format("%.1f", v)
                local tx, ty = at(i / 20, ro - 24)
                text(str, tx, ty - fh("Small") / 2, C.ink, "Small", "center")
            end
        end
        text(T("IGUI_DazedPower_BoardKw"), cx, cy + d * 0.2, C.muted, "Small", "center")
        text(title, cx, y + d + 2, C.ink, "Medium", "center")
        -- The needle texture points right with its pivot 14 px in, at mid height; it is drawn as a turned quad.
        local _, _, a = at(clamp(f or 0, -0.02, 1.02), 0)
        local k = (ro - 4) / 80
        local dx, dy = math.cos(a), -math.sin(a)
        local px, py = -dy, dx
        local function pt(u, v) return cx + (u * dx + v * px) * k, cy + (u * dy + v * py) * k end
        local q = {}
        for _, uv in ipairs({ { -14, -8 }, { 82, -8 }, { 82, 8 }, { -14, 8 } }) do
            local qx, qy = pt(uv[1], uv[2])
            q[#q + 1] = qx; q[#q + 1] = qy
        end
        ops[#ops + 1] = { k = "quad", name = Board.TEX .. "needle.png", pts = q, a = 1 }
        tex("hub.png", cx - 10, cy - 10, 20, 20)
    end
    local needles, scales = o.needles or {}, o.scales or {}
    gauge(20, 46, 170, online and needles.src or 0, scales.src or 2000, T("IGUI_DazedPower_BoardSourcesIn"))
    gauge(206, 46, 170, online and needles.load or 0, scales.load or 2000, T("IGUI_DazedPower_BoardLoadOut"), 0.85)

    -- NET on number wheels under the dials.
    local function section1()
        local net = s.net or 0
        local str, unit
        if math.abs(net) >= 10000 then str, unit = string.format("%4.1f", math.min(99.9, math.abs(net) / 1000)), "kW"
        else str, unit = string.format("%04d", math.floor(math.abs(net) + 0.5)), "W" end
        if not online then str = "----" end
        local chars = { online and (net < 0 and "-" or "+") or " " }
        for i = 1, #str do chars[#chars + 1] = str:sub(i, i) end
        local ww, gap = 22, 4
        local total = #chars * ww + (#chars - 1) * gap
        local nx = 198 - total / 2 + 14
        text(T("IGUI_DazedPower_BoardNet"), nx - 10, 262 - fh("Medium") / 2, C.ink, "Medium", "right")
        for i, ch in ipairs(chars) do
            local wx = nx + (i - 1) * (ww + gap)
            tex("wheel.png", wx, 246, ww, 32)
            text(ch, wx + ww / 2, 262 - fh("CodeLarge") / 2, C.white, "CodeLarge", "center")
        end
        text(unit, nx + total + 10, 262 - fh("Medium") / 2, C.ink, "Medium")
    end
    section1()

    -- The battery column: ten segments, amber below the floor, with the floor marked in red.
    local function section2()
        local bx, by = 396, 52
        tex("battery_case.png", bx, by, 60, 170)
        local soc, floor = clamp(s.soc or 0, 0, 1), clamp(s.dod or 0.25, 0, 1)
        local ix, iy, iw, ih, n, g = bx + 9, by + 19, 42, 140, 10, 3
        local sh = (ih - (n - 1) * g) / n
        local lit = math.floor(soc * n + 0.5)
        for i = 1, n do
            local sy = iy + ih - i * sh - (i - 1) * g
            local col = C.segOff
            if i <= lit then col = (i / n <= floor + 1e-6) and C.segLow or C.segOn end
            rect(ix, sy, iw, sh, col)
        end
        local fy = iy + ih - ih * floor
        rect(bx - 8, fy - 1, 76, 2, C.red)
        text(string.format("%d%%", math.floor(soc * 100 + 0.5)), bx + 30, by + 176, C.ink, "Medium", "center")
        local wh = (s.capacity or 0) < 10000 and string.format("%d / %d Wh", math.floor((s.charge or 0) + 0.5), math.floor((s.capacity or 0) + 0.5))
            or (Board.fmtWh(s.charge) .. " / " .. Board.fmtWh(s.capacity))
        text(wh, bx + 30, by + 176 + fh("Medium"), C.muted, "Small", "center")
        text(TX("IGUI_DazedPower_BoardFloor", math.floor(floor * 100 + 0.5) .. "%"), bx + 30, by + 176 + fh("Medium") + fh("Small"), C.red, "Small", "center")
    end
    section2()

    -- The bank: one tile per cell with its charge and a lamp, amber for a worn cell.
    local function section3()
        local bx, by, bw = 470, 50, 276
        local cells = type(s.bankCells) == "table" and s.bankCells or {}
        local total = math.max(tonumber(s.cells) or 0, #cells)
        text(TX("IGUI_DazedPower_BoardBank", total), bx, by, C.ink, "Medium")
        local tw, th, g = 63, 32, 6
        if #cells == 0 then
            text(TX("IGUI_DazedPower_BankHeader", s.cells or 0, s.cellCap or 0), bx, by + 32, C.muted, "Small")
        end
        local shown = #cells
        if total > 12 then shown = 11 end
        shown = math.min(shown, 12)
        for i = 1, shown do
            local tx = bx + ((i - 1) % 4) * (tw + g)
            local ty = by + 24 + math.floor((i - 1) / 4) * (th + g)
            card(tx, ty, tw, th, C.card, C.line)
            local worn = type(s.bankWear) == "table" and (s.bankWear[i] or 0) or 0
            lamp(worn >= 10 and "amber" or "green", online, tx + 7, ty + th / 2 - 8, 16)
            text(tostring(cells[i]), tx + tw - 9, ty + th / 2 - fh("CodeMedium") / 2, C.ink, "CodeMedium", "right")
        end
        if total > shown and shown > 0 then
            local i = shown + 1
            local tx = bx + ((i - 1) % 4) * (tw + g)
            local ty = by + 24 + math.floor((i - 1) / 4) * (th + g)
            card(tx, ty, tw, th, C.card, C.line)
            text("+" .. (total - shown), tx + tw / 2, ty + th / 2 - fh("CodeMedium") / 2, C.muted, "CodeMedium", "center")
        end
        local ny = by + 24 + 3 * (th + g)
        if #cells > 0 then text(T("IGUI_DazedPower_BoardCellNote"), bx, ny, C.muted, "NewSmall") end
        local eq = s.equalise and TX("IGUI_DazedPower_BoardEqOn", Board.fmtWh(s.equaliseToday)) or T("IGUI_DazedPower_BoardEqOff")
        text(eq, bx, ny + fh("NewSmall") + 1, s.equalise and C.amber or C.muted, "NewSmall")
        -- The status lamps, each with its name under it.
        local lamps = Board.lamps(s)
        local pitch = bw / #lamps
        local ly = ny + 2 * fh("NewSmall") + 8
        for i, L in ipairs(lamps) do
            local cx = bx + (i - 0.5) * pitch
            lamp(L.col, L.lit and (not L.blink or o.blink), cx - 8, ly, 16)
            text(fit(L.lab, "NewSmall", pitch - 2), cx, ly + 17, L.lit and C.ink or C.muted, "NewSmall", "center")
        end
    end
    section3()

    -- Received today: the hourly history on chart paper, midnight to now.
    local function section4()
        local x, y, w, h = 14, 284, 368, 136
        card(x, y, w, h, C.dark, C.dark)
        text(T("IGUI_DazedPower_ReceivedToday"), x + 12, y + 8, C.cream, "Medium")
        local hist = type(s.dayHist) == "table" and s.dayHist or {}
        local sum, peak = 0, 1
        for i = 1, 24 do
            local v = tonumber(hist[i]) or 0
            sum = sum + v
            if v > peak then peak = v end
        end
        text(Board.fmtWh(sum), x + w - 12, y + 9, C.cream, "Code", "right")
        local px, py, pw, ph = x + 10, y + 32, w - 20, 80
        rect(px, py, pw, ph, C.paper)
        for i = 1, 7 do rect(px + pw * i / 8, py, 1, ph, C.grid) end
        for i = 1, 3 do rect(px, py + ph * i / 4, pw, 1, C.grid) end
        local nowF = clamp(hour / 24, 0, 1)
        local lastX, lastY
        for i = 1, 24 do
            local t = (i - 0.5) / 24
            if t > nowF then break end
            local vx, vy = px + pw * t, py + ph - 3 - (ph - 8) * clamp((tonumber(hist[i]) or 0) / peak, 0, 1)
            if lastX then line(lastX, lastY, vx, vy, 2, C.trace) end
            lastX, lastY = vx, vy
        end
        local mx = px + pw * nowF
        for dy = 0, ph - 3, 6 do rect(mx, py + dy, 1.5, 3, C.red) end
        for i = 0, 8 do
            text(string.format("%02d", i * 3), px + pw * i / 8, py + ph + 4, C.cream, "NewSmall", i == 0 and "left" or (i == 8 and "right" or "center"), 0.85)
        end
    end
    section4()

    -- Sources in: each fixture with its state and watts.
    local function section5()
        local x, y, w, h = 14, 428, 368, 120
        card(x, y, w, h, C.card, C.line)
        text(T("IGUI_DazedPower_BoardSources"), x + 12, y + 8, C.ink, "Medium")
        text(Board.fmtW(s.gen or 0), x + w - 12, y + 9, C.ink, "Code", "right")
        local rows = Board.sources(s)
        local ry, pitch = y + 32, 17
        if #rows == 0 then text(T("IGUI_DazedPower_SrcNone"), x + 12, ry, C.muted, "Small") end
        local fitN = math.floor((y + h - 6 - ry) / pitch)
        local shown = #rows > fitN and fitN - 1 or #rows
        for i = 1, shown do
            local r = rows[i]
            local on = (r.w or 0) > 0
            lamp("green", online and on, x + 12, ry + pitch / 2 - 6, 12)
            local name = T(SRC_KIND[r.k] or "IGUI_DazedPower_SrcSolar")
            if r.t then name = name .. " " .. T("IGUI_DazedPower_SrcTier_" .. r.t) end
            local wStr = Board.fmtW(r.w or 0)
            local right = x + w - 12 - mw("Code", "00.0 kW") - 8
            local sx = x + 190
            name = fit(name, "Small", sx - x - 36)
            text(name, x + 30, ry + pitch / 2 - fh("Small") / 2, on and C.ink or C.muted, "Small")
            local st = T("IGUI_DazedPower_SrcState_" .. tostring(r.s))
            if string.find(st, "IGUI_", 1, true) then st = tostring(r.s or "") end
            text(fit(st, "Small", right - sx), sx, ry + pitch / 2 - fh("Small") / 2, C.muted, "Small")
            text(wStr, x + w - 12, ry + pitch / 2 - fh("Code") / 2, on and C.ink or C.muted, "Code", "right")
            ry = ry + pitch
        end
        if shown < #rows then
            local rest = 0
            for i = shown + 1, #rows do rest = rest + (rows[i].w or 0) end
            text(TX("IGUI_DazedPower_SrcMore", #rows - shown, Board.fmtW(rest)), x + 30, ry + pitch / 2 - fh("Small") / 2, C.muted, "Small")
        end
    end
    section5()

    -- Circuits: every load the controller feeds, and the total.
    local function section6()
        local x, y, w = 394, 284, 182
        text(T("IGUI_DazedPower_BoardCircuits"), x, y + 2, C.ink, "Medium")
        local list = type(s.loadList) == "table" and s.loadList or {}
        local ry, pitch = y + 26, 19
        local starred = false
        local max = 8
        if #list == 0 then text("--", x, ry, C.muted, "Small") ry = ry + pitch end
        for i, e in ipairs(list) do
            if i > max then
                local rest = 0
                for j = i, #list do rest = rest + (list[j].w or 0) end
                text(TX("IGUI_DazedPower_LoadMore", #list - i + 1), x + 18, ry + 2, C.muted, "Small")
                text(Board.fmtW(rest), x + w, ry + 2, C.muted, "Code", "right")
                ry = ry + pitch
                break
            end
            if e.more then
                text(TX("IGUI_DazedPower_LoadMore", e.more), x + 18, ry + 2, C.muted, "Small")
            else
                local lab = T("IGUI_DazedPower_Load_" .. tostring(e.k))
                lab = Board.titleCase(lab)
                if COMPRESSOR[e.k] then lab = lab .. " *"; starred = true end
                lamp("green", online and s.powered and not e.idle, x, ry + pitch / 2 - 6, 12)
                text(fit(lab, "Small", w - 18 - mw("Code", "0000 W") - 6), x + 18, ry + pitch / 2 - fh("Small") / 2, e.idle and C.muted or C.ink, "Small")
            end
            text(Board.fmtW(e.w or 0), x + w, ry + pitch / 2 - fh("Code") / 2, e.idle and C.muted or C.ink, "Code", "right")
            ry = ry + pitch
        end
        ry = math.max(ry, y + 26 + 4 * pitch) + 4
        rect(x, ry, w, 1.5, C.ink)
        local why = (s.lvd and "IGUI_DazedPower_LowBatt") or (s.starting and "IGUI_DazedPower_StartingUp")
            or (not s.powered and "IGUI_DazedPower_Offline") or nil
        text(T("IGUI_DazedPower_Total"), x, ry + 6, C.ink, "Medium")
        text(Board.fmtW(s.demand or 0), x + w, ry + 6, C.ink, "Code", "right")
        local ny = ry + 6 + fh("Medium") + 2
        if why then text(T(why), x, ny, C.red, "NewSmall"); ny = ny + fh("NewSmall") end
        if starred then text(T("IGUI_DazedPower_BoardCompressor"), x, ny, C.muted, "NewSmall") end
    end
    section6()

    -- The main isolator: a big flip switch, up for on; click to throw it.
    local function section7()
        local x, y, w, h = 394, 490, 182, 58
        local inert = s.rigLock ~= nil and s.rigLock ~= false
        local a = inert and 0.4 or 1
        card(x, y, w, h, C.dark, C.dark)
        tex(online and "isolator_on.png" or "isolator_off.png", x + 16, y + 3, 38, 52, a)
        -- Three stacked lines, centred in the card so ON/OFF never runs into the breaker line.
        local ty = y + math.max(2, (h - 2 * fh("NewSmall") - fh("Medium")) / 2)
        text(T("IGUI_DazedPower_Isolator"), x + 64, ty, C.cream, "NewSmall", "left", a)
        ty = ty + fh("NewSmall")
        text(online and T("IGUI_DazedPower_BoardOn") or T("IGUI_DazedPower_BoardOff"), x + 64, ty,
            online and C.segOn or C.segLow, "Medium", "left", a)
        ty = ty + fh("Medium")
        local trip = s.trip and T("IGUI_DazedPower_Tripped") or T("IGUI_DazedPower_BoardNoTrip")
        text(trip, x + 64, ty, s.trip and C.red or C.cream, "NewSmall", "left", (s.trip and not o.blink) and 0.4 or 0.75)
        hit(x, y, w, h, "isolator")
    end
    section7()

    -- The generator: one at a time, its own AUTO and ON switches, the shared Auto and its two levels.
    local function section8()
        local x, y, w, h = 588, 284, 158, 264
        card(x, y, w, h, C.card, C.line)
        local rows = type(s.bkRows) == "table" and s.bkRows or {}
        local n = 0
        for i = 1, 4 do if rows[i] ~= nil then n = i else break end end
        text(T("IGUI_DazedPower_BoardGenerator"), x + 10, y + 8, C.ink, "Medium")
        local live = online and not o.readOnly
        local locked = s.lock ~= nil and s.lock ~= false
        local gi = clamp(o.genIndex or 1, 1, math.max(1, n))
        local cy = y + 8 + fh("Medium") + 2
        local pager = 0
        if n > 1 then
            pager = 52
            local px = x + w - 8 - pager
            text("<", px + 6, cy - 2, C.ink, "Medium", "center")
            text(gi .. "/" .. n, px + pager / 2, cy, C.muted, "Code", "center")
            text(">", px + pager - 6, cy - 2, C.ink, "Medium", "center")
            hit(px - 4, cy - 4, 18, 22, "genPrev")
            hit(px + pager - 14, cy - 4, 18, 22, "genNext")
        end
        if n == 0 then
            for _, l in ipairs(wrap(T("IGUI_DazedPower_GenNone"), "Small", w - 20)) do
                text(l, x + 10, cy, C.ink, "Small")
                cy = cy + fh("Small")
            end
            cy = cy + 6
            for _, l in ipairs(wrap(T("IGUI_DazedPower_GenHowTo"), "NewSmall", w - 20)) do
                if cy + fh("NewSmall") > y + h - 8 then break end
                text(l, x + 10, cy, C.muted, "NewSmall")
                cy = cy + fh("NewSmall") + 1
            end
        else
            local r = rows[gi]
            local rowLocked = type(s.bkLocks) == "table" and s.bkLocks[gi] ~= nil and s.bkLocks[gi] ~= false
            local running = r.s == "running"
            local brand = GEN_BRAND[r.t] and T(GEN_BRAND[r.t]) or string.upper(tostring(r.t or "?"))
            lamp("green", running, x + 10, cy + 1, 12)
            text(fit(brand, "Small", w - 36 - pager), x + 26, cy, C.ink, "Small")
            cy = cy + fh("Small") + 1
            local st = T(GEN_STATE[r.s] or "IGUI_DazedPower_GenOff")
            if running then st = st .. "  " .. Board.fmtW(r.w or 0) end
            if r.far then st = st .. "  " .. T("IGUI_DazedPower_GenFar") end
            if r.mix then st = st .. "  " .. T("IGUI_DazedPower_GenMix") end
            if (r.lost or 0) > 0 then st = st .. "  " .. T("IGUI_DazedPower_GenLost") end
            text(fit(st, "NewSmall", w - 20), x + 10, cy, C.muted, "NewSmall")
            cy = cy + fh("NewSmall") + 4
            -- Three switches: the controller's Auto, this generator's Auto, and on/off (greyed while its Auto has it).
            local sw, shh, sg = 30, 40, 16
            local sx0 = x + (w - 3 * sw - 2 * sg) / 2
            local function switch(i, label, on, greyed, id)
                local sx = sx0 + (i - 1) * (sw + sg)
                local a = greyed and 0.35 or 1
                tex(on and "toggle_up.png" or "toggle_down.png", sx, cy, sw, shh, a)
                text(label, sx + sw / 2, cy + shh + 2, C.ink, "NewSmall", "center", a)
                if live and not greyed then hit(sx - 4, cy, sw + 8, shh + fh("NewSmall") + 2, id) end
            end
            switch(1, T("IGUI_DazedPower_BoardAllAuto"), s.bkAuto == true, locked, "gen:bkMaster")
            switch(2, T("IGUI_DazedPower_GenSwAuto"), r.auto == true, rowLocked or r.noAuto == true, "gen:bkAuto:" .. gi)
            switch(3, T("IGUI_DazedPower_BoardRun"), running, rowLocked or r.auto == true, "gen:bkRun:" .. gi)
            cy = cy + shh + fh("NewSmall") + 5
            -- The two levels on number wheels, each with its - and +.
            local function level(label, value, cmd, atLo, atHi)
                text(label, x + 10, cy, C.ink, "NewSmall")
                cy = cy + fh("NewSmall") + 2
                local str = string.format("%02d", clamp(math.floor(value * 100 + 0.5), 0, 99))
                local wx = x + w / 2 - 24
                for i = 1, 2 do
                    tex("wheel.png", wx + (i - 1) * 21, cy, 19, 24)
                    text(str:sub(i, i), wx + (i - 1) * 21 + 9.5, cy + 12 - fh("CodeMedium") / 2, C.white, "CodeMedium", "center")
                end
                text("%", wx + 44, cy + 12 - fh("Small") / 2, C.ink, "Small")
                local function step(bx, lab, dir, atEnd)
                    local a = (locked or atEnd) and 0.35 or 1
                    card(bx, cy + 2, 22, 20, C.board, C.line, a)
                    text(lab, bx + 11, cy + 12 - fh("Medium") / 2, C.ink, "Medium", "center", a)
                    if live and not locked then hit(bx, cy + 2, 22, 20, "gen:" .. cmd .. ":" .. dir) end
                end
                step(x + 10, "-", -1, atLo)
                step(x + w - 32, "+", 1, atHi)
                cy = cy + 28
            end
            local e = 1e-6
            local start, stop = s.bkStart or 0, s.bkStop or 0
            level(T("IGUI_DazedPower_BoardStartBelow"), s.bkStartShown or start, "bkLevelStart", start <= (s.bkLo or 0) + e, start >= (s.bkHi or 1) - e)
            level(T("IGUI_DazedPower_BoardStopAbove"), stop, "bkLevelStop", stop <= start + 0.10 + e, stop >= 0.95 - e)
            -- Fuel, burn, hours left, condition and today's output.
            local kg = r.u == "kg"
            local hours = r.left or -1
            local left = hours >= 10 and string.format("%d", math.floor(hours + 0.5)) or (hours >= 0 and string.format("%.1f", hours) or "--")
            local info = {
                TX(kg and "IGUI_DazedPower_GenTankKg" or "IGUI_DazedPower_GenTank", string.format("%.1f", r.tank or 0), string.format("%.1f", r.feed or 0)),
                TX(kg and "IGUI_DazedPower_GenBurnKg" or "IGUI_DazedPower_GenBurn", string.format("%.2f", r.burn or 0)) .. "  " .. TX("IGUI_DazedPower_GenLeft", left),
                TX("IGUI_DazedPower_BoardCond", math.floor((r.cond or 0) + 0.5) .. "%") .. "  " .. Board.fmtWh(s.bkWhToday or 0),
            }
            for _, l in ipairs(info) do
                if cy + fh("Code") > y + h - 4 then break end
                text(fit(l, "Code", w - 20), x + 10, cy, C.muted, "Code")
                cy = cy + fh("Code")
            end
        end
    end
    section8()

    -- Scale to the loaded font set.
    if S ~= 1 then
        for _, op in ipairs(ops) do
            for _, f in ipairs({ "x", "y", "w", "h", "x2", "y2", "th" }) do if op[f] then op[f] = op[f] * S end end
            if op.pts then for i = 1, #op.pts do op.pts[i] = op.pts[i] * S end end
        end
        for _, h0 in ipairs(hits) do h0.x, h0.y, h0.w, h0.h = h0.x * S, h0.y * S, h0.w * S, h0.h * S end
    end
    return { w = W * S, h = H * S, ops = ops, hits = hits }
end

return Board
