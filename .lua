local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")

local queue_on_teleport = syn and syn.queue_on_teleport or queue_on_teleport or (fluxus and fluxus.queue_on_teleport)

local plr = Players.LocalPlayer

local EJw = game:GetService("ReplicatedStorage"):WaitForChild("EJw")
local RemoteEvents = {
    RobEvent = EJw:WaitForChild("a3126821-130a-4135-80e1-1d28cece4007"),
    SellItem = EJw:WaitForChild("eb233e6a-acb9-4169-acb9-129fe8cb06bb"),
}

local VENDING_COLLECT_CODE = "wRl"
local ProximityPromptTimeBet = 1.2

_G.vendingActive = false
_G.flightSpeed = 240
_G.vendingPoliceRange = 55

local vendingLoopThread = nil
local instantCollectThread = nil

local teleportActive = false
local currentTween = nil
local currentTweenConn = nil
local tweenSpeed = _G.flightSpeed

local SERVERHOP_POSITION = Vector3.new(-1292.9005126953125, -2, 3685.330810546875)
local DROP_Y = -2
local SAFE_POSITION = Vector3.new(-1292.9005126953125, DROP_Y, 3685.330810546875)

local function getChar()
    local char = plr.Character
    if not char then return nil, nil, nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local root = char:FindFirstChild("HumanoidRootPart")
    return char, hum, root
end

local function clickAtCoordinates(rx, ry)
    local vp = Workspace.CurrentCamera.ViewportSize
    VirtualInputManager:SendMouseButtonEvent(vp.X * rx, vp.Y * ry, 0, true, game, 0)
    task.wait(0.02)
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
        Text = text,
        Time = 2
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

local function forceEnterVehicle()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if vehicle then
        local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
        if driveSeat then
            local _, hum, hrp = getChar()
            if hum and hrp then
                hrp.CFrame = driveSeat.CFrame
                task.wait(0.05)
                driveSeat:Sit(hum)
                task.wait(0.1)
                return true
            end
        end
    end
    return false
end

local function startAutoCollect()
    local dropsFolder = Workspace:WaitForChild("Drops")
    local myName = plr.Name

    while _G.vendingActive do
        for _, obj in ipairs(dropsFolder:GetChildren()) do
            if obj:IsA("MeshPart") and obj.Name == myName and obj.Transparency == 0 then
                task.spawn(function()
                    RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, true)
                    task.wait(ProximityPromptTimeBet)
                    RemoteEvents.RobEvent:FireServer(obj, VENDING_COLLECT_CODE, false)
                end)
            end
        end
        task.wait(0.2)
    end
end

local function tweenTo(destination)
    if teleportActive then stopCurrentTween() end
    teleportActive = true

    local character, humanoid, hrp = getChar()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if not vehicle then teleportActive = false; return false end

    local driveSeat = vehicle:FindFirstChild("DriveSeat", true) or vehicle:FindFirstChildWhichIsA("VehicleSeat", true)
    if not driveSeat then teleportActive = false; return false end
    vehicle.PrimaryPart = driveSeat

    if humanoid and humanoid.SeatPart ~= driveSeat then
        hrp.CFrame = driveSeat.CFrame
        task.wait(0.05)
        driveSeat:Sit(humanoid)
        task.wait(0.1)
    end

    local targetCF = (typeof(destination) == "CFrame") and destination or CFrame.new(destination)
    local targetPos = targetCF.Position
    local pivotNow = vehicle:GetPivot()
    
    vehicle:PivotTo(CFrame.new(Vector3.new(pivotNow.X, DROP_Y, pivotNow.Z)))
    driveSeat.AssemblyLinearVelocity = Vector3.zero
    driveSeat.AssemblyAngularVelocity = Vector3.zero

    local distance = (vehicle:GetPivot().Position - targetPos).Magnitude
    if distance > 0.5 then
        local duration = distance / _G.flightSpeed
        local val = Instance.new("CFrameValue")
        val.Value = vehicle:GetPivot()

        currentTweenConn = val.Changed:Connect(function(newCF)
            vehicle:PivotTo(newCF)
            driveSeat.AssemblyLinearVelocity = Vector3.new(0, 0.05, 0)
        end)

        currentTween = TweenService:Create(val, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCF})
        currentTween:Play()
        currentTween.Completed:Wait()

        if currentTweenConn then currentTweenConn:Disconnect(); currentTweenConn = nil end
        val:Destroy()
    end

    teleportActive = false
    clickAtCoordinates(0.5, 0.9)
    return true
