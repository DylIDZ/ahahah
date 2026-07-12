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

-- State lelang tambahan
local ignoredAuctionUnits = {}
local currentAuctionUnit = nil

-- Variabel global remote game (akan diisi secara independen di background)
local PlaceStockItem = nil
local GetPlayerInventory = nil
local TransferVehicleItemsToInventory = nil
local BidEvent = nil

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

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

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
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:GetAttribute("OwnerUserId") == LocalPlayer.UserId then
            if obj:FindFirstChildWhichIsA("VehicleSeat", true) then
                return obj
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
    
    -- 3. Resolusi Remote untuk Plot (PlaceStockItem)
    task.spawn(function()
        local PlotEvents = Events:WaitForChild('Plot')
        if PlotEvents then
            PlaceStockItem = PlotEvents:WaitForChild('PlaceStockItem')
            print("[Storage Hunters] Remote PlaceStockItem berhasil dideteksi!")
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
    
    -- 6. Inisialisasi Lelang (Auto-Bid)
    task.spawn(function()
        local AuctionEvents = Events:WaitForChild('Auction')
        if AuctionEvents then
            BidEvent = AuctionEvents:WaitForChild('Bid')
            local UpdateCurrentWinningBid = AuctionEvents:WaitForChild('UpdateCurrentWinningBid')
            local LeaveAuction = AuctionEvents:FindFirstChild('LeaveAuction') or AuctionEvents:WaitForChild('LeaveAuction')
            
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
        print("[Auto Place] Loop started")
        while AutoPlaceEnabled do
            local plot = getMyPlot()
            if not plot then
                warn("[Auto Place] Plot Anda tidak ditemukan di Workspace! Menunggu...")
                task.wait(2)
                continue
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
            
            print("[Auto Place] GetPlayerInventory success: " .. tostring(success) .. ", type: " .. type(inventory))
            if success and type(inventory) == "table" then
                -- Print sample structure of first item for F9 debug logs
                for k, v in pairs(inventory) do
                    print("[Auto Place] Inventory Item Sample: Key=" .. tostring(k) .. ", Value type=" .. type(v))
                    if type(v) == "table" then
                        for kk, vv in pairs(v) do
                            print("  " .. tostring(kk) .. " = " .. tostring(vv))
                        end
                    end
                    break
                end
            end
            
            if not success or type(inventory) ~= "table" then
                inventory = getLocalInventory()
            end
            
            if inventory and type(inventory) == "table" then
                for itemId, itemData in pairs(inventory) do
                    if not AutoPlaceEnabled then break end
                    
                    local idToSend
                    if type(itemData) == "table" then
                        idToSend = itemData.UID or itemData.uid or itemData.Id or itemData.id or itemId
                    else
                        idToSend = itemData
                    end
                    
                    print("[Auto Place] Meletakkan barang: " .. tostring(idToSend) .. " ke Plot: " .. plot.Name)
                    
                    if PlaceStockItem then
                        local placeStatus, placeErr = pcall(function()
                            if PlaceStockItem:IsA("RemoteEvent") then
                                PlaceStockItem:FireServer(plot, idToSend)
                            elseif PlaceStockItem:IsA("RemoteFunction") then
                                PlaceStockItem:InvokeServer(plot, idToSend)
                            end
                        end)
                        if not placeStatus then
                            warn("[Auto Place] Gagal meletakkan item: " .. tostring(placeErr))
                        end
                    else
                        warn("[Auto Place] Remote PlaceStockItem belum siap!")
                    end
                    task.wait(0.5) -- Throttle anti-kick
                end
            else
                print("[Auto Place] Inventori kosong atau tidak terbaca.")
            end
            task.wait(2)
        end
        print("[Auto Place] Loop stopped")
    end)
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
