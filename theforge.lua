-- == The Forge: Auto-Mine & Auto Mobs (Tabbed UI + Perfect Collision Snapshot) ==
pcall(function() setfpscap(60) end)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local HttpService       = game:GetService("HttpService")
local LocalPlayer       = Players.LocalPlayer

-- ==========================================
-- CONFIG SYSTEM
-- ==========================================
local ConfigFile = "ForgeMiner_Mobs_Config.json"

local defaults = {
    ToggleKey        = Enum.KeyCode.RightShift,
    FlySpeed         = 80,

    AutoMine         = false,
    StandDistance    = 3,
    RightOffset      = 2.5,
    MinDelay         = 0.25,
    MaxDelay         = 0.4,
    SelectedRocks    = {},
    RotateToRock     = true,
    SkipDurationRock = 30,
    StuckTimeoutRock = 10,

    FlyToMob         = false,
    MobHeightOffset  = 3,
    MobSideOffset    = 1,
    TimeoutDelayMob  = 5,
    SkipDurationMob  = 15,
    SelectedMobs     = {},
}

local function SaveConfig()
    if not writefile then return end
    local data = {
        AutoMine         = false,
        StandDistance    = getgenv().Config.StandDistance,
        RightOffset      = getgenv().Config.RightOffset,
        MinDelay         = getgenv().Config.MinDelay,
        MaxDelay         = getgenv().Config.MaxDelay,
        SelectedRocks    = getgenv().Config.SelectedRocks,
        RotateToRock     = getgenv().Config.RotateToRock,
        SkipDurationRock = getgenv().Config.SkipDurationRock,
        StuckTimeoutRock = getgenv().Config.StuckTimeoutRock,

        FlyToMob         = getgenv().Config.FlyToMob,
        MobHeightOffset  = getgenv().Config.MobHeightOffset,
        MobSideOffset    = getgenv().Config.MobSideOffset,
        TimeoutDelayMob  = getgenv().Config.TimeoutDelayMob,
        SkipDurationMob  = getgenv().Config.SkipDurationMob,
        SelectedMobs     = getgenv().Config.SelectedMobs,

        ToggleKey        = getgenv().Config.ToggleKey.Name,
        FlySpeed         = getgenv().Config.FlySpeed,
    }
    local success, encoded = pcall(function() return HttpService:JSONEncode(data) end)
    if success then
        pcall(writefile, ConfigFile, encoded)
    end
end

local function LoadConfig()
    getgenv().Config = {}
    for k, v in pairs(defaults) do getgenv().Config[k] = v end

    if not isfile or not readfile then return end
    if isfile(ConfigFile) then
        local success, content = pcall(readfile, ConfigFile)
        if success and content then
            local decodeSuccess, data = pcall(function() return HttpService:JSONDecode(content) end)
            if decodeSuccess and type(data) == "table" then
                for k, v in pairs(data) do
                    if k == "ToggleKey" then
                        local key = Enum.KeyCode[v]
                        if key then getgenv().Config[k] = key end
                    elseif k == "SelectedRocks" or k == "SelectedMobs" then
                        if type(v) == "table" then getgenv().Config[k] = v end
                    elseif k ~= "AutoMine" then
                        getgenv().Config[k] = v
                    end
                end
            end
        end
    end
    getgenv().Config.AutoMine = false
end

LoadConfig()

-- ==========================================
-- STATE
-- ==========================================
local Connections = {}
local function Track(conn) table.insert(Connections, conn); return conn end

if getgenv().CombinedScriptLoaded then
    pcall(function()
        if getgenv().CombinedCleanup then getgenv().CombinedCleanup() end
    end)
    task.wait(0.3)
end

getgenv().ScriptActive      = true
getgenv().CurrentScriptTick = tick()
local MyTick = getgenv().CurrentScriptTick
getgenv().CombinedScriptLoaded = true

local SavedHumanoid  = {}
local InitialCollisions = {} -- Stores collision state from script startup
local CamConnection  = nil
local AttackTarget   = nil

local CurrentRock    = nil
local RockPhase      = "Top" 
local RockStartTime  = 0
local SkippedRocks   = {}

local CurrentMob     = nil
local HasArrivedMob  = false
local MobWaitStartTime = 0
local SkippedMobs    = {}

local function Alive()
    return getgenv().ScriptActive and getgenv().CurrentScriptTick == MyTick
end

-- ==========================================
-- COLLISION SNAPSHOT LOGIC
-- ==========================================
local function SnapshotCollisions()
    local char = LocalPlayer.Character
    if not char then return end
    
    -- Clear old snapshot
    InitialCollisions = {}
    
    -- Save current state of all BaseParts
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            InitialCollisions[v] = v.CanCollide
        end
    end
end

-- Take snapshot immediately if character exists
if LocalPlayer.Character then
    SnapshotCollisions()
end

-- Take snapshot if character respawns while script is running
Track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    SnapshotCollisions()
end))

