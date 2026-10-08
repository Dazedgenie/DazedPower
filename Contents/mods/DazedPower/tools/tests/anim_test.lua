-- Checks for the windmill spin frames and the pedalling animation hookup. Run from load_test.lua.
return function(check, E)
    local P, W = DazedPower.Parts, DazedPower.WindSpin
    check(W ~= nil and W.pick ~= nil, "the windmill spin module loads")
    local info = P.spriteInfo(P.sprite("windmill", "ground", "makeshift", "turning", "S"))

    -- Turning: four frames in order, then round again.
    local seen = {}
    for k = 0, 4 do seen[#seen + 1] = P.spriteInfo(W.pick(info, { state = "turning", facing = "S", windMs = 6 }, k)).frame end
    check(seen[1] == "spin1" and seen[2] == "spin2" and seen[4] == "spin4" and seen[5] == "spin1", "turning walks through the four frames")
    local fast = W.pick(info, { state = "turning", facing = "S", windMs = W.MAX_MS + 1 }, 2)
    check(fast == P.sprite("windmill", "ground", "makeshift", "turning", "S"), "a gale shows the motion-blur sprite")
    local east = P.spriteInfo(W.pick(info, { state = "turning", facing = "E", windMs = 6 }, 1))
    check(east.facing == "E" and east.tier == "makeshift", "frames follow the stored facing")

    -- Still, furled and broken.
    check(W.pick(info, { state = "still", facing = "S", windMs = 1 }, 3) == P.sprite("windmill", "ground", "makeshift", "still", "S"), "still stays still")
    check(W.pick(info, { state = "furled", facing = "N", windMs = 20 }, 3) == P.sprite("windmill", "ground", "makeshift", "furled", "N"), "furled stays furled")
    local rock = {}
    for k = 0, 2 do rock[k + 1] = P.spriteInfo(W.pick(info, { state = "broken", facing = "S", windMs = 8 }, k)).frame or "rest" end
    check(rock[1] == "rest" and rock[2] == "rest" and rock[3] == "wobble", "a broken rotor rocks one beat in three")
    check(W.pick(info, { state = "broken", facing = "S", windMs = 0.5 }, 2) == P.sprite("windmill", "ground", "makeshift", "broken", "S"),
        "a broken rotor in calm air doesn't move")

    -- Speed follows the wind, capped.
    check(W.fps("makeshift", 3.5) == W.MIN_FPS and W.fps("makeshift", 8) > W.fps("makeshift", 5) and W.fps("workshop", 40) == W.MAX_FPS,
        "frame rate rises with the wind up to a cap")

    -- One windmill near a player, ticked for a second of game time: it changes frames and goes back when turned off.
    do
        local function spr(name) return { getName = function() return name end } end
        local sq = { getX = function() return 10 end, getY = function() return 10 end }
        local obj = { sprite = spr(P.sprite("windmill", "ground", "salvaged", "turning", "S")), md = { dazedpower = { state = "turning", facing = "S", windMs = 7 } } }
        function obj:getSprite() return self.sprite end
        function obj:setSprite(s) self.sprite = s; self.swaps = (self.swaps or 0) + 1 end
        function obj:getObjectIndex() return 1 end
        function obj:getSquare() return sq end
        function obj:hasModData() return true end
        function obj:getModData() return self.md end
        local pl = { getX = function() return 12 end, getY = function() return 11 end, getZ = function() return 0 end, isDead = function() return false end }
        local g0, n0, s0, t0, c0 = getSprite, getNumActivePlayers, getSpecificPlayer, getTimestampMs, getCell
        local now = 0
        getSprite = function(name) return spr(name) end
        getNumActivePlayers = function() return 1 end
        getSpecificPlayer = function() return pl end
        getTimestampMs = function() return now end
        getCell = function() return { getGridSquare = function() return nil end } end
        W.tracked, W.count = {}, 0
        W.consider(obj)
        check(W.count == 1, "a windmill on screen is tracked")
        for _ = 1, 30 do now = now + 33; W.tick() end
        local f = P.spriteInfo(obj.sprite:getName())
        check(f.kind == "windmill" and f.frame ~= nil and (obj.swaps or 0) >= 3, "it steps through frames: " .. tostring(obj.swaps))
        local on0 = DazedCore.Options.on
        DazedCore.Options.on = function() return false end
        now = now + 33; W.tick()
        check(P.spriteInfo(obj.sprite:getName()).frame == nil and W.count == 0, "turning the option off puts the plain sprite back")
        DazedCore.Options.on = on0
        getSprite, getNumActivePlayers, getSpecificPlayer, getTimestampMs, getCell = g0, n0, s0, t0, c0
    end

    -- Pedalling: the animation node and the action that plays it.
    check(DPM_Pedal ~= nil and DPM_Pedal.start ~= nil, "the pedal action exists")
    local x, y, f = DPM_Pedal.seat({ facing = "E", tier = "workshop" }, 100, 200)
    check(math.abs(x - (100.5 - DPM_PEDAL_SEAT_BACK.workshop)) < 1e-9 and y == 200.5 and f == "E", "an east-facing rider sits back toward the west")
    x, y = DPM_Pedal.seat({ facing = "N", tier = "makeshift" }, 0, 0)
    check(x == 0.5 and math.abs(y - (0.5 + DPM_PEDAL_SEAT_BACK.makeshift)) < 1e-9, "a north-facing rider sits back toward the south")
    -- Start, then stop: the rider is put on the saddle and back where they stood.
    do
        local c = { x = 99.2, y = 200.5, vars = {} }
        function c:getX() return self.x end
        function c:getY() return self.y end
        function c:setX(v) self.x = v end
        function c:setY(v) self.y = v end
        function c:setDir(d) self.dir = d end
        function c:SetVariable(k, v)
            assert(type(v) ~= "number", "SetVariable only takes text in game")
            self.vars[k] = v
        end
        function c:setVariable(k, v) self.vars[k] = v end
        function c:isTimedActionInstant() return false end
        local sq = { getX = function() return 100 end, getY = function() return 200 end }
        local bike = { md = { dazedpower = { gear = "racing" } } }
        function bike:getSquare() return sq end
        function bike:getObjectIndex() return 1 end
        function bike:getSprite() return { getName = function() return P.sprite("pedal", "ground", "salvaged", "off", "S") end } end
        function bike:getModData() return self.md end
        function bike:hasModData() return true end
        function bike:transmitModData() end
        local a = DPM_Pedal:new(c, bike)
        a.setActionAnim = function(self, n) self.anim = n end
        IsoDirections = IsoDirections or { N = "N", E = "E", S = "S", W = "W" }
        a:start()
        check(a.anim == "DazedPedal" and c.vars.DazedPedalSpeed == DPM_PEDAL_PACE.racing, "riding plays the pedal animation at the gear's pace")
        check(math.abs(c.y - (200.5 - DPM_PEDAL_SEAT_BACK.salvaged)) < 1e-9 and c.x == 100.5 and c.dir == IsoDirections.S, "the rider is on the saddle, facing south")
        a.dismount(a)
        check(c.x == 99.2 and c.y == 200.5, "getting off puts the rider back where they stood")
    end
end
