--[[ DazedPower -- schema versions for the world-wide ModData tables.

     Those tables are maps keyed by house, square or system, so a version field inside them would be
     read as one more entry. Their versions live together in one small table instead, and each
     tag's steps run once at game start before anything reads it. Part ModData is versioned in
     P.data (DP_Parts). ]]

if isClient() then return end

DazedPower = DazedPower or {}
DazedPower.Migrate = DazedPower.Migrate or {}
local G = DazedPower.Migrate

G.TAG = "DazedPowerSchema"
-- tag -> { latest = n, steps = { [n] = function(tbl) ... end } }; step n turns version n-1 into n.
G.TABLES = {
    DazedPowerGrid = { latest = 1, steps = {} },
    DazedPowerRemote = { latest = 1, steps = {} },
    DazedPowerSeeded = { latest = 1, steps = {} },
    DazedPowerSeedWaiting = { latest = 1, steps = {} },
}

--- Run every table's pending steps and record its new version; returns how many tables moved.
function G.run()
    if not (ModData and ModData.getOrCreate) then return 0 end
    local book = ModData.getOrCreate(G.TAG)
    local moved = 0
    for tag, spec in pairs(G.TABLES) do
        local have = tonumber(book[tag]) or 0
        if have < spec.latest then
            -- A table that does not exist yet is simply new at the latest version.
            if ModData.exists and ModData.exists(tag) then
                local t = ModData.get(tag)
                for n = have + 1, spec.latest do
                    local step = spec.steps[n]
                    if type(step) == "function" then pcall(step, t) end
                end
            end
            book[tag] = spec.latest
            moved = moved + 1
        end
    end
    return moved
end

Events.OnInitGlobalModData.Add(G.run)

return G
