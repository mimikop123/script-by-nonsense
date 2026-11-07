-- == The Forge: Auto-Mine V49 (Top Hit then Bottom) ==
pcall(function() setfpscap(60) end)

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local LocalPlayer       = Players.LocalPlayer

-- ==========================================
-- STATE
-- ==========================================
local Connections = {}
local function Track(conn) table.insert(Connections, conn); return conn end

if getgenv().ForgeMinerLoaded then
    pcall(function()
        if getgenv().ForgeCleanup then getgenv().ForgeCleanup() end
    end)
    task.wait(0.3)
end

getgenv().ScriptActive      = true
getgenv().CurrentScriptTick = tick()
local MyTick = getgenv().CurrentScriptTick
getgenv().ForgeMinerLoaded  = true

local CurrentTarget  = nil
local TargetPhase    = "Top" -- "Top" или "Bottom"
local SavedHumanoid  = {}
local SkippedRocks   = {}
local TargetStartTime = 0

local function Alive()
    return getgenv().ScriptActive and getgenv().CurrentScriptTick == MyTick
end

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
    for _, v in ipairs(char:GetDescendants()) do
        if v:IsA("BasePart") then
            if v.Name == "HumanoidRootPart" then
                v.CanCollide = false
            elseif v.Name == "Head" or v.Name == "Torso" or v.Name == "UpperTorso"
                or v.Name == "LowerTorso" or v.Name:match("Arm")
                or v.Name:match("Leg")  or v.Name:match("Foot") then
                v.CanCollide = not enabled
            end
        end
    end
end

local function KillRockMovers()
    local char = LocalPlayer.Character
    if not char then return end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    for _, n in ipairs({"MinerFly","MinerFreeze","MinerGyro"}) do
        local m = hrp:FindFirstChild(n); if m then m:Destroy() end
    end
end

local function Cleanup()
    getgenv().ScriptActive = false
    ToggleNoclip(false)

    local char = LocalPlayer.Character
    if char then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.Anchored = false end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            RestoreHumanoidState(hum)
            hum.PlatformStand = false
            if hum:GetState() == Enum.HumanoidStateType.Physics
                or hum:GetState() == Enum.HumanoidStateType.Freefall then
                hum:ChangeState(Enum.HumanoidStateType.GettingUp)
            end
        end
        KillRockMovers()
    end

    for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
    table.clear(Connections)

    CurrentTarget = nil
    SkippedRocks  = {}
    if getgenv().ForgeUI then getgenv().ForgeUI:Destroy(); getgenv().ForgeUI = nil end
end
getgenv().ForgeCleanup = Cleanup

-- ==========================================
-- CONFIG
-- ==========================================
local defaults = {
    AutoMine         = false,
    StandDistance    = 3,
    RightOffset      = 2.5,
    FlySpeed         = 60,
    MinDelay         = 0.25,
    MaxDelay         = 0.4,
    SelectedRocks    = {},
    ToggleKey        = Enum.KeyCode.RightShift,
    SkipKey          = Enum.KeyCode.Z,
    AutoSelectAll    = false,
    RotateToRock     = false,
    SkipDuration     = 30,
    StuckTimeout     = 10,
}
getgenv().Config = getgenv().Config or {}
for k, v in pairs(defaults) do
    if getgenv().Config[k] == nil then getgenv().Config[k] = v end
end

-- ==========================================
-- TOOL ACTIVATION
-- ==========================================
local function ActivateTool()
    pcall(function()
        if typeof(mouse1click) == "function" then 
            mouse1click() 
        elseif typeof(VirtualUser) == "table" then
            VirtualUser:CaptureController()
            VirtualUser:ClickButton1(Vector2.new(0,0))
        end
    end)
end

local function EnsureToolEquipped(Character)
    if not Character then return nil end
    local tool = Character:FindFirstChildOfClass("Tool")
    if tool then return tool end
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    if not backpack then return nil end
    local bpTool = backpack:FindFirstChildOfClass("Tool")
    if not bpTool then return nil end
    local hum = Character:FindFirstChildOfClass("Humanoid")
    if not hum then return nil end
    pcall(function() hum:EquipTool(bpTool) end)
    task.wait(0.15)
    return Character:FindFirstChildOfClass("Tool") or bpTool
end

-- ==========================================
-- ROCK HELPERS
-- ==========================================
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