local function RestoreCollisions()
    local char = LocalPlayer.Character
    if not char then return end
    
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            if InitialCollisions[v] ~= nil then
                -- Restore exactly as it was at the beginning
                v.CanCollide = InitialCollisions[v]
            else
                -- Fallback for newly spawned parts (e.g. tools)
                -- Body parts default to true, HRP and accessories to false
                v.CanCollide = (v.Name ~= "HumanoidRootPart") and not v:FindFirstAncestorOfClass("Accessory")
            end
        end
    end
end

-- ==========================================
-- SHARED HELPERS
-- ==========================================
local function SaveHumanoidState(hum)
    if SavedHumanoid.Saved then return end
    pcall(function()
        SavedHumanoid.WalkSpeed  = hum.WalkSpeed
        SavedHumanoid.JumpPower  = hum.JumpPower
        SavedHumanoid.AutoRotate = hum.AutoRotate
        SavedHumanoid.Saved = true
    end)
end

local function RestoreHumanoidState(hum)
    if not SavedHumanoid.Saved then return end
    pcall(function() hum.WalkSpeed  = SavedHumanoid.WalkSpeed  end)
    pcall(function() hum.JumpPower  = SavedHumanoid.JumpPower  end)
    pcall(function() hum.AutoRotate = SavedHumanoid.AutoRotate end)
    SavedHumanoid = {}
end

local function UnanchorRoot()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if hrp and hrp.Anchored then hrp.Anchored = false end
end

local function ToggleNoclip(enabled)
    getgenv().Noclip = enabled
    local char = LocalPlayer.Character
    if not char then return end
    
    if enabled then
        -- Disable collision temporarily
        for _, v in ipairs(char:GetDescendants()) do
            if v:IsA("BasePart") then
                v.CanCollide = false
            end
        end
    else
        -- Restore exact snapshot
        RestoreCollisions()
    end
end

local function KillMovers()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    for _, n in ipairs({"MinerFly","MinerFreeze","MinerGyro","MobFly","MobGyro"}) do
        local m = hrp:FindFirstChild(n); if m then m:Destroy() end
    end
end

local function StopCameraLock()
    if CamConnection then
        CamConnection:Disconnect()
        CamConnection = nil
    end
    AttackTarget = nil
    local cam = workspace.CurrentCamera
    if cam then
        cam.CameraType = Enum.CameraType.Custom
    end
end

-- ==========================================
-- CLEANUP (Perfect Restoration, Keeps Config)
-- ==========================================
local function Cleanup()
    -- 1. Stop all loops
    getgenv().ScriptActive = false
    
    -- 2. Restore character physical state
    ToggleNoclip(false) -- This calls RestoreCollisions
    StopCameraLock()

    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then 
            hrp.Anchored = false
            hrp.AssemblyLinearVelocity = Vector3.zero 
        end
        
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            RestoreHumanoidState(hum)
            hum.PlatformStand = false
            hum.AutoRotate = true
            
            -- Force standard humanoid values if something went wrong
            if hum.WalkSpeed <= 0 then hum.WalkSpeed = 16 end
            if hum.JumpPower <= 0 then hum.JumpPower = 50 end

            if hum:GetState() == Enum.HumanoidStateType.Physics
                or hum:GetState() == Enum.HumanoidStateType.Freefall then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        
        KillMovers()
    end

    -- 3. Disconnect all events
    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Connections)

    -- 4. Destroy UI
    if getgenv().CombinedUI then 
        getgenv().CombinedUI:Destroy() 
        getgenv().CombinedUI = nil 
    end
    
    -- 5. Clear specific flags but KEEP Config
    getgenv().CurrentScriptTick = nil
    getgenv().CombinedScriptLoaded = nil
    getgenv().CombinedCleanup = nil
    getgenv().Noclip = nil
    
    print("[The Forge] Script stopped. Collisions restored to startup snapshot. Config saved.")
end
getgenv().CombinedCleanup = Cleanup

-- ==========================================
-- MINING HELPERS
-- ==========================================
local ToolActivate
pcall(function()
    local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
    local PK     = Shared and Shared:FindFirstChild("Packages")
    local Knit   = PK and PK:FindFirstChild("Knit")
    local Svc    = Knit and Knit:FindFirstChild("Services")
    local TS     = Svc and Svc:FindFirstChild("ToolService")
    local RF     = TS and TS:FindFirstChild("RF")
    ToolActivate = RF and RF:FindFirstChild("ToolActivated")
end)

local function GetRockHP(Hitbox)
    local Model = Hitbox:FindFirstAncestorWhichIsA("Model")
    if not Model then return nil end
    local Info = Model:FindFirstChild("infoFrame", true)
    if not Info then return nil end
    local Frame = Info:FindFirstChild("Frame")
    if not Frame then return nil end
    local Label = Frame:FindFirstChild("rockHP")
    if not Label or not Label:IsA("TextLabel") then return nil end
    local txt = (Label.Text or ""):gsub(",", ""):gsub("[^%d]", "")
    return tonumber(txt)
end

local function IsMineableRock(Hitbox)
    local Model = Hitbox:FindFirstAncestorWhichIsA("Model")
    if not Model then return false end
    return Model:FindFirstChild("infoFrame", true) ~= nil
end

