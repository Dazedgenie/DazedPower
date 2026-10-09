-- Checks for the 0.7.0 fixes: ghost objects in the registries, stale part links, the pedal heartbeat, the spin sprite.
return function(check, E)
    local P = DazedPower.Parts

    -- A square the cell no longer holds: the chunk streamed out (and maybe back in as new squares).
    local function streamOut(sq)
        E.squares[sq.x .. "," .. sq.y .. "," .. sq.z] = nil
        return E.square(sq.x, sq.y, sq.z)
    end
    local windmill = P.sprite("windmill", "ground", "salvaged", "still", "S")

    ------------------------------------------------------------ P.alive
    do
        local sq = E.square(900, 900, 0)
        local o = E.object(windmill, sq)
        check(P.alive(o), "an object on a square the cell holds is alive")
        local o2 = E.object(windmill, sq)
        check(P.alive(o2), "an object past the first slot of its square is alive")
        sq:RemoveTileObject(o)
        check(not P.alive(o), "an object no longer in its square's list is dead, whatever its index says")
        streamOut(sq)
        check(not P.alive(o2), "an object on a square the cell no longer holds is dead")
        check(not P.alive(nil) and not P.alive({}), "nil and stand-ins without an index are dead")
    end

    ------------------------------------------------------------ the registries drop ghosts
    do
        local B = DazedPower.More.Bridge
        local I = DazedPower.More.Instruments
        check(getmetatable(B.loaded) == nil and getmetatable(I.loaded) == nil, "the loaded lists are plain tables, pruned by hand")

        local sq = E.square(910, 910, 0)
        local ghost = E.object(windmill, sq)
        streamOut(sq)

        B.loaded[ghost] = true
        B.sweepLoose()
        check(B.loaded[ghost] == nil, "the loose sweep drops a part whose chunk streamed out")

        I.loaded[ghost] = true
        pcall(I.tick)
        check(I.loaded[ghost] == nil, "the instrument tick drops a streamed-out instrument")

        local L = DazedPower.Lamps
        L.lamps["910,910,0"] = ghost
        local Env = DazedPower.Env
        local read0 = Env.read
        Env.read = function() return {} end    -- the stand-in has no game calendar
        local lok, lerr = pcall(L.tick)
        Env.read = read0
        check(lok, "the lamp tick runs: " .. tostring(lerr))
        check(L.lamps["910,910,0"] == nil, "the lamp tick drops a streamed-out lamp")

        local A = DazedPower.Appliances
        A.outsideCoolers[ghost] = "room"
        check(A.outsideCoolerCools({ key = "room" }) == false and A.outsideCoolers[ghost] == nil,
            "a streamed-out cooler serves no room and leaves the list")
        A.outsideCoolers[ghost] = "room"
        check(A.outsideCoolerHeat({ key = "room" }) == 0 and A.outsideCoolers[ghost] == nil, "and adds no chill")

        local Mc = DazedPower.More.Machines
        Mc.objs[ghost] = true
        local walked = false
        Mc.each(function(o) if o == ghost then walked = true end end)
        check(not walked and Mc.objs[ghost] == nil, "the client machine list drops a streamed-out machine")

        DPM_Pedal.solid[ghost] = 0
        ghost.setAlphaAndTarget = function() end
        DPM_Pedal.keepSolid()
        check(DPM_Pedal.solid[ghost] == nil, "a streamed-out bike stops being held solid")

        -- A ghost left on a spin frame is not re-sprited when the option goes off; a live one is.
        local W = DazedPower.WindSpin
        local frame = P.sprite("windmill", "ground", "salvaged", "spin2", "S")
        local live = E.object(frame, E.square(911, 911, 0))
        ghost.sprite = frame
        live.md.dazedpower, ghost.md.dazedpower = { state = "still" }, { state = "still" }
        live.hasModData, ghost.hasModData = function() return true end, function() return true end
        local gs0 = getSprite
        getSprite = function(name) return { getName = function() return name end } end
        live.setSprite = function(self, s) self.sprite = s:getName() end
        ghost.setSprite = live.setSprite
        W.tracked, W.count = { [ghost] = { phase = 0 }, [live] = { phase = 0 } }, 2
        W.restoreAll()
        getSprite = gs0
        check(live.sprite == windmill and ghost.sprite == frame, "turning the spin off restores live windmills and leaves ghosts alone")
    end

    ------------------------------------------------------------ stale part links
    do
        local S = DazedPower.System
        local bankSq = E.square(920, 920, 0)
        local bank = E.object(P.sprite("bank", "ground", "salvaged", "c0", "S") or windmill, bankSq)
        local arr = E.object(windmill, E.square(921, 920, 0))
        local rec = { arrays = { arr }, banks = { bank }, xfmrs = {} }
        check(S.staleLinks(rec) == false, "parts on loaded squares are not stale")
        streamOut(bankSq)
        check(S.staleLinks(rec) == true, "a bank whose chunk streamed out under a loaded controller triggers a relink")
    end

    ------------------------------------------------------------ the pedal heartbeat
    do
        local B, S = DazedPower.More.Bridge, DazedPower.System
        local pedalSq = E.square(930, 930, 0)
        local bike = E.object(P.sprite("pedal", "ground", "salvaged", "off", "S"), pedalSq)
        Perks.Fitness = Perks.Fitness or "Fitness"
        local rider = { x = 930.5, y = 931.2 }
        function rider:getX() return self.x end
        function rider:getY() return self.y end
        function rider:getPerkLevel() return 7 end
        function rider:isDead() return false end
        function rider:faceThisObject() end
        function rider:isTimedActionInstant() return false end
        local a = DPM_Pedal:new(rider, bike)
        local t0, c0, s0 = getTimestampMs, isClient, sendClientCommand
        local now, sent = 5000, {}
        getTimestampMs = function() return now end
        sendClientCommand = function(pl, module, command, args) sent[#sent + 1] = { module, command, args } end

        -- Single player: written on the object every frame, as before.
        a:update()
        check(bike.md.dazedpower.pedalHeartbeat == 5000 and bike.md.dazedpower.pedalFitness == 7 and #sent == 0,
            "single player writes the heartbeat locally and sends nothing")

        -- A multiplayer client: no local write, one command a second.
        isClient = function() return true end
        bike.md.dazedpower.pedalHeartbeat = 0
        for _, t in ipairs({ 6000, 6400, 6999, 7000, 7500, 8100 }) do now = t; a:update() end
        isClient = c0
        check(#sent == 3 and bike.md.dazedpower.pedalHeartbeat == 0, "a client sends about one heartbeat a second: " .. #sent)
        check(sent[1][1] == "DazedPower" and sent[1][2] == "pedalBeat" and sent[1][3].x == 930 and sent[1][3].y == 930
            and sent[1][3].z == 0, "the heartbeat names the bike's square")

        -- The server writes it on its own clock, for a living rider in reach only.
        now = 9000
        check(S.onCommand("pedalBeat", rider, sent[1][3]) and bike.md.dazedpower.pedalHeartbeat == 9000
            and bike.md.dazedpower.pedalFitness == 7, "the server writes the heartbeat it is sent")
        now = 9500
        rider.x = 940
        check(not B.pedalBeat(rider, sent[1][3]) and bike.md.dazedpower.pedalHeartbeat == 9000, "a rider out of reach is refused")
        rider.x = 930.5
        rider.isDead = function() return true end
        check(not B.pedalBeat(rider, sent[1][3]), "a dead rider is refused")
        check(not B.pedalBeat(rider, { x = "a" }) and not B.pedalBeat(nil, sent[1][3]), "a bad request is refused")
        getTimestampMs, sendClientCommand = t0, s0
    end

    ------------------------------------------------------------ the spin frame and setState
    do
        local function sp(tier, st, f) return P.sprite("windmill", "ground", tier or "salvaged", st, f or "S") end
        local mill = E.object(sp(nil, "spin3"), E.square(940, 940, 0))
        mill.md.dazedpower = { state = "turning", facing = "S" }
        check(P.setState(mill, "turning") == false and mill.sprite == sp(nil, "spin3"),
            "single player: a spin frame already counts as turning, so the sprite is left alone")
        mill.sprite = sp(nil, "wobble")
        check(P.setState(mill, "broken") == false and mill.sprite == sp(nil, "wobble"), "and a rocking frame already counts as broken")
        mill.sprite = sp(nil, "spin1")
        mill.md.dazedpower.state = "still"
        check(P.setState(mill, "turning") == false and mill.md.dazedpower.state == "turning",
            "the logical state is still recorded when the frame is kept")
        check(P.setState(mill, "turning", "E") == true and mill.sprite == sp(nil, "turning", "E"), "a new facing still swaps the sprite")
        mill.sprite = sp(nil, "spin2")
        check(P.setState(mill, "still") == true and mill.sprite == sp(nil, "still"), "a real change of state still swaps the sprite")
        local s0 = isServer
        isServer = function() return true end
        mill.sprite = sp(nil, "spin2")
        local ok = P.setState(mill, "turning")
        isServer = s0
        check(ok == true and mill.sprite == sp(nil, "turning"), "a server puts the plain turning sprite back for clients to sync")
    end
end