-- Функция возвращает точку, куда смотреть (верх или низ)
local function GetLookPos(Hitbox, phase)
    if phase == "Top" then
        return Hitbox.Position + Vector3.new(0, Hitbox.Size.Y / 2, 0)
    else
        return Hitbox.Position - Vector3.new(0, Hitbox.Size.Y / 2, 0)
    end
end

-- Функция возвращает позицию для телепорта/полета с учетом фазы и смещения
local function GetStandPos(Hitbox, phase)
    local lookPos = GetLookPos(Hitbox, phase)
    local rightVec = Hitbox.CFrame.RightVector
    local offsetPos = lookPos + (rightVec * getgenv().Config.RightOffset)
    
    local yOffset = (phase == "Top") and getgenv().Config.StandDistance or -getgenv().Config.StandDistance
    return offsetPos + Vector3.new(0, yOffset, 0) + Vector3.new(0.1, 0, 0.1)
end

local function IsSkipped(hitbox)
    local model = hitbox:FindFirstAncestorWhichIsA("Model")
    if not model then return false end
    if not model.Parent then SkippedRocks[model] = nil; return false end
    local t = SkippedRocks[model]
    if not t then return false end
    if tick() - t > getgenv().Config.SkipDuration then
        SkippedRocks[model] = nil
        return false
    end
    return true
end

local function CountSkipped()
    local n = 0
    for model, t in pairs(SkippedRocks) do
        if not model.Parent or tick() - t > getgenv().Config.SkipDuration then
            SkippedRocks[model] = nil
        else
            n = n + 1
        end
    end
    return n
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

local function ScanRockTypesInWorld()
    local types, total = {}, 0
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj.Name == "Hitbox" and obj:IsA("BasePart") and IsMineableRock(obj) then
            local model = obj:FindFirstAncestorWhichIsA("Model")
            if model then
                local base = model.Name
                    :gsub("%s*%b()$", "")
                    :gsub("%s*%d+$", "")
                    :gsub("^%s+", ""):gsub("%s+$", "")
                if base ~= "" then
                    types[base] = (types[base] or 0) + 1
                    total = total + 1
                end
            end
        end
    end
    return types, total
end

-- ==========================================
-- NOCLIP + CACHE LOOPS
-- ==========================================
task.spawn(function()
    while Alive() do
        task.wait(1)
        if getgenv().Noclip and LocalPlayer.Character then
            for _, v in ipairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("BasePart") and v.CanCollide then v.CanCollide = false end
            end
        end
    end
end)

Track(LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5); if getgenv().Noclip then ToggleNoclip(true) end
end))

local HitboxCache = {}
task.spawn(function()
    while Alive() do
        local newCache = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj.Name == "Hitbox" and obj:IsA("BasePart") and IsMineableRock(obj) then
                table.insert(newCache, obj)
            end
        end
        HitboxCache = newCache
        task.wait(0.7)
    end
end)

-- ==========================================
-- UI
-- ==========================================
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ForgeMinerModernUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
getgenv().ForgeUI = ScreenGui

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
Title.Text = "The Forge | Auto Miner V49"
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

local HomeTabBtn     = CreateTabButton("Home", 1)
local SettingsTabBtn = CreateTabButton("Settings", 2)

local HomeTab = Instance.new("ScrollingFrame")
HomeTab.Size = UDim2.new(1, -20, 1, -10)
HomeTab.Position = UDim2.new(0, 10, 0, 5)
HomeTab.BackgroundTransparency = 1
HomeTab.ScrollBarThickness = 2
HomeTab.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 120)
HomeTab.Parent = ContentArea
Instance.new("UIListLayout", HomeTab).Padding = UDim.new(0, 10)

local function CreateSectionLabel(text, parent, order)
    local L = Instance.new("TextLabel")
    L.Size = UDim2.new(1, -20, 0, 20)
    L.BackgroundTransparency = 1
    L.Text = text
    L.TextColor3 = Color3.fromRGB(100, 100, 120)
    L.Font = Enum.Font.GothamBold
    L.TextSize = 11
    L.TextXAlignment = Enum.TextXAlignment.Left
    L.LayoutOrder = order
    L.Parent = parent
    return L
end