local function GetRockLookPos(Hitbox, phase)
    if phase == "Top" then
        return Hitbox.Position + Vector3.new(0, Hitbox.Size.Y / 2, 0)
    else
        return Hitbox.Position - Vector3.new(0, Hitbox.Size.Y / 2, 0)
    end
end

local function GetRockStandPos(Hitbox, phase)
    local lookPos = GetRockLookPos(Hitbox, phase)
    local rightVec = Hitbox.CFrame.RightVector
    local offsetPos = lookPos + (rightVec * getgenv().Config.RightOffset)
    
    local yOffset = (phase == "Top") and getgenv().Config.StandDistance or -getgenv().Config.StandDistance
    return offsetPos + Vector3.new(0, yOffset, 0) + Vector3.new(0.1, 0, 0.1)
end

local function IsRockSkipped(hitbox)
    local model = hitbox:FindFirstAncestorWhichIsA("Model")
    if not model then return false end
    if not model.Parent then SkippedRocks[model] = nil; return false end
    local t = SkippedRocks[model]
    if not t then return false end
    if tick() - t > getgenv().Config.SkipDurationRock then
        SkippedRocks[model] = nil
        return false
    end
    return true
end

local function RockMatches(hitbox)
    local model = hitbox:FindFirstAncestorWhichIsA("Model")
    if not model then return false end
    if #getgenv().Config.SelectedRocks == 0 then return false end
    for _, sel in ipairs(getgenv().Config.SelectedRocks) do
        if model.Name:find(sel, 1, true) then return true end
    end
    return false
end

local function FindClosestRock(HRP)
    local closest, bestDist = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Hitbox" and obj:IsA("BasePart") and IsMineableRock(obj) then
            if RockMatches(obj) and not IsRockSkipped(obj) then
                local hp = GetRockHP(obj)
                if hp and hp > 0 then
                    local standPos = GetRockStandPos(obj, "Bottom")
                    local dist = (HRP.Position - standPos).Magnitude
                    if dist < bestDist then
                        closest = obj
                        bestDist = dist
                    end
                end
            end
        end
    end
    return closest, bestDist
end

local function ActivateMiningTool()
    if ToolActivate then 
        pcall(function() ToolActivate:InvokeServer() end) 
    end
    pcall(function()
        if typeof(mouse1click) == "function" then 
            mouse1click() 
        end
    end)
end

-- ==========================================
-- MOB HELPERS
-- ==========================================
local function IsEnemyAlive(model)
    if not model or not model.Parent then return false end
    if not model:IsA("Model") then return false end
    if model == LocalPlayer.Character then return false end
    
    local hum = model:FindFirstChildOfClass("Humanoid")
    local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
    
    if hum and root and hum.Health > 0 then
        if not Players:GetPlayerFromCharacter(model) then
            return true
        end
    end
    return false
end

local function IsMobSkipped(mob)
    if not mob then return false end
    if not mob.Parent then SkippedMobs[mob] = nil; return false end
    local t = SkippedMobs[mob]
    if not t then return false end
    if tick() - t > getgenv().Config.SkipDurationMob then
        SkippedMobs[mob] = nil
        return false
    end
    return true
end

local function MobMatches(mob)
    if #getgenv().Config.SelectedMobs == 0 then return false end
    for _, sel in ipairs(getgenv().Config.SelectedMobs) do
        if mob.Name:find(sel, 1, true) then return true end
    end
    return false
end

local function FindClosestMob(HRP)
    local closest, bestDist = nil, math.huge
    for _, model in ipairs(workspace:GetDescendants()) do
        if IsEnemyAlive(model) and MobMatches(model) and not IsMobSkipped(model) then
            local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
            if root then
                local dist = (HRP.Position - root.Position).Magnitude
                if dist < bestDist then
                    closest = model
                    bestDist = dist
                end
            end
        end
    end
    return closest, bestDist
end

-- ==========================================
-- UI CREATION
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ForgeCombinedUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
getgenv().CombinedUI = ScreenGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 520, 0, 450)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -225)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)
local Stroke = Instance.new("UIStroke", MainFrame)
Stroke.Color = Color3.fromRGB(60, 60, 70)

local TopBar = Instance.new("Frame")
TopBar.Size = UDim2.new(1, 0, 0, 35)
TopBar.BackgroundTransparency = 1
TopBar.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, -100, 1, 0)
Title.Position = UDim2.new(0, 15, 0, 0)
Title.BackgroundTransparency = 1
Title.Text = "The Forge | Combined Script"
Title.TextColor3 = Color3.fromRGB(255, 255, 255)
Title.Font = Enum.Font.GothamBold
Title.TextSize = 14
Title.TextXAlignment = Enum.TextXAlignment.Left
Title.Parent = TopBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 25, 0, 25)
CloseBtn.Position = UDim2.new(1, -35, 0, 5)
CloseBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = TopBar
Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 4)
CloseBtn.MouseButton1Click:Connect(function() MainFrame.Visible = false end)

