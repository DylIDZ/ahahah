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
local AutoCollect = false

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

-- Remote Events & Modules
local Events = ReplicatedStorage:WaitForChild('Events')
local NPCShopper = Events:WaitForChild('NPCShopper')
local RespondOffer = NPCShopper:WaitForChild('RespondOffer')
local ShowOffer = NPCShopper:WaitForChild('ShowOffer')

local PlotEvents = Events:WaitForChild('Plot')
local PlaceStockItem = PlotEvents:WaitForChild('PlaceStockItem')
local GetPlayerInventory = Events:WaitForChild('Inventory'):WaitForChild('GetPlayerInventory')

local VehicleEvents = Events:WaitForChild('Vehicles')
local TransferVehicleItemsToInventory = VehicleEvents:WaitForChild('TransferVehicleItemsToInventory')

local AuctionEvents = Events:WaitForChild('Auction')
local BidEvent = AuctionEvents:WaitForChild('Bid')
local UpdateCurrentWinningBid = AuctionEvents:WaitForChild('UpdateCurrentWinningBid')

-- Load Game Config Modules
require(ReplicatedStorage.Modules.Items)
require(ReplicatedStorage.Modules.MutatorModule)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Grading = GameConfig.Grading

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Safely get the local player's HumanoidRootPart
local function getRootPart()
    local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    return character:WaitForChild('HumanoidRootPart')
end

-- Teleport utility supporting vehicle teleportation if seated
local function teleportTo(destinationCFrame)
    local character = LocalPlayer.Character
    if not character then return end
    
    local humanoid = character:FindFirstChildOfClass('Humanoid')
    local rootPart = character:FindFirstChild('HumanoidRootPart')
    if not rootPart then return end
    
    -- If player is sitting in a vehicle, teleport the entire vehicle
    if humanoid and humanoid.SeatPart and humanoid.SeatPart:IsA('VehicleSeat') then
        local vehicle = humanoid.SeatPart:FindFirstAncestorOfClass('Model')
        if vehicle then
            local vehicleRoot = vehicle.PrimaryPart or vehicle:FindFirstChild('VehicleSeat') or vehicle:FindFirstChildWhichIsA('BasePart')
            if vehicleRoot then
                vehicleRoot.CFrame = destinationCFrame
                return
            end
        end
    end
    
    -- Standalone character teleport
    rootPart.CFrame = destinationCFrame
end

-- Find a location in workspace by name
local function findLocationByName(name)
    local areas = Workspace:FindFirstChild("Areas")
    if areas then
        local found = areas:FindFirstChild(name, true)
        if found and found:IsA("BasePart") then return found end
    end
    
    local shops = Workspace:FindFirstChild("Shops")
    if shops then
        local found = shops:FindFirstChild(name, true)
        if found and found:IsA("BasePart") then return found end
    end
    
    -- Global fallback search
    for _, desc in ipairs(Workspace:GetDescendants()) do
        if desc:IsA("BasePart") and desc.Name:lower():find(name:lower()) then
            return desc
        end
    end
    return nil
end