local StatusFrame = Instance.new("Frame")
StatusFrame.Size = UDim2.new(1, 0, 0, 60)
StatusFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
StatusFrame.LayoutOrder = 0
StatusFrame.Parent = HomeTab
Instance.new("UICorner", StatusFrame).CornerRadius = UDim.new(0, 6)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -16, 1, -8)
StatusLabel.Position = UDim2.new(0, 8, 0, 4)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "Загрузка..."
StatusLabel.TextColor3 = Color3.fromRGB(180, 220, 255)
StatusLabel.Font = Enum.Font.Code
StatusLabel.TextSize = 12
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Parent = StatusFrame

local function SetStatus(txt) StatusLabel.Text = txt end

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
    Btn.MouseButton1Click:Connect(function()
        state = not state
        TweenService:Create(Btn, TweenInfo.new(0.2),
            {BackgroundColor3 = state and Color3.fromRGB(60,120,200) or Color3.fromRGB(50,50,60)}):Play()
        TweenService:Create(Knob, TweenInfo.new(0.2),
            {Position = state and UDim2.new(1,-18,0.5,-8) or UDim2.new(0,2,0.5,-8)}):Play()
        callback(state)
    end)
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
    
    local BoxStroke = Instance.new("UIStroke")
    BoxStroke.Color = Color3.fromRGB(70, 70, 80)
    BoxStroke.Parent = Box

    Box.FocusLost:Connect(function(enterPressed)
        local val = tonumber(Box.Text)
        if not val then val = default end
        Box.Text = tostring(val)
        callback(val)
    end)
end

CreateSectionLabel("MAIN SETTINGS", HomeTab, 1)

CreateToggle(HomeTab, "Auto-Mine", getgenv().Config.AutoMine, 2, function(s)
    getgenv().Config.AutoMine = s
    if not s then
        ToggleNoclip(false)
        UnanchorRoot()
        local char = LocalPlayer.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then
                RestoreHumanoidState(hum)
                hum.PlatformStand = false
            end
            KillRockMovers()
        end
        CurrentTarget = nil
    end
end)

CreateToggle(HomeTab, "Aim Camera at Rock", getgenv().Config.RotateToRock, 3, function(s)
    getgenv().Config.RotateToRock = s
    CurrentTarget = nil
end)

CreateInput(HomeTab, "Fly Speed", getgenv().Config.FlySpeed, 4,
    function(v) getgenv().Config.FlySpeed = v end)
    
CreateInput(HomeTab, "Depth Under Rock", getgenv().Config.StandDistance, 5,
    function(v) getgenv().Config.StandDistance = v; CurrentTarget = nil end)
    
CreateInput(HomeTab, "Right Offset", getgenv().Config.RightOffset, 6,
    function(v) getgenv().Config.RightOffset = v; CurrentTarget = nil end)
    
CreateInput(HomeTab, "Swing Delay (ms)", math.floor(getgenv().Config.MinDelay * 1000), 7,
    function(v)
        getgenv().Config.MinDelay = v / 1000
        getgenv().Config.MaxDelay = (v + 100) / 1000
    end)

CreateInput(HomeTab, "Stuck Timeout (0=Off)", getgenv().Config.StuckTimeout, 8,
    function(v) getgenv().Config.StuckTimeout = v end)

local RescanBtn = Instance.new("TextButton")
RescanBtn.Size = UDim2.new(1, 0, 0, 35)
RescanBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
RescanBtn.Text = "Rescan World"
RescanBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
RescanBtn.Font = Enum.Font.GothamSemibold
RescanBtn.TextSize = 14
RescanBtn.LayoutOrder = 9
RescanBtn.Parent = HomeTab
Instance.new("UICorner", RescanBtn).CornerRadius = UDim.new(0, 6)

local SkipBtn = Instance.new("TextButton")
SkipBtn.Size = UDim2.new(1, 0, 0, 40)
SkipBtn.BackgroundColor3 = Color3.fromRGB(180, 60, 60)
SkipBtn.Text = string.format("Skip Current Rock  [%s]", getgenv().Config.SkipKey.Name)
SkipBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SkipBtn.Font = Enum.Font.GothamBold
SkipBtn.TextSize = 14
SkipBtn.LayoutOrder = 10
SkipBtn.Parent = HomeTab
Instance.new("UICorner", SkipBtn).CornerRadius = UDim.new(0, 6)

CreateSectionLabel("DETECTED ROCKS", HomeTab, 11)