local Sidebar = Instance.new("Frame")
Sidebar.Size = UDim2.new(0, 130, 1, -35)
Sidebar.Position = UDim2.new(0, 0, 0, 35)
Sidebar.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
Sidebar.Parent = MainFrame
Instance.new("UICorner", Sidebar).CornerRadius = UDim.new(0, 8)
local SL = Instance.new("UIListLayout")
SL.Padding = UDim.new(0, 5)
SL.HorizontalAlignment = Enum.HorizontalAlignment.Center
SL.Parent = Sidebar
Instance.new("UIPadding", Sidebar).PaddingTop = UDim.new(0, 10)

local ContentArea = Instance.new("Frame")
ContentArea.Size = UDim2.new(1, -130, 1, -35)
ContentArea.Position = UDim2.new(0, 130, 0, 35)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainFrame

-- Helpers
local function CreateTabButton(name, order)
    local B = Instance.new("TextButton")
    B.Size = UDim2.new(0, 110, 0, 35)
    B.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    B.Text = name
    B.TextColor3 = Color3.fromRGB(180, 180, 180)
    B.Font = Enum.Font.GothamSemibold
    B.TextSize = 13
    B.LayoutOrder = order
    B.Parent = Sidebar
    Instance.new("UICorner", B).CornerRadius = UDim.new(0, 6)
    return B
end

local function CreateStatusBox(parent, order)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, 40)
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Frame.LayoutOrder = order
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 4)

    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -16, 1, -8)
    Label.Position = UDim2.new(0, 8, 0, 4)
    Label.BackgroundTransparency = 1
    Label.Text = "Status: Idle"
    Label.TextColor3 = Color3.fromRGB(180, 220, 255)
    Label.Font = Enum.Font.Code
    Label.TextSize = 12
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.TextYAlignment = Enum.TextYAlignment.Top
    Label.Parent = Frame
    return Label
end

local function CreateToggle(parent, text, default, order, callback)
    local C = Instance.new("Frame")
    C.Size = UDim2.new(1, 0, 0, 30)
    C.BackgroundTransparency = 1
    C.LayoutOrder = order
    C.Parent = parent

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -60, 1, 0)
    L.BackgroundTransparency = 1
    L.Text = text
    L.TextColor3 = Color3.fromRGB(220, 220, 220)
    L.Font = Enum.Font.Gotham
    L.TextSize = 14
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = C

    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(0, 40, 0, 20)
    Btn.Position = UDim2.new(1, -40, 0.5, -10)
    Btn.BackgroundColor3 = default and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(50, 50, 60)
    Btn.Text = ""
    Btn.Parent = C
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(1, 0)

    local Knob = Instance.new("Frame")
    Knob.Size = UDim2.new(0, 16, 0, 16)
    Knob.Position = default and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
    Knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    Knob.Parent = Btn
    Instance.new("UICorner", Knob).CornerRadius = UDim.new(1, 0)

    local state = default
    local function setVisual(newState, skipCallback)
        state = newState
        TweenService:Create(Btn, TweenInfo.new(0.2),
            {BackgroundColor3 = state and Color3.fromRGB(60,120,200) or Color3.fromRGB(50,50,60)}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.2),
            {Position = state and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}):Play()
        if not skipCallback then callback(state) end
    end

    Btn.MouseButton1Click:Connect(function()
        setVisual(not state, false)
        SaveConfig()
    end)

    return { Button = Btn, Knob = Knob, Set = setVisual }
end

local function CreateInput(parent, text, default, order, callback)
    local C = Instance.new("Frame")
    C.Size = UDim2.new(1, 0, 0, 30)
    C.BackgroundTransparency = 1
    C.LayoutOrder = order
    C.Parent = parent

    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -90, 1, 0)
    L.BackgroundTransparency = 1
    L.Text = text
    L.TextColor3 = Color3.fromRGB(220, 220, 220)
    L.Font = Enum.Font.Gotham
    L.TextSize = 14
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.Parent = C

    local Box = Instance.new("TextBox")
    Box.Size = UDim2.new(0, 80, 0, 24)
    Box.Position = UDim2.new(1, -80, 0.5, -12)
    Box.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
    Box.TextColor3 = Color3.fromRGB(60, 120, 200)
    Box.Font = Enum.Font.GothamBold
    Box.TextSize = 14
    Box.Text = tostring(default)
    Box.Parent = C
    Instance.new("UICorner", Box).CornerRadius = UDim.new(0, 4)
    Instance.new("UIStroke", Box).Color = Color3.fromRGB(70, 70, 80)

    Box.FocusLost:Connect(function()
        local val = tonumber(Box.Text)
        if not val then val = default end
        Box.Text = tostring(val)
        callback(val)
        SaveConfig()
    end)
end

local function CreateButton(parent, text, order, callback)
    local Btn = Instance.new("TextButton")
    Btn.Size = UDim2.new(1, 0, 0, 35)
    Btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
    Btn.Text = text
    Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    Btn.Font = Enum.Font.GothamSemibold
    Btn.TextSize = 14
    Btn.LayoutOrder = order
    Btn.Parent = parent
    Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)
    Btn.MouseButton1Click:Connect(callback)
    return Btn
end

