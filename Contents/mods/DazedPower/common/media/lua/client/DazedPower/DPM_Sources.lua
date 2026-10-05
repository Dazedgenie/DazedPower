--[[ Dazed Power -- a SOURCE page on the controller's screen.
     It lists every wired power fixture with the watts it delivers, so a player can see
     what is feeding the house. Dazed Power's own window is wrapped, never edited.
]]

require "DazedPower/DP_Window"
require "DazedPower/DP_Parts"

if not (DP_Window and DP_Window.LAYOUT and DP_Window.refresh) then return end

local P = DazedPower.Parts
local L = DP_Window.LAYOUT
local S = DP_Window.SCALE or 1
local function px(v) return math.floor(v * S + 0.5) end

DazedPower.More = DazedPower.More or {}
DazedPower.More.Sources = DazedPower.More.Sources or {}
local X = DazedPower.More.Sources

local KEYS = { "status", "loads", "batt", "day", "gen", "src" }
local LABEL = { src = "IGUI_DazedPower_SrcPage" }
local INK, DIM = { 0.620, 0.890, 0.490 }, { 0.482, 0.494, 0.525 }

local function textW(str, font)
    return getTextManager():MeasureStringX(font, tostring(str))
end

local function fmtW(w)
    if w >= 10000 then return string.format("%.1f kW", w / 1000) end
    return string.format("%d W", math.floor(w + 0.5))
end

--- Shorten `str` with "..." until it fits `w` pixels.
local function fit(str, w, font)
    if textW(str, font) <= w then return str end
    while #str > 1 and textW(str .. "...", font) > w do str = string.sub(str, 1, #str - 1) end
    return str .. "..."
end

