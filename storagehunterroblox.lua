-- [[
--    Storage Hunters: Open World - Refactored Script (Astralux UI)
--    Deobfuscated & Cleaned by Antigravity
--    Original generated at discord.gg/25ms
-- ]]

-- =============================================================================
-- SERVICES & UTILS
-- =============================================================================
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local Workspace = game:GetService('Workspace')
local CoreGui = game:GetService('CoreGui')

local LocalPlayer = Players.LocalPlayer

-- =============================================================================
-- CLEANUP OF PREVIOUS EXECUTION (Self-Destruct / Re-run Safety)
-- =============================================================================
local function cleanupUI()
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    local targets = {CoreGui, playerGui}
    for _, parent in ipairs(targets) do
        if parent then
            -- Cari dan hapus UI Astralux lama
            local oldGui = parent:FindFirstChild("Astralux")
            if oldGui then
                pcall(function() oldGui:Destroy() end)
            end
        end
    end
end

-- Jika ada fungsi pembersihan dari eksekusi sebelumnya, jalankan sekarang
if getgenv().StorageHuntersScriptCleanUp then
    pcall(getgenv().StorageHuntersScriptCleanUp)
end

-- =============================================================================
-- STATE & SETTINGS
-- =============================================================================
local AutoAcceptOffers = false
local MinAcceptPercent = 15
local AutoPlaceEnabled = false
local AutoBid = false
local MaxBid = 0
local MinBid = 0
local AutoCollect = false

-- Auto Sell State
local AutoSellEnabled = false
local MinSellRate = -15
local MinWeight = 20
local SaveTrophies = true
local SaveAccessories = true
local CurrentWeight = 0
local CurrentRate = 1.0
local SellCooldown = 0
local SellSyncing = false

-- Pathfinder State
local PathfinderEnabled = false
local PathfinderPhase = "Idle"
local PathfinderStatus = "Waiting for activation"
local PathfinderRunning = false
local State_itemsAvailable = false
local AreaToggles = {
    ["Junk Yard"] = true,
    ["Back Alley"] = true,
    ["Farmyard"] = true,
    ["Shipyard"] = true
}

local ItemsModule = (function()
    local ok, result = pcall(function()
        return require(ReplicatedStorage.Modules.Items)
    end)
    if ok then return result end
    return {}
end)()

local AREA_GARAGES = {
    ["Junk Yard"] = { "Scrap Garage" },
    ["Back Alley"] = { "Shop Front" },
    ["Farmyard"] = { "Stable Garage", "Barn Garage" },
    ["Shipyard"] = { "Small Container Garage", "Large Container Garage", "Warehouse Garage" }
}

-- State lelang tambahan
local ignoredAuctionUnits = {}
local currentAuctionUnit = nil

-- Variabel global remote game (akan diisi secara independen di background)
local PlaceStockItem = nil
local GetPlayerInventory = nil
local TransferVehicleItemsToInventory = nil
local BidEvent = nil
local GetShopStock = nil

local GetPawnState = nil
local GetSellableItems = nil
local SellItems = nil
local RateChanged = nil
local VehicleWeightUpdate = nil
local AuctionPickupStart = nil
local AuctionPickupEnd = nil
local LeaveAuctionRemote = nil

-- List untuk melacak koneksi event aktif agar bisa di-disconnect saat re-execute
local activeConnections = {}

local function registerConnection(connection)
    table.insert(activeConnections, connection)
    return connection
end

-- Daftarkan fungsi pembersihan baru untuk eksekusi saat ini
getgenv().StorageHuntersScriptCleanUp = function()
    -- Matikan semua flag loop agar thread background berhenti secara natural
    AutoAcceptOffers = false
    AutoPlaceEnabled = false
    AutoBid = false
    AutoCollect = false
    AutoSellEnabled = false
    PathfinderEnabled = false
    PathfinderRunning = false
    
    -- Putuskan semua koneksi event
    for _, conn in ipairs(activeConnections) do
        if conn and conn.Connected then
            pcall(function() conn:Disconnect() end)
        end
    end
    table.clear(activeConnections)
    
    -- Hapus UI
    cleanupUI()
end

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Helper to get player Character Root Part
local function getRoot()
    local char = LocalPlayer.Character
    if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    return root
end

-- Helper to get player Humanoid
local function getHumanoid()
    local char = LocalPlayer.Character
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

-- Find nearest EnterAuction proximity prompt
local function findNearestAuction()
    local root = getRoot()
    if not root then return nil end
    
    local rootPos = root.Position
    local bestDist = math.huge
    local bestPrompt = nil
    
    for _, prompt in ipairs(Workspace:GetDescendants()) do
        if prompt:IsA("ProximityPrompt") and prompt.Name == "EnterAuction" then
            local garageType = prompt.ObjectText
            local areaMatch = false
            local areaName = nil
            for area, garages in pairs(AREA_GARAGES) do
                if AreaToggles[area] then
                    for _, g in ipairs(garages) do
                        if g == garageType then
                            areaMatch = true
                            areaName = area
                            break
                        end
                    end
                end
                if areaMatch then break end
            end
            
            if areaMatch then
                local promptParent = prompt.Parent
                if promptParent then
                    local dist = (promptParent.Position - rootPos).Magnitude
                    if dist < bestDist then
                        bestDist = dist
                        bestPrompt = {
                            prompt = prompt,
                            promptParent = promptParent,
                            position = promptParent.Position,
                            garageType = garageType,
                            areaName = areaName,
                            distance = dist
                        }
                    end
                end
            end
        end
    end
    
    return bestPrompt
end

