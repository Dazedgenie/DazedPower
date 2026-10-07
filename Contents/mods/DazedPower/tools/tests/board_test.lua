-- Checks the analog charge board's layout: its click regions, what greys out, scaling and the source list.
return function(check)
    local B = DazedPower.BoardLayout
    local function opts(extra)
        local o = { S = 1, fontH = function() return 16 end, measure = function(_, s) return #s * 7 end,
            getText = function(k) return k end, txt = function(k) return k end, needles = { src = 0.5, load = 0.2 }, scales = { src = 2000, load = 2000 } }
        for k, v in pairs(extra or {}) do o[k] = v end
        return o
    end
    local function snap(extra)
        local s = { online = true, powered = true, gen = 900, load = 300, net = 600, soc = 0.6, charge = 600, capacity = 1000, dod = 0.25, cells = 2,
            bankCells = { 60, 61 }, bankWear = { 0, 20 }, env = { hour = 12 }, bkAuto = true, bkStart = 0.4, bkStop = 0.9, bkLo = 0.3, bkHi = 0.8,
            bkRows = { { t = "petrol_salvaged", s = "standby", auto = false }, { t = "propane_workshop", s = "running", auto = true } } }
        for k, v in pairs(extra or {}) do s[k] = v end
        return s
    end
    local function ids(m) local out = {} for _, h in ipairs(m.hits) do out[h.id] = h end return out end
    local m = B.build(snap(), opts())
    local h = ids(m)
    check(m.w == B.W and m.h == B.H, "board has its base size")
    check(h.close and h.isolator and h["gen:bkMaster"] and h["gen:bkAuto:1"] and h["gen:bkRun:1"] and h["gen:bkLevelStart:-1"]
        and h["gen:bkLevelStop:1"] and h.genPrev and h.genNext, "board offers every control")
    local m2 = ids(B.build(snap(), opts({ genIndex = 2 })))
    check(m2["gen:bkAuto:2"] and m2["gen:bkRun:2"] == nil, "a generator on its own Auto has no ON switch to press")
    local off = ids(B.build(snap({ online = false }), opts()))
    check(off.isolator and off["gen:bkMaster"] == nil, "a switched-off board keeps only the isolator live")
    local ro = ids(B.build(snap(), opts({ readOnly = true })))
    check(ro["gen:bkMaster"] == nil and ro["gen:bkLevelStart:1"] == nil, "a wall gauge's board switches nothing")
    local locked = ids(B.build(snap({ lock = "IGUI_x" }), opts()))
    check(locked["gen:bkMaster"] == nil and locked["gen:bkLevelStop:1"] == nil and locked["gen:bkAuto:1"], "the owner's lock greys the controller's controls")
    local big = B.build(snap(), opts({ S = 2 }))
    check(big.w == 2 * B.W and ids(big).isolator.w == 2 * h.isolator.w, "the board scales with the font set")
    check(B.fullScale(0) == 2000 and B.fullScale(1900) == 4000 and B.fullScale(1e9) == 80000, "dial ranges grow in steps")
    local rows = B.sources({ gen = 500, solarW = 200, dpmRows = { { k = "pedal", w = 0 }, { k = "windmill", w = 300 } } })
    check(#rows == 3 and rows[1].k == "windmill" and rows[2].k == "solar" and rows[3].k == "pedal", "sources list biggest first, solar included")
    check(B.titleCase("WATER PUMP") == "Water pump" and B.titleCase("TV") == "TV", "circuit names read as words")
    local none = B.build(snap({ bkRows = {}, loadList = {}, bankCells = {} }), opts())
    check(ids(none)["gen:bkMaster"] == nil and #none.ops > 50, "an empty rig still draws a full board")
    local quad
    for _, op in ipairs(m.ops) do if op.k == "quad" then quad = op end end
    check(quad and #quad.pts == 8, "the needles are turned quads")

    -- Eight sources don't fit: the list scrolls instead of ending in "+N more".
    local many = {}
    for i = 1, 8 do many[i] = { k = "windmill", w = 900 - i * 100 } end
    local function srcNames(model)
        local out = {}
        for _, op in ipairs(model.ops) do if op.k == "text" and op.str:find("IGUI_DazedPower_Sr", 1, true) == 1 and op.str ~= "IGUI_DazedPower_SrcNone" then out[#out + 1] = op end end
        return out
    end
    local function scrollOf(model) for _, a in ipairs(model.scrolls) do if a.id == "src" then return a end end end
    local top = B.build(snap({ dpmRows = many, gen = 0 }), opts())
    local area = scrollOf(top)
    local seen = #srcNames(top)
    check(area and area.max == 8 - seen and area.off == 0 and seen >= 4, "a long sources list scrolls: " .. tostring(seen) .. " rows shown")
    local moreText = false
    for _, op in ipairs(top.ops) do if op.k == "text" and op.str:find("SrcMore", 1, true) then moreText = true end end
    check(not moreText and ids(top)["src:down"] ~= nil, "no +N more line, and the scroll bar can be clicked")
    local down = B.build(snap({ dpmRows = many, gen = 0 }), opts({ srcScroll = 99 }))
    check(scrollOf(down).off == area.max and #srcNames(down) == seen, "the scroll stops at the last row")
    local short = scrollOf(B.build(snap(), opts({ srcScroll = 5 })))
    check(short and short.max == 0 and short.off == 0 and ids(m)["src:up"] == nil, "a short list doesn't scroll")
end
