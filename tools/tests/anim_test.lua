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

    -- The look registered on DP_MachineFx (0.14.0) is the same as W.pick, state by state and frame by frame.
    do
        local M = DazedPower.MachineFx
        local same, n = true, 0
        for _, tier in ipairs({ "makeshift", "salvaged", "workshop" }) do
            for _, st in ipairs({ "still", "turning", "furled", "broken" }) do
                for _, ms in ipairs({ 0, 1, 2.5, 6, 14.9, 15, 30 }) do
                    for k = 0, 7 do
                        local d = { state = st, facing = "W", windMs = ms }
                        local i = P.spriteInfo(P.sprite("windmill", "ground", tier, st, "W"))
                        local a = W.pick(i, d, k)
                        local b = M.pick("windmill", tier, st, "W", k, d)
                        n = n + 1
                        if a ~= b or a == nil then same = false end
                    end
                end
            end
        end
        check(same and n == 672, "the shared module shows exactly what W.pick picks (" .. n .. " cases)")
        check(W.rate("spin", "salvaged", { windMs = 9 }) == W.fps("salvaged", 9, "turning")
              and W.rate("rock", "salvaged", { windMs = 9 }) == W.fps("salvaged", 9, "broken"), "the frame rate is W.fps")
    end

    -- One windmill near a player, ticked for a second of game time through the shared module: it changes frames at
    -- the wind's rate, holds while paused, and goes back when the tick box is turned off.
    do
        local M, T = DazedPower.MachineFx, DazedCore.Tick
        local function spr(name) return { getName = function() return name end } end
        local sq = { getX = function() return 10 end, getY = function() return 10 end, getZ = function() return 0 end,
                     IsOnScreen = function() return true end }
        local obj = { sprite = spr(P.sprite("windmill", "ground", "salvaged", "turning", "S")), md = { dazedpower = { state = "turning", facing = "S", windMs = 7 } } }
        function obj:getSprite() return self.sprite end
        function obj:setSprite(s) self.sprite = s; self.swaps = (self.swaps or 0) + 1 end
        function obj:getObjectIndex() return 0 end
        function obj:getSquare() return sq end
        function sq:getObjects() return { size = function() return 1 end, get = function() return obj end } end
        function obj:hasModData() return true end
        function obj:getModData() return self.md end
        local pl = { getX = function() return 12 end, getY = function() return 11 end, getZ = function() return 0 end, isDead = function() return false end }
        local g0, n0, s0, t0, c0, p0 = getSprite, getNumActivePlayers, getSpecificPlayer, getTimestampMs, getCell, isGamePaused
        local now, paused = 0, false
        getSprite = function(name) return spr(name) end
        getNumActivePlayers = function() return 1 end
        getSpecificPlayer = function() return pl end
        getTimestampMs = function() return now end
        isGamePaused = function() return paused end
        getCell = function() return { getGridSquare = function(_, x, y) return (x == 10 and y == 10) and sq or nil end } end
        M.reset()
        M.consider(obj)
        check(M.count == 1 and M.tracked[obj] and M.tracked[obj].spec.kind == "windmill", "a windmill is followed by the shared module")
        local function run(ms) local stop = now + ms while now < stop do now = now + 16; T.onTick() end end
        run(1100)
        local s0w = obj.swaps or 0
        run(2000)
        local f = P.spriteInfo(obj.sprite:getName())
        local want = W.fps("salvaged", 7, "turning") * 2
        check(f.kind == "windmill" and f.frame ~= nil, "it shows blade frames")
        local slow = obj.swaps - s0w
        check(math.abs(slow - want) <= 2, "two seconds at 7 m/s: about " .. want .. " frames, got " .. (obj.swaps - s0w))
        check(M.frameMs == M.FAST_MS, "a spinning windmill runs the frame job at the fast period")
        obj.md.dazedpower.windMs = 13
        run(1100)
        local s1 = obj.swaps
        run(2000)
        check(obj.swaps - s1 > slow + 4, "a stronger wind spins it faster: " .. slow .. " -> " .. (obj.swaps - s1))
        paused = true
        s1 = obj.swaps
        run(2000)
        check(obj.swaps == s1, "paused, the blades hold (they used to keep turning)")
        paused = false
        run(500)
        check(obj.swaps > s1 and obj.swaps - s1 <= 12, "unpaused, they carry on without a jump")
        local on0 = DazedCore.Options.on
        DazedCore.Options.on = function() return false end
        run(1100)
        check(P.spriteInfo(obj.sprite:getName()).frame == nil and not T.has(M.FRAME_ID), "turning the tick box off puts the plain sprite back")
        s1 = obj.swaps
        run(1500)
        check(obj.swaps == s1, "and it stays plain")
        DazedCore.Options.on = on0
        run(1100)
        check(P.spriteInfo(obj.sprite:getName()).frame ~= nil, "on again, it spins again")
        -- A gale: the plain motion-blur sprite, no frame job for it.
        obj.md.dazedpower.windMs = 20
        run(1300)
        check(obj.sprite:getName() == P.sprite("windmill", "ground", "salvaged", "turning", "S") and not T.has(M.FRAME_ID), "a gale shows the blur sprite")
        -- The server yaws it into the wind (a plain sprite facing E): the frames follow the new facing at once.
        obj.md.dazedpower.windMs = 7
        run(1300)
        obj.sprite = spr(P.sprite("windmill", "ground", "salvaged", "turning", "E")); obj.md.dazedpower.facing = "E"
        run(300)
        check(P.spriteInfo(obj.sprite:getName()).facing == "E" and P.spriteInfo(obj.sprite:getName()).frame ~= nil, "a yaw is followed before the next scan")
        M.onRemoved(obj)
        run(1100)
        check(M.count == 0 and not T.has(M.SCAN_ID) and not T.has(M.FRAME_ID), "gone: no jobs left")
        M.reset()
        getSprite, getNumActivePlayers, getSpecificPlayer, getTimestampMs, getCell, isGamePaused = g0, n0, s0, t0, c0, p0
    end

    -- Pedalling: the animation node and the action that plays it.
    check(DPM_Pedal ~= nil and DPM_Pedal.start ~= nil, "the pedal action exists")
    local x, y, f = DPM_Pedal.seat({ facing = "E", tier = "workshop" }, 100, 200)
    check(x == 100.5 and y == 200.5 and f == "E", "the rider stands on the bike's centre, facing the bike's way")
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
        function c:setSittingOnFurniture(v) self.sitting = v end
        function c:setSitOnFurnitureObject(o) self.seat = o end
        function c:setSitOnFurnitureDirection(d) self.seatDir = d end
        local sq = { getX = function() return 100 end, getY = function() return 200 end, getZ = function() return 0 end }
        local bike = { md = { dazedpower = { gear = "racing" } } }
        function bike:getSquare() return sq end
        function bike:getObjectIndex() return 0 end
        function sq:getObjects() return { size = function() return 1 end, get = function() return bike end } end
        local c1 = getCell
        getCell = function() return { getGridSquare = function(_, x, y) return (x == 100 and y == 200) and sq or nil end } end
        function bike:getSprite() return { getName = function() return P.sprite("pedal", "ground", "salvaged", "off", "S") end } end
        function bike:getModData() return self.md end
        function bike:hasModData() return true end
        function bike:transmitModData() end
        function bike:setAlphaAndTarget(pn, a) self.alpha = a end
        local a = DPM_Pedal:new(c, bike)
        a.setActionAnim = function(self, n) self.anim = n end
        IsoDirections = IsoDirections or { N = "N", E = "E", S = "S", W = "W" }
        a:start()
        check(a.anim == "DazedPedal" and c.vars.DazedPedalSpeed == DazedPower.More.Actions.PEDAL_PACE.racing, "riding plays the pedal animation at the gear's pace")
        check(c.vars.DazedPedalTier == "salvaged", "the animation is picked for the bike's tier")
        check(c.y == 200.5 and c.x == 100.5 and c.dir == IsoDirections.S, "the rider is on the bike, facing south")
        bike.alpha = 0.3; DPM_Pedal.keepSolid()
        check(bike.alpha == 1.0, "the bike is kept fully drawn while ridden")
        check(c.sitting == true and c.seat == bike and c.seatDir == IsoDirections.S, "the rider counts as seated on the bike")
        a.dismount(a)
        check(c.sitting == false and c.seat == nil, "getting off clears the seat")
        check(c.x == 99.2 and c.y == 200.5, "getting off puts the rider back where they stood")
        bike.alpha = 0.3; DPM_Pedal.keepSolid()
        check(bike.alpha == 0.3, "after getting off the game fades it as usual")
        getCell = c1
    end

    -- The treadmill: one animation node per gait, picked by the action's variables.
    do
        local dir = (arg and arg[1] or "../../Contents/mods/DazedPower/common/media/lua") .. "/../AnimSets/player/actions/"
        local guids, dupes = {}, 0
        local function read(name)
            local f = io.open(dir .. name .. ".xml")
            local txt = f and f:read("*a")
            if f then f:close() end
            return txt
        end
        local function count(txt)
            for g in txt:gmatch('x_name="([%w%-]+)"') do
                if guids[g] then dupes = dupes + 1 end
                guids[g] = true
            end
        end
        for _, name in ipairs({ "DazedPedal", "DazedPedalSalvaged", "DazedPedalWorkshop" }) do count(read(name) or "") end
        for _, mode in ipairs({ "walk", "run", "sprint" }) do
            local node = "DazedTreadmill" .. mode:sub(1, 1):upper() .. mode:sub(2)
            local txt = read(node)
            check(txt ~= nil, node .. ".xml exists")
            if txt then
                count(txt)
                local anim = "Bob_" .. mode:sub(1, 1):upper() .. mode:sub(2)
                check(txt:find("<m_Name>" .. node .. "</m_Name>", 1, true) and txt:find("<m_AnimName>" .. anim .. "</m_AnimName>", 1, true),
                    node .. " plays " .. anim)
                check(txt:find("<m_SpeedScale>DazedTreadmillSpeed</m_SpeedScale>", 1, true), node .. " is paced by DazedTreadmillSpeed")
                check(txt:find("<m_Name>PerformingAction</m_Name>%s*<m_Type>STRING</m_Type>%s*<m_Value>DazedTreadmill</m_Value>")
                    and txt:find("<m_Name>DazedTreadmillMode</m_Name>%s*<m_Type>STRING</m_Type>%s*<m_Value>" .. mode .. "</m_Value>"),
                    node .. " is chosen by the action and the gait")
                check(txt:find("<boneName>Dummy01</boneName>", 1, true) and txt:find("<boneName>Translation_Data</boneName>", 1, true),
                    node .. " keeps the pedal's bone weights")
            end
        end
        check(dupes == 0, "no animation node reuses a condition GUID")
        local c = { vars = {}, x = 1, y = 1 }
        function c:SetVariable(k, v) assert(type(v) == "string", "SetVariable only takes text in game") self.vars[k] = v end
        function c:setVariable(k, v) self.vars[k] = v end
        DPM_Treadmill.setVar(c, "DazedTreadmillSpeed", 1.5)
        DPM_Treadmill.setVar(c, "DazedTreadmillMode", "run")
        check(c.vars.DazedTreadmillSpeed == 1.5 and c.vars.DazedTreadmillMode == "run", "the action sets numbers as floats and the gait as text")
        local c2 = { vars = {} }
        function c2:SetVariable(k, v) assert(type(v) == "string") self.vars[k] = v end
        DPM_Treadmill.setVar(c2, "DazedTreadmillSpeed", 1)
        check(c2.vars.DazedTreadmillSpeed == "1", "with no float setter the speed goes as text")
    end
end