local RockListFrame = Instance.new("Frame")
RockListFrame.Size = UDim2.new(1, 0, 0, 150)
RockListFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
RockListFrame.LayoutOrder = 12
RockListFrame.Parent = HomeTab
Instance.new("UICorner", RockListFrame).CornerRadius = UDim.new(0, 6)

local RockList = Instance.new("ScrollingFrame")
RockList.Size = UDim2.new(1, -10, 1, -10)
RockList.Position = UDim2.new(0, 5, 0, 5)
RockList.BackgroundTransparency = 1
RockList.ScrollBarThickness = 2
RockList.ScrollBarImageColor3 = Color3.fromRGB(60, 120, 200)
RockList.Parent = RockListFrame
Instance.new("UIListLayout", RockList).Padding = UDim.new(0, 5)

-- === Settings ===
local SettingsTab = Instance.new("Frame")
SettingsTab.Size = UDim2.new(1, -20, 1, -10)
SettingsTab.Position = UDim2.new(0, 10, 0, 5)
SettingsTab.BackgroundTransparency = 1
SettingsTab.Visible = false
SettingsTab.Parent = ContentArea
Instance.new("UIListLayout", SettingsTab).Padding = UDim.new(0, 10)

CreateSectionLabel("SKIP ROCK", SettingsTab, 1)

CreateInput(SettingsTab, "Skip Duration (s)", getgenv().Config.SkipDuration, 2,
    function(v) getgenv().Config.SkipDuration = v end)

local SkipKeyBox = Instance.new("TextButton")
SkipKeyBox.Size = UDim2.new(1, 0, 0, 35)
SkipKeyBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
SkipKeyBox.Text = "Skip Key: " .. getgenv().Config.SkipKey.Name
SkipKeyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
SkipKeyBox.Font = Enum.Font.GothamSemibold
SkipKeyBox.TextSize = 14
SkipKeyBox.LayoutOrder = 3
SkipKeyBox.Parent = SettingsTab
Instance.new("UICorner", SkipKeyBox).CornerRadius = UDim.new(0, 6)

CreateSectionLabel("MENU TOGGLE KEYBIND", SettingsTab, 4)

local KeyBox = Instance.new("TextButton")
KeyBox.Size = UDim2.new(1, 0, 0, 35)
KeyBox.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
KeyBox.Text = getgenv().Config.ToggleKey.Name
KeyBox.TextColor3 = Color3.fromRGB(255, 255, 255)
KeyBox.Font = Enum.Font.GothamSemibold
KeyBox.TextSize = 14
KeyBox.LayoutOrder = 5
KeyBox.Parent = SettingsTab
Instance.new("UICorner", KeyBox).CornerRadius = UDim.new(0, 6)

local isBinding     = false
local bindMode      = nil

KeyBox.MouseButton1Click:Connect(function()
    if not isBinding then
        isBinding = true; bindMode = "toggle"
        KeyBox.Text = "Press any key..."
    end
end)

SkipKeyBox.MouseButton1Click:Connect(function()
    if not isBinding then
        isBinding = true; bindMode = "skip"
        SkipKeyBox.Text = "Press any key..."
    end
end)

local StopBtn = Instance.new("TextButton")
StopBtn.Size = UDim2.new(1, 0, 0, 40)
StopBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
StopBtn.Text = "STOP SCRIPT"
StopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
StopBtn.Font = Enum.Font.GothamBold
StopBtn.TextSize = 14
StopBtn.LayoutOrder = 6
StopBtn.Parent = SettingsTab
Instance.new("UICorner", StopBtn).CornerRadius = UDim.new(0, 6)

local function SetTab(aB, aT, iB, iT)
    aB.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
    aB.TextColor3 = Color3.fromRGB(255, 255, 255)
    iB.BackgroundColor3 = Color3.fromRGB(35, 35, 40)
    iB.TextColor3 = Color3.fromRGB(180, 180, 180)
    aT.Visible = true; iT.Visible = false
end
HomeTabBtn.MouseButton1Click:Connect(function() SetTab(HomeTabBtn, HomeTab, SettingsTabBtn, SettingsTab) end)
SettingsTabBtn.MouseButton1Click:Connect(function() SetTab(SettingsTabBtn, SettingsTab, HomeTabBtn, HomeTab) end)

StopBtn.MouseButton1Click:Connect(Cleanup)