-- Walk to a target position using PathfindingService
local function walkTo(targetPos, timeoutSeconds)
    local hum = getHumanoid()
    local root = getRoot()
    if not hum or not root then
        task.wait(1)
        return false
    end
    
    local startTime = tick()
    while tick() - startTime < (timeoutSeconds or 30) do
        root = getRoot()
        hum = getHumanoid()
        if not root or not hum then
            return false
        end
        
        local dist = (root.Position - targetPos).Magnitude
        if dist < 5 then
            hum:MoveTo(targetPos)
            return true
        end
        
        local pathParams = {
            AgentRadius = 2,
            AgentHeight = 5,
            AgentCanJump = true,
            AgentMaxSlope = 45,
            WaypointSpacing = 4
        }
        local ok, path = pcall(function()
            local p = game:GetService("PathfindingService"):CreatePath(pathParams)
            p:ComputeAsync(root.Position, targetPos)
            return p
        end)
        
        if ok and path and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            hum:MoveTo(waypoints[#waypoints].Position)
            
            for _, wp in ipairs(waypoints) do
                if tick() - startTime >= (timeoutSeconds or 30) then
                    hum:MoveTo(root.Position)
                    return false
                end
                
                if wp.Action == Enum.PathWaypointAction.Jump then
                    hum.Jump = true
                end
                
                hum:MoveTo(wp.Position)
                repeat
                    task.wait(0.1)
                    root = getRoot()
                    if not root then
                        hum:MoveTo(root and root.Position or Vector3.new())
                        return false
                    end
                until (root.Position - wp.Position).Magnitude < 5 or not hum
            end
        else
            hum:MoveTo(targetPos)
            task.wait(1)
        end
        
        root = getRoot()
        if root and (root.Position - targetPos).Magnitude < 5 then
            hum:MoveTo(targetPos)
            return true
        end
    end
    
    return false
end

-- Find ProximityPrompts of a specific name within a radius
local function findPromptsNear(centerPos, radius, promptName)
    local results = {}
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("ProximityPrompt") and desc.Name == promptName then
            local parentPart = desc.Parent
            if parentPart and parentPart:IsA("BasePart") then
                local dist = (parentPart.Position - centerPos).Magnitude
                if dist <= radius then
                    table.insert(results, {
                        prompt = desc,
                        part = parentPart,
                        position = parentPart.Position,
                        distance = dist
                    })
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.distance < b.distance end)
    return results
end

-- Trigger ProximityPrompt instantly
local function triggerPrompt(prompt)
    local ok = pcall(function()
        fireproximityprompt(prompt)
    end)
    task.wait(0.1)
    return ok
end

-- Safely call remote events or functions without causing execution halts
local function safeCallRemote(remote, ...)
    if not remote then return false, "Remote not found" end
    local args = {...}
    if remote:IsA("RemoteEvent") then
        local status, err = pcall(function()
            remote:FireServer(unpack(args))
        end)
        return status, err
    elseif remote:IsA("RemoteFunction") then
        local status, result = pcall(function()
            return remote:InvokeServer(unpack(args))
        end)
        return status, result
    end
    return false, "Invalid remote type"
end

-- Get the player's current vehicle (seated or owned in workspace)
-- Find the highest Model ancestor below Workspace
local function getTopLevelModel(instance)
    if not instance then return nil end
    local current = instance
    local lastModel = nil
    while current and current ~= Workspace do
        if current:IsA("Model") then
            lastModel = current
        end
        current = current.Parent
    end
    return lastModel
end

-- Get the player's current vehicle (seated or owned in workspace)
local function getMyVehicle()
    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass('Humanoid')
    
    -- Prioritas 1: Kendaraan tempat pemain sedang duduk
    if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA('VehicleSeat') then
        return getTopLevelModel(humanoid.SeatPart)
    end
    
    -- Prioritas 2: Cari di Workspace secara mendalam berdasarkan atribut OwnerUserId
    local plotsFolder = Workspace:FindFirstChild("_Plots")
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            local isPlot = false
            if plotsFolder and obj:IsDescendantOf(plotsFolder) then
                isPlot = true
            end
            if obj.Name:lower():find("plot") then
                isPlot = true
            end
            
            if not isPlot then
                if obj:FindFirstChildWhichIsA("VehicleSeat", true) then
                    return obj
                end
            end
        end
    end
    return nil
end

-- Teleport utility supporting vehicle teleportation if seated
local function teleportTo(destinationCFrame)
    local vehicle = getMyVehicle()
    if vehicle then
        print("[Teleport] Teleporting vehicle: " .. tostring(vehicle))
        -- Stabilisasi fisika sebelum teleportasi untuk menghindari snapback/glitch
        local root = vehicle.PrimaryPart or vehicle:FindFirstChildWhichIsA("BasePart", true)
        if root then
            local wasAnchored = root.Anchored
            root.Anchored = true
            local success, err = pcall(function()
                vehicle:PivotTo(destinationCFrame)
            end)
            if not success then warn("[Teleport] Vehicle PivotTo failed: " .. tostring(err)) end
            
            -- Pindahkan wait ke luar pcall (di task.spawn) agar aman dari batas yield C-call boundary di executor tertentu
            task.spawn(function()
                task.wait(0.15)
                root.Anchored = wasAnchored
            end)
        else
            pcall(function()
                vehicle:PivotTo(destinationCFrame)
            end)
        end
        return
    end
    
    -- Standalone character teleport
    local character = LocalPlayer.Character
    if character then
        print("[Teleport] Teleporting character")
        local success, err = pcall(function()
            character:PivotTo(destinationCFrame)
        end)
        if not success then warn("[Teleport] Character PivotTo failed: " .. tostring(err)) end
    else
        warn("[Teleport] Character not found!")
    end
end

-- Find a location in workspace by name
local function findLocationByName(name)
    local areas = Workspace:FindFirstChild("Areas")
    if areas then
        local found = areas:FindFirstChild(name, true)
        if found and (found:IsA("BasePart") or found:IsA("Model")) then return found end
    end
    
    local shops = Workspace:FindFirstChild("Shops")
    if shops then
        local found = shops:FindFirstChild(name, true)
        if found and (found:IsA("BasePart") or found:IsA("Model")) then return found end
    end
    
    -- Global fallback search
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if (desc:IsA("BasePart") or desc:IsA("Model")) and desc.Name:lower():find(name:lower()) then
            return desc
        end
    end
    return nil
end

-- Find local player's plot
local function getMyPlot()
    -- Coba cari di _Plots
    local plots = Workspace:FindFirstChild("_Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            if plot:GetAttribute('OwnerUserId') == LocalPlayer.UserId then
                return plot
            end
        end
    end
    
    -- Coba cari langsung di Workspace (Plot direct child)
    for _, obj in ipairs(Workspace:GetChildren()) do
        if obj:GetAttribute('OwnerUserId') == LocalPlayer.UserId and not obj:FindFirstChildWhichIsA("VehicleSeat", true) then
            return obj
        end
    end
    return nil
end

-- Fallback to search player inventory in local folders if remote call fails
local function getLocalInventory()
    local invFolders = {
        LocalPlayer.Character,
        LocalPlayer:FindFirstChild("Backpack"),
        LocalPlayer:FindFirstChild("Inventory"),
        LocalPlayer:FindFirstChild("PlayerGui") and LocalPlayer.PlayerGui:FindFirstChild("Inventory")
    }
    for _, folder in ipairs(invFolders) do
        if folder then
            local list = {}
            for _, child in ipairs(folder:GetChildren()) do
                list[child.Name] = { Id = child.Name, Name = child.Name, UID = child:GetAttribute("UID") or child.Name }
            end
            return list
        end
    end
    return nil
end

-- =============================================================================
-- USER INTERFACE INITIALIZATION (Astralux UI)
-- =============================================================================
local Library
local success, err = pcall(function()
    -- Coba muat secara online dari GitHub raw Anda
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/DylIDZ/ahahah/refs/heads/main/AstraluxLib.lua"))()
end)

if success and type(err) == "table" then
    Library = err
else
    -- Fallback lokal jika belum diupload atau sedang offline
    local status, localLib = pcall(function()
        return loadstring(readfile("AstraluxLib.lua"))()
    end)
    if status and localLib then
        Library = localLib
    end
end

if not Library then
    error("Gagal memuat Astralux UI Library!")
end

print("[Storage Hunters] Library terisi: " .. tostring(Library))

-- Create Main Window
local Window = Library:Window({
    Title = "Storage Hunters by Astralux",
    Desc = "Open World",
    Icon = 105059922903197,
    Theme = "Dark", 
    Config = {
        Keybind = Enum.KeyCode.LeftControl,
        Size = UDim2.new(0, 580, 0, 460)
    },
    CloseUIButton = {
        Enabled = true,
        Text = "Astralux"
    }
})

-- Create Tabs
local AuctionTab = Window:Tab({Title = "Auction", Icon = "star"})
local TeleportTab = Window:Tab({Title = "Teleport", Icon = "map"})
local CollectTab = Window:Tab({Title = "Collect", Icon = "briefcase"})
local PathfinderTab = Window:Tab({Title = "Pathfinder", Icon = "map"})

-- -----------------------------------------------------------------------------
-- Collect Tab Elements
-- -----------------------------------------------------------------------------
CollectTab:Section({ Title = "Offers & Plot" })

CollectTab:Toggle({
    Title = 'Auto-Accept Offers',
    Desc = 'Otomatis menerima penawaran shopper NPC',
    Value = false,
    Callback = function(state)
        AutoAcceptOffers = state
        print("[Settings] AutoAcceptOffers set to: " .. tostring(state))
    end,
})

CollectTab:Textbox({
    Title = 'Min Accept %',
    Desc = 'Persentase minimal keuntungan tawaran yang diterima',
    Value = '15',
    Placeholder = '15',
    ClearText = false,
    Callback = function(value)
        local num = tonumber(value)
        if num then
            MinAcceptPercent = num
            print("[Settings] MinAcceptPercent set to: " .. tostring(num))
        else
            warn('Min Accept %: invalid number entered')
        end
    end,
})

-- Forward declaration of loop function
local startAutoPlaceLoop

CollectTab:Toggle({
    Title = 'Auto Place Items',
    Desc = 'Otomatis meletakkan item dari inventori ke plot Anda',
    Value = false,
    Callback = function(state)
        AutoPlaceEnabled = state
        print("[Settings] AutoPlaceEnabled set to: " .. tostring(state))
        if state then
            startAutoPlaceLoop()
        end
    end,
})

CollectTab:Button({
    Title = 'Copy Diagnostics Info',
    Desc = 'Jalankan diagnostik Auto-Place dan salin hasilnya ke clipboard',
    Callback = function()
        local logLines = {}
        local function logPrint(str)
            print(str)
            table.insert(logLines, str)
        end
        
        logPrint("=== STORAGE HUNTERS DIAGNOSTICS START ===")
        logPrint("Player Name: " .. LocalPlayer.Name)
        logPrint("Player UserId: " .. tostring(LocalPlayer.UserId))
        
        -- 1. DIAGNOSE PLOTS
        logPrint("\n--- 1. Plots Diagnostic ---")
        local plots = Workspace:FindFirstChild("_Plots")
        if plots then
            logPrint("Found '_Plots' folder in Workspace.")
            for _, plot in ipairs(plots:GetChildren()) do
                local ownerAttr = plot:GetAttribute("OwnerUserId")
                logPrint(string.format("  Plot: %s | OwnerUserId Attribute: %s (Type: %s)", 
                    plot.Name, tostring(ownerAttr), typeof(ownerAttr)))
                
                local attrs = plot:GetAttributes()
                for k, v in pairs(attrs) do
                    logPrint(string.format("    Attribute -> %s: %s (%s)", k, tostring(v), typeof(v)))
                end
                
                for _, child in ipairs(plot:GetChildren()) do
                    if child.Name:lower():find("owner") then
                        local valSuccess, val = pcall(function() return child.Value end)
                        logPrint(string.format("    Found Owner object: %s (Class: %s, Value: %s)", 
                            child.Name, child.ClassName, tostring(valSuccess and val or "N/A")))
                    end
                end
            end
        else
            logPrint("WARNING: '_Plots' folder NOT found in Workspace!")
            for _, obj in ipairs(Workspace:GetChildren()) do
                local ownerAttr = obj:GetAttribute("OwnerUserId")
                if ownerAttr then
                    logPrint(string.format("  Found object with OwnerUserId: %s | Value: %s", obj.Name, tostring(ownerAttr)))
                end
            end
        end
        
        -- 2. DIAGNOSE REMOTES
        logPrint("\n--- 2. Remotes Diagnostic ---")
        local events = ReplicatedStorage:FindFirstChild("Events")
        if events then
            logPrint("Found 'Events' folder in ReplicatedStorage.")
            
            local inventoryFolder = events:FindFirstChild("Inventory")
            if inventoryFolder then
                local getPlayerInv = inventoryFolder:FindFirstChild("GetPlayerInventory")
                if getPlayerInv then
                    logPrint(string.format("Found GetPlayerInventory Remote! ClassName: %s", getPlayerInv.ClassName))
                else
                    logPrint("ERROR: GetPlayerInventory remote NOT found in Events.Inventory!")
                end
            else
                logPrint("ERROR: Inventory folder NOT found in Events!")
            end
            
            local plotFolder = events:FindFirstChild("Plot")
            if plotFolder then
                local placeStock = plotFolder:FindFirstChild("PlaceStockItem")
                if placeStock then
                    logPrint(string.format("Found PlaceStockItem Remote! ClassName: %s", placeStock.ClassName))
                else
                    logPrint("ERROR: PlaceStockItem remote NOT found in Events.Plot!")
                end
            else
                logPrint("ERROR: Plot folder NOT found in Events!")
            end
        else
            logPrint("ERROR: 'Events' folder NOT found in ReplicatedStorage!")
        end
        
        -- 3. DIAGNOSE INVENTORY DATA
        logPrint("\n--- 3. Inventory Diagnostic ---")
        local inventory = nil
        local getPlayerInv = events and events:FindFirstChild("Inventory") and events.Inventory:FindFirstChild("GetPlayerInventory")
        
        if getPlayerInv then
            if getPlayerInv:IsA("RemoteFunction") then
                local success, result = pcall(function()
                    return getPlayerInv:InvokeServer()
                end)
                
                logPrint("GetPlayerInventory:InvokeServer() call status: " .. tostring(success))
                if success then
                    logPrint("Returned data type: " .. typeof(result))
                    if typeof(result) == "table" then
                        inventory = result
                        local jsonSuccess, jsonStr = pcall(function()
                            return game:GetService("HttpService"):JSONEncode(result)
                        end)
                        if jsonSuccess then
                            logPrint("Inventory JSON: " .. jsonStr)
                        else
                            logPrint("Failed to encode inventory to JSON: " .. tostring(jsonStr))
                        end
                    else
                        logPrint("Returned result is not a table!")
                    end
                else
                    logPrint("ERROR: Remote call failed: " .. tostring(result))
                end
            else
                logPrint("WARNING: GetPlayerInventory is not a RemoteFunction, it is a: " .. getPlayerInv.ClassName)
            end
        end
        
        if not inventory then
            logPrint("Attempting to read local folders for inventory...")
            local localInv = getLocalInventory()
            if localInv then
                logPrint("Found items locally.")
                inventory = localInv
            else
                logPrint("No inventory items found locally.")
            end
        end
        
        if inventory and typeof(inventory) == "table" then
            logPrint("\nListing inventory items:")
            for k, v in pairs(inventory) do
                logPrint(string.format("  Key: %s (%s)", tostring(k), typeof(k)))
                if typeof(v) == "table" then
                    for prop, val in pairs(v) do
                        logPrint(string.format("    %s = %s (%s)", tostring(prop), tostring(val), typeof(val)))
                    end
                else
                    logPrint(string.format("    Value: %s (%s)", tostring(v), typeof(v)))
                end
            end
        else
            logPrint("No inventory available to inspect.")
        end
        
        logPrint("\n=== STORAGE HUNTERS DIAGNOSTICS END ===")
        
        local finalLog = table.concat(logLines, "\n")
        local setClipboardFunc = setclipboard or toclipboard or writeclipboard or (Clipboard and Clipboard.set)
        if setClipboardFunc then
            local success, err = pcall(function()
                setClipboardFunc(finalLog)
            end)
            if success then
                if Library and Library.Notify then
                    Library:Notify({
                        Title = "Diagnostics Copied!",
                        Description = "Hasil diagnostik berhasil disalin ke clipboard Anda.",
                        Time = 5
                    })
                end
            else
                if Library and Library.Notify then
                    Library:Notify({
                        Title = "Clipboard Error",
                        Description = "Gagal menyalin: " .. tostring(err),
                        Time = 5
                    })
                end
            end
        else
            if Library and Library.Notify then
                Library:Notify({
                    Title = "Executor Unsupported",
                    Description = "Executor Anda tidak mendukung fungsi clipboard.",
                    Time = 5
                })
            end
        end
    end,
})

CollectTab:Button({
    Title = 'Show All Plots & Owners',
    Desc = 'Cetak daftar semua plot dan pemiliknya ke console F9',
    Callback = function()
        local plots = Workspace:FindFirstChild("_Plots")
        if not plots then
            if Library and Library.Notify then
                Library:Notify({ Title = "Plots Error", Description = "Folder _Plots tidak ditemukan!", Time = 3 })
            end
            return
        end
        
        local logLines = { "=== DAFTAR PLOT & PEMILIK ===" }
        for _, plot in ipairs(plots:GetChildren()) do
            local ownerId = plot:GetAttribute("OwnerUserId")
            local ownerName = plot:GetAttribute("OwnerName") or "Unknown"
            table.insert(logLines, string.format("Plot: %s | OwnerName: %s | OwnerUserId: %s", 
                plot.Name, tostring(ownerName), tostring(ownerId)))
        end
        
        local finalLog = table.concat(logLines, "\n")
        print(finalLog)
        
        local setClipboardFunc = setclipboard or toclipboard or writeclipboard or (Clipboard and Clipboard.set)
        if setClipboardFunc then
            pcall(function() setClipboardFunc(finalLog) end)
            if Library and Library.Notify then
                Library:Notify({ Title = "Plots Listed!", Description = "Daftar plot berhasil disalin ke clipboard.", Time = 4 })
            end
        else
            if Library and Library.Notify then
                Library:Notify({ Title = "Plots Listed!", Description = "Daftar plot dicetak ke console F9.", Time = 4 })
            end
        end
    end
})

CollectTab:Section({ Title = "Truck Utilities" })

local function isGUID(str)
    if type(str) ~= "string" then return false end
    if #str ~= 36 then return false end
    local hyphens = 0
    for i = 1, #str do
        if str:sub(i, i) == "-" then
            hyphens = hyphens + 1
        end
    end
    return hyphens == 4
end

local function getVehicleItems(vehicle)
    local uids = {}
    local seen = {}
    
    local function addUid(uid)
        if isGUID(uid) and not seen[uid] then
            seen[uid] = true
            table.insert(uids, uid)
        end
    end
    
    if vehicle then
        for _, desc in ipairs(vehicle:GetDescendants()) do
            addUid(desc.Name)
            if desc:IsA("StringValue") then
                addUid(desc.Value)
            end
            
            local attrs = desc:GetAttributes()
            for k, v in pairs(attrs) do
                if type(v) == "string" then
                    addUid(v)
                end
            end
        end
    end
    
    -- Scan PlayerGui just in case (untuk trunk UI)
    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        for _, desc in ipairs(playerGui:GetDescendants()) do
            addUid(desc.Name)
            if desc:IsA("StringValue") then
                addUid(desc.Value)
            end
            
            local attrs = desc:GetAttributes()
            for k, v in pairs(attrs) do
                if type(v) == "string" then
                    addUid(v)
                end
            end
        end
    end
    
    return uids
end

CollectTab:Button({
    Title = 'Unload Truck',
    Desc = 'Pindahkan seluruh isi barang di kendaraan Anda ke inventori',
    Callback = function()
        print("[Unload Truck] Unloading started")
        local vehicle = getMyVehicle()
        print("[Unload Truck] Vehicle detected: " .. (vehicle and vehicle.Name or "None"))
        
        if TransferVehicleItemsToInventory then
            local itemUids = getVehicleItems(vehicle)
            print("[Unload Truck] Ditemukan " .. tostring(#itemUids) .. " item UID di dalam kendaraan:")
            for _, uid in ipairs(itemUids) do
                print("  - " .. uid)
            end
            
            if #itemUids > 0 then
                local success, result = safeCallRemote(TransferVehicleItemsToInventory, itemUids)
                if success then
                    print("[Unload Truck] Sukses mengirim perintah unload. Hasil: " .. tostring(result))
                else
                    warn("[Unload Truck] Gagal memicu unload: " .. tostring(result))
                end
            else
                warn("[Unload Truck] Tidak ada item UID yang terdeteksi di dalam kendaraan!")
            end
        else
            warn("[Unload Truck] Remote TransferVehicleItemsToInventory belum siap!")
        end
    end,
})

CollectTab:Label({
    Title = 'Penting!',
    Desc = 'Anda harus berada di kursi pengemudi Truk agar fitur Unload bekerja'
})

CollectTab:Section({ Title = "Auto-Collect" })

CollectTab:Toggle({
    Title = 'Auto-Collect',
    Desc = 'Teleport dan koleksi barang otomatis menggunakan ProximityPrompt',
    Value = false,
    Callback = function(state)
        AutoCollect = state
        print("[Settings] AutoCollect set to: " .. tostring(state))
    end,
})

-- -----------------------------------------------------------------------------
-- Collect Tab Elements: Auto Sell Section
-- -----------------------------------------------------------------------------
CollectTab:Section({ Title = "Auto Sell" })

CollectTab:Toggle({
    Title = 'Auto Sell Enabled',
    Desc = 'Otomatis menjual barang ketika harga dan kapasitas terpenuhi',
    Value = false,
    Callback = function(state)
        AutoSellEnabled = state
        if state then
            startAutoSellLoop()
        end
    end,
})

CollectTab:Slider({
    Title = 'Min Sell Rate (%)',
    Desc = 'Persentase minimal rate quick-sell lelang (profit/loss)',
    Min = -50,
    Max = 50,
    Value = -15,
    Rounding = 0,
    Callback = function(value)
        MinSellRate = value
    end,
})

CollectTab:Slider({
    Title = 'Min Load Weight (kg)',
    Desc = 'Kapasitas muatan kendaraan minimal sebelum menjual',
    Min = 0,
    Max = 100,
    Value = 20,
    Rounding = 0,
    Callback = function(value)
        MinWeight = value
    end,
})

CollectTab:Toggle({
    Title = 'Save Trophies',
    Desc = 'Jangan jual barang kategori Trophy (misal Gavel Trophy)',
    Value = true,
    Callback = function(state)
        SaveTrophies = state
    end,
})

CollectTab:Toggle({
    Title = 'Save Accessories',
    Desc = 'Jangan jual barang kategori Accessories',
    Value = true,
    Callback = function(state)
        SaveAccessories = state
    end,
})

CollectTab:Section({ Title = "Auto Sell Live Status" })

local RateLabel = CollectTab:Label({
    Title = 'Current Rate',
    Desc = 'Rate: Wait for data...'
})

local WeightLabel = CollectTab:Label({
    Title = 'Vehicle Load',
    Desc = 'Weight: Wait for data...'
})

local SellStatusLabel = CollectTab:Label({
    Title = 'Status',
    Desc = 'Inactive'
})

CollectTab:Button({
    Title = 'Refresh Rate Now',
    Desc = 'Paksa update data rate Pawn Shop saat ini',
    Callback = function()
        task.spawn(function()
            if GetPawnState then
                local ok, state = pcall(function()
                    return GetPawnState:InvokeServer()
                end)
                if ok and type(state) == "table" and state.rate then
                    CurrentRate = state.rate
                end
            end
        end)
    end,
})

registerConnection(game:GetService("RunService").Heartbeat:Connect(function()
    if not RateLabel or not WeightLabel or not SellStatusLabel then return end
    
    local pct = math.floor((CurrentRate - 1) * 100 + 0.5)
    local rateText = pct >= 0 and "+" .. pct .. "%" or pct .. "%"
    RateLabel:SetDesc("Rate: " .. rateText)
    
    WeightLabel:SetDesc("Weight: " .. math.floor(CurrentWeight) .. " kg")
    
    if not AutoSellEnabled then
        SellStatusLabel:SetDesc("Disabled")
        return
    end
    
    if pct < MinSellRate then
        SellStatusLabel:SetDesc(string.format("Waiting rate (%d%% < %d%%)", pct, MinSellRate))
        return
    end
    
    if CurrentWeight < MinWeight then
        SellStatusLabel:SetDesc(string.format("Waiting weight (%dkg < %dkg)", math.floor(CurrentWeight), MinWeight))
        return
    end
    
    if SellSyncing then
        SellStatusLabel:SetDesc("Selling...")
        return
    end
    
    if tick() < SellCooldown then
        SellStatusLabel:SetDesc(string.format("Cooldown (%ds)", math.ceil(SellCooldown - tick())))
        return
    end
    
    SellStatusLabel:SetDesc("Ready to sell")
end))

-- ---------------------------------------------------------------------------------------------
-- Teleport Tab Elements
-- -----------------------------------------------------------------------------
TeleportTab:Section({ Title = "Base Teleport" })

local function findUnpackZone()
    print("[Teleport] Menjalankan pencarian UnpackZone...")
    
    -- 1. Cari langsung di Workspace (dengan/tanpa spasi)
    local zone = Workspace:FindFirstChild("UnpackZone") or Workspace:FindFirstChild("Unpack Zone")
    if zone then return zone end
    
    -- 2. Cari di dalam plot pemain
    local plot = getMyPlot()
    print("[Teleport] Plot terdeteksi: " .. (plot and plot:GetFullName() or "None"))
    if plot then
        zone = plot:FindFirstChild("UnpackZone") or plot:FindFirstChild("Unpack Zone") or plot:FindFirstChild("UnpackZone", true) or plot:FindFirstChild("Unpack Zone", true)
        if zone then return zone end
    end
    
    -- 3. Cari secara rekursif nama yang mengandung "unpack" dan "zone"
    for _, desc in ipairs(Workspace:GetDescendants()) do
        local name = desc.Name:lower()
        if name:find("unpack") and name:find("zone") then
            return desc
        end
    end
    
    -- 4. Cari secara rekursif nama yang mengandung "unpack"
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc.Name:lower():find("unpack") then
            return desc
        end
    end
    
    -- Debug: Cetak semua anak langsung dari Workspace untuk membantu pengguna melacak letak UnpackZone via F9 console
    print("[Teleport] Debug: Mencetak semua anak langsung dari Workspace:")
    for _, child in ipairs(Workspace:GetChildren()) do
        print("  - " .. child.Name .. " (Class: " .. child.ClassName .. ")")
    end
    
    return nil
end

TeleportTab:Button({
    Title = 'TP base',
    Desc = 'Teleport ke base (Harus ada minimal 1 barang di mobil agar Unpack Zone muncul)',
    Callback = function()
        local unpackZone = findUnpackZone()
        if unpackZone then
            print("[Teleport] Base UnpackZone ditemukan: " .. unpackZone:GetFullName())
            teleportTo(unpackZone:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("UnpackZone not found! Pastikan ada minimal 1 barang di dalam mobil.")
        end
    end,
})

TeleportTab:Label({
    Title = 'Tips Truk',
    Desc = 'Jika duduk di kursi Truk, truk tersebut akan ikut berteleportasi'
})

TeleportTab:Label({
    Title = 'Penting!',
    Desc = 'Harus ada minimal 1 barang di bagasi mobil agar Unpack Zone muncul di base Anda!'
})

TeleportTab:Section({ Title = 'Zones' })

TeleportTab:Button({
    Title = 'TP to JunkYard',
    Desc = 'Teleport ke area Junk Yard',
    Callback = function()
        local areas = Workspace:FindFirstChild('Areas')
        local junkyard = areas and areas:FindFirstChild('Junk Yard')
        local centrePiece = junkyard and junkyard:FindFirstChild('CentrePiece', true)
        
        if centrePiece then
            teleportTo(centrePiece:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Junk Yard CentrePiece not found!")
        end
    end,
})

TeleportTab:Button({
    Title = 'TP to Back Alley',
    Desc = 'Teleport ke area Back Alley',
    Callback = function()
        local areas = Workspace:FindFirstChild('Areas')
        local backAlley = areas and areas:FindFirstChild('Back Alley')
        local road = backAlley and backAlley:FindFirstChild('Back Alley Road', true)
        
        if road then
            teleportTo(road:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Back Alley Road not found!")
        end
    end,
})

TeleportTab:Button({
    Title = 'TP to Farm Yard',
    Desc = 'Teleport ke area Farmyard',
    Callback = function()
        local areas = Workspace:FindFirstChild('Areas')
        local farmyard = areas and areas:FindFirstChild('Farmyard')
        local box = farmyard and farmyard:FindFirstChild('Lost and Found Box', true)
        
        if box then
            teleportTo(box:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Farmyard Lost and Found Box not found!")
        end
    end,
})

TeleportTab:Button({
    Title = 'TP to ShipYard',
    Desc = 'Teleport ke area Shipyard',
    Callback = function()
        local areas = Workspace:FindFirstChild('Areas')
        local shipyard = areas and areas:FindFirstChild('Shipyard')
        local box = shipyard and shipyard:FindFirstChild('Lost and Found Box', true)
        
        if box then
            teleportTo(box:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Shipyard Lost and Found Box not found!")
        end
    end,
})

TeleportTab:Section({ Title = 'Shops' })

TeleportTab:Button({
    Title = 'TP Mall',
    Desc = 'Teleport ke Pawn Shop / Mall',
    Callback = function()
        local mallPart = findLocationByName("Mall") or findLocationByName("Pawn Shop")
        if mallPart then
            teleportTo(mallPart:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Mall location not found!")
        end
    end,
})

TeleportTab:Button({
    Title = 'Item Cleaning Service',
    Desc = 'Teleport ke tempat pencucian barang / cleaning',
    Callback = function()
        local cleanPart = findLocationByName("Cleaning") or findLocationByName("Wash") or findLocationByName("Cleaning Service")
        if cleanPart then
            teleportTo(cleanPart:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Item Cleaning Service location not found!")
        end
    end,
})

TeleportTab:Button({
    Title = 'CarGarage',
    Desc = 'Teleport ke Car Garage / Dealer',
    Callback = function()
        local garagePart = findLocationByName("CarGarage") or findLocationByName("Car Garage") or findLocationByName("Garage")
        if garagePart then
            teleportTo(garagePart:GetPivot() + Vector3.new(0, 5, 0))
        else
            warn("Car Garage location not found!")
        end
    end,
})

-- -----------------------------------------------------------------------------
-- Auction Tab Elements
-- -----------------------------------------------------------------------------
AuctionTab:Section({ Title = "Auction Bidding" })

AuctionTab:Toggle({
    Title = 'Auto-Bid',
    Desc = 'Otomatis melakukan bid saat lelang berlangsung',
    Value = false,
    Callback = function(state)
        AutoBid = state
        print("[Settings] AutoBid set to: " .. tostring(state))
    end,
})

AuctionTab:Textbox({
    Title = 'Min Starting Bid',
    Desc = 'Batas minimal harga awal lelang untuk ikut menawar',
    Value = '0',
    Placeholder = '0',
    ClearText = false,
    Callback = function(value)
        local num = tonumber(value)
        MinBid = num or 0
        print("[Settings] MinBid set to: " .. tostring(MinBid))
    end,
})

AuctionTab:Textbox({
    Title = 'Max Bid',
    Desc = 'Jumlah maksimum penawaran bid Anda',
    Value = '',
    Placeholder = 'Enter your max bid',
    ClearText = false,
    Callback = function(value)
        local num = tonumber(value)
        MaxBid = num or 0
        print("[Settings] MaxBid set to: " .. tostring(MaxBid))
    end,
})

AuctionTab:Button({
    Title = "Leave Auction",
    Desc = "Keluar dari lelang aktif",
    Callback = function()
        local ok, result = pcall(function()
            if LeaveAuctionRemote then
                return LeaveAuctionRemote:InvokeServer()
            end
        end)
        if ok and result then
            local UIController = require(ReplicatedStorage.Modules.UIController)
            UIController:Close("AuctionBidding")
            UIController:Close("AuctionPowers")
            UIController:Close("AuctionWinningBid")
        end
    end,
})

-- -----------------------------------------------------------------------------
-- Pathfinder Tab Elements
-- -----------------------------------------------------------------------------
PathfinderTab:Section({ Title = "Master Control" })

PathfinderTab:Toggle({
    Title = "Master Pathfinder",
    Desc = "Aktifkan siklus lelang otomatis (berjalan, trigger lelang, kumpulkan item)",
    Value = false,
    Callback = function(state)
        setPathfinderEnabled(state)
    end,
})

PathfinderTab:Section({ Title = "Target Areas" })

PathfinderTab:Toggle({
    Title = "Junk Yard",
    Desc = "Scrap Garage",
    Value = true,
    Callback = function(state)
        AreaToggles["Junk Yard"] = state
    end,
})

PathfinderTab:Toggle({
    Title = "Back Alley",
    Desc = "Shop Front",
    Value = true,
    Callback = function(state)
        AreaToggles["Back Alley"] = state
    end,
})

PathfinderTab:Toggle({
    Title = "Farmyard",
    Desc = "Stable Garage, Barn Garage",
    Value = true,
    Callback = function(state)
        AreaToggles["Farmyard"] = state
    end,
})

PathfinderTab:Toggle({
    Title = "Shipyard",
    Desc = "Small, Large & Warehouse Garage",
    Value = true,
    Callback = function(state)
        AreaToggles["Shipyard"] = state
    end,
})

PathfinderTab:Section({ Title = "Status" })

local PhaseLabel = PathfinderTab:Label({
    Title = "Phase",
    Desc = "Idle"
})

local StatusLabel = PathfinderTab:Label({
    Title = "State",
    Desc = "Waiting for activation..."
})

registerConnection(game:GetService("RunService").Heartbeat:Connect(function()
    if not PhaseLabel or not StatusLabel then return end
    PhaseLabel:SetDesc("Phase: " .. tostring(PathfinderPhase))
    StatusLabel:SetDesc("State: " .. tostring(PathfinderStatus))
end))

-- =============================================================================
-- BACKGROUND LOAD & CONNECTION SETUP (Non-Blocking & Independent Threads)
-- =============================================================================
task.spawn(function()
    print("[Storage Hunters] Memulai inisialisasi background...")
    
    -- Tunggu folder Events secara non-blocking
    local Events = ReplicatedStorage:WaitForChild('Events')
    print("[Storage Hunters] Folder Events berhasil terdeteksi!")
    
    -- 1. Memuat modul konfigurasi game
    task.spawn(function()
        pcall(function()
            require(ReplicatedStorage.Modules.Items)
            require(ReplicatedStorage.Modules.MutatorModule)
            local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
            local Grading = GameConfig.Grading
            print("[Storage Hunters] Modul game berhasil di-require.")
        end)
    end)
    
    -- 2. Inisialisasi NPCShopper (Auto-Accept Offers)
    task.spawn(function()
        local NPCShopper = Events:WaitForChild('NPCShopper')
        if NPCShopper then
            local RespondOffer = NPCShopper:WaitForChild('RespondOffer')
            local ShowOffer = NPCShopper:WaitForChild('ShowOffer')
            
            if ShowOffer and RespondOffer then
                registerConnection(ShowOffer.OnClientEvent:Connect(function(...)
                    local args = {...}
                    print("[NPCShopper] ShowOffer fired. Arguments:")
                    for i, v in ipairs(args) do
                        print("  Arg " .. tostring(i) .. ": " .. tostring(v) .. " (" .. typeof(v) .. ")")
                    end
                    
                    if not AutoAcceptOffers then return end
                    local offerId = args[1]
                    if not offerId then return end
                    
                    -- Cari persentase otomatis (menangani format string "+24%", kalkulasi matematika harga, maupun number desimal)
                    local function getParsedPercent(tbl)
                        -- 1. Scan untuk string yang mengandung % di seluruh argumen (indeks 2 ke atas)
                        for i = 2, #tbl do
                            local v = tbl[i]
                            if type(v) == "string" and v:find("%%") then
                                local cleanStr = v:gsub("[^%d%.%-]", "")
                                local num = tonumber(cleanStr)
                                if num then return num end
                            end
                        end
                        
                        -- 2. Jika ada offerPrice (Arg 4) dan basePrice (Arg 5), hitung persentase profitnya secara matematis
                        local offerPrice = tonumber(tbl[4])
                        local basePrice = tonumber(tbl[5])
                        if offerPrice and basePrice and basePrice > 0 then
                            local computed = ((offerPrice - basePrice) / basePrice) * 100
                            if computed >= -100 and computed <= 500 then
                                return math.round(computed)
                            end
                        end
                        
                        -- 3. Fallback: Scan untuk nilai desimal/float (misal 0.3 untuk 30%) dari indeks 5 ke atas
                        for i = 5, #tbl do
                            local v = tbl[i]
                            local num = tonumber(v)
                            if num and num > 0 and num < 1 then
                                return num * 100
                            end
                        end
                        
                        -- 4. Fallback: Scan untuk number murni di range [-100, 100] dari indeks 5 ke atas
                        for i = 5, #tbl do
                            local v = tbl[i]
                            local num = tonumber(v)
                            if num and num >= -100 and num <= 100 then
                                return num
                            end
                        end
                        return 0
                    end
                    
                    local percent = getParsedPercent(args)
                    
                    print("[NPCShopper] Parsed percent: " .. tostring(percent) .. "%, MinAccept: " .. tostring(MinAcceptPercent) .. "%")
                    
                    if percent >= MinAcceptPercent then
                        print("[NPCShopper] Auto-Accepting offer: " .. tostring(offerId))
                        safeCallRemote(RespondOffer, offerId, true) -- Accept
                    else
                        print("[NPCShopper] Auto-Declining offer: " .. tostring(offerId))
                        safeCallRemote(RespondOffer, offerId, false) -- Decline
                    end
                end))
                print("[Storage Hunters] Event NPCShopper berhasil di-hook!")
            end
        end
    end)
    
    -- 3. Resolusi Remote untuk Plot (PlaceStockItem & GetShopStock)
    task.spawn(function()
        local PlotEvents = Events:WaitForChild('Plot')
        if PlotEvents then
            PlaceStockItem = PlotEvents:WaitForChild('PlaceStockItem')
            GetShopStock = PlotEvents:FindFirstChild('GetShopStock') or PlotEvents:WaitForChild('GetShopStock')
            print("[Storage Hunters] Remote Plot events (PlaceStockItem & GetShopStock) berhasil dideteksi!")
        end
    end)
    
    -- 4. Resolusi Remote untuk Inventori (GetPlayerInventory)
    task.spawn(function()
        local InventoryEvents = Events:WaitForChild('Inventory')
        if InventoryEvents then
            GetPlayerInventory = InventoryEvents:WaitForChild('GetPlayerInventory')
            print("[Storage Hunters] Remote GetPlayerInventory berhasil dideteksi!")
        end
    end)
    
    -- 5. Resolusi Remote untuk Kendaraan (TransferVehicleItemsToInventory)
    task.spawn(function()
        local VehicleEvents = Events:WaitForChild('Vehicles')
        if VehicleEvents then
            TransferVehicleItemsToInventory = VehicleEvents:WaitForChild('TransferVehicleItemsToInventory')
            print("[Storage Hunters] Remote TransferVehicleItemsToInventory berhasil dideteksi!")
        end
    end)
    
    -- 6. Resolusi Remote untuk Pawn (Auto Sell)
    task.spawn(function()
        local Pawn = Events:WaitForChild('Pawn')
        if Pawn then
            GetPawnState = Pawn:WaitForChild('GetPawnState')
            GetSellableItems = Pawn:WaitForChild('GetSellableItems')
            SellItems = Pawn:WaitForChild('SellItems')
            RateChanged = Pawn:WaitForChild('RateChanged')
            
            registerConnection(RateChanged.OnClientEvent:Connect(function(data)
                if type(data) == "table" and data.rate then
                    CurrentRate = data.rate
                end
            end))
            print("[Storage Hunters] Remote Pawn events berhasil dideteksi!")
        end
    end)
    
    -- 7. Resolusi Remote untuk UI (Weight Update)
    task.spawn(function()
        local UIEvents = Events:WaitForChild('UI')
        if UIEvents then
            VehicleWeightUpdate = UIEvents:WaitForChild('VehicleWeightUpdate')
            
            registerConnection(VehicleWeightUpdate.OnClientEvent:Connect(function(currentKg, maxKg)
                CurrentWeight = tonumber(currentKg) or 0
            end))
            print("[Storage Hunters] Remote UI events berhasil dideteksi!")
        end
    end)
    
    -- 8. Inisialisasi Lelang (Auto-Bid & Pickup)
    task.spawn(function()
        local AuctionEvents = Events:WaitForChild('Auction')
        if AuctionEvents then
            BidEvent = AuctionEvents:WaitForChild('Bid')
            local UpdateCurrentWinningBid = AuctionEvents:WaitForChild('UpdateCurrentWinningBid')
            local LeaveAuction = AuctionEvents:FindFirstChild('LeaveAuction') or AuctionEvents:WaitForChild('LeaveAuction')
            LeaveAuctionRemote = LeaveAuction
            
            AuctionPickupStart = AuctionEvents:WaitForChild('AuctionPickupStart')
            AuctionPickupEnd = AuctionEvents:WaitForChild('AuctionPickupEnd')
            
            registerConnection(AuctionPickupStart.OnClientEvent:Connect(function(bidAmount, totalValue)
                State_itemsAvailable = true
            end))
            registerConnection(AuctionPickupEnd.OnClientEvent:Connect(function()
                State_itemsAvailable = false
            end))
            
            if UpdateCurrentWinningBid and BidEvent then
                registerConnection(UpdateCurrentWinningBid.OnClientEvent:Connect(function(currentBid, winningPlayer, storageUnit, timeLeft)
                    if not AutoBid then return end
                    
                    local currentBidNum = tonumber(currentBid)
                    if not currentBidNum then
                        -- Jika nilai awal lelang nil (sebelum ada bid pertama dari player/NPC), abaikan secara diam-diam tanpa memicu warning console
                        return
                    end
                    
                    -- Deteksi lelang unit baru
                    if storageUnit and storageUnit ~= currentAuctionUnit then
                        currentAuctionUnit = storageUnit
                        if currentBidNum < MinBid then
                            ignoredAuctionUnits[storageUnit] = true
                            print("[Auction] Mengabaikan unit lelang " .. tostring(storageUnit) .. " karena harga awal (" .. tostring(currentBidNum) .. ") di bawah Min Bid (" .. tostring(MinBid) .. ")")
                            
                            -- Panggil LeaveAuction secara non-blocking karena ini adalah RemoteFunction (InvokeServer)
                            if LeaveAuction then
                                print("[Auction] Harga awal terlalu rendah. Mengirim sinyal LeaveAuction...")
                                task.spawn(function()
                                    safeCallRemote(LeaveAuction)
                                end)
                            end
                        else
                            ignoredAuctionUnits[storageUnit] = false
                            print("[Auction] Mengikuti lelang untuk unit " .. tostring(storageUnit) .. " dengan harga awal " .. tostring(currentBidNum))
                        end
                    end
                    
                    -- Jika unit ini ditandai untuk diabaikan, hentikan bid
                    if storageUnit and ignoredAuctionUnits[storageUnit] then
                        return
                    end
                    
                    local isWinning = false
                    if typeof(winningPlayer) == "Instance" and winningPlayer:IsA("Player") then
                        isWinning = (winningPlayer == LocalPlayer)
                    elseif type(winningPlayer) == "string" then
                        isWinning = (winningPlayer == LocalPlayer.Name)
                    elseif type(winningPlayer) == "number" then
                        isWinning = (winningPlayer == LocalPlayer.UserId)
                    end
                    
                    if isWinning then return end
                    
                    local nextBid = currentBidNum + 50
                    if nextBid <= MaxBid then
                        if storageUnit then
                            safeCallRemote(BidEvent, storageUnit, nextBid)
                        else
                            safeCallRemote(BidEvent, nextBid)
                        end
                    end
                end))
                print("[Storage Hunters] Event Auction berhasil di-hook!")
            end
        end
    end)
    
    print("[Storage Hunters] Inisialisasi thread background selesai!")
end)

-- =============================================================================
-- AUTO PLACE ITEMS FUNCTION BODY
-- =============================================================================
startAutoPlaceLoop = function()
    task.spawn(function()
        while AutoPlaceEnabled do
            local plot = getMyPlot()
            if plot then
                -- Ambil data stock aktif dari plot (untuk mendeteksi snap point yang sudah terisi)
                local occupiedPoints = {}
                if GetShopStock then
                    local success, stock = pcall(function()
                        return GetShopStock:InvokeServer(plot)
                    end)
                    if success and type(stock) == "table" then
                        for _, itemGroup in ipairs(stock) do
                            if type(itemGroup) == "table" then
                                for _, placedItem in ipairs(itemGroup) do
                                    if type(placedItem) == "table" and placedItem.Attrs then
                                        local sGUID = placedItem.Attrs.ShelfGUID or placedItem.Attrs.shelfGUID
                                        local sName = placedItem.Attrs.SnapPointName or placedItem.Attrs.snapPointName
                                        if sGUID and sName then
                                            occupiedPoints[sGUID .. "_" .. sName] = true
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Ambil data inventory (dari remote atau fallback lokal)
                local success, inventory
                if GetPlayerInventory then
                    success, inventory = pcall(function()
                        if GetPlayerInventory:IsA("RemoteFunction") then
                            return GetPlayerInventory:InvokeServer()
                        end
                    end)
                end
                
                if not success or type(inventory) ~= "table" then
                    inventory = getLocalInventory()
                end
                
                -- Siapkan list barang dari inventory
                local itemsToPlace = {}
                if inventory and type(inventory) == "table" then
                    for itemUID, itemData in pairs(inventory) do
                        local itemId = nil
                        if type(itemData) == "table" then
                            itemId = itemData.ItemId or itemData.itemId or itemData.Id or itemData.id
                        else
                            itemId = itemData
                        end
                        if itemUID and itemId then
                            table.insert(itemsToPlace, { uid = itemUID, id = itemId })
                        end
                    end
                end
                
                -- Scan plot untuk mencari snap point meja/rak yang kosong
                local emptySnapPoints = {}
                if plot then
                    for _, desc in ipairs(plot:GetDescendants()) do
                        if desc:IsA("ProximityPrompt") then
                            local promptName = desc.Name:lower()
                            local actionText = desc.ActionText:lower()
                            
                            -- Pengecekan case-insensitive yang benar
                            if promptName:find("additem") or actionText:find("add item") then
                                local snapPoint = desc.Parent
                                if snapPoint and (snapPoint:IsA("BasePart") or snapPoint:IsA("Attachment")) then
                                    local current = snapPoint
                                    local shelfGUID = nil
                                    while current and current ~= plot do
                                        shelfGUID = current:GetAttribute("GUID")
                                        if shelfGUID then break end
                                        current = current.Parent
                                    end
                                    
                                    if shelfGUID then
                                        local key = shelfGUID .. "_" .. snapPoint.Name
                                        if not occupiedPoints[key] then
                                            local worldCFrame = snapPoint:IsA("Attachment") and snapPoint.WorldCFrame or snapPoint.CFrame
                                            table.insert(emptySnapPoints, {
                                                prompt = desc,
                                                snapPoint = snapPoint,
                                                worldCFrame = worldCFrame,
                                                shelfGUID = shelfGUID,
                                                name = snapPoint.Name
                                            })
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Mulai meletakkan barang ke snap point kosong
                if #itemsToPlace > 0 and #emptySnapPoints > 0 then
                    for _, snapPointInfo in ipairs(emptySnapPoints) do
                        if not AutoPlaceEnabled then break end
                        if #itemsToPlace == 0 then break end
                        
                        local item = table.remove(itemsToPlace, 1)
                        print(string.format("[Auto Place] Meletakkan item %s (%s) ke rak %s (%s)", tostring(item.uid), tostring(item.id), snapPointInfo.name, snapPointInfo.shelfGUID))
                        
                        if PlaceStockItem then
                            local placeStatus, placeErr = pcall(function()
                                if PlaceStockItem:IsA("RemoteEvent") then
                                    PlaceStockItem:FireServer(
                                        item.uid,
                                        tostring(item.id),
                                        snapPointInfo.worldCFrame,
                                        0, -- YRotation default
                                        snapPointInfo.shelfGUID,
                                        snapPointInfo.name
                                    )
                                elseif PlaceStockItem:IsA("RemoteFunction") then
                                    PlaceStockItem:InvokeServer(
                                        item.uid,
                                        tostring(item.id),
                                        snapPointInfo.worldCFrame,
                                        0, -- YRotation default
                                        snapPointInfo.shelfGUID,
                                        snapPointInfo.name
                                    )
                                end
                            end)
                            if not placeStatus then
                                warn("[Auto Place] Gagal meletakkan barang: " .. tostring(placeErr))
                            end
                            task.wait(0.5) -- Throttle anti-kick
                        else
                            break
                        end
                    end
                end
            else
                task.wait(2)
            end
            task.wait(2)
        end
    end)
end

-- =============================================================================
-- AUTO QUICK-SELL FUNCTION BODY
-- =============================================================================
local function startAutoSellLoop()
    task.spawn(function()
        while AutoSellEnabled do
            if SellSyncing then
                task.wait(1)
            elseif tick() < SellCooldown then
                task.wait(1)
            else
                -- Hitung persentase rate saat ini (misal 1.15 -> +15%)
                local pct = math.floor((CurrentRate - 1) * 100 + 0.5)
                if pct < MinSellRate then
                    task.wait(2)
                elseif CurrentWeight < MinWeight then
                    task.wait(2)
                else
                    -- Siapkan proses penjualan
                    SellSyncing = true
                    
                    if GetSellableItems and SellItems then
                        local success, items = pcall(function()
                            return GetSellableItems:InvokeServer()
                        end)
                        
                        if success and type(items) == "table" then
                            local toSell = {}
                            for guid, info in pairs(items) do
                                if not info.Favorited then
                                    local itemDef = ItemsModule[info.ItemId]
                                    local skip = false
                                    if itemDef then
                                        if SaveTrophies and itemDef.Category == "Trophy" then
                                            skip = true
                                        end
                                        if SaveAccessories and itemDef.Category == "Accessories" then
                                            skip = true
                                        end
                                    end
                                    if not skip then
                                        table.insert(toSell, guid)
                                    end
                                end
                            end
                            
                            if #toSell > 0 then
                                local sellSuccess, result = pcall(function()
                                    return SellItems:InvokeServer(toSell)
                                end)
                                if sellSuccess then
                                    -- Set cooldown 15 detik
                                    SellCooldown = tick() + 15
                                end
                            end
                        end
                    end
                    
                    SellSyncing = false
                    task.wait(2)
                end
            end
        end
    end)
end

-- =============================================================================
-- PATHFINDER (AUTO AUCTION LOOP) BODY
-- =============================================================================
local function pathfinderLoop()
    while PathfinderEnabled and PathfinderRunning do
        -- STATE 1: FIND AUCTION
        PathfinderPhase = "Finding Auction"
        local target = findNearestAuction()
        if not target then
            PathfinderStatus = "No eligible auctions found, waiting..."
            task.wait(5)
        else
            PathfinderStatus = "Walking to " .. target.garageType .. " (" .. target.areaName .. ")"

            -- STATE 2: WALK TO AUCTION
            PathfinderPhase = "Walking to Auction"
            local walked = walkTo(target.position, 45)
            if not walked then
                PathfinderStatus = "Failed to reach auction, retrying..."
                task.wait(3)
            else
                -- STATE 3: TRIGGER AUCTION
                PathfinderPhase = "Triggering Auction"
                PathfinderStatus = "Starting auction..."
                walkTo(target.position, 5)

                triggerPrompt(target.prompt)
                task.wait(1)

                local gui = LocalPlayer.PlayerGui:FindFirstChild("UIControllerGui")
                local container = gui and gui:FindFirstChild("AuctionBiddingContainer")
                if not (container and container.Visible) then
                    triggerPrompt(target.prompt)
                    task.wait(1)
                end

                -- STATE 4: WAIT FOR BIDDING TO FINISH
                PathfinderPhase = "Waiting for Bidding"
                PathfinderStatus = "Auction in progress, waiting..."

                State_itemsAvailable = false
                local biddingEndTime = tick()
                local inAuction = true

                while inAuction and PathfinderEnabled do
                    task.wait(0.5)

                    gui = LocalPlayer.PlayerGui:FindFirstChild("UIControllerGui")
                    container = gui and gui:FindFirstChild("AuctionBiddingContainer")

                    if not (container and container.Visible) then
                        if State_itemsAvailable then
                            inAuction = false
                        else
                            if tick() - biddingEndTime > 8 then
                                inAuction = false
                            end
                        end
                    else
                        biddingEndTime = tick()
                    end

                    if tick() - biddingEndTime > 180 then
                        inAuction = false
                    end
                end

                -- STATE 5: COLLECT ITEMS (if won)
                if State_itemsAvailable then
                    PathfinderPhase = "Collecting Items"
                    PathfinderStatus = "Auction won! Collecting..."
                    task.wait(1)

                    local function findGarageModel()
                        for _, model in ipairs(Workspace:GetChildren()) do
                            local name = model.Name
                            if name == target.garageType or name:find(target.garageType) then
                                return model
                            end
                        end
                        return nil
                    end

                    local garageModel = findGarageModel()
                    local garagePos = garageModel and garageModel:GetPivot().Position or target.position

                    local blacklist = {}
                    local function isBlacklisted(key)
                        return blacklist[key] and blacklist[key].attempts >= 3
                    end
                    local function recordAttempt(key)
                        blacklist[key] = blacklist[key] or { attempts = 0 }
                        blacklist[key].attempts = blacklist[key].attempts + 1
                    end

                    local garageLoopStart = tick()
                    local garageCleared = false

                    while not garageCleared and PathfinderEnabled do
                        if tick() - garageLoopStart > 20 then
                            PathfinderStatus = "Garage timeout, moving on"
                            task.wait(0.5)
                            break
                        end

                        -- A: Open boxes
                        PathfinderStatus = "Opening boxes..."
                        local boxes = findPromptsNear(garagePos, 80, "OpenBoxPrompt")
                        for i, box in ipairs(boxes) do
                            if not PathfinderEnabled then break end
                            local key = tostring(box.prompt)
                            if not isBlacklisted(key) then
                                PathfinderStatus = string.format("Opening box %d/%d", i, #boxes)
                                local arrived = walkTo(box.position, 15)
                                if arrived then
                                    triggerPrompt(box.prompt)
                                    task.wait(0.3)
                                else
                                    recordAttempt(key)
                                end
                            end
                        end

                        -- B: Collect items
                        PathfinderStatus = "Collecting items..."
                        local pickups = findPromptsNear(target.position, 60, "PickupPrompt")

                        if #pickups == 0 and garageModel then
                            pickups = findPromptsNear(garagePos, 80, "PickupPrompt")
                        end

                        if #pickups == 0 then
                            for _, desc in ipairs(Workspace:GetDescendants()) do
                                if desc:IsA("ProximityPrompt") and desc.Name == "PickupPrompt" then
                                    local parent = desc.Parent
                                    if parent and parent:IsA("BasePart") then
                                        table.insert(pickups, {
                                            prompt = desc,
                                            part = parent,
                                            position = parent.Position,
                                            distance = 0
                                        })
                                    end
                                end
                            end
                            table.sort(pickups, function(a, b) return a.distance < b.distance end)
                        end

                        for i, pickup in ipairs(pickups) do
                            if not PathfinderEnabled then break end
                            local key = tostring(pickup.prompt)
                            if not isBlacklisted(key) then
                                PathfinderStatus = string.format("Collecting item %d/%d", i, #pickups)
                                local arrived = walkTo(pickup.position, 15)
                                if arrived then
                                    triggerPrompt(pickup.prompt)
                                    task.wait(0.3)
                                else
                                    recordAttempt(key)
                                end
                            end
                        end

                        task.wait(0.3)
                        local remainingBoxes = findPromptsNear(garagePos, 80, "OpenBoxPrompt")
                        local remainingItems = findPromptsNear(garagePos, 80, "PickupPrompt")

                        if #remainingBoxes == 0 and #remainingItems == 0 then
                            garageCleared = true
                            PathfinderStatus = "Garage cleared!"
                        else
                            PathfinderStatus = string.format("Remaining: %d boxes, %d items", #remainingBoxes, #remainingItems)
                        end
                        task.wait(0.3)
                    end

                    -- Exit garage
                    PathfinderPhase = "Exiting Garage"
                    PathfinderStatus = "Returning to board..."
                    walkTo(target.position, 20)

                    local exitStart = tick()
                    local root = getRoot()
                    while root and (root.Position - target.position).Magnitude >= 6 and PathfinderEnabled do
                        if tick() - exitStart > 15 then break end
                        root = getRoot()
                        if root then
                            local hum = getHumanoid()
                            if hum then hum:MoveTo(target.position) end
                        end
                        task.wait(0.5)
                    end
                else
                    PathfinderStatus = "Auction lost / no items"
                    task.wait(2)
                end

                PathfinderStatus = "Cycle complete, searching next..."
                task.wait(1)
            end
        end
    end

    PathfinderPhase = "Idle"
    if not PathfinderEnabled then
        PathfinderStatus = "Disabled"
    else
        PathfinderStatus = "Stopped"
    end
    PathfinderRunning = false
end

local function setPathfinderEnabled(value)
    PathfinderEnabled = value
    if value and not PathfinderRunning then
        PathfinderRunning = true
        PathfinderStatus = "Starting..."
        task.spawn(pathfinderLoop)
    elseif not value then
        PathfinderStatus = "Disabled"
    end
end

-- =============================================================================
-- AUTO-COLLECT BACKGROUND THREAD
-- =============================================================================
task.spawn(function()
    while true do
        task.wait(0.5)
        if AutoCollect then
            local character = LocalPlayer.Character
            local rootPart = character and character:FindFirstChild("HumanoidRootPart")
            if rootPart then
                for _, desc in ipairs(Workspace:GetDescendants()) do
                    if not AutoCollect then break end
                    if desc:IsA("ProximityPrompt") then
                        local actionText = desc.ActionText:lower()
                        local objectText = desc.ObjectText:lower()
                        
                        -- Target collectibles (pick up/collect items)
                        if actionText:find("collect") or actionText:find("pick up") or actionText:find("take") or objectText:find("item") then
                            local promptParent = desc.Parent
                            if promptParent and promptParent:IsA("BasePart") then
                                -- Safe teleportation with anchoring
                                local wasAnchored = rootPart.Anchored
                                rootPart.Anchored = true
                                rootPart.CFrame = promptParent.CFrame + Vector3.new(0, 3, 0)
                                task.wait(0.15)
                                
                                if fireproximityprompt then
                                    fireproximityprompt(desc)
                                else
                                    desc:InputHoldBegin()
                                    task.wait(desc.HoldDuration + 0.05)
                                    desc:InputHoldEnd()
                                end
                                task.wait(0.15)
                                rootPart.Anchored = wasAnchored
                            end
                        end
                    end
                end
            end
        end
    end
end)
