local Players             = game:GetService("Players")
local TweenService        = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui          = game:GetService("StarterGui")
local Workspace           = game:GetService("Workspace")
local TeleportService     = game:GetService("TeleportService")
local HttpService         = game:GetService("HttpService")

local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

local plr = Players.LocalPlayer

local EJw = game:GetService("ReplicatedStorage"):WaitForChild("EJw")
local RemoteEvents = {
    RobEvent = EJw:WaitForChild("a3126821-130a-4135-80e1-1d28cece4007"),
    SellItem = EJw:WaitForChild("eb233e6a-acb9-4169-acb9-129fe8cb06bb"),
}

local VENDING_COLLECT_CODE   = "wRl"
local ProximityPromptTimeBet = 2.5

_G.vendingActive      = false
_G.flightSpeed        = 160
_G.vendingPoliceRange = 55

local vendingLoopThread    = nil
local instantCollectThread = nil

local teleportActive   = false
local currentTween     = nil
local currentTweenConn = nil
local tweenSpeed       = _G.flightSpeed

local DROP_Y             = -2
local SAFE_POSITION      = Vector3.new(-1292.9005126953125, DROP_Y, 3685.330810546875)

local function getChar()
    local char = plr.Character
    if not char then return nil, nil, nil end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

local function clickAtCoordinates(rx, ry)
    local vp = Workspace.CurrentCamera.ViewportSize
    VirtualInputManager:SendMouseButtonEvent(vp.X * rx, vp.Y * ry, 0, true,  game, 0)
    task.wait(0.05)
    VirtualInputManager:SendMouseButtonEvent(vp.X * rx, vp.Y * ry, 0, false, game, 0)
end

local function stopCurrentTween()
    if currentTween then currentTween:Cancel(); currentTween = nil end
    if currentTweenConn then currentTweenConn:Disconnect(); currentTweenConn = nil end
    teleportActive = false
end

local function notify(title, text)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text  = text,
        Time  = 4
    })
end

local function isPoliceNearby()
    local _, _, root = getChar()
    if not root then return false end

    local hum = root.Parent:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health <= 25 then
        return true
    end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= plr and p.Team and p.Team.Name == "Police" then
            local pChar = p.Character
            if pChar then
                local pRoot = pChar:FindFirstChild("HumanoidRootPart")
                if pRoot and (pRoot.Position - root.Position).Magnitude <= _G.vendingPoliceRange then
                    return true
                end
            end
        end
    end
    return false
end

local function fleeFromPolice()
    local char, hum, root = getChar()
    if not root then return end
    
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if vehicle then
        local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
        if driveSeat then
            root.CFrame = driveSeat.CFrame
            task.wait(0.05)
            driveSeat:Sit(hum)
            -- Kurze Flucht nach oben/vorne
            vehicle:PivotTo(vehicle:GetPivot() * CFrame.new(0, 50, 50))
        end
    end
end

local function startAutoCollect()
    local Character         = plr.Character or plr.CharacterAdded:Wait()
    local HumanoidRootPart = Character:WaitForChild("HumanoidRootPart")

    local Collected = {}
    local Range     = 30
    local myName    = plr.Name
    local dropsFolder = Workspace:WaitForChild("Drops")

    local function collectDrop(obj)
        if Collected[obj] then return end
        if not obj or not obj.Parent then return end
        if obj.Transparency ~= 0 then return end
        Collected[obj] = true
        task.spawn(function()
            if isPoliceNearby() then Collected[obj] = nil; return end
            RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, true)
            task.wait(ProximityPromptTimeBet)
            RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, false)
            task.wait(0.3)
            if obj and obj.Parent and obj.Transparency == 0 then
                Collected[obj] = nil
            end
        end)
    end

    local function loot()
        local _, _, root = getChar()
        if root then HumanoidRootPart = root end
        if not HumanoidRootPart then return end
        for _, obj in ipairs(dropsFolder:GetChildren()) do
            if obj:IsA("MeshPart") and obj.Name == myName and obj.Transparency == 0
                and not Collected[obj]
                and (obj.Position - HumanoidRootPart.Position).Magnitude <= Range
            then
                collectDrop(obj)
            end
        end
    end

    while _G.vendingActive do
        loot()
        task.wait(0.25)
    end
end

local function tweenTo(destination)
    if teleportActive then stopCurrentTween() end
    teleportActive = true

    local character = plr.Character or plr.CharacterAdded:Wait()
    local humanoid  = character:FindFirstChildOfClass("Humanoid")
    local hrp       = character:FindFirstChild("HumanoidRootPart")

    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false; return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false; return false end
    vehicle.PrimaryPart = driveSeat

    if humanoid and humanoid.SeatPart ~= driveSeat then
        if hrp then hrp.CFrame = driveSeat.CFrame end
        task.wait(0.1)
        driveSeat:Sit(humanoid)
    end

    local targetCF  = (typeof(destination) == "CFrame") and destination or CFrame.new(destination)
    local distance = (driveSeat.Position - targetCF.Position).Magnitude

    if distance > 1 then
        local duration = distance / _G.flightSpeed
        local val = Instance.new("CFrameValue")
        val.Value = vehicle:GetPivot()

        currentTweenConn = val.Changed:Connect(function(newCF)
            vehicle:PivotTo(newCF)
            driveSeat.AssemblyLinearVelocity = Vector3.new(0, 0.05, 0)
        end)

        currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
        currentTween:Play()
        
        -- Während des Fluges auf Polizei checken
        local policeInterrupted = false
        while currentTween and currentTween.PlaybackState == Enum.PlaybackState.Playing do
            if isPoliceNearby() then
                currentTween:Cancel()
                policeInterrupted = true
                break
            end
            task.wait(0.1)
        end
        
        if currentTweenConn then currentTweenConn:Disconnect(); currentTweenConn = nil end
        val:Destroy()
        if policeInterrupted then teleportActive = false; return false end
    end

    teleportActive = false
    clickAtCoordinates(0.5, 0.9)
    return true
