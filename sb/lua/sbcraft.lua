-- SBCraft logic (game thread, run by the loader in Mods/SBCraft/Scripts/main.lua; reloaded when this file changes).
--
-- The native ReShade add-on (SBCraft.addon64) reads SB's camera straight from memory at present time and talks to
-- Minecraft. This gives it what only the game thread can:
--   * where the camera lives: the addresses of PlayerCameraManager.CameraCachePrivate.POV.{Location,Rotation,FOV}
--     and of the pawn's root component RelativeLocation (the capsule centre), found by reflection, no offsets baked in;
--   * SB's floors around Gregory: line traces down, one column per Minecraft block.
--
-- Files in LINK_DIR (written to a temp file, then renamed):
--   sb_link.txt    gen, addresses, capsule half height (cm), check values      (every second; gen bumps on change)
--   sb_ground.txt  seq, centre, then one "x y zTop" line per column, UE units  (each finished scan)
-- Commands come back in sb_cmd.txt (deleted once read).
local M = {}

-- The folder shared with the add-on (both run with SB's Win64 folder as the working directory): SBCRAFT_LINK, else
-- the path in Mods\SBCraft\link_dir.txt, else Mods\SBCraft\link.
local function link_dir()
    local env = os.getenv("SBCRAFT_LINK")
    if env and env ~= "" then return env end
    local f = io.open("Mods\\SBCraft\\link_dir.txt", "r")
    if f then
        local line = (f:read("*l") or ""):gsub("%s+$", "")
        f:close()
        if line ~= "" then return line end
    end
    return "Mods\\SBCraft\\link"
end
local LINK_DIR = link_dir()
local GROUND_RADIUS = 12          -- columns out from Gregory (blocks = metres)
local TRACES_PER_TICK = 96        -- line traces per game-thread tick
local TRACE_UP = 180.0            -- start this far above the capsule centre (cm)
local TRACE_DOWN = 700.0          -- and end this far below
local WALL_HEIGHTS = {50.0, 150.0, 250.0} -- cm above Gregory's feet: one Minecraft block each
local WALL_HITS = 8               -- surfaces per trace line

local UEHelpers = require("UEHelpers")

local function log(fmt, ...)
    print(string.format("[SBCraft] " .. fmt .. "\n", ...))
end

local function write_file(name, text)
    local path = LINK_DIR .. "\\" .. name
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(text)
    f:close()
    os.remove(path)
    return os.rename(tmp, path)
end

local function valid(o)
    return o ~= nil and type(o) == "userdata" and o:IsValid()
end

--- A named property of a struct/class, walking super structs.
local function find_property(struct, name)
    local s = struct
    while valid(s) do
        local found
        s:ForEachProperty(function(prop)
            if prop:GetFName():ToString() == name then
                found = prop
                return true
            end
        end)
        if found then return found end
        s = s:GetSuperStruct()
    end
    return nil
end

local function property_names(struct)
    local names = {}
    struct:ForEachProperty(function(prop)
        names[#names + 1] = prop:GetFName():ToString() .. "@" .. prop:GetOffset_Internal()
    end)
    return table.concat(names, " ")
end

local function offset_of(struct, name)
    local p = find_property(struct, name)
    if not p then error("no property " .. name .. " in " .. struct:GetFullName() .. ": " .. property_names(struct)) end
    return p:GetOffset_Internal(), p
end

local function resolve_offsets(pcm, root)
    local o = {}
    local cacheOff, cacheProp = offset_of(pcm:GetClass(), "CameraCachePrivate")
    local cacheStruct = cacheProp:GetStruct()
    log("CameraCacheEntry: %s", property_names(cacheStruct))
    local povOff, povProp = offset_of(cacheStruct, "POV")
    local povStruct = povProp:GetStruct()
    o.loc = cacheOff + povOff + offset_of(povStruct, "Location")
    o.rot = cacheOff + povOff + offset_of(povStruct, "Rotation")
    o.fov = cacheOff + povOff + offset_of(povStruct, "FOV")
    local stamp = find_property(cacheStruct, "Timestamp") or find_property(cacheStruct, "TimeStamp")
    o.stamp = stamp and (cacheOff + stamp:GetOffset_Internal()) or -1
    o.rel = offset_of(root:GetClass(), "RelativeLocation")
    log("offsets: CameraCachePrivate %d POV %d -> loc %d rot %d fov %d stamp %d; RelativeLocation %d",
        cacheOff, povOff, o.loc, o.rot, o.fov, o.stamp, o.rel)
    return o
end

local function refresh_link(s)
    local pc = UEHelpers.GetPlayerController()
    if not valid(pc) then return end
    local pcm, pawn = pc.PlayerCameraManager, pc.Pawn
    if not valid(pcm) or not valid(pawn) then return end
    local root = pawn.RootComponent
    if not valid(root) then return end
    if not s.offsets then s.offsets = resolve_offsets(pcm, root) end
    local o = s.offsets
    local half = 0.0
    if find_property(root:GetClass(), "CapsuleHalfHeight") then half = root.CapsuleHalfHeight end
    local base = pcm:GetAddress()
    local cam, rot = pcm:GetCameraLocation(), pcm:GetCameraRotation()
    local key = string.format("%d %d %d", base, pawn:GetAddress(), root:GetAddress())
    if key ~= s.linkKey then
        s.linkKey = key
        s.gen = (s.gen or 0) + 1
        local rl = root.RelativeLocation
        log("link gen %d: pawn %s at %.0f %.0f %.0f (half %.0f), camera %.0f %.0f %.0f pitch %.1f yaw %.1f fov %.1f",
            s.gen, pawn:GetFullName(), rl.X, rl.Y, rl.Z, half, cam.X, cam.Y, cam.Z, rot.Pitch, rot.Yaw, pcm:GetFOVAngle())
    end
    s.pawn = pawn
    s.root = root
    write_file("sb_link.txt", string.format(
        "gen %d\npcm %d\nloc %d\nrot %d\nfov %d\nstamp %d\npawnloc %d\nhalf %.3f\npawn %s\ncheck %.3f %.3f %.3f %.3f %.3f %.3f %.3f\n",
        s.gen, base, base + o.loc, base + o.rot, base + o.fov, o.stamp >= 0 and base + o.stamp or 0,
        root:GetAddress() + o.rel, half, pawn:GetClass():GetFName():ToString(),
        cam.X, cam.Y, cam.Z, rot.Pitch, rot.Yaw, rot.Roll, pcm:GetFOVAngle()))
end

-- Ground scan: floor columns around Gregory (nearest rings first), then wall lines across the same square at three
-- heights in both directions along both axes; a few traces per tick, published when the pass is done.
local function start_scan(s)
    local loc = s.root.RelativeLocation
    local half = 0.0
    if find_property(s.root:GetClass(), "CapsuleHalfHeight") then half = s.root.CapsuleHalfHeight end
    local sc = {cx = math.floor(loc.X / 100.0), cy = math.floor(loc.Y / 100.0), z = loc.Z, feet = loc.Z - half,
        jobs = {}, i = 1, out = {}}
    for r = 0, GROUND_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    sc.jobs[#sc.jobs + 1] = {kind = "floor", x = sc.cx + dx, y = sc.cy + dy}
                end
            end
        end
    end
    local lo, hi = -GROUND_RADIUS, GROUND_RADIUS + 1
    for _, h in ipairs(WALL_HEIGHTS) do
        for d = -GROUND_RADIUS, GROUND_RADIUS do
            for _, axis in ipairs({"x", "y"}) do
                local row = (axis == "x" and sc.cy or sc.cx) + d
                local base = axis == "x" and sc.cx or sc.cy
                local fixed = (row + 0.5) * 100.0
                for _, flip in ipairs({false, true}) do
                    local from, to = (base + lo) * 100.0, (base + hi) * 100.0
                    if flip then from, to = to, from end
                    sc.jobs[#sc.jobs + 1] = {kind = "wall", axis = axis, row = row, fixed = fixed, z = sc.feet + h,
                        from = from, to = to}
                end
            end
        end
    end
    s.scan = sc
end

local NO_COLOR = {R = 0, G = 0, B = 0, A = 0}

--- First surface from a to b that isn't a character (animatronics, Gregory), or nil.
local CHARACTER = nil
local function is_character(actor)
    if not valid(CHARACTER) then CHARACTER = StaticFindObject("/Script/Engine.Character") end
    return valid(actor) and valid(CHARACTER) and actor:IsA(CHARACTER)
end

local function trace(s, kismet, ax, ay, az, bx, by, bz)
    for _ = 1, 3 do
        local hit = {}
        local ok = kismet:LineTraceSingle(s.pawn,
            {X = ax, Y = ay, Z = az}, {X = bx, Y = by, Z = bz},
            0, false, {s.pawn}, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
        if not ok or not hit.ImpactPoint then return nil end
        local p = hit.ImpactPoint
        local actor = hit.Actor and hit.Actor:Get()
        local ours = valid(actor) and s.boxAddr and s.boxAddr[actor:GetAddress()]
        if not is_character(actor) and not ours then return p end
        -- through the character and on
        local dx, dy, dz = bx - ax, by - ay, bz - az
        local len = math.sqrt(dx * dx + dy * dy + dz * dz)
        if len < 1.0 then return nil end
        local step = 120.0 / len
        ax, ay, az = p.X + dx * step, p.Y + dy * step, p.Z + dz * step
        if (bx - ax) * dx + (by - ay) * dy + (bz - az) * dz <= 0 then return nil end
    end
    return nil
end

--- Floor: straight down through the column's centre.
local function floor_job(s, kismet, job)
    local px, py = (job.x + 0.5) * 100.0, (job.y + 0.5) * 100.0
    local p = trace(s, kismet, px, py, s.scan.z + TRACE_UP, px, py, s.scan.z - TRACE_DOWN)
    if p then s.scan.out[#s.scan.out + 1] = string.format("%d %d %.1f", job.x, job.y, p.Z) end
    return 1
end

--- Walls: a horizontal line across the scan area; every surface it meets marks the cell just behind it.
local function wall_job(s, kismet, job)
    local traces = 0
    local a, b = job.from, job.to
    local dir = b > a and 1.0 or -1.0
    for _ = 1, WALL_HITS do
        local p
        if job.axis == "x" then
            p = trace(s, kismet, a, job.fixed, job.z, b, job.fixed, job.z)
        else
            p = trace(s, kismet, job.fixed, a, job.z, job.fixed, b, job.z)
        end
        traces = traces + 1
        if not p then break end
        local along = job.axis == "x" and p.X or p.Y
        local cell = math.floor((along + dir * 2.0) / 100.0)
        local cx, cy
        if job.axis == "x" then cx, cy = cell, job.row else cx, cy = job.row, cell end
        s.scan.out[#s.scan.out + 1] = string.format("w %d %d %.1f", cx, cy, job.z)
        a = along + dir * 6.0 -- carry on past this surface (from inside a wall the far face isn't hit)
        if (b - a) * dir <= 0 then break end
    end
    return traces
end

local function scan_tick(s)
    if not valid(s.pawn) or not valid(s.root) then return end
    if not valid(s.kismet) then s.kismet = UEHelpers.GetKismetSystemLibrary() end
    if not s.scan then start_scan(s) end
    local sc = s.scan
    local n = 0
    while sc.i <= #sc.jobs and n < TRACES_PER_TICK do
        local job = sc.jobs[sc.i]
        if job.kind == "floor" then
            n = n + floor_job(s, s.kismet, job)
        else
            n = n + wall_job(s, s.kismet, job)
        end
        sc.i = sc.i + 1
    end
    if sc.i > #sc.jobs then
        s.groundSeq = (s.groundSeq or 0) + 1
        write_file("sb_ground.txt", string.format("seq %d\ncenter %d %d %.1f\n", s.groundSeq, sc.cx, sc.cy, sc.z) ..
            table.concat(sc.out, "\n") .. "\n")
        if s.groundSeq == 1 or s.groundSeq % 100 == 0 then
            local walls = 0
            for _, line in ipairs(sc.out) do if line:sub(1, 1) == "w" then walls = walls + 1 end end
            log("ground pass %d: %d floor columns, %d wall cells", s.groundSeq, #sc.out - walls, walls)
        end
        s.scan = nil
    end
end

-- Minecraft's blocks in SB: one invisible blocking box per solid block (sb_blocks.txt from the add-on), so Gregory and
-- the animatronics can't walk through them. Ender pearls: sb_teleport.txt moves Gregory.
local BOX_HALF = 50.0
local MAX_BOXES = 4000

local function read_lines(name)
    local f = io.open(LINK_DIR .. "\\" .. name, "r")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local function step(name, f, ...)
    local ok, r = pcall(f, ...)
    if not ok then error("spawn step " .. name .. ": " .. tostring(r) .. " (" .. type(r) .. ")", 0) end
    return r
end

local function spawn_box(s, x, y, z)
    local world = step("GetWorld", function() return s.pawn:GetWorld() end)
    if not valid(s.boxClass) then s.boxClass = StaticFindObject("/Script/Engine.TriggerBox") end
    if not valid(s.boxClass) then error("no TriggerBox class", 0) end
    local actor = step("SpawnActor", function()
        return world:SpawnActor(s.boxClass, {X = x, Y = y, Z = z}, {Pitch = 0, Yaw = 0, Roll = 0})
    end)
    if not valid(actor) then error("SpawnActor returned nothing", 0) end
    local box = actor.RootComponent
    step("SetBoxExtent", function() box:SetBoxExtent({X = BOX_HALF, Y = BOX_HALF, Z = BOX_HALF}, true) end)
    step("SetCollisionProfileName", function() box:SetCollisionProfileName(FName("BlockAll"), true) end)
    step("SetCollisionEnabled", function() box:SetCollisionEnabled(3) end) -- QueryAndPhysics
    -- solid for bodies (Gregory, animatronics), but transparent to SB's interaction/visibility traces and its camera,
    -- so doors, buttons and pickups behind or next to a block still work
    pcall(function() box:SetCollisionResponseToChannel(3, 0) end) -- ECC_Visibility -> ignore
    pcall(function() box:SetCollisionResponseToChannel(4, 0) end) -- ECC_Camera -> ignore
    pcall(function() actor:SetActorHiddenInGame(true) end) -- TriggerBox draws nothing in game anyway
    return actor
end

local function sync_blocks(s)
    local text = read_lines("sb_blocks.txt")
    if not text then return end
    local seq = tonumber(text:match("^seq (%d+)"))
    if not seq or seq == s.blocksSeq then return end
    s.blocksSeq = seq
    s.boxes = s.boxes or {}
    s.boxAddr = s.boxAddr or {}
    local want = {}
    for x, y, z in text:gmatch("\n(%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)") do
        want[x .. " " .. y .. " " .. z] = {tonumber(x), tonumber(y), tonumber(z)}
    end
    local removed, added = 0, 0
    for key, actor in pairs(s.boxes) do
        if not want[key] then
            if valid(actor) then
                s.boxAddr[actor:GetAddress()] = nil
                actor:K2_DestroyActor()
            end
            s.boxes[key] = nil
            removed = removed + 1
        end
    end
    local count = 0
    for _ in pairs(s.boxes) do count = count + 1 end
    for key, p in pairs(want) do
        if not s.boxes[key] and count < MAX_BOXES then
            local actor = spawn_box(s, p[1], p[2], p[3])
            if actor then
                s.boxes[key] = actor
                s.boxAddr[actor:GetAddress()] = true
                added = added + 1
                count = count + 1
            end
        end
    end
    if added > 0 or removed > 0 then log("blocks %d: +%d -%d, %d boxes in SB", seq, added, removed, count) end
end

local function sync_teleport(s)
    local text = read_lines("sb_teleport.txt")
    if not text then
        if s.teleportSeq == nil then s.teleportSeq = 0 end -- no file yet: the next one is a real pearl
        return
    end
    local seq = tonumber(text:match("^seq (%d+)"))
    if not seq or seq == s.teleportSeq then return end
    local first = s.teleportSeq == nil
    s.teleportSeq = seq
    if first then return end -- a file already there at start (the add-on clears them, but be safe)
    local x, y, z = text:match("feet (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
    if not x or not valid(s.pawn) then return end
    local half = 0.0
    if find_property(s.root:GetClass(), "CapsuleHalfHeight") then half = s.root.CapsuleHalfHeight end
    local ok = s.pawn:K2_SetActorLocation({X = tonumber(x), Y = tonumber(y), Z = tonumber(z) + half + 2.0}, false, {}, true)
    log("ender pearl: Gregory to %s %s %s (%s)", x, y, z, tostring(ok))
    s.scan = nil -- new surroundings
end

-- Actions from Minecraft (sb_actions.txt, "id action args", newest last):
--   melee                 a sword swing: animatronics in front of Gregory (3.5 m, ~70 degrees) are stunned (SB's own stun)
--   explode x y z r       TNT/creeper: animatronics within 2r are stunned; small static props and wall pieces within r
--                         are blown away (hidden, no collision) — never floors, big level chunks or gameplay actors
local MELEE_RANGE = 350.0
local MELEE_STUN = 4.0
local BLAST_STUN = 8.0
local PROP_MAX_EXTENT = 500.0  -- half size: anything bigger is level structure, not a prop/wall piece
local BLAST_MAX = 120          -- mesh pieces per explosion

local function seekers()
    local list = {}
    for _, cname in ipairs({"AISeeker_C", "StaffBotBase_C"}) do
        for _, a in ipairs(FindAllOf(cname) or {}) do
            if valid(a) then list[#list + 1] = a end
        end
    end
    return list
end

local function stun(a, seconds)
    local ok, can = pcall(function() return a:CanBeStunned() end)
    if ok and can == false then return false end
    local okS = pcall(function() a:StunForDuration(seconds) end)
    if not okS then okS = pcall(function() a:Stun() end) end
    return okS
end

local function melee(s)
    if not valid(s.pawn) then return end
    local pc = UEHelpers.GetPlayerController()
    local pcm = pc.PlayerCameraManager
    local cam, rot = pcm:GetCameraLocation(), pcm:GetCameraRotation()
    local yaw, pitch = math.rad(rot.Yaw), math.rad(rot.Pitch)
    local fx, fy, fz = math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), math.sin(pitch)
    local hits = {}
    for _, a in ipairs(seekers()) do
        local l = a.RootComponent.RelativeLocation
        local dx, dy, dz = l.X - cam.X, l.Y - cam.Y, l.Z - cam.Z
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        if d < MELEE_RANGE and d > 1 and (dx * fx + dy * fy + dz * fz) / d > 0.35 then
            if stun(a, MELEE_STUN) then hits[#hits + 1] = a:GetClass():GetFName():ToString() end
        end
    end
    log("sword: %d stunned %s", #hits, table.concat(hits, " "))
end

local function explode(s, x, y, z, r)
    local stunned = 0
    for _, a in ipairs(seekers()) do
        local l = a.RootComponent.RelativeLocation
        local dx, dy, dz = l.X - x, l.Y - y, l.Z - z
        if dx * dx + dy * dy + dz * dz < (2 * r) * (2 * r) and stun(a, BLAST_STUN) then stunned = stunned + 1 end
    end
    s.destroyed = s.destroyed or {}
    local gone, looked = 0, 0
    for _, c in ipairs(FindAllOf("StaticMeshComponent") or {}) do
        if gone >= BLAST_MAX then break end
        local okl, l = pcall(function() return c:K2_GetComponentLocation() end)
        if okl and l and math.abs(l.X - x) < r + 1000 and math.abs(l.Y - y) < r + 1000 and math.abs(l.Z - z) < r + 1000 then
            local owner = c:GetOwner()
            local oname = valid(owner) and owner:GetClass():GetFName():ToString() or ""
            local skip = not valid(owner) or (s.boxAddr and s.boxAddr[owner:GetAddress()]) or is_character(owner)
                or oname:find("Door") or oname:find("Gate") or oname:find("Save") or oname:find("Elevator")
                or oname:find("Lift") or oname:find("Vent") or oname:find("Pickup") or oname:find("Interact")
            if not skip and c:IsVisible() then
                looked = looked + 1
                local mn, mx = {}, {}
                local okb = pcall(function() c:GetLocalBounds(mn, mx) end)
                local sc = c:K2_GetComponentScale()
                if okb and mn.X and mx.X then
                    -- world box, ignoring rotation (horizontal extents take the larger of the two)
                    local ex = (mx.X - mn.X) * 0.5 * math.abs(sc.X)
                    local ey = (mx.Y - mn.Y) * 0.5 * math.abs(sc.Y)
                    local ez = (mx.Z - mn.Z) * 0.5 * math.abs(sc.Z)
                    local eh = math.max(ex, ey)
                    local ox = l.X + (mx.X + mn.X) * 0.5 * sc.X
                    local oy = l.Y + (mx.Y + mn.Y) * 0.5 * sc.Y
                    local oz = l.Z + (mx.Z + mn.Z) * 0.5 * sc.Z
                    local cx = math.max(ox - eh, math.min(x, ox + eh))
                    local cy = math.max(oy - eh, math.min(y, oy + eh))
                    local cz = math.max(oz - ez, math.min(z, oz + ez))
                    local d2 = (cx - x) ^ 2 + (cy - y) ^ 2 + (cz - z) ^ 2
                    local big = math.max(eh, ez) > PROP_MAX_EXTENT
                    local top, bottom = oz + ez, oz - ez
                    local floorZ = z - 50.0                               -- TNT sits half a block above its floor
                    -- anything reaching below the floor may *be* the floor (hallway modules include theirs): keep it
                    local below = bottom < floorZ - 40.0
                    local slab = ez < 30.0 and top < z + 40.0 and eh > ez -- thin and flat at the blast's feet: floor
                    if s.blastDebug then
                        log("  piece %s/%s ext %.0f %.0f top %.0f dist %.0f big %s below %s slab %s", oname,
                            c:GetFName():ToString(), eh, ez, top, math.sqrt(d2), tostring(big), tostring(below), tostring(slab))
                    end
                    if d2 < r * r and not big and not below and not slab then
                        local prev = 1
                        pcall(function() prev = c:GetCollisionEnabled() end)
                        c:SetHiddenInGame(true, false)
                        c:SetCollisionEnabled(0)
                        s.destroyed[#s.destroyed + 1] = {c, prev}
                        gone = gone + 1
                    end
                end
            end
        end
    end
    log("boom at %.0f %.0f %.0f r %.0f: %d animatronics stunned, %d/%d pieces blown away", x, y, z, r, stunned, gone, looked)
    s.scan = nil -- the walls changed: rescan (the add-on rebuilds Minecraft's barriers from it)
end

local function restore(s)
    local n = 0
    for _, d in ipairs(s.destroyed or {}) do
        local c, prev = d[1], d[2]
        if valid(c) then
            c:SetHiddenInGame(false, false)
            c:SetCollisionEnabled(type(prev) == "number" and prev or 3)
            n = n + 1
        end
    end
    s.destroyed = {}
    s.scan = nil
    log("restored %d blown-away pieces", n)
end

local function sync_actions(s)
    local text = read_lines("sb_actions.txt")
    if not text then
        if s.actionId == nil then s.actionId = 0 end -- no file yet: everything that comes is new
        return
    end
    local newest = 0
    for id in text:gmatch("(%d+) [^\n]*") do newest = math.max(newest, tonumber(id)) end
    if s.actionId == nil or newest < s.actionId then
        s.actionId = newest -- first look (or the add-on restarted): don't replay old actions
        return
    end
    for idText, action, args in text:gmatch("(%d+) (%a+) ?([^\n]*)") do
        local id = tonumber(idText)
        if id > s.actionId then
            s.actionId = id
            if action == "melee" then
                local ok, err = pcall(melee, s)
                if not ok then log("sword failed: %s", tostring(err)) end
            elseif action == "explode" then
                local x, y, z, r = args:match("(%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
                if x then
                    local ok, err = pcall(explode, s, tonumber(x), tonumber(y), tonumber(z), tonumber(r))
                    if not ok then log("explosion failed: %s", tostring(err)) end
                end
            end
        end
    end
end

local function read_commands(s)
    local path = LINK_DIR .. "\\sb_cmd.txt"
    local f = io.open(path, "r")
    if not f then return end
    local text = f:read("*a")
    f:close()
    os.remove(path)
    for line in text:gmatch("[^\r\n]+") do
        log("command: %s", line)
        if line == "rescan" then s.scan = nil end
        if line == "relink" then s.offsets = nil; s.linkKey = nil end
        if line == "restore" then restore(s) end
        if line == "blastdebug" then s.blastDebug = not s.blastDebug end
        if line == "meshcount" then
            local t0 = os.clock()
            local list = FindAllOf("StaticMeshComponent") or {}
            local t1 = os.clock()
            local owners = {}
            local near = 0
            local ploc = s.root.RelativeLocation
            for i, c in ipairs(list) do
                if i <= 20000 then
                    local okl, l = pcall(function() return c:K2_GetComponentLocation() end)
                    if okl and l and math.abs(l.X - ploc.X) < 1500 and math.abs(l.Y - ploc.Y) < 1500 then
                        near = near + 1
                        local o = c:GetOwner()
                        local n = valid(o) and o:GetClass():GetFName():ToString() or "?"
                        owners[n] = (owners[n] or 0) + 1
                    end
                end
            end
            local t2 = os.clock()
            local top = {}
            for n, k in pairs(owners) do top[#top + 1] = {n, k} end
            table.sort(top, function(a, b) return a[2] > b[2] end)
            local parts = {}
            for i = 1, math.min(15, #top) do parts[#parts + 1] = top[i][1] .. "=" .. top[i][2] end
            log("meshcount: %d components (find %.0f ms, locate %.0f ms), %d within 15 m: %s", #list, (t1 - t0) * 1000,
                (t2 - t1) * 1000, near, table.concat(parts, " "))
        end
        if line == "boundsprobe" then
            local a = FindFirstOf("StaticMeshActor")
            local function show(v)
                if type(v) ~= "table" and type(v) ~= "userdata" then return tostring(v) end
                local okx, x = pcall(function() return v.X end)
                return type(v) .. (okx and (" X=" .. tostring(x)) or "")
            end
            local o, e = {}, {}
            local ok, r1, r2, r3 = pcall(function() return a:GetActorBounds(true, o, e, false) end)
            log("bounds A ok=%s r=%s %s %s o=%s e=%s", tostring(ok), show(r1), show(r2), show(r3), show(o), show(e))
            local o2, e2 = {X = 0, Y = 0, Z = 0}, {X = 0, Y = 0, Z = 0}
            ok, r1 = pcall(function() return a:GetActorBounds(false, o2, e2) end)
            log("bounds B ok=%s r=%s o=%s e=%s", tostring(ok), show(r1), show(o2), show(e2))
            local mesh = a.StaticMeshComponent
            ok, r1 = pcall(function() local mn, mx = {}, {} mesh:GetLocalBounds(mn, mx) return show(mn) .. " / " .. show(mx) end)
            log("localbounds ok=%s %s", tostring(ok), tostring(r1))
        end
        if line == "stuntest" then
            local e = FindFirstOf("Endo_C")
            if valid(e) then
                local function try(name, f)
                    local ok, r = pcall(f)
                    local rs = tostring(r)
                    if type(r) == "table" then local t = {} for k, v in pairs(r) do t[#t + 1] = tostring(k) .. "=" .. tostring(v) end rs = "{" .. table.concat(t, ",") .. "}" end
                    log("stuntest %s: ok=%s r=%s (%s)", name, tostring(ok), rs, type(r))
                end
                try("CanBeStunned()", function() return e:CanBeStunned() end)
                try("CanBeStunned({})", function() local o = {} e:CanBeStunned(o) return o end)
                try("IsStunned()", function() return e:IsStunned() end)
                try("StunForDuration(4)", function() return e:StunForDuration(4.0) end)
                try("IsStunned() after", function() return e:IsStunned() end)
            end
        end
        if line == "stunsig" then
            for _, cname in ipairs({"MontyStandard_C", "Endo_C", "StaffBotBase_C"}) do
                local c = FindFirstOf(cname)
                if valid(c) then
                    local k = c:GetClass()
                    while valid(k) and k:GetFName():ToString() ~= "Character" do
                        k:ForEachFunction(function(f)
                            local n = f:GetFName():ToString()
                            if n == "Stun" or n == "StunForDuration" or n == "CanBeStunned" or n == "Unstun" or n == "IsStunned" then
                                local params = {}
                                local okp, errp = pcall(function()
                                    f:ForEachProperty(function(pr)
                                        local t = "?"
                                        pcall(function() t = pr:GetClass():GetFName():ToString() end)
                                        params[#params + 1] = pr:GetFName():ToString() .. ":" .. t
                                    end)
                                end)
                                if not okp then params[#params + 1] = "(no params: " .. type(errp) .. ")" end
                                log("sig %s.%s (%s): %s", cname, n, k:GetFName():ToString(), table.concat(params, ", "))
                            end
                        end)
                        k = k:GetSuperStruct()
                    end
                end
            end
        end
        if line == "chars" then
            -- recon: every character in the level, and its class's functions about stunning
            for _, c in ipairs(FindAllOf("Character") or {}) do
                if valid(c) then
                    local cls = c:GetClass()
                    local l = c.RootComponent.RelativeLocation
                    local fns = {}
                    local k = cls
                    while valid(k) do
                        local name = k:GetFName():ToString()
                        if name == "Character" then break end
                        k:ForEachFunction(function(f)
                            local n = f:GetFName():ToString()
                            local ln = n:lower()
                            if ln:find("stun") or ln:find("shock") or ln:find("disable") or ln:find("flash") then fns[#fns + 1] = n end
                        end)
                        k = k:GetSuperStruct()
                    end
                    log("char %s at %.0f %.0f %.0f: %s", cls:GetFullName(), l.X, l.Y, l.Z, table.concat(fns, " "))
                end
            end
        end
        local ux, uy, uz = line:match("^unbox (%-?[%d%.]+) (%-?[%d%.]+) (%-?[%d%.]+)")
        if ux then
            -- remove stray boxes of ours at exactly this spot (never SB's own trigger boxes: those are elsewhere and
            -- keep their overlap-only profile)
            local n = 0
            for _, a in ipairs(FindAllOf("TriggerBox") or {}) do
                local l = a.RootComponent.RelativeLocation
                if math.abs(l.X - tonumber(ux)) < 1 and math.abs(l.Y - tonumber(uy)) < 1 and math.abs(l.Z - tonumber(uz)) < 1 then
                    a:K2_DestroyActor()
                    n = n + 1
                end
            end
            log("unbox: removed %d", n)
        end
        if line == "probe" and valid(s.pawn) then
            -- what's straight ahead of Gregory's eyes (4 m), including our own boxes
            local pc = UEHelpers.GetPlayerController()
            local cam, rot = pc.PlayerCameraManager:GetCameraLocation(), pc.PlayerCameraManager:GetCameraRotation()
            local yaw = math.rad(rot.Yaw)
            local hit = {}
            local ok = s.kismet:LineTraceSingle(s.pawn, cam,
                {X = cam.X + 400 * math.cos(yaw), Y = cam.Y + 400 * math.sin(yaw), Z = cam.Z - 40},
                0, false, {s.pawn}, 0, hit, true, NO_COLOR, NO_COLOR, 0.0)
            local actor = ok and hit.Actor and hit.Actor:Get()
            log("probe: hit %s at %.0f cm: %s", tostring(ok), ok and hit.Distance or -1,
                valid(actor) and actor:GetFullName() or "nothing")
        end
    end
end

function M.init(s)
    s.scan = nil
    s.offsets = nil
    s.linkKey = nil
    s.elapsed = 1000
    local f, err = io.open(LINK_DIR .. "\\sb_writetest.txt", "w")
    if f then f:write("ok\n") f:close() end
    log("logic init, link dir %s (write test: %s)", LINK_DIR, f and "ok" or tostring(err))
end

function M.tick(s, dt)
    s.elapsed = (s.elapsed or 0) + dt
    if s.elapsed >= 1000 then
        s.elapsed = 0
        local ok, err = pcall(refresh_link, s)
        if not ok then
            s.linkErrors = (s.linkErrors or 0) + 1
            if s.linkErrors < 10 or s.linkErrors % 60 == 0 then log("link refresh failed: %s", tostring(err)) end
        end
        local okc, errc = pcall(read_commands, s)
        if not okc then log("command failed: %s", tostring(errc)) end
    end
    s.syncElapsed = (s.syncElapsed or 0) + dt
    if s.syncElapsed >= 200 and valid(s.pawn) then
        s.syncElapsed = 0
        s.boxAddr = s.boxAddr or {}
        local okb, errb = pcall(sync_blocks, s)
        if not okb then
            s.blockErrors = (s.blockErrors or 0) + 1
            if s.blockErrors < 10 then log("block sync failed: %s", tostring(errb)) end
        end
        local okt, errt = xpcall(sync_teleport, debug.traceback, s)
        if not okt then log("teleport failed: %s", tostring(errt)) end
        local oka, erra = pcall(sync_actions, s)
        if not oka then log("actions failed: %s", tostring(erra)) end
    end
    local ok, err = xpcall(scan_tick, debug.traceback, s)
    if not ok then
        s.scanErrors = (s.scanErrors or 0) + 1
        if s.scanErrors < 10 or s.scanErrors % 200 == 0 then log("ground scan failed: %s", tostring(err)) end
        s.scan = nil
    end
end

return M