end

local function plrTween(targetCFrame)
    local _, hum, root = getChar()
    if not root then return end
    local dist = (root.Position - targetCFrame.Position).Magnitude
    local duration = dist / 120
    local tVal = Instance.new("CFrameValue")
    tVal.Value = root.CFrame
    local conn = tVal.Changed:Connect(function(newCF)
        if root then root.CFrame = newCF end
    end)
    local tw = TweenService:Create(tVal, TweenInfo.new(duration, Enum.EasingStyle.Linear), {Value = targetCFrame})
    tw:Play()
    tw.Completed:Wait()
    conn:Disconnect()
    tVal:Destroy()
end

local function isVendingReady(color)
    return math.abs(color.R - (73/255)) < 0.1 and math.abs(color.G - (147/255)) < 0.1
end

local function findNearestRobbableVending()
    local folder = Workspace:FindFirstChild("Robberies") and Workspace.Robberies:FindFirstChild("VendingMachines")
    if not folder then return nil end
    local _, _, root = getChar()
    if not root then return nil end
    local nearest, minDist = nil, math.huge
    for _, model in ipairs(folder:GetChildren()) do
        local light = model:FindFirstChild("Light")
        local glass = model:FindFirstChild("Glass")
        if light and glass and isVendingReady(light.Color) then
            local dist = (glass.Position - root.Position).Magnitude
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
    if not tweenTo(CFrame.lookAt(targetPos, glass.Position)) then return false end

    task.wait(0.2)
    if isPoliceNearby() then forceEnterVehicle(); return false end

    local char, hum, root = getChar()
    if hum then hum.Sit = false end
    task.wait(0.3)

    local offsetPos = glass.Position - glass.CFrame.LookVector * 1.6
    plrTween(CFrame.lookAt(offsetPos, glass.Position))
    task.wait(0.1)

    for i = 1, 10 do
        if isPoliceNearby() then forceEnterVehicle(); return false end
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
        task.wait(0.05)
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        task.wait(0.1)
    end

    task.wait(0.5)
    return true
end

local function flyUpAndHop()
    local vehicle = Workspace.Vehicles:FindFirstChild(plr.Name)
    if vehicle then
        forceEnterVehicle()
        tweenTo(CFrame.new(SERVERHOP_POSITION + Vector3.new(0, 500, 0)))
    end

    if queue_on_teleport then
        pcall(function() queue_on_teleport("task.wait(2)\nloadstring(game:HttpGet('https://raw.githubusercontent.com/fluxgitscripts/testtext/refs/heads/main/.lua'))()") end)
    end

    local success, servers = pcall(function()
        return HttpService:JSONDecode(game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")).data
    end)

    if success then
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
        if isPoliceNearby() then
            forceEnterVehicle()
            task.wait(0.5)
        end

        local target = findNearestRobbableVending()
        if not target then
            flyUpAndHop()
            break
        end

        VendingRob(target)
        task.wait(0.4)
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
local Window = OrionLib:MakeWindow({Name = "MoonHub - Vending Rob", IntroText = "Launching Vending Rob...", SaveConfig = true, ConfigFolder = "VendingRobConfig"})
local MainTab = Window:MakeTab({Name = "Vending Rob", Icon = "rbxassetid://4483345998"})

MainTab:AddSection({Name = 'Robbery'})
MainTab:AddToggle({
    Name = "Activate Vending Rob",
    Default = true,
    Callback = function(Value) setVendingActive(Value) end
})

MainTab:AddSection({Name = 'Settings'})
MainTab:AddSlider({
    Name = "Flight Speed",
    Min = 50, Max = 400, Default = 240,
    Increment = 10,
    Callback = function(Value) _G.flightSpeed = Value end
})

MainTab:AddSlider({
    Name = "Police Detection Range",
    Min = 30, Max = 150, Default = 55,
    Increment = 5,
    Callback = function(Value) _G.vendingPoliceRange = Value end
})

local ConfigTab = Window:MakeTab({Name = "Config", Icon = "rbxassetid://4483345998"})
ConfigTab:AddButton({
    Name = "Reset Config",
    Callback = function() OrionLib:ResetConfiguration() end
})

OrionLib:Init()