local function CreateList(parent, height, order)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, height)
    Frame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
    Frame.LayoutOrder = order
    Frame.Parent = parent
    Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 6)

    local Scroll = Instance.new("ScrollingFrame")
    Scroll.Size = UDim2.new(1, -10, 1, -10)
    Scroll.Position = UDim2.new(0, 5, 0, 5)
    Scroll.BackgroundTransparency = 1
    Scroll.ScrollBarThickness = 2
    Scroll.ScrollBarImageColor3 = Color3.fromRGB(60, 120, 200)
    Scroll.Parent = Frame
    Instance.new("UIListLayout", Scroll).Padding = UDim.new(0, 5)
    return Scroll
end

-- ==========================================
-- BUILD TABS
-- ==========================================
local TabMiningBtn = CreateTabButton("Mining", 1)
local TabMobsBtn   = CreateTabButton("Mobs", 2)
local TabSettingsBtn = CreateTabButton("Settings", 3)

-- 1. MINING TAB
local MiningTab = Instance.new("ScrollingFrame")
MiningTab.Size = UDim2.new(1, -20, 1, -10)
MiningTab.Position = UDim2.new(0, 10, 0, 5)
MiningTab.BackgroundTransparency = 1
MiningTab.ScrollBarThickness = 2
MiningTab.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
MiningTab.Parent = ContentArea
Instance.new("UIListLayout", MiningTab).Padding = UDim.new(0, 10)

local MineStatusLabel = CreateStatusBox(MiningTab, 1)
local MineToggle, MobToggle

MineToggle = CreateToggle(MiningTab, "Auto-Mine", getgenv().Config.AutoMine, 2, function(s)
    getgenv().Config.AutoMine = s
    if s then
        if getgenv().Config.FlyToMob then
            MobToggle.Set(false, true)
            getgenv().Config.FlyToMob = false
            CurrentMob = nil
            HasArrivedMob = false
            ToggleNoclip(false)
            UnanchorRoot()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    RestoreHumanoidState(hum)
                    hum.PlatformStand = false
                end
            end
            KillMovers()
        end
    else
        CurrentRock = nil
        StopCameraLock()
        ToggleNoclip(false)
        UnanchorRoot()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                RestoreHumanoidState(hum)
                hum.PlatformStand = false
            end
        end
        KillMovers()
    end
end)

CreateToggle(MiningTab, "Aim Camera", getgenv().Config.RotateToRock, 3, function(s) getgenv().Config.RotateToRock = s end)
CreateInput(MiningTab, "Swing Delay (ms)", math.floor(getgenv().Config.MinDelay * 1000), 4, function(v)
    getgenv().Config.MinDelay = v / 1000
    getgenv().Config.MaxDelay = (v + 100) / 1000
end)
CreateInput(MiningTab, "Stuck Timeout (s)", getgenv().Config.StuckTimeoutRock, 5, function(v) getgenv().Config.StuckTimeoutRock = v end)
CreateInput(MiningTab, "Skip Duration (s)", getgenv().Config.SkipDurationRock, 6, function(v) getgenv().Config.SkipDurationRock = v end)