-- Find local player's plot
local function getMyPlot()
    local plots = Workspace:FindFirstChild("_Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        if plot:GetAttribute('OwnerUserId') == LocalPlayer.UserId then
            return plot
        end
    end
    return nil
end

-- =============================================================================
-- AUTO-FEATURES LOGIC
-- =============================================================================

-- 1. Auto-Accept Offers
registerConnection(ShowOffer.OnClientEvent:Connect(function(offerId, npcName, itemName, price, percent, ...)
    if not AutoAcceptOffers then return end
    
    local offerPercent = tonumber(percent) or 0
    if offerPercent >= MinAcceptPercent then
        RespondOffer:FireServer(offerId, true) -- Accept
    else
        RespondOffer:FireServer(offerId, false) -- Decline
    end
end))

-- 2. Auto Place Items Loop
local function startAutoPlaceLoop()
    task.spawn(function()
        while AutoPlaceEnabled do
            local plot = getMyPlot()
            if plot then
                local success, inventory = pcall(function()
                    return GetPlayerInventory:InvokeServer()
                end)
                
                if success and type(inventory) == "table" then
                    for itemId, itemData in pairs(inventory) do
                        if not AutoPlaceEnabled then break end
                        
                        pcall(function()
                            local idToSend = type(itemData) == "table" and (itemData.Id or itemData.id or itemId) or itemData
                            PlaceStockItem:FireServer(idToSend)
                        end)
                        task.wait(0.5) -- Throttle to avoid rate limiting
                    end
                end
            end
            task.wait(1)
        end
    end)
end

-- 3. Auto-Bid
registerConnection(UpdateCurrentWinningBid.OnClientEvent:Connect(function(currentBid, winningPlayer, storageUnit, timeLeft)
    if not AutoBid then return end
    
    -- Check if we are already winning
    local isWinning = false
    if typeof(winningPlayer) == "Instance" and winningPlayer:IsA("Player") then
        isWinning = (winningPlayer == LocalPlayer)
    elseif type(winningPlayer) == "string" then
        isWinning = (winningPlayer == LocalPlayer.Name)
    elseif type(winningPlayer) == "number" then
        isWinning = (winningPlayer == LocalPlayer.UserId)
    end
    
    if isWinning then return end
    
    -- Calculate next bid (assuming standard Roblox increment of 50)
    local nextBid = currentBid + 50
    if nextBid <= MaxBid then
        if storageUnit then
            BidEvent:FireServer(storageUnit, nextBid)
        else
            BidEvent:FireServer(nextBid)
        end
    end
end))

-- 4. Auto-Collect Proximity Prompts
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

-- =============================================================================
-- USER INTERFACE INITIALIZATION (Astralux UI)
-- =============================================================================
local Library
local success, err = pcall(function()
    -- Coba muat secara online dari GitHub raw
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
        else
            warn('Min Accept %: invalid number entered')
        end
    end,
})

CollectTab:Toggle({
    Title = 'Auto Place Items',
    Desc = 'Otomatis meletakkan item dari inventori ke plot Anda',
    Value = false,
    Callback = function(state)
        AutoPlaceEnabled = state
        if state then
            startAutoPlaceLoop()
        end
    end,
})

CollectTab:Section({ Title = "Truck Utilities" })

CollectTab:Button({
    Title = 'Unload Truck',
    Desc = 'Pindahkan seluruh isi barang di kendaraan Anda ke inventori',
    Callback = function()
        TransferVehicleItemsToInventory:FireServer()
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
    end,
})

-- -----------------------------------------------------------------------------
-- Teleport Tab Elements
-- -----------------------------------------------------------------------------
TeleportTab:Section({ Title = "Base Teleport" })

TeleportTab:Button({
    Title = 'TP base',
    Desc = 'Teleport ke base Anda (Truk ikut jika sedang dikendarai)',
    Callback = function()
        local unpackZone = Workspace:FindFirstChild('UnpackZone')
        if unpackZone then
            teleportTo(unpackZone.CFrame + Vector3.new(0, 5, 0))
        else
            warn("UnpackZone not found!")
        end
    end,
})

TeleportTab:Label({
    Title = 'Tips Truk',
    Desc = 'Jika duduk di kursi Truk, truk tersebut akan ikut berteleportasi'
})

TeleportTab:Section({ Title = 'Zones' })

TeleportTab:Button({
    Title = 'TP to JunkYard',
    Desc = 'Teleport ke area Junk Yard',
    Callback = function()
        local areas = Workspace:FindFirstChild('Areas')
        local junkyard = areas and areas:FindFirstChild('Junk Yard')
        local parts = junkyard and junkyard:FindFirstChild('Parts')
        local centrePiece = parts and parts:FindFirstChild('CentrePiece')
        
        if centrePiece then
            teleportTo(centrePiece.CFrame + Vector3.new(0, 5, 0))
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
        local parts = backAlley and backAlley:FindFirstChild('Parts')
        local road = parts and parts:FindFirstChild('Back Alley Road')
        
        if road then
            teleportTo(road.CFrame + Vector3.new(0, 5, 0))
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
        local box = farmyard and farmyard:FindFirstChild('Lost and Found Box')
        
        if box then
            teleportTo(box.CFrame + Vector3.new(0, 5, 0))
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
        local box = shipyard and shipyard:FindFirstChild('Lost and Found Box')
        
        if box then
            teleportTo(box.CFrame + Vector3.new(0, 5, 0))
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
            teleportTo(mallPart.CFrame + Vector3.new(0, 5, 0))
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
            teleportTo(cleanPart.CFrame + Vector3.new(0, 5, 0))
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
            teleportTo(garagePart.CFrame + Vector3.new(0, 5, 0))
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
    end,
})
