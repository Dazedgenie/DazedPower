--[[ DazedPower -- the controller's window: the analog charge board.

     Two dials (every source in, the load out), NET on number wheels, the battery column with its floor, the bank's
     cells, today's history on chart paper, the sources and circuits lists, the main isolator and the generator's
     switches, all on one face (DP_BoardLayout lays it out). There is no vanilla title bar: the board is the chrome,
     dragging comes from ISPanel.moveWithMouse and closing is the drawn X. Clicks land on the layout's regions.
]]

require "ISUI/ISPanel"
require "DazedPower/DP_Parts"
require "DazedPower/DP_Env"
require "DazedPower/DP_BoardLayout"

DazedPower = DazedPower or {}
local P = DazedPower.Parts
local M = DazedPower.Model
local E = DazedPower.Env
local Board = DazedPower.BoardLayout

DP_Window = ISPanel:derive("DP_Window")
DazedPower.Window = DazedPower.Window or {}

-- The game has no UI scale: Options > Font Size loads a bigger font set, so the face grows by the same ratio.
local S = math.max(1, getTextManager():getFontHeight(UIFont.CodeSmall) / 16)
local function px(v) return math.floor(v * S + 0.5) end   -- a base-size pixel count at this font scale
local W, H = math.floor(Board.W * S + 0.5), math.floor(Board.H * S + 0.5)
local GEN_ROWS = 4

DP_Window.SCALE = S
DP_Window.LAYOUT = { W = W, H = H }

local FONTS = { Small = UIFont.Small, Medium = UIFont.Medium, Large = UIFont.Large, Code = UIFont.Code,
    CodeSmall = UIFont.CodeSmall, CodeMedium = UIFont.CodeMedium, CodeLarge = UIFont.CodeLarge, NewSmall = UIFont.NewSmall }
local function font(name) return FONTS[name] or UIFont.Small end
local function fontH(name) return getTextManager():getFontHeight(font(name)) end
local function measure(name, str)
    local tm = getTextManager()
    local ok, w = pcall(tm.MeasureStringX, tm, font(name), tostring(str))
    if ok and type(w) == "number" then return w end
    return #tostring(str) * math.floor(fontH(name) * 0.6)
end

local TEXCACHE = {}
local function tex(name)
    local t = TEXCACHE[name]
    if t == nil then
        t = getTexture(name) or false
        TEXCACHE[name] = t
    end
    return t or nil
end

----------------------------------------------------------------- lifecycle

function DP_Window:createChildren()
end

function DP_Window:onClose()
    self:close()
end

function DP_Window:close()
    self:removeFromUIManager()
    DazedPower.Window.current = nil
end

--- Why this player may not throw the main isolator, or nil: the
--  controller's pick-up lock (2026-09-29: "Lock them in 3.0.0"),
--  DP_Place's G.useRefusal, the question DP_ResetBreaker's completion asks
--  again on the authority. Nil where DP_Place is not loaded. Reading the
--  panel asks nothing.
function DP_Window:rigLock(playerObj)
    local G = DazedPower.Place
    if not (playerObj and self.object and G and G.useRefusal) then return nil end
    return G.useRefusal(playerObj, P.try(self.object, "getSquare"), self.object)
end

--- The knob. For a player the controller's lock refuses it is drawn greyed
--  (drawColumn) and does nothing but put the reason above him in the
--  warning colour: he is not walked over to be refused.
function DP_Window:onPowerToggle()
    local playerObj = getSpecificPlayer(0)
    if not playerObj or not self.object then return end
    if self.readOnly then
        P.haloNote(playerObj, getText("IGUI_DazedPower_GaugeReadOnly"), true)
        return
    end
    local why = self:rigLock(playerObj)
    if why then
        P.haloNote(playerObj, getText(why), true)
        return
    end
    local on = not (self.snap and self.snap.online)
    if DazedPower.Context and DazedPower.Context.onBreaker then
        DazedPower.Context.onBreaker(nil, self.object, playerObj, on)
    end
end

-- A switch press in flight. A switch asks for the opposite of what it
-- shows, and what it shows is the controller's copy, pushed by the server;
-- a second press before that copy shows the first one's result would ask
-- for the same thing again, or, on a picture half caught up, the reverse
-- (live campaign on 42.21, 2026-09-28: a press meant as a start came out as
-- a stop). So a switch whose press is in flight takes no second one. It is
-- in flight until GEN shows what it asked for, and at most GEN_HOLD_MS
-- real milliseconds after the short action carrying it left the player's
-- queue: long enough for the server's push to arrive, short enough that a
-- press the server refused (Start on an empty tank, a walk cancelled) does
-- not hold the switch for long. The level boxes are steps, every press
-- meant, and are never held.
DP_Window.GEN_HOLD_MS = 3000
local GEN_SWITCH = { bkMaster = true, bkAuto = true, bkRun = true }