local RockList = CreateList(MiningTab, 150, 8)
CreateButton(MiningTab, "Rescan Rocks", 7, function()
    local types, total = {}, 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Hitbox" and obj:IsA("BasePart") and IsMineableRock(obj) then
            local model = obj:FindFirstAncestorWhichIsA("Model")
            if model then
                local base = model.Name:gsub("%s*%b()$", ""):gsub("%s*%d+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
                if base ~= "" then types[base] = (types[base] or 0) + 1; total = total + 1 end
            end
        end
    end
    local names = {}
    for n in pairs(types) do table.insert(names, n) end
    table.sort(names)
    
    for _, ch in ipairs(RockList:GetChildren()) do
        if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end
    end

    if total == 0 then
        local L = Instance.new("TextLabel")
        L.Size = UDim2.new(1, 0, 0, 40)
        L.BackgroundTransparency = 1
        L.Text = "No rocks found."
        L.TextColor3 = Color3.fromRGB(200, 120, 120)
        L.Parent = RockList
        return
    end

    local existing = {}
    for _, n in ipairs(names) do existing[n] = true end
    for i = #getgenv().Config.SelectedRocks, 1, -1 do
        if not existing[getgenv().Config.SelectedRocks[i]] then table.remove(getgenv().Config.SelectedRocks, i) end
    end

    local function selected(name)
        for _, n in ipairs(getgenv().Config.SelectedRocks) do if n == name then return true end end
        return false
    end

    for i, n in ipairs(names) do
        local on = selected(n)
        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, 0, 0, 25)
        Btn.BackgroundColor3 = on and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(50, 50, 60)
        Btn.Text = string.format("%s %s", n, on and "ON" or "OFF")
        Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        Btn.Font = Enum.Font.Gotham
        Btn.TextSize = 13
        Btn.LayoutOrder = i
        Btn.Parent = RockList
        Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)

        Btn.MouseButton1Click:Connect(function()
            local removed = false
            for idx, name in ipairs(getgenv().Config.SelectedRocks) do
                if name == n then
                    table.remove(getgenv().Config.SelectedRocks, idx)
                    removed = true; break
                end
            end
            if removed then
                Btn.Text = string.format("%s OFF", n)
                Btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            else
                table.insert(getgenv().Config.SelectedRocks, n)
                Btn.Text = string.format("%s ON", n)
                Btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
            end
            CurrentRock = nil
            SaveConfig()
        end)
    end
    RockList.CanvasSize = UDim2.new(0, 0, 0, #names * 30)
    MineStatusLabel.Text = string.format("Loaded %d rock types.", #names)
end)

-- 2. MOBS TAB
local MobsTab = Instance.new("ScrollingFrame")
MobsTab.Size = UDim2.new(1, -20, 1, -10)
MobsTab.Position = UDim2.new(0, 10, 0, 5)
MobsTab.BackgroundTransparency = 1
MobsTab.ScrollBarThickness = 2
MobsTab.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
MobsTab.Visible = false
MobsTab.Parent = ContentArea
Instance.new("UIListLayout", MobsTab).Padding = UDim.new(0, 10)

local MobStatusLabel = CreateStatusBox(MobsTab, 1)

MobToggle = CreateToggle(MobsTab, "Auto Mobs", getgenv().Config.FlyToMob, 2, function(s)
    getgenv().Config.FlyToMob = s
    if s then
        if getgenv().Config.AutoMine then
            MineToggle.Set(false, true)
            getgenv().Config.AutoMine = false
            CurrentRock = nil
            StopCameraLock()
            ToggleNoclip(false)
            UnanchorRoot()
            local char = LocalPlayer.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum then
                    RestoreHumanoidState(hum)
                    hum.PlatformStand = false
                end
            end
            KillMovers()
        end
    else
        CurrentMob = nil
        HasArrivedMob = false
        ToggleNoclip(false)
        UnanchorRoot()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                RestoreHumanoidState(hum)
                hum.PlatformStand = false
            end
        end
        KillMovers()
    end
end)

CreateInput(MobsTab, "Height Offset", getgenv().Config.MobHeightOffset, 3, function(v) getgenv().Config.MobHeightOffset = v end)
CreateInput(MobsTab, "Timeout Delay (s)", getgenv().Config.TimeoutDelayMob, 4, function(v) getgenv().Config.TimeoutDelayMob = v end)
CreateInput(MobsTab, "Skip Duration (s)", getgenv().Config.SkipDurationMob, 5, function(v) getgenv().Config.SkipDurationMob = v end)

local MobList = CreateList(MobsTab, 150, 7)
CreateButton(MobsTab, "Rescan Mobs", 6, function()
    local types, total = {}, 0
    for _, model in ipairs(workspace:GetDescendants()) do
        if IsEnemyAlive(model) then
            local base = model.Name:gsub("%s*%b()$", ""):gsub("%s*%d+$", ""):gsub("^%s+", ""):gsub("%s+$", "")
            if base ~= "" then types[base] = (types[base] or 0) + 1; total = total + 1 end
        end
    end

    local names = {}
    for n in pairs(types) do table.insert(names, n) end
    table.sort(names)
    
    for _, ch in ipairs(MobList:GetChildren()) do
        if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end
    end

    if total == 0 then
        local L = Instance.new("TextLabel")
        L.Size = UDim2.new(1, 0, 0, 40)
        L.BackgroundTransparency = 1
        L.Text = "No mobs found."
        L.TextColor3 = Color3.fromRGB(200, 120, 120)
        L.Parent = MobList
        return
    end

    local existing = {}
    for _, n in ipairs(names) do existing[n] = true end
    for i = #getgenv().Config.SelectedMobs, 1, -1 do
        if not existing[getgenv().Config.SelectedMobs[i]] then table.remove(getgenv().Config.SelectedMobs, i) end
    end

    local function selected(name)
        for _, n in ipairs(getgenv().Config.SelectedMobs) do if n == name then return true end end
        return false
    end

    for i, n in ipairs(names) do
        local on = selected(n)
        local Btn = Instance.new("TextButton")
        Btn.Size = UDim2.new(1, 0, 0, 25)
        Btn.BackgroundColor3 = on and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(50, 50, 60)
        Btn.Text = string.format("%s %s", n, on and "ON" or "OFF")
        Btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        Btn.Font = Enum.Font.Gotham
        Btn.TextSize = 13
        Btn.LayoutOrder = i
        Btn.Parent = MobList
        Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 4)

        Btn.MouseButton1Click:Connect(function()
            local removed = false
            for idx, name in ipairs(getgenv().Config.SelectedMobs) do
                if name == n then
                    table.remove(getgenv().Config.SelectedMobs, idx)
                    removed = true; break
                end
            end
            if removed then
                Btn.Text = string.format("%s OFF", n)
                Btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            else
                table.insert(getgenv().Config.SelectedMobs, n)
                Btn.Text = string.format("%s ON", n)
                Btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
            end
            CurrentMob = nil
            HasArrivedMob = false
            SaveConfig()
        end)
    end
    MobList.CanvasSize = UDim2.new(0, 0, 0, #names * 30)
    MobStatusLabel.Text = string.format("Loaded %d mob types.", #names)
end)

-- 3. SETTINGS TAB
local SettingsTab = Instance.new("Frame")
SettingsTab.Size = UDim2.new(1, -20, 1, -10)
SettingsTab.Position = UDim2.new(0, 10, 0, 5)
SettingsTab.BackgroundTransparency = 1
SettingsTab.Visible = false
SettingsTab.Parent = ContentArea
Instance.new("UIListLayout", SettingsTab).Padding = UDim.new(0, 10)

CreateInput(SettingsTab, "Fly Speed (Global)", getgenv().Config.FlySpeed, 1, function(v) getgenv().Config.FlySpeed = v end)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(1, 0, 0, 40)
StopBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
StopBtn.Text = "STOP SCRIPT"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.Font = Enum.Font.GothamBold
StopBtn.TextSize = 14
StopBtn.LayoutOrder = 2
StopBtn.Parent = SettingsTab
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 6)
StopBtn.MouseButton1Click:Connect(Cleanup)

-- TAB SWITCHING LOGIC
local function SwitchTab(activeTab, activeBtn, inactiveTab1, inactiveBtn1, inactiveTab2, inactiveBtn2)
    activeBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
    activeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    inactiveBtn1.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    inactiveBtn1.TextColor3 = Color3.fromRGB(180, 180, 180)
    inactiveBtn2.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    inactiveBtn2.TextColor3 = Color3.fromRGB(180, 180, 180)
    
    activeTab.Visible = true
    inactiveTab1.Visible = false
    inactiveTab2.Visible = false
end

TabMiningBtn.MouseButton1Click:Connect(function() SwitchTab(MiningTab, TabMiningBtn, MobsTab, TabMobsBtn, SettingsTab, TabSettingsBtn) end)
TabMobsBtn.MouseButton1Click:Connect(function() SwitchTab(MobsTab, TabMobsBtn, MiningTab, TabMiningBtn, SettingsTab, TabSettingsBtn) end)
TabSettingsBtn.MouseButton1Click:Connect(function() SwitchTab(SettingsTab, TabSettingsBtn, MiningTab, TabMiningBtn, MobsTab, TabMobsBtn) end)

-- Select Mining by default
TabMiningBtn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
TabMiningBtn.TextColor3 = Color3.fromRGB(255, 255, 255)

-- ==========================================
-- MINING LOOP
-- ==========================================
task.spawn(function()
    while Alive() do
        task.wait(0.1)

        if not getgenv().Config.AutoMine then
            task.wait(0.5)
        else
            local char = LocalPlayer.Character
            if char then
                local hum  = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")
                local tool = char:FindFirstChildOfClass("Tool")

                if hum and root and tool then
                    if #getgenv().Config.SelectedRocks == 0 then
                        MineStatusLabel.Text = "Status: Select rocks in list!"
                        task.wait(0.5)
                    else
                        local rock, _ = FindClosestRock(root)
                        if rock then
                            if CurrentRock ~= rock then
                                CurrentRock = rock
                                RockPhase = "Top"
                                RockStartTime = tick()
                            end

                            local targetPos = rock.Position
                            local standPos = GetRockStandPos(rock, RockPhase)
                            local distToStand = (root.Position - standPos).Magnitude

                            if distToStand > 3.5 then
                                StopCameraLock()
                                if root.Anchored then root.Anchored = false; task.wait(0.05) end
                                ToggleNoclip(true)
                                SaveHumanoidState(hum)
                                if not hum.PlatformStand then hum.PlatformStand = true end
                                pcall(function() hum.AutoRotate = false end)

                                local bv = root:FindFirstChild("MinerFly")
                                if not bv then bv = Instance.new("BodyVelocity", root); bv.Name = "MinerFly" end
                                bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)

                                local delta = standPos - root.Position
                                local safeSpeed = delta.Magnitude / 0.15
                                local speed = math.min(getgenv().Config.FlySpeed, safeSpeed)
                                speed = math.max(speed, 8)
                                bv.Velocity = delta.Unit * speed
                                
                                MineStatusLabel.Text = string.format("Flying to %s", rock:FindFirstAncestorWhichIsA("Model").Name)
                            else
                                KillMovers()
                                SaveHumanoidState(hum)
                                pcall(function() hum.WalkSpeed = 0 end)
                                pcall(function() hum.JumpPower = 0 end)
                                pcall(function() hum.AutoRotate = false end)

                                root.Anchored = true
                                local lookPos = GetRockLookPos(rock, RockPhase)
                                local targetCF = CFrame.lookAt(standPos, lookPos)
                                root.CFrame = targetCF

                                local gyro = root:FindFirstChild("MinerGyro")
                                if not gyro then gyro = Instance.new("BodyGyro", root); gyro.Name = "MinerGyro" end
                                gyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                                gyro.D = 500
                                gyro.P = 30000
                                gyro.CFrame = targetCF

                                if getgenv().Config.RotateToRock then
                                    AttackTarget = lookPos
                                    if not CamConnection then
                                        local cam = workspace.CurrentCamera
                                        if cam then cam.CameraType = Enum.CameraType.Scriptable end
                                        CamConnection = RunService.RenderStepped:Connect(function()
                                            if AttackTarget and workspace.CurrentCamera then
                                                workspace.CurrentCamera.CFrame = CFrame.lookAt(workspace.CurrentCamera.CFrame.Position, AttackTarget)
                                            end
                                        end)
                                    end
                                end

                                task.wait(0.05)
                                ActivateMiningTool()

                                MineStatusLabel.Text = string.format("Mining %s (%s)", rock:FindFirstAncestorWhichIsA("Model").Name, RockPhase)

                                if RockPhase == "Top" then RockPhase = "Bottom" end

                                if tick() - RockStartTime > getgenv().Config.StuckTimeoutRock then
                                    SkippedRocks[rock:FindFirstAncestorWhichIsA("Model")] = tick()
                                    CurrentRock = nil
                                    MineStatusLabel.Text = "Rock timeout. Skipped."
                                end
                                task.wait(getgenv().Config.MinDelay)
                            end
                        else
                            StopCameraLock()
                            ToggleNoclip(false)
                            UnanchorRoot()
                            if hum.PlatformStand then hum.PlatformStand = false end
                            RestoreHumanoidState(hum)
                            MineStatusLabel.Text = "Searching for rocks..."
                            task.wait(0.5)
                        end
                    end
                else
                    MineStatusLabel.Text = "No tool equipped!"
                    task.wait(1)
                end
            end
        end
    end
end)