end

local function plrTween(targetCFrame)
    local _, _, root = getChar()
    if not root then return end
    local tw = TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Linear), {CFrame = targetCFrame})
    tw:Play()
    tw.Completed:Wait()
end

local function isVendingReady(color)
    local targetR, targetG, targetB = 73/255, 147/255, 0/255
    return math.abs(color.R - targetR) < 0.05
end

local function findNearestRobbableVending()
    local folder = Workspace:FindFirstChild("Robberies") and Workspace.Robberies:FindFirstChild("VendingMachines")
    if not folder then return nil end
    local _, _, root = getChar()
    if not root then return nil end

    local nearest, minDist = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local light = model:FindFirstChild("Light")
        if light and isVendingReady(light.Color) then
            local dist = (light.Position - root.Position).Magnitude
            if dist < minDist then
                minDist = dist
                nearest = model
            end
        end
    end
    return nearest
end

local function VendingRob(targetVending)
    local glass = targetVending:FindFirstChild("Glass")
    if not glass then return false end

    local targetPos = glass.Position - glass.CFrame.LookVector * 12
    local lookDir   = glass.CFrame.RightVector

    if not tweenTo(CFrame.lookAt(targetPos, targetPos + lookDir)) then return false end

    task.wait(0.4)
    if isPoliceNearby() then fleeFromPolice(); return false end

    local _, hum, _ = getChar()
    if hum then hum.Sit = false end
    task.wait(0.5)

    local offsetPos = glass.Position - glass.CFrame.LookVector * 1.6
    plrTween(CFrame.lookAt(offsetPos, glass.Position))
    
    if isPoliceNearby() then fleeFromPolice(); return false end

    -- SCHNELLERER F-SPAM
    for i = 1, 10 do
        if isPoliceNearby() then fleeFromPolice(); return false end
        VirtualInputManager:SendKeyEvent(true,  Enum.KeyCode.F, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        task.wait(0.15)
    end

    task.wait(0.4)
    return true
end

-- SERVER HOP: Direkt 500 Studs hoch vom aktuellen Punkt
local function flyUpAndHop()
    notify("Server Hop", "Flying UP - Switching server!")
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if vehicle then
        local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
        if driveSeat then
            local _, hum, hrp = getChar()
            hrp.CFrame = driveSeat.CFrame
            task.wait(0.05)
            driveSeat:Sit(hum)
            
            local targetUp = vehicle:GetPivot() * CFrame.new(0, 500, 0)
            local tw = TweenService:Create(driveSeat, TweenInfo.new(0.5, Enum.EasingStyle.Linear), {CFrame = targetUp})
            tw:Play()
            tw.Completed:Wait()
        end
    end

    task.wait(0.2)
    if queue_on_teleport then
        pcall(function() queue_on_teleport([[wait(3); loadstring(game:HttpGet("https://raw.githubusercontent.com/fluxgitscripts/vending-rob/refs/heads/main/.lua"))()]]) end)
    end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")).data
    end)

    if success and servers then
        for _, server in pairs(servers) do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
                TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, plr)
                return
            end
        end
    end
    TeleportService:Teleport(game.PlaceId, plr)
end

local function vendingMainLoop()
    while _G.vendingActive do
        if not Workspace.Vehicles:FindFirstChild(plr.Name) then
            task.wait(2)
            continue
        end

        if isPoliceNearby() then
            fleeFromPolice()
            task.wait(3)
            continue
        end

        local target = findNearestRobbableVending()
        if not target then
            flyUpAndHop()
            break
        end

        VendingRob(target)
        task.wait(1.5)
    end
end

local function setVendingActive(enabled)
    _G.vendingActive = enabled
    if enabled then
        task.spawn(startAutoCollect)
        vendingLoopThread = task.spawn(vendingMainLoop)
        notify("Vending Rob", "Activated!")
    else
        if vendingLoopThread then task.cancel(vendingLoopThread); vendingLoopThread = nil end
        stopCurrentTween()
        notify("Vending Rob", "Deactivated!")
    end
end

local OrionLib = loadstring(game:HttpGet("https://moon-hub.pages.dev/orion.lua"))()
local Window = OrionLib:MakeWindow({Name = "MoonHub - Vending Rob", SaveConfig = true, ConfigFolder = "VendingRobConfig"})
local MainTab = Window:MakeTab({Name = "Vending Rob", Icon = "rbxassetid://4483345998"})

MainTab:AddToggle({
    Name = "Activate Vending Rob",
    Default = true,
    Callback = function(Value) setVendingActive(Value) end
})

MainTab:AddSlider({
    Name = "Flight Speed",
    Min = 50, Max = 250, Default = 160,
    Callback = function(Value) _G.flightSpeed = Value end
})

OrionLib:Init()
