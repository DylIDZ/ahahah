-- ts file was generated at discord.gg/25ms

local _LocalPlayer4 = game:GetService('Players').LocalPlayer
local _call7 = _LocalPlayer4.Character:WaitForChild('HumanoidRootPart')
local _call9 = game:GetService('ReplicatedStorage')
local _call11 = _call9:WaitForChild('Events')
local _15 = loadstring(game:HttpGet('https://raw.githubusercontent.com/csgo1compte-cloud/RayVoidUi/refs/heads/main/RayVoid'))()

_15:ShowCredit()
_15:SetScriptName('Storage Hunters')

local _call21 = _15:CreateWindow({
    LoadingTitle = 'RayVoid',
    LoadingSubtitle = 'by AKkiwi',
    Name = 'Storage Hunters Open World',
})
local _call23 = _call21:CreateTab('Auction', 4483362458)
local _call25 = _call21:CreateTab('Teleport', 4483362458)
local _call27 = _call21:CreateTab('Collect', 4483362458)
local _call29 = _call11:WaitForChild('NPCShopper')

_call29:WaitForChild('RespondOffer')
_call29:WaitForChild('ShowOffer').OnClientEvent:Connect(function(_37, _37_2, _37_3, _37_4, _37_5, _37_6, _37_7) end)
_call27:CreateToggle({
    CurrentValue = false,
    Callback = function(_40) end,
    Name = 'Auto-Accept Offers',
    Flag = 'AutoAcceptOffersToggle',
})
_call27:CreateInput({
    Name = 'Min Accept %',
    RemoveTextAfterFocusLost = false,
    CurrentValue = '15',
    PlaceholderText = '15',
    Callback = function(_43, _43_2, _43_3)
        warn('Min Accept %: invalid number entered')
    end,
    Flag = 'MinAcceptPercentInput',
})
require(_call9.Modules.Items)
require(_call9.Modules.MutatorModule)

local _ = require(_call9.Modules.GameConfig).Grading

_call11:WaitForChild('Inventory'):WaitForChild('GetPlayerInventory')
_call11:WaitForChild('Plot'):WaitForChild('PlaceStockItem')
_call27:CreateToggle({
    CurrentValue = false,
    Callback = function(_65, _65_2, _65_3, _65_4)
        task.spawn(function(_68, _68_2)
            for _73, _73_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _73_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _82, _82_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _82_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _91, _91_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _91_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _100, _100_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _100_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _109, _109_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _109_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _118, _118_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _118_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _127, _127_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _127_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _136, _136_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _136_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _145, _145_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _145_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _154, _154_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _154_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _163, _163_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _163_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _172, _172_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _172_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _181, _181_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _181_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _190, _190_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _190_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _199, _199_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _199_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)

            for _208, _208_2 in ipairs(workspace:FindFirstChild('_Plots'):GetChildren())do
                local _ = _208_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
            end

            task.wait(1)
            error('internal 583: <25ms: infinitelooperror>')
        end)
    end,
    Name = 'Auto Place Items',
    Flag = 'AutoPlaceItemsToggle',
})
_call25:CreateButton({
    Name = 'TP base',
    Callback = function()
        local _call218 = workspace:FindFirstChild('UnpackZone')

        _call218:IsA('BasePart')
        _call218:IsA('BasePart')

        local _call231 = _LocalPlayer4.Character:FindFirstChildOfClass('Humanoid')
        local _ = _call231.SeatPart

        _call231.SeatPart:IsA('VehicleSeat')

        for _238, _238_2 in ipairs(workspace:GetChildren())do
            local _ = _238_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
        end

        _call7.CFrame = CFrame.new((_call218.Position + Vector3.new(0, 5, 0)))
    end,
})
_call25:CreateLabel('If seated in the Truck, it teleports with you')
_call25:CreateSection('Zones')
_call25:CreateButton({
    Name = 'TP to JunkYard',
    Callback = function(_249, _249_2, _249_3, _249_4, _249_5)
        workspace:FindFirstChild('Areas')
        workspace.Areas:FindFirstChild('Junk Yard')
        workspace.Areas['Junk Yard']:FindFirstChild('Parts')

        local _call263 = workspace.Areas['Junk Yard'].Parts:FindFirstChild('CentrePiece')

        _call263:IsA('BasePart')

        local _call274 = _LocalPlayer4.Character:FindFirstChildOfClass('Humanoid')
        local _ = _call274.SeatPart

        _call274.SeatPart:IsA('VehicleSeat')

        for _281, _281_2 in ipairs(workspace:GetChildren())do
            local _ = _281_2:GetAttribute('OwnerUserId') == _LocalPlayer4.UserId
        end

        _call7.CFrame = CFrame.new((_call263.Position + Vector3.new(0, 5, 0)))
    end,
})
_call25:CreateButton({
    Name = 'TP to Back Alley',
    Callback = function(_288, _288_2)
        workspace:FindFirstChild('Areas')
        workspace.Areas:FindFirstChild('Back Alley')
        workspace.Areas['Back Alley']:FindFirstChild('Parts')

        local _ = workspace.Areas['Back Alley'].Parts:FindFirstChild('Back Alley Road').IsA

        error('internal 583: <25ms: infinitelooperror>')
    end,
})
_call25:CreateButton({
    Name = 'TP to Farm Yard',
    Callback = function(_307, _307_2, _307_3)
        workspace:FindFirstChild('Areas')
        workspace.Areas:FindFirstChild('Farmyard')
        workspace.Areas.Farmyard:FindFirstChild('Lost and Found Box')
        error('internal 583: <25ms: infinitelooperror>')
    end,
})
_call25:CreateButton({
    Name = 'TP to ShipYard',
    Callback = function(_320, _320_2, _320_3, _320_4, _320_5)
        workspace:FindFirstChild('Areas')
        workspace.Areas:FindFirstChild('Shipyard')
        workspace.Areas.Shipyard:FindFirstChild('Lost and Found Box')
        error('internal 583: <25ms: infinitelooperror>')
    end,
})
_call25:CreateSection('Shops')
_call25:CreateButton({
    Name = 'TP Mall',
    Callback = function(_335) end,
})
_call25:CreateButton({
    Name = 'Item Cleaning Service',
    Callback = function() end,
})
_call25:CreateButton({
    Name = 'CarGarage',
    Callback = function(_341, _341_2) end,
})
_call11:WaitForChild('Vehicles'):WaitForChild('TransferVehicleItemsToInventory')
_call27:CreateButton({
    Name = 'Unload Truck',
    Callback = function(_348) end,
})
_call27:CreateLabel('Must be seated in the Truck for this to work')

local _call352 = _call11:WaitForChild('Auction')

_call352:WaitForChild('Bid')
_call352:WaitForChild('UpdateCurrentWinningBid').OnClientEvent:Connect(function(_360, _360_2, _360_3, _360_4, _360_5) end)
_call23:CreateToggle({
    CurrentValue = false,
    Callback = function(_363, _363_2, _363_3, _363_4) end,
    Name = 'Auto-Bid',
    Flag = 'AutoBidToggle',
})
_call23:CreateInput({
    Name = 'Max Bid',
    RemoveTextAfterFocusLost = false,
    CurrentValue = '',
    PlaceholderText = 'Enter your max bid',
    Callback = function(_366, _366_2, _366_3, _366_4, _366_5) end,
    Flag = 'MaxBidInput',
})
_call27:CreateToggle({
    CurrentValue = false,
    Callback = function(_369, _369_2, _369_3) end,
    Name = 'Auto-Collect',
    Flag = 'AutoCollectToggle',
})