--- The rows to draw: the controller's wired fixtures plus Dazed Power's own solar and backup generators.
function X.rows(s)
    local rows, ours = {}, 0
    for _, r in ipairs(s.dpmRows or {}) do
        rows[#rows + 1] = r
        ours = ours + (r.w or 0)
    end
    -- Dazed Power's own total already includes ours, so solar is what is left over.
    local solar = math.max(0, (s.gen or 0) - ours)
    if solar >= 1 then rows[#rows + 1] = { k = "solar", w = solar, s = "sun" } end
    if (s.bkW or 0) >= 1 then rows[#rows + 1] = { k = "backup", w = s.bkW, s = "running" } end
    for i = 1, #rows do rows[i].i = i end
    table.sort(rows, function(a, b)
        if (a.w or 0) ~= (b.w or 0) then return (a.w or 0) > (b.w or 0) end
        return a.i < b.i
    end)
    return rows, (s.gen or 0) + (s.bkW or 0)
end

local KIND = { pedal = "IGUI_DazedPower_SrcPedal", windmill = "IGUI_DazedPower_SrcWind", steam = "IGUI_DazedPower_SrcSteam",
               propane = "IGUI_DazedPower_SrcPropane", petrol = "IGUI_DazedPower_SrcPetrol", hydro = "IGUI_DazedPower_SrcHydro", car = "IGUI_DazedPower_SrcCar",
               solar = "IGUI_DazedPower_SrcSolar", backup = "IGUI_DazedPower_SrcBackup" }

local function stateText(st)
    local txt = getText("IGUI_DazedPower_SrcState_" .. tostring(st))
    if txt == nil or string.find(txt, "IGUI_DazedPower_SrcState_", 1, true) then return tostring(st) end
    return txt
end

--- The small figure after the state: wind speed, or the fuel a gas engine has left.
local function detailText(r)
    if r.v == nil then return nil end
    if r.k == "windmill" then return P.txt("IGUI_DazedPower_SrcMs", string.format("%.1f", r.v)) end
    if r.k == "propane" then return P.txt("IGUI_DazedPower_SrcKg", string.format("%.1f", r.v)) end
    if r.k == "petrol" then return P.txt("IGUI_DazedPower_SrcL", string.format("%.1f", r.v)) end
    return nil
end

local function rowLabel(r)
    local name = getText(KIND[r.k] or "IGUI_DazedPower_SrcSolar")
    if r.t then name = name .. " " .. getText("IGUI_DazedPower_SrcTier_" .. r.t) end
    return name
end

local pageDay0 = DP_Window.pageDay
function DP_Window:pageDay(s, x, y)
    if self.page ~= "src" then return pageDay0(self, s, x, y) end
    local font = UIFont.CodeSmall
    local fh = getTextManager():getFontHeight(font)
    local iw = L.LCD_W - px(28)
    local rows, total = X.rows(s)

    self:drawText(getText("IGUI_DazedPower_SrcHeader"), x, y, INK[1], INK[2], INK[3], 0.85, font)
    self:drawTextRight(P.txt("IGUI_DazedPower_SrcTotal", fmtW(total)), x + iw, y, INK[1], INK[2], INK[3], 1, font)
    y = y + fh + px(4)
    self:drawRect(x, y, iw, px(1), 0.35, INK[1], INK[2], INK[3])
    y = y + px(5)

    if #rows == 0 then
        self:drawText(getText("IGUI_DazedPower_SrcNone"), x, y, INK[1], INK[2], INK[3], 0.9, font)
        return
    end

    local pitch = fh + px(6)
    local bottom = L.MID_Y + L.LCD_H - px(12)
    local fit_n = math.max(1, math.floor((bottom - y) / pitch))
    local shown = (#rows > fit_n) and (fit_n - 1) or #rows
    local wCol = textW("00.0 kW", font)
    local peak = math.max(1, rows[1].w or 1)
    for i = 1, shown do
        local r = rows[i]
        local a = (r.w or 0) > 0 and 1 or 0.55
        local wStr = fmtW(r.w or 0)
        local right = x + iw
        self:drawTextRight(wStr, right, y, INK[1], INK[2], INK[3], a, font)
        local limit = right - wCol - px(6)
        local label = fit(rowLabel(r), limit - x, font)
        self:drawText(label, x, y, INK[1], INK[2], INK[3], a, font)
        local cx = x + textW(label, font) + px(6)
        for _, piece in ipairs({ stateText(r.s), detailText(r) }) do
            if piece and cx + textW(piece, font) <= limit then
                self:drawText(piece, cx, y, INK[1], INK[2], INK[3], 0.65, font)
                cx = cx + textW(piece, font) + px(6)
            end
        end
        local bar = math.floor(iw * (r.w or 0) / peak)
        if bar > 0 then self:drawRect(x, y + fh + px(1), bar, px(2), 0.55, INK[1], INK[2], INK[3]) end
        y = y + pitch
    end
    if shown < #rows then
        local rest = 0
        for i = shown + 1, #rows do rest = rest + (rows[i].w or 0) end
        self:drawText(P.txt("IGUI_DazedPower_SrcMore", #rows - shown, fmtW(rest)), x, y, DIM[1], DIM[2], DIM[3], 1, font)
    end
end

--- Six keys now span the screen where five did; the extra key is ours.
local function keyGeometry()
    local gap = px(8)
    local w = math.floor((L.LCD_W - (#KEYS - 1) * gap) / #KEYS)
    return gap, w
end

local create0 = DP_Window.createChildren
function DP_Window:createChildren()
    create0(self)
    local gap, w = keyGeometry()
    for i, b in ipairs(self.keyBtns or {}) do
        b:setX(L.PAD + (i - 1) * (w + gap))
        b:setWidth(w)
    end
    local i = #KEYS
    local b = ISButton:new(L.PAD + (i - 1) * (w + gap), L.KEYS_Y, w, px(30), "", self, DP_Window.onPageKey)
    b:initialise()
    b:instantiate()
    b.background = false
    b.displayBackground = false
    b.isHighlightedBackgroundVisible = false
    b.backgroundColorMouseOver = { r = 0, g = 0, b = 0, a = 0 }
    b.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    b.textColor = { r = 0, g = 0, b = 0, a = 0 }
    b.pageName = "src"
    self:addChild(b)
    self.keyBtns[i] = b
end

local PAGE_KEY = { status = "IGUI_DazedPower_PgStatus", loads = "IGUI_DazedPower_PgLoads", batt = "IGUI_DazedPower_PgBatt",
                   day = "IGUI_DazedPower_PgDay", gen = "IGUI_DazedPower_PgGen", src = "IGUI_DazedPower_SrcPage" }

function DP_Window:drawKeys(s)
    local page = self.page or "status"
    local gap, w = keyGeometry()
    local font = UIFont.NewSmall
    local fh = getTextManager():getFontHeight(font)
    local h = px(30)
    for i, name in ipairs(KEYS) do
        local kx = L.PAD + (i - 1) * (w + gap)
        local lit = name == page
        local t = getTexture("media/ui/DazedPower/" .. (lit and "key_lit.png" or "key_norm.png"))
        if t then
            self:drawTextureScaled(t, kx, L.KEYS_Y, w, h, 1, 1, 1, 1)
        else
            self:drawRect(kx, L.KEYS_Y, w, h, 1, 0.106, 0.110, 0.122)
        end
        local label = fit(getText(PAGE_KEY[name]), w - px(4), font)
        local c = lit and { 0.784, 0.792, 0.816 } or { 0.482, 0.494, 0.525 }
        self:drawTextCentre(label, kx + w / 2, L.KEYS_Y + math.floor((h - fh) / 2), c[1], c[2], c[3], 1, font)
    end
end

local refresh0 = DP_Window.refresh
function DP_Window:refresh()
    refresh0(self)
    if self.snap and self.object then
        local d = P.data(self.object)
        self.snap.dpmRows = d.dpmRows
    end
end

return X
