-- SBCraft loader: runs the logic in sbcraft.lua and reloads it whenever the file changes (no SB restart while
-- developing). The logic is read from SBCRAFT_LOGIC, else from a dev checkout at DEV_LOGIC if there is one, else from
-- this mod's own folder (where install.sh puts it).
local DEV_LOGIC = os.getenv("SBCRAFT_DEV_LOGIC") or "C:\\fnafsbxmc\\sb\\lua\\sbcraft.lua"
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
local TICK_MS = 50

local function read(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local text = f:read("*a")
    f:close()
    return text
end

local logicPath = os.getenv("SBCRAFT_LOGIC")
if not logicPath then
    logicPath = read(DEV_LOGIC) and DEV_LOGIC or (here .. "sbcraft.lua")
end

local state = {}      -- survives reloads
local module = nil
local loadedText = nil
local sinceCheck = 1000

local function reload()
    local text = read(logicPath)
    if not text or text == loadedText then return end
    loadedText = text
    local chunk, err = load(text, "@" .. logicPath)
    if not chunk then
        print("[SBCraft] logic does not compile: " .. tostring(err) .. "\n")
        return
    end
    local ok, m = pcall(chunk)
    if not ok or type(m) ~= "table" then
        print("[SBCraft] logic failed to load: " .. tostring(m) .. "\n")
        return
    end
    module = m
    if module.init then
        local ok2, err2 = pcall(module.init, state)
        if not ok2 then print("[SBCraft] init failed: " .. tostring(err2) .. "\n") end
    end
    print("[SBCraft] logic loaded from " .. logicPath .. "\n")
end

LoopAsync(TICK_MS, function()
    ExecuteInGameThread(function()
        sinceCheck = sinceCheck + TICK_MS
        if sinceCheck >= 1000 then
            sinceCheck = 0
            reload()
        end
        if module and module.tick then
            local ok, err = pcall(module.tick, state, TICK_MS)
            if not ok then
                state.errors = (state.errors or 0) + 1
                if state.errors < 20 or state.errors % 200 == 0 then
                    print("[SBCraft] tick error: " .. tostring(err) .. "\n")
                end
            end
        end
    end)
    return false
end)
print("[SBCraft] loader up, logic " .. logicPath .. "\n")