local function nowMs()
    return getTimestampMs and getTimestampMs() or 0
end

--- Whose GEN controls these are (2026-09-29: "Owner's group only").
--  The master AUTO and Start at / Stop at are the controller's; a
--  generator's AUTO and ON/OFF are its own when it stands in memory here,
--  else its controller's, as the authority asks them (BK.unlocked). The
--  reason comes from DP_Place's lock, or nil.
local function unitAt(r)
    if type(r) ~= "table" or not getSquare then return nil end
    local x, y, z = tonumber(r.x), tonumber(r.y), tonumber(r.z)
    if not (x and y and z) then return nil end
    return P.objectAt(x, y, z, r.kind == "petrol" and "petrol" or "propane")
end

--- Why the owner's lock refuses this player a GEN control, or nil: the generator's own when it is
--  loaded here, else the controller's (DP_Place's G.useRefusal, asked again on the authority).
function DP_Window:genLock(playerObj, row)
    local G = DazedPower.Place
    if not (playerObj and self.object and G and G.useRefusal) then return nil end
    local obj = (row and unitAt(row)) or self.object
    return G.useRefusal(playerObj, P.try(obj, "getSquare"), obj)
end

--- Does the snapshot show what a press in flight asked for? A generator
--  gone from the page has nothing left to hold.
local function genShows(p, s)
    if p.cmd == "bkMaster" then return s.bkAuto == p.want end
    local rows = s.bkRows
    if type(rows) ~= "table" then return true end
    for i = 1, GEN_ROWS do
        local r = rows[i]
        if r == nil then break end
        if type(r) == "table" and r.k == p.k then
            if p.cmd == "bkAuto" then return (r.auto == true) == p.want end
            return (r.s == "running") == p.want
        end
    end
    return true
end