-- ==========================================
-- SKIP LOGIC
-- ==========================================
local function SkipCurrentRock()
    local skippedAny = false

    if CurrentTarget and CurrentTarget.Parent then
        local model = CurrentTarget:FindFirstAncestorWhichIsA("Model")
        if model then
            SkippedRocks[model] = tick()
            skippedAny = true
        end
    end

    if not skippedAny then
        local char = LocalPlayer.Character
        if char then
            local root = char:FindFirstChild("HumanoidRootPart")
            if root then
                local closest = nil
                local minDist = math.huge
                for _, hitbox in ipairs(HitboxCache) do
                    if hitbox.Parent and RockMatches(hitbox) and not IsSkipped(hitbox) then
                        local d = (root.Position - hitbox.Position).Magnitude
                        local hp = GetRockHP(hitbox)
                        if hp and hp > 0 then
                            if d < minDist then closest, minDist = hitbox, d end
                        end
                    end
                end
                if closest then
                    local model = closest:FindFirstAncestorWhichIsA("Model")
                    if model then
                        SkippedRocks[model] = tick()
                        skippedAny = true
                    end
                end
            end
        end
    end

    CurrentTarget = nil
    UnanchorRoot()
    KillRockMovers()

    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum then
            hum.PlatformStand = false
            RestoreHumanoidState(hum)
        end
    end

    SetStatus(skippedAny
        and string.format("Скипнут. Всего скипнуто: %d", CountSkipped())
        or "Нечего скипать")
end

SkipBtn.MouseButton1Click:Connect(SkipCurrentRock)

Track(UserInputService.InputBegan:Connect(function(input, gp)
    if isBinding then
        if input.KeyCode ~= Enum.KeyCode.Unknown then
            if bindMode == "toggle" then
                getgenv().Config.ToggleKey = input.KeyCode
                KeyBox.Text = input.KeyCode.Name
            elseif bindMode == "skip" then
                getgenv().Config.SkipKey = input.KeyCode
                SkipKeyBox.Text = "Skip Key: " .. input.KeyCode.Name
                SkipBtn.Text = string.format("Skip Current Rock  [%s]", input.KeyCode.Name)
            end
            isBinding = false
            bindMode = nil
        end
    elseif not gp then
        local focused = false
        pcall(function() focused = UserInputService:GetFocusedTextBox() ~= nil end)
        if not focused then
            if input.KeyCode == getgenv().Config.ToggleKey then
                MainFrame.Visible = not MainFrame.Visible
            elseif input.KeyCode == getgenv().Config.SkipKey then
                SkipCurrentRock()
            end
        end
    end
end))

-- ==========================================
-- AUTO ROCK LIST
-- ==========================================
local function RefreshRockList(types, total)
    if not RockList then return end

    for _, ch in ipairs(RockList:GetChildren()) do
        if ch:IsA("TextButton") or ch:IsA("TextLabel") then ch:Destroy() end
    end

    if total == 0 then
        local L = Instance.new("TextLabel")
        L.Size = UDim2.new(1, 0, 0, 40)
        L.BackgroundTransparency = 1
        L.Text = "Руда не найдена.\nПодойди ближе к шахте и нажми Rescan."
        L.TextColor3 = Color3.fromRGB(200, 120, 120)
        L.Font = Enum.Font.Gotham
        L.TextSize = 13
        L.TextWrapped = true
        L.Parent = RockList
        RockList.CanvasSize = UDim2.new(0, 0, 0, 60)
        return
    end

    local names = {}
    for name in pairs(types) do table.insert(names, name) end
    table.sort(names)

    local existing = {}
    for _, n in ipairs(names) do existing[n] = true end
    for i = #getgenv().Config.SelectedRocks, 1, -1 do
        if not existing[getgenv().Config.SelectedRocks[i]] then
            table.remove(getgenv().Config.SelectedRocks, i)
        end
    end

    local function selected(name)
        for _, n in ipairs(getgenv().Config.SelectedRocks) do
            if n == name then return true end
        end
        return false
    end

    for i, n in ipairs(names) do
        local on = selected(n)
        local Btn = Instance.new("TextButton")
        if not Btn then return end
        Btn.Size = UDim2.new(1, 0, 0, 25)
        Btn.BackgroundColor3 = on and Color3.fromRGB(60, 120, 200) or Color3.fromRGB(50, 50, 60)
        
        Btn.Text = string.format("%s  %s", n, on and "ON" or "OFF")
        
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
                Btn.Text = string.format("%s  OFF", n)
                Btn.BackgroundColor3 = Color3.fromRGB(50, 50, 60)
            else
                table.insert(getgenv().Config.SelectedRocks, n)
                Btn.Text = string.format("%s  ON", n)
                Btn.BackgroundColor3 = Color3.fromRGB(60, 120, 200)
            end
            CurrentTarget = nil
        end)
    end
    RockList.CanvasSize = UDim2.new(0, 0, 0, #names * 30)
end

local function DoRescan()
    local types, total = ScanRockTypesInWorld()
    RefreshRockList(types, total)
    local tc = 0; for _ in pairs(types) do tc = tc + 1 end
    
    SetStatus(string.format("Типов: %d | Выбрано: %d", tc, #getgenv().Config.SelectedRocks))
    print(string.format("[Forge V49] Detected %d types", tc))
end

if RescanBtn then
    RescanBtn.MouseButton1Click:Connect(DoRescan)
end

task.spawn(function()
    local lastFP = nil
    while Alive() do
        task.wait(5)
        CountSkipped()
        local types, total = ScanRockTypesInWorld()
        local fpParts = {}
        for n in pairs(types) do table.insert(fpParts, n) end
        table.sort(fpParts)
        local fp = table.concat(fpParts, "|")
        if fp ~= lastFP then
            lastFP = fp
            RefreshRockList(types, total)
            local tc = 0; for _ in pairs(types) do tc = tc + 1 end
            
            SetStatus(string.format("Авто-скан: типов %d, выбрано %d", tc, #getgenv().Config.SelectedRocks))
            print("[Forge V49] Auto-rescan triggered")
        end
    end
end)

DoRescan()

-- ==========================================
-- FIND / FLY / MINE
-- ==========================================
local function FindClosestRock(Root)
    local closest, bestTargetDist = nil, math.huge
    for _, hitbox in ipairs(HitboxCache) do
        if hitbox.Parent and RockMatches(hitbox) and not IsSkipped(hitbox) then
            local hp = GetRockHP(hitbox)
            if hp and hp > 0 then
                local standPos = GetStandPos(hitbox, "Bottom") -- Ищем по нижней позиции
                local targetDist = (Root.Position - standPos).Magnitude
                if targetDist < bestTargetDist then
                    closest, bestTargetDist = hitbox, targetDist
                end
            end
        end
    end
    return closest, bestTargetDist
end

local function DoFly(Root, Humanoid, targetPos)
    if Root.Anchored then
        Root.Anchored = false
        task.wait(0.05)
    end
    ToggleNoclip(true)
    SaveHumanoidState(Humanoid)
    if not Humanoid.PlatformStand then Humanoid.PlatformStand = true end
    pcall(function() Humanoid.AutoRotate = false end)

    local fBp = Root:FindFirstChild("MinerFreeze"); if fBp then fBp:Destroy() end
    local fBg = Root:FindFirstChild("MinerGyro");   if fBg then fBg:Destroy() end

    local bv = Root:FindFirstChild("MinerFly")
    if not bv then bv = Instance.new("BodyVelocity", Root); bv.Name = "MinerFly" end
    bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)

    local delta = targetPos - Root.Position
    local dist  = delta.Magnitude

    if dist < 0.1 then
        bv.Velocity = Vector3.zero
    else
        local safeSpeed = dist / 0.15
        local speed = math.min(getgenv().Config.FlySpeed, safeSpeed)
        speed = math.max(speed, 8)
        bv.Velocity = delta.Unit * speed
    end
    task.wait(0.05)
end

local function DoMine(Root, Humanoid, Hitbox)
    ToggleNoclip(true)
    KillRockMovers()

    SaveHumanoidState(Humanoid)
    pcall(function() Humanoid.AutoRotate = false end)
    pcall(function() Humanoid.WalkSpeed  = 0 end)
    pcall(function() Humanoid.JumpPower  = 0 end)

    local isNewTarget = (CurrentTarget ~= Hitbox)
    if isNewTarget then
        CurrentTarget = Hitbox
        TargetPhase = "Top" -- Новый камень, начинаем сверху
        TargetStartTime = tick()
    end

    local standPos = GetStandPos(Hitbox, TargetPhase)
    local lookPos  = GetLookPos(Hitbox, TargetPhase)

    Root.Anchored = true
    Root.CFrame = CFrame.lookAt(standPos, lookPos)

    if isNewTarget then
        task.wait(0.2)
    else
        task.wait(0.05)
    end

    local cam = workspace.CurrentCamera
    if cam and getgenv().Config.RotateToRock then
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, lookPos)
    end

    ActivateTool()

    -- Если ударили сверху, переключаемся на низ для следующих ударов
    if TargetPhase == "Top" then
        TargetPhase = "Bottom"
        task.wait(0.2) -- Небольшая пауза перед тем, как лететь вниз
    end

    local delay = math.random(
        math.floor(getgenv().Config.MinDelay * 1000),
        math.floor(getgenv().Config.MaxDelay * 1000)) / 1000
    task.wait(delay)
end

-- ==========================================
-- MAIN LOOP
-- ==========================================
task.spawn(function()
    print("[Forge V49] Main loop started")
    while Alive() do
        task.wait(0.1)

        if not getgenv().Config.AutoMine then
            ToggleNoclip(false)
            UnanchorRoot()
            task.wait(0.5)
        else
            local char = LocalPlayer.Character
            if not char then
                task.wait(0.5)
            else
                local hum  = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart")

                if not hum or not root then
                    task.wait(0.5)
                else
                    local tool = EnsureToolEquipped(char)
                    if not tool then
                        ToggleNoclip(false)
                        UnanchorRoot()
                        if hum.PlatformStand then hum.PlatformStand = false end
                        RestoreHumanoidState(hum)
                        CurrentTarget = nil
                        SetStatus("Нет кирки (ни в руках, ни в бэкпаке)")
                        task.wait(1)
                    else
                        local hitbox, targetDist = FindClosestRock(root)
                        if hitbox then
                            -- Определяем, куда лететь/телепортироваться в зависимости от фазы
                            local currentPhase = (CurrentTarget == hitbox) and TargetPhase or "Top"
                            local standPos = GetStandPos(hitbox, currentPhase)
                            local dist = (root.Position - standPos).Magnitude

                            local shouldFly = false
                            if not root.Anchored then
                                if dist > 2.5 then shouldFly = true end
                            else
                                if dist > 12 then shouldFly = true end
                            end

                            if shouldFly then
                                DoFly(root, hum, standPos)
                                SetStatus(string.format("Цель: %s\nДо позиции: %.1f | Режим: Полет (%s)",
                                    hitbox:FindFirstAncestorWhichIsA("Model").Name, dist, currentPhase))
                            else
                                local isTimeout = false
                                if getgenv().Config.StuckTimeout > 0 and CurrentTarget == hitbox then
                                    if (tick() - TargetStartTime) > getgenv().Config.StuckTimeout then
                                        isTimeout = true
                                    end
                                end

                                if isTimeout then
                                    local model = hitbox:FindFirstAncestorWhichIsA("Model")
                                    if model then
                                        SkippedRocks[model] = tick()
                                    end
                                    CurrentTarget = nil
                                    UnanchorRoot()
                                    KillRockMovers()
                                    if hum.PlatformStand then hum.PlatformStand = false end
                                    RestoreHumanoidState(hum)
                                    SetStatus(string.format("Камень не сломался за %d сек. Скипнут.", getgenv().Config.StuckTimeout))
                                    task.wait(0.5)
                                else
                                    DoMine(root, hum, hitbox)
                                    local model = hitbox:FindFirstAncestorWhichIsA("Model")
                                    SetStatus(string.format("Цель: %s\nДо позиции: %.1f | Режим: Добыча (%s)",
                                        model and model.Name or "?", dist, TargetPhase))
                                end
                            end
                        else
                            ToggleNoclip(false)
                            UnanchorRoot()
                            KillRockMovers()
                            CurrentTarget = nil
                            if hum.PlatformStand then hum.PlatformStand = false end
                            RestoreHumanoidState(hum)
                            
                            if #getgenv().Config.SelectedRocks == 0 then
                                SetStatus("Выберите камни в списке ниже (DETECTED ROCKS)")
                            else
                                SetStatus(string.format("Руда не найдена\nСкипнуто: %d", CountSkipped()))
                            end
                            task.wait(0.5)
                        end
                    end
                end
            end
        end
    end
end)