-- ==========================================
-- MOB FLY LOOP
-- ==========================================
task.spawn(function()
    while Alive() do
        task.wait(0.1)

        if not getgenv().Config.FlyToMob then
            task.wait(0.5)
        else
            local char = LocalPlayer.Character
            if char then
                local hum  = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")

                if hum and root then
                    if #getgenv().Config.SelectedMobs == 0 then
                        MobStatusLabel.Text = "Status: Select mobs in list!"
                        task.wait(0.5)
                    else
                        if CurrentMob and not IsEnemyAlive(CurrentMob) then
                            CurrentMob = nil
                            HasArrivedMob = false
                        end

                        if not CurrentMob then
                            local mob, _ = FindClosestMob(root)
                            if mob then
                                CurrentMob = mob
                                HasArrivedMob = false
                            else
                                ToggleNoclip(false)
                                UnanchorRoot()
                                RestoreHumanoidState(hum)
                                hum.PlatformStand = false
                                MobStatusLabel.Text = "Searching for mobs..."
                                task.wait(0.5)
                            end
                        end

                        if CurrentMob then
                            local mobRoot = CurrentMob:FindFirstChild("HumanoidRootPart") or CurrentMob.PrimaryPart
                            if mobRoot then
                                local targetPos = mobRoot.Position
                                local rightVec = mobRoot.CFrame.RightVector
                                local standPos = targetPos - Vector3.new(0, getgenv().Config.MobHeightOffset, 0) + (rightVec * getgenv().Config.MobSideOffset)
                                
                                local distToStand = (root.Position - standPos).Magnitude

                                if not HasArrivedMob then
                                    if distToStand > 3.5 then
                                        if root.Anchored then root.Anchored = false; task.wait(0.05) end
                                        ToggleNoclip(true)
                                        SaveHumanoidState(hum)
                                        if not hum.PlatformStand then hum.PlatformStand = true end
                                        pcall(function() hum.AutoRotate = false end)

                                        local bv = root:FindFirstChild("MobFly")
                                        if not bv then bv = Instance.new("BodyVelocity", root); bv.Name = "MobFly" end
                                        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)

                                        local delta = standPos - root.Position
                                        local safeSpeed = delta.Magnitude / 0.15
                                        local speed = math.min(getgenv().Config.FlySpeed, safeSpeed)
                                        speed = math.max(speed, 8)
                                        bv.Velocity = delta.Unit * speed
                                        
                                        MobStatusLabel.Text = string.format("Flying to %s", CurrentMob.Name)
                                    else
                                        HasArrivedMob = true
                                        MobWaitStartTime = tick()
                                        
                                        KillMovers()
                                        ToggleNoclip(false)
                                        UnanchorRoot()
                                        pcall(function() hum.PlatformStand = false end)
                                        RestoreHumanoidState(hum)

                                        MobStatusLabel.Text = "Arrived! You have control."
                                    end
                                else
                                    local timeSinceArrival = tick() - MobWaitStartTime
                                    if timeSinceArrival > getgenv().Config.TimeoutDelayMob then
                                        if CurrentMob and CurrentMob.Parent then
                                            SkippedMobs[CurrentMob] = tick()
                                        end
                                        CurrentMob = nil
                                        HasArrivedMob = false
                                        MobStatusLabel.Text = "Timeout! Skipping mob."
                                        task.wait(1)
                                    else
                                        MobStatusLabel.Text = string.format("Killing... Skip in %.1fs", getgenv().Config.TimeoutDelayMob - timeSinceArrival)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)