--- Bring the presses in flight up to date with the snapshot: one GEN now
--  shows is done; one whose action is still queued is restamped, so its
--  hold counts from when the action left the queue; one past its hold is
--  let go. Called on every refresh and before a press is judged.
function DP_Window:genTrack()
    local held = self.genHeld
    local s = self.snap
    if not held or not s then return end
    local now = nowMs()
    local Q = ISTimedActionQueue
    local done = {}
    for key, p in pairs(held) do
        if genShows(p, s) then
            done[#done + 1] = key
        elseif p.act ~= nil and Q and Q.hasAction and Q.hasAction(p.act) then
            p.seen = now
        elseif now - p.seen >= DP_Window.GEN_HOLD_MS then
            done[#done + 1] = key
        end
    end
    for i = 1, #done do held[done[i]] = nil end
end

--- A GEN button: a switch asks for the state opposite the one it shows (the
--  master and a row's AUTO flip that Auto, ON/OFF starts a stopped
--  generator and stops a running one), a level box steps its level. Sent
--  the way the menu sends it (C.onGenPanel walks the player over and
--  queues a short action at the controller whose completion sends it), as
--  the knob goes through onBreaker. An ON/OFF switch drawn greyed, its
--  generator's own AUTO on, sends nothing: the server would refuse it
--  (K.handRefusal), so the player is not walked over for a no. Nor does a
--  switch whose last press is still in flight (genTrack). Nor does any
--  button the owner's lock refuses this player (genLock, asked now, before
--  anything else as the authority asks it): it is drawn greyed, and a press
--  puts the reason above him in the warning colour instead.
function DP_Window:onGenButton(button)
    local playerObj = getSpecificPlayer(0)
    local s = self.snap
    local C = DazedPower.Context
    if not playerObj or not self.object or not s or not s.online
            or not (C and C.onGenPanel) then
        return
    end
    local cmd, row, value = button.genCmd, nil, nil
    if button.genRow then
        row = type(s.bkRows) == "table" and s.bkRows[button.genRow] or nil
        if not row then return end
    end
    local why = self:genLock(playerObj, row)
    if why then
        P.haloNote(playerObj, getText(why), true)
        return
    end
    if cmd == "bkMaster" then value = not s.bkAuto
    elseif cmd == "bkLevelStart" or cmd == "bkLevelStop" then value = button.genDir
    elseif cmd == "bkAuto" then value = not row.auto
    elseif cmd == "bkRun" then
        if row.auto == true then return end        -- greyed (genRow)
        value = row.s ~= "running"
    else return end
    local key = nil
    if GEN_SWITCH[cmd] then
        key = cmd .. "|" .. tostring(row and row.k or "")
        self:genTrack()
        if self.genHeld and self.genHeld[key] then return end
    end
    local act = C.onGenPanel(playerObj, self.object, cmd,
                             { gx = row and row.x, gy = row and row.y, gz = row and row.z,
                               kind = row and row.kind, value = value })
    if key then
        self.genHeld = self.genHeld or {}
        self.genHeld[key] = { cmd = cmd, k = row and row.k, want = value, act = act,
                              seen = nowMs() }
    end
end

--- Turn a click on one of the board's regions into its action.
function DP_Window:onHit(id)
    if id == "close" then return self:onClose() end
    if id == "isolator" then return self:onPowerToggle() end
    if id == "genPrev" or id == "genNext" then
        local rows = self.snap and self.snap.bkRows
        local n = 0
        if type(rows) == "table" then for i = 1, GEN_ROWS do if rows[i] ~= nil then n = i else break end end end
        if n > 0 then self.genIndex = ((self.genIndex or 1) - 1 + (id == "genNext" and 1 or -1)) % n + 1 end
        return
    end
    local cmd, arg = id:match("^gen:(%w+):?(%-?%d*)$")
    if not cmd then return end
    local button = { genCmd = cmd }
    if cmd == "bkLevelStart" or cmd == "bkLevelStop" then button.genDir = tonumber(arg)
    elseif cmd == "bkAuto" or cmd == "bkRun" then button.genRow = tonumber(arg) end
    self:onGenButton(button)
end

function DP_Window:hitAt(x, y)
    local hits = self.model and self.model.hits or {}
    for i = #hits, 1, -1 do
        local h = hits[i]
        if x >= h.x and x < h.x + h.w and y >= h.y and y < h.y + h.h then return h end
    end
    return nil
end

-- The board drags by its body, so a press counts as a click only when the mouse hardly moved.
function DP_Window:onMouseDown(x, y)
    self.pressAt = { getMouseX(), getMouseY() }
    return ISPanel.onMouseDown(self, x, y)
end

function DP_Window:onMouseUp(x, y)
    local press = self.pressAt
    self.pressAt = nil
    ISPanel.onMouseUp(self, x, y)
    if press and math.abs(getMouseX() - press[1]) + math.abs(getMouseY() - press[2]) <= 4 then
        local h = self:hitAt(x, y)
        if h then self:onHit(h.id) end
    end
    return true
end

function DP_Window:update()
    ISPanel.update(self)
    if not self.object or self.object:getObjectIndex() == -1 then
        self:close()
        return
    end
    self.tick = (self.tick or 0) + 1
    if self.tick % 6 == 0 or not self.snap then
        self:refresh()
    end
end

--- Pull the live numbers off the controller's ModData.
--  Everything the pages draw is read here, ONCE per beat, never mid-draw.
function DP_Window:refresh()
    local d = P.data(self.object)
    local env = E.read()
    local snap = {
        online = d.online and not d.trip,
        powered = d.powered == true,
        trip = d.trip or false,
        lvd = d.lvd == true,
        -- Only a shed the bank really ran into is stamped. A rig with no
        -- cells is shed too, but it comes back the moment cells go in, so
        -- promising "back at 25%" there was simply untrue.
        lvdAt = d.lvdAt,
        lvdSoc = d.lvdSoc or M.lvdThreshold(d.dod),
        gen = d.gen or 0,
        load = d.load or 0,
        demand = d.demand or 0,
        soc = d.soc or 0,
        charge = d.charge or 0,
        capacity = d.capacity or 0,
        health = d.health or 1,
        equalise = d.equalise or false,
        equaliseToday = d.equaliseToday or 0,
        cells = d.cells or 0,
        cellCap = d.cellCap or 0,
        -- The floor on the gauge's own scale, which the controller writes
        -- every tick: the grade's floor from 15 C up, higher in the cold,
        -- where the load really drops (DP_Model.step). A controller that has
        -- not ticked under this build yet has only its grade's floor.
        dod = d.floorSoc or d.dod or M.DAMAGE_SOC,
        coldWatts = d.coldWatts or 0,
        coldHours = d.coldHours or 0,
        coldSafe = d.coldSafe ~= false,
        loadList = d.loadList,
        bankCells = d.bankCells,
        bankWear = d.bankWear,
        dayHist = d.dayHist,
        env = env,
        -- The gas generators, from the controller's mirror under bk* (DP_GenPanel)
        -- names; d.gen is every source together, the gas engines included.
        bkW = d.bkW or 0,
        bkCap = d.bkCap or 0,
        bkN = d.bkN or 0,
        bkRows = d.bkRows,
        bkAuto = d.bkAuto ~= false,
        bkWhToday = d.bkWhToday or 0,
        bkFuelL = d.bkFuelL or 0,
        bkFuelKg = d.bkFuelKg or 0,
        bkMore = d.bkMore or 0,
        -- The SOURCES IN list: every wired fixture (Dazed Power More's bridge) and the arrays' own share.
        dpmRows = d.dpmRows,
        solarW = d.solarW,
    }
    -- The levels as the server last clamped them. Before it has written any
    -- (nothing cabled yet) the model gives the same answer from the same
    -- fields, and it gives the ends of both ranges for GEN's - and +.
    local lvStart, lvStop, lvEff, lvLo, lvHi = M.backupLevels(d.dod or M.DAMAGE_SOC,
                                                              d.floorSoc, d.bkStart, d.bkStop)
    snap.bkStart = d.bkStartNow or lvStart
    snap.bkStop = d.bkStopNow or lvStop
    snap.bkLo, snap.bkHi = lvLo, lvHi
    -- Can chose to see where Auto really starts (2026-09-29, "Approved, show
    -- real start"): M.backupLevels' eff, never under 5 points above the
    -- cut-off, which rises in the cold. The - and + still step (and dim
    -- against) the level he set, snap.bkStart.
    snap.bkStartShown = math.max(snap.bkStart, lvEff)
    -- What the house nets: every source in (the controller's d.gen already counts the gas engines), the load out.
    snap.net = snap.gen - snap.load
    -- Charging is the model's own rule: a surplus, and room in the bank for
    -- it. A full bank clips its surplus and charges nothing.
    snap.charging = snap.net > 0 and (snap.capacity - snap.charge) > 0.01
    -- The tick's own want-predicate (holdPower), so STARTING UP is only ever
    -- promised when the system can actually deliver a start. A running
    -- rig with no cells never starts, whatever is running (holdPower).
    snap.starting = snap.online and not snap.powered and not snap.lvd
        and snap.cells > 0 and (snap.gen > 0 or snap.charge > 0)
    -- How many of its generators GEN shows RUNNING: STATUS reads GEN RUNNING
    -- while any does, whatever it delivers.
    snap.bkRunning = 0
    -- Which of GEN's controls the owner's lock refuses this player (genLock):
    -- the controller's (lock), and each generator's (bkLocks[i]). Drawn
    -- greyed; asked again at a press.
    local who = getSpecificPlayer and getSpecificPlayer(0)
    -- and whether the controller's lock refuses him the main isolator
    -- (rigLock; 2026-09-29: "Lock them in 3.0.0"), drawn greyed
    snap.rigLock = self:rigLock(who) or false
    snap.lock = self:genLock(who, nil) or false
    snap.bkLocks = {}
    if type(snap.bkRows) == "table" then
        for i = 1, GEN_ROWS do
            local r = snap.bkRows[i]
            if r == nil then break end
            if type(r) == "table" and r.s == "running" then
                snap.bkRunning = snap.bkRunning + 1
            end
            if type(r) == "table" then snap.bkLocks[i] = self:genLock(who, r) or false end
        end
    end
    self.snap = snap
    self:genTrack()
end

------------------------------------------------------------------ the face

--- The dials ease toward their readings, and each one's range only grows while the window is open.
function DP_Window:dials(s)
    self.peak = self.peak or { src = 0, load = 0 }
    self.peak.src = math.max(self.peak.src, s.gen or 0)
    self.peak.load = math.max(self.peak.load, s.load or 0)
    local scales = { src = Board.fullScale(self.peak.src), load = Board.fullScale(self.peak.load) }
    self.needles = self.needles or { src = 0, load = 0 }
    for k, v in pairs({ src = (s.gen or 0) / scales.src, load = (s.load or 0) / scales.load }) do
        self.needles[k] = self.needles[k] + (v - self.needles[k]) * 0.15
    end
    return scales
end

function DP_Window:prerender()
    local s = self.snap
    if not s then return end
    self.blink = math.floor((self.tick or 0) / 18) % 2 == 0
    local scales = self:dials(s)
    self.model = Board.build(s, {
        S = S, fontH = fontH, measure = measure, getText = getText, txt = P.txt,
        needles = self.needles, scales = scales, genIndex = self.genIndex, blink = self.blink,
        tier = self.tier, readOnly = self.readOnly,
    })
    self:drawOps(self.model.ops)
end

local R = 8
--- A rounded card from the corner textures, the way the dashboard draws them.
function DP_Window:card(x, y, w, h, f, b, a)
    local r = math.min(R * S, w / 2, h / 2)
    self:drawRect(x + r, y, w - 2 * r, h, a, f[1], f[2], f[3])
    self:drawRect(x, y + r, r, h - 2 * r, a, f[1], f[2], f[3])
    self:drawRect(x + w - r, y + r, r, h - 2 * r, a, f[1], f[2], f[3])
    for _, c in ipairs({ { "tl", x, y }, { "tr", x + w - r, y }, { "bl", x, y + h - r }, { "br", x + w - r, y + h - r } }) do
        local t = tex(Board.TEX .. "cardfill_" .. c[1] .. ".png")
        if t then self:drawTextureScaled(t, c[2], c[3], r, r, a, f[1], f[2], f[3]) end
        if b then
            local tl = tex(Board.TEX .. "cardline_" .. c[1] .. ".png")
            if tl then self:drawTextureScaled(tl, c[2], c[3], r, r, a, b[1], b[2], b[3]) end
        end
    end
    if b then
        self:drawRect(x + r, y, w - 2 * r, 1, a, b[1], b[2], b[3])
        self:drawRect(x + r, y + h - 1, w - 2 * r, 1, a, b[1], b[2], b[3])
        self:drawRect(x, y + r, 1, h - 2 * r, a, b[1], b[2], b[3])
        self:drawRect(x + w - 1, y + r, 1, h - 2 * r, a, b[1], b[2], b[3])
    end
end

function DP_Window:drawOps(ops)
    for _, op in ipairs(ops) do
        local c = op.c
        if op.k == "rect" then
            self:drawRect(op.x, op.y, op.w, op.h, op.a, c[1], c[2], c[3])
        elseif op.k == "card" then
            self:card(op.x, op.y, op.w, op.h, c, op.line, op.a)
        elseif op.k == "tex" then
            local t = tex(op.name)
            if t then
                if c then self:drawTextureScaled(t, op.x, op.y, op.w, op.h, op.a, c[1], c[2], c[3])
                else self:drawTextureScaled(t, op.x, op.y, op.w, op.h, op.a, 1, 1, 1) end
            end
        elseif op.k == "quad" then
            local t = tex(op.name)
            local q = op.pts
            if t then self:drawTextureAllPoint(t, q[1], q[2], q[3], q[4], q[5], q[6], q[7], q[8], 1, 1, 1, op.a) end
        elseif op.k == "line" then
            self:drawLine(nil, op.x, op.y, op.x2, op.y2, op.th, op.a, c[1], c[2], c[3])
        elseif op.k == "text" then
            local f = font(op.font)
            if op.align == "right" then self:drawTextRight(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f)
            elseif op.align == "center" then self:drawTextCentre(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f)
            else self:drawText(op.str, op.x, op.y, c[1], c[2], c[3], op.a, f) end
        end
    end
    -- A faint wash over whatever the mouse would click.
    local h = self:isMouseOver() and self:hitAt(self:getMouseX(), self:getMouseY())
    if h and h.id ~= "close" then self:drawRect(h.x, h.y, h.w, h.h, 0.08, 1, 1, 1) end
end

------------------------------------------------------------------- opening

function DP_Window:new(x, y, object, opts)
    local o = ISPanel.new(self, x, y, W, H)
    o.object = object
    -- Opened from a wall gauge: everything reads, nothing switches.
    o.readOnly = type(opts) == "table" and opts.readOnly == true
    o.moveWithMouse = true
    o.background = false
    local ci = P.describe(object)
    o.tier = ci and ci.tier or "makeshift"
    o.tick = 0
    return o
end

function DazedPower.Window.open(playerObj, object, opts)
    if DazedPower.Window.current then
        DazedPower.Window.current:close()
    end
    local x = getPlayerScreenLeft(0) + px(60)
    local y = getPlayerScreenTop(0) + px(60)
    -- The 4x face is 1330 px wide, so on anything under the full screen it
    -- is pulled back until the keys and the close X are on screen. getCore
    -- is engine-only and the headless suite has none, hence the guard.
    if getCore and getCore() then
        local ok, sw, sh = pcall(function()
            return getCore():getScreenWidth(), getCore():getScreenHeight()
        end)
        if ok and sw and sh then
            x = math.max(0, math.min(x, sw - W))
            y = math.max(0, math.min(y, sh - H))
        end
    end
    local win = DP_Window:new(x, y, object, opts)
    win:initialise()
    win:addToUIManager()
    win:refresh()
    DazedPower.Window.current = win
    return win
end

return DP_Window