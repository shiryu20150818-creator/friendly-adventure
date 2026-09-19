--[[
    ねこなのはぶ 統合版 (OrionLib)
    全部の機能を一つのUIに直接表示
    いもはぶ / lemon / ドリフト / 最初のスクリプト 主要機能収録
    ブラックホールなし
]]

local StarterGui = game:GetService("StarterGui")
local function Notify(title, text, duration)
    StarterGui:SetCore("SendNotification", {
        Title = title,
        Text = text,
        Duration = duration or 3
    })
end

-- OrionLib
local OrionLib
local ok, res = pcall(function()
    return loadstring(game:HttpGet("https://raw.githubusercontent.com/jadpy/suki/refs/heads/main/orion"))()
end)
if not ok or not res then
    Notify("エラー", "OrionLib読み込み失敗", 5)
    return
end
OrionLib = res

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local GrabEvents = ReplicatedStorage:FindFirstChild("GrabEvents")
local CreateGrabLine = GrabEvents and GrabEvents:FindFirstChild("CreateGrabLine")
local DestroyGrabLine = GrabEvents and GrabEvents:FindFirstChild("DestroyGrabLine")
local SetNetworkOwner = GrabEvents and GrabEvents:FindFirstChild("SetNetworkOwner")
local MenuToys = ReplicatedStorage:FindFirstChild("MenuToys")

-- ==============================
-- 状態
-- ==============================
local lineLagEnabled = false
local lineLagThread = nil
local isActiveKick = false
local barrierBreakDone = false
local currentBlob = nil
local playerStatus = {}
local orbitRunning = false
local orbitCurrentLoopId = 0
local selectedTargetName = ""
local orbitRadius = 19
local orbitSpeed = 8.5
local orbitHeightOffset = 0
local grabReleaseInterval = 0.08
local respawnTrackingEnabled = false
local infiniteJumpEnabled = false
local infiniteJumpConnection = nil
_G.FixP = 40000000
_G.FixD = 1000

-- ==============================
-- ユーティリティ
-- ==============================
local function GetAllPlayers()
    local t = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then table.insert(t, p) end
    end
    return t
end

local function GetMyRoot()
    return LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
end

local function GetPlayerNames()
    local names = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            table.insert(names, p.DisplayName .. " (@" .. p.Name .. ")")
        end
    end
    return names
end

local function ExtractName(display)
    if not display then return nil end
    local start = string.find(display, "%(@")
    if start then
        return string.sub(display, start + 2, -2)
    end
    return display
end

local function NotifyMissing(name)
    OrionLib:MakeNotification({Name = "エラー", Content = name .. " が見つかりません", Time = 4})
end

-- ==============================
-- Line Lag
-- ==============================
local function startLineLag()
    if lineLagEnabled then return end
    lineLagEnabled = true
    lineLagThread = task.spawn(function()
        if not CreateGrabLine then NotifyMissing("CreateGrabLine") return end
        while lineLagEnabled do
            local target = Workspace:FindFirstChild("SpawnLocation") or Workspace:FindFirstChild("Spawn") or GetMyRoot()
            if target then
                for i = 1, 12 do
                    pcall(function()
                        CreateGrabLine:FireServer(target, CFrame.new(math.random(-1e9,1e9), 0, math.random(-1e9,1e9)))
                    end)
                end
            end
            task.wait(0.04)
        end
    end)
end

local function stopLineLag()
    lineLagEnabled = false
    if lineLagThread then pcall(function() task.cancel(lineLagThread) end) end
end

-- ==============================
-- Fix / Unfix
-- ==============================
local function FixPlayer(targetRoot, pos)
    if not targetRoot then return end
    for _, v in ipairs(targetRoot:GetChildren()) do
        if v:IsA("BodyPosition") or v:IsA("BodyGyro") then v:Destroy() end
    end
    local bp = Instance.new("BodyPosition")
    bp.MaxForce = Vector3.new(1e9,1e9,1e9)
    bp.P = _G.FixP or 4e7
    bp.D = _G.FixD or 1000
    bp.Position = pos
    bp.Parent = targetRoot
    local bg = Instance.new("BodyGyro")
    bg.MaxTorque = Vector3.new(1e9,1e9,1e9)
    bg.P = _G.FixP or 4e7
    bg.D = _G.FixD or 1000
    bg.CFrame = CFrame.new(pos)
    bg.Parent = targetRoot
end

local function UnfixAll()
    for _, plr in ipairs(GetAllPlayers()) do
        local hrp = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, v in ipairs(hrp:GetChildren()) do
                if v:IsA("BodyPosition") or v:IsA("BodyGyro") then v:Destroy() end
            end
        end
    end
end

-- ==============================
-- Barrier Break
-- ==============================
local function BarrierBreak()
    if barrierBreakDone then
        OrionLib:MakeNotification({Name = "ねこなのはぶ", Content = "バリアは既に破壊済み", Time = 2})
        return
    end
    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        OrionLib:MakeNotification({Name = "エラー", Content = "キャラクターがありません", Time = 3})
        return
    end
    local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    local originalWalkSpeed, originalJumpPower
    if humanoid then
        originalWalkSpeed = humanoid.WalkSpeed
        originalJumpPower = humanoid.JumpPower
        pcall(function() humanoid.WalkSpeed = 0 humanoid.JumpPower = 0 end)
    end
    local success, err = pcall(function()
        local MT = ReplicatedStorage:WaitForChild("MenuToys", 5)
        if not MT then error("MenuToys not found") end
        local SpawnToy = MT:FindFirstChild("SpawnToyRemoteFunction")
        if not SpawnToy then error("SpawnToyRemoteFunction not found") end
        local DestroyToy = MT:FindFirstChild("DestroyToy")
        local hrp = LocalPlayer.Character.HumanoidRootPart
        local originalCF = hrp.CFrame
        hrp.CFrame = CFrame.new(246.052, -7.35, 431.821)
        task.wait(0.05)
        SpawnToy:InvokeServer("InstrumentWoodwindOcarina",
            CFrame.new(184.148834, -5.54824972, 498.136749, 0.829037189, -0.214714944, 0.516328275, 0, 0.923344612, 0.383972496, -0.559193552, -0.318327487, 0.765486956),
            Vector3.new(0, 34, 0))
        task.wait(0.2)
        local toyFolder = Workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
        if not toyFolder then error("SpawnedInToys not found") end
        local ocarina = toyFolder:FindFirstChild("InstrumentWoodwindOcarina")
        if not ocarina then error("Ocarina not found") end
        if ocarina:FindFirstChild("HoldPart") and ocarina.HoldPart:FindFirstChild("HoldItemRemoteFunction") then
            pcall(function() ocarina.HoldPart.HoldItemRemoteFunction:InvokeServer(ocarina, LocalPlayer.Character) end)
            task.wait(0.2)
        end
        LocalPlayer.Character.HumanoidRootPart.CFrame = CFrame.new(304.06, 25.77, 488.54)
        task.wait(0.05)
        if DestroyToy then DestroyToy:FireServer(ocarina) end
        task.wait(0.05)
        if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
            LocalPlayer.Character.HumanoidRootPart.CFrame = originalCF
        end
        barrierBreakDone = true
        OrionLib:MakeNotification({Name = "成功", Content = "バリアを破壊しました", Time = 3})
    end)
    if humanoid then
        pcall(function()
            if originalWalkSpeed then humanoid.WalkSpeed = originalWalkSpeed end
            if originalJumpPower then humanoid.JumpPower = originalJumpPower end
        end)
    end
    if not success then
        OrionLib:MakeNotification({Name = "エラー", Content = tostring(err), Time = 4})
    end
end

-- ==============================
-- Kick All
-- ==============================
local function KickAll()
    if isActiveKick then return end
    isActiveKick = true
    local allPlayers = GetAllPlayers()
    if #allPlayers == 0 then
        OrionLib:MakeNotification({Name = "エラー", Content = "対象がいません", Time = 3})
        isActiveKick = false
        return
    end
    for _, p in ipairs(allPlayers) do playerStatus[p.UserId] = "Targeting" end

    local rootPart = GetMyRoot()
    if rootPart and MenuToys then
        local spawnToy = MenuToys:FindFirstChild("SpawnToyRemoteFunction")
        if spawnToy then
            spawnToy:InvokeServer("CreatureBlobman", rootPart.CFrame * CFrame.new(0,0,-5), Vector3.new(0,127,0))
        end
    end
    task.wait(0.5)
    local toyFolder = Workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
    currentBlob = toyFolder and toyFolder:FindFirstChild("CreatureBlobman")
    if not currentBlob then
        OrionLib:MakeNotification({Name = "エラー", Content = "Blobman生成失敗", Time = 3})
        isActiveKick = false
        return
    end
    local seat = currentBlob:FindFirstChild("VehicleSeat")
    if seat and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then pcall(function() seat:Sit(hum) end) end
    end
    task.wait(0.3)
    local myRoot = GetMyRoot()
    if not myRoot then isActiveKick = false return end

    for _, target in ipairs(allPlayers) do
        local tRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if tRoot then
            myRoot.CFrame = tRoot.CFrame
            task.wait()
            for i = 1, 6 do
                pcall(function()
                    local scriptObj = currentBlob:FindFirstChild("BlobmanSeatAndOwnerScript")
                    if scriptObj then
                        scriptObj.CreatureGrab:FireServer(currentBlob.LeftDetector, tRoot, currentBlob.LeftDetector.LeftWeld)
                        scriptObj.CreatureRelease:FireServer(currentBlob.LeftDetector.LeftWeld)
                        scriptObj.CreatureGrab:FireServer(currentBlob.RightDetector, tRoot, currentBlob.RightDetector.RightWeld)
                        scriptObj.CreatureRelease:FireServer(currentBlob.RightDetector.RightWeld)
                    end
                end)
                task.wait()
            end
        end
    end
    myRoot.CFrame = CFrame.new(0, 100, 0)
    task.wait(0.1)
    for _, part in ipairs(currentBlob:GetDescendants()) do
        if part:IsA("BasePart") then pcall(function() part.Anchored = true end) end
    end
    task.wait(0.1)
    local radius, height = 15, 110
    for i, target in ipairs(allPlayers) do
        local tRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if tRoot then
            local angle = math.rad((i-1) * (360 / #allPlayers))
            local pos = Vector3.new(radius * math.cos(angle), height, radius * math.sin(angle))
            tRoot.CFrame = CFrame.new(pos)
            FixPlayer(tRoot, pos)
        end
    end
    task.wait(0.15)
    for _ = 1, 2 do
        for _, target in ipairs(allPlayers) do
            local tRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
            if tRoot then
                task.spawn(function()
                    pcall(function()
                        if SetNetworkOwner then SetNetworkOwner:FireServer(tRoot, CFrame.new(tRoot.Position)) end
                        if DestroyGrabLine then DestroyGrabLine:FireServer(tRoot) end
                    end)
                end)
            end
        end
        task.wait(0.1)
    end
    task.wait(0.25)
    for _, target in ipairs(allPlayers) do
        local tRoot = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if tRoot then
            task.spawn(function()
                pcall(function()
                    local scriptObj = currentBlob:FindFirstChild("BlobmanSeatAndOwnerScript")
                    if scriptObj then
                        scriptObj.CreatureGrab:FireServer(currentBlob.LeftDetector, tRoot, currentBlob.LeftDetector.LeftWeld)
                        scriptObj.CreatureGrab:FireServer(currentBlob.RightDetector, tRoot, currentBlob.RightDetector.RightWeld)
                    end
                end)
            end)
        end
    end
    task.wait(0.1)
    for _, part in ipairs(currentBlob:GetDescendants()) do
        if part:IsA("BasePart") then pcall(function() part.Anchored = false end) end
    end
    task.wait(1)
    isActiveKick = false
end

-- ==============================
-- Drift Kick / Orbit (ドリフト)
-- ==============================
local function StartDriftKick()
    if orbitRunning then return end
    orbitRunning = true
    orbitCurrentLoopId = orbitCurrentLoopId + 1
    local myLoopId = orbitCurrentLoopId

    local targetName = ExtractName(selectedTargetName)
    local target = targetName and Players:FindFirstChild(targetName)
    if not target or not target.Character or not target.Character:FindFirstChild("HumanoidRootPart") then
        OrionLib:MakeNotification({Name = "エラー", Content = "ターゲットが無効です", Time = 3})
        orbitRunning = false
        return
    end

    task.spawn(function()
        local blobman = nil
        local spawned = Workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
        if spawned then blobman = spawned:FindFirstChild("CreatureBlobman") end
        if not blobman and MenuToys then
            local st = MenuToys:FindFirstChild("SpawnToyRemoteFunction")
            if st then
                local myRoot = GetMyRoot()
                if myRoot then
                    st:InvokeServer("CreatureBlobman", myRoot.CFrame + Vector3.new(0,5,0), Vector3.zero)
                    task.wait(0.8)
                    spawned = Workspace:FindFirstChild(LocalPlayer.Name .. "SpawnedInToys")
                    if spawned then blobman = spawned:FindFirstChild("CreatureBlobman") end
                end
            end
        end
        if not blobman then
            OrionLib:MakeNotification({Name = "エラー", Content = "Blobman取得失敗", Time = 3})
            orbitRunning = false
            return
        end

        local scriptObj = blobman:FindFirstChild("BlobmanSeatAndOwnerScript")
        local grabRemote = scriptObj and scriptObj:FindFirstChild("CreatureGrab")
        local dropRemote = scriptObj and scriptObj:FindFirstChild("CreatureDrop")
        local rDet = blobman:FindFirstChild("RightDetector") or blobman:FindFirstChild("LeftDetector")
        local weld = rDet and (rDet:FindFirstChild("RightWeld") or rDet:FindFirstChild("LeftWeld") or rDet:FindFirstChildWhichIsA("Weld"))
        local seat = blobman:FindFirstChild("VehicleSeat")
        local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if seat and hum and seat.Occupant ~= hum then
            LocalPlayer.Character.HumanoidRootPart.CFrame = seat.CFrame + Vector3.new(0,2,0)
            task.wait(0.2)
            seat:Sit(hum)
            task.wait(0.4)
        end

        if not grabRemote or not dropRemote or not rDet then
            OrionLib:MakeNotification({Name = "エラー", Content = "必要なRemoteが見つかりません", Time = 4})
            orbitRunning = false
            return
        end

        OrionLib:MakeNotification({Name = "ねこなのはぶ", Content = "drift kick 開始", Time = 2})

        local blobRoot = blobman:FindFirstChild("HumanoidRootPart") or blobman.PrimaryPart
        local angle = 0
        local lastDrop = tick()
        local SavedPos = target.Character.HumanoidRootPart.CFrame
        local center = SavedPos + Vector3.new(0, 30, 0)

        while orbitRunning and myLoopId == orbitCurrentLoopId and blobman and blobman.Parent do
            if not target or not target.Parent then break end
            local tChar = target.Character
            if not tChar then
                if respawnTrackingEnabled then
                    while not target.Character and target.Parent and orbitRunning and myLoopId == orbitCurrentLoopId do
                        task.wait(0.5)
                    end
                    if not target.Character then break end
                    tChar = target.Character
                    SavedPos = tChar.HumanoidRootPart.CFrame
                    center = SavedPos + Vector3.new(0, 30, 0)
                else
                    break
                end
            end
            local tRoot = tChar:FindFirstChild("HumanoidRootPart")
            local tHum = tChar:FindFirstChild("Humanoid")
            if not tRoot or not tHum or tHum.Health <= 0 then break end

            angle = angle + (orbitSpeed * 0.016)
            local offsetX = math.cos(angle) * orbitRadius
            local offsetZ = math.sin(angle) * orbitRadius
            local blobPos = center.Position + Vector3.new(offsetX, orbitHeightOffset, offsetZ)

            if blobRoot then
                blobRoot.CFrame = CFrame.new(blobPos, center.Position)
                blobRoot.AssemblyLinearVelocity = Vector3.zero
            end
            tRoot.CFrame = center
            tRoot.AssemblyLinearVelocity = Vector3.zero
            tHum.PlatformStand = true

            pcall(function()
                if SetNetworkOwner then SetNetworkOwner:FireServer(tRoot, center) end
                local cw = rDet:FindFirstChild("RightWeld") or rDet:FindFirstChild("LeftWeld") or rDet:FindFirstChildWhichIsA("Weld")
                if cw and dropRemote then dropRemote:FireServer(cw) end
                if DestroyGrabLine then DestroyGrabLine:FireServer(tRoot) end
                if grabRemote then grabRemote:FireServer(rDet, tRoot, weld) end
                if CreateGrabLine then CreateGrabLine:FireServer(tRoot, Vector3.zero, center.Position, false) end
            end)

            if (tick() - lastDrop) > grabReleaseInterval then
                lastDrop = tick()
                pcall(function()
                    local cw = rDet:FindFirstChild("RightWeld") or rDet:FindFirstChild("LeftWeld") or rDet:FindFirstChildWhichIsA("Weld")
                    if cw and dropRemote then dropRemote:FireServer(cw) end
                    if DestroyGrabLine then DestroyGrabLine:FireServer(tRoot) end
                end)
                if blobRoot then
                    blobRoot.CFrame = SavedPos
                    blobRoot.AssemblyLinearVelocity = Vector3.zero
                end
                task.wait(0.03)
            end
            RunService.Heartbeat:Wait()
        end
        orbitRunning = false
    end)
end

local function StopDriftKick()
    orbitRunning = false
    orbitCurrentLoopId = orbitCurrentLoopId + 1
end

-- ==============================
-- 無限ジャンプ
-- ==============================
local function toggleInfiniteJump(enabled)
    if infiniteJumpConnection then
        infiniteJumpConnection:Disconnect()
        infiniteJumpConnection = nil
    end
    infiniteJumpEnabled = enabled
    if enabled then
        infiniteJumpConnection = UserInputService.JumpRequest:Connect(function()
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChild("Humanoid")
            if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
        end)
    end
end

-- ==============================
-- UI 統合（全部直接見える）
-- ==============================
local Window = OrionLib:MakeWindow({
    Name = "ねこなのはぶ",
    HidePremium = true,
    SaveConfig = true,
    ConfigFolder = "NekoNanoHub",
    IntroEnabled = false
})

-- ===== ラグ＆キック =====
local LagTab = Window:MakeTab({Name = "ラグ＆キック", Icon = "rbxassetid://4483345998", PremiumOnly = false})

LagTab:AddButton({
    Name = "ラグ＆Kick All 開始 (20秒)",
    Callback = function()
        if lineLagEnabled then
            OrionLib:MakeNotification({Name="ねこなのはぶ", Content="既に実行中です", Time=2})
            return
        end
        startLineLag()
        task.spawn(function() pcall(KickAll) end)
        OrionLib:MakeNotification({Name="ねこなのはぶ", Content="20秒間ラグ+Kick All開始", Time=2})
        task.delay(20, function()
            if lineLagEnabled then
                stopLineLag()
                OrionLib:MakeNotification({Name="ねこなのはぶ", Content="20秒経過・停止", Time=2})
            end
        end)
    end
})

LagTab:AddButton({
    Name = "Kick All のみ実行",
    Callback = function()
        task.spawn(function() pcall(KickAll) end)
    end
})

LagTab:AddButton({
    Name = "固定解除 (全員)",
    Callback = function()
        UnfixAll()
        OrionLib:MakeNotification({Name="ねこなのはぶ", Content="全員固定解除", Time=2})
    end
})

-- ===== ドリフトキック =====
local DriftTab = Window:MakeTab({Name = "ドリフトキック", Icon = "rbxassetid://4483345998", PremiumOnly = false})

local targetDropdown = DriftTab:AddDropdown({
    Name = "ターゲット選択",
    Default = "",
    Options = GetPlayerNames(),
    Callback = function(Value)
        selectedTargetName = type(Value) == "table" and Value[1] or Value
    end
})

DriftTab:AddButton({
    Name = "プレイヤーリスト更新",
    Callback = function()
        targetDropdown:Set(GetPlayerNames())
    end
})

DriftTab:AddSlider({
    Name = "Orbit半径",
    Min = 5, Max = 50, Default = 19, Increment = 1,
    Callback = function(v) orbitRadius = v end
})

DriftTab:AddSlider({
    Name = "Orbit速度",
    Min = 1, Max = 20, Default = 8.5, Increment = 0.5,
    Callback = function(v) orbitSpeed = v end
})

DriftTab:AddSlider({
    Name = "高度オフセット",
    Min = -10, Max = 10, Default = 0, Increment = 1,
    Callback = function(v) orbitHeightOffset = v end
})

DriftTab:AddSlider({
    Name = "Grab Release速度 (秒)",
    Min = 0.05, Max = 1.0, Default = 0.08, Increment = 0.01,
    Callback = function(v) grabReleaseInterval = v end
})

DriftTab:AddToggle({
    Name = "Respawn追跡",
    Default = false,
    Callback = function(v) respawnTrackingEnabled = v end
})

DriftTab:AddToggle({
    Name = "drift kick 開始/停止",
    Default = false,
    Callback = function(v)
        if v then
            StartDriftKick()
        else
            StopDriftKick()
            OrionLib:MakeNotification({Name="ねこなのはぶ", Content="drift kick 停止", Time=2})
        end
    end
})

-- ===== バリア =====
local BarrierTab = Window:MakeTab({Name = "バリア破壊", Icon = "rbxassetid://4483345998", PremiumOnly = false})

BarrierTab:AddButton({
    Name = "バリア破壊",
    Callback = function() task.spawn(function() pcall(BarrierBreak) end) end
})

BarrierTab:AddButton({
    Name = "自動バリア破壊",
    Callback = function()
        task.spawn(function()
            while not barrierBreakDone do
                pcall(BarrierBreak)
                task.wait(5)
            end
        end)
        OrionLib:MakeNotification({Name="ねこなのはぶ", Content="自動バリア破壊開始", Time=2})
    end
})

BarrierTab:AddParagraph("注意", "1回成功したら以降は実行しません")

-- ===== 固定オプション =====
local OptTab = Window:MakeTab({Name = "固定オプション", Icon = "rbxassetid://4483345998", PremiumOnly = false})

OptTab:AddSlider({
    Name = "固定の強さ (P値)",
    Min = 1, Max = 40000000, Default = 40000000, Increment = 100000,
    Callback = function(v) _G.FixP = v end
})

OptTab:AddSlider({
    Name = "固定の減衰 (D値)",
    Min = 1, Max = 10000, Default = 1000, Increment = 10,
    Callback = function(v) _G.FixD = v end
})

-- ===== プレイヤー =====
local PlayerTab = Window:MakeTab({Name = "プレイヤー", Icon = "rbxassetid://4483345998", PremiumOnly = false})

PlayerTab:AddToggle({
    Name = "無限ジャンプ",
    Default = false,
    Callback = function(v)
        toggleInfiniteJump(v)
        OrionLib:MakeNotification({Name="ねこなのはぶ", Content = v and "無限ジャンプ ON" or "無限ジャンプ OFF", Time=2})
    end
})

-- ===== 情報 =====
local InfoTab = Window:MakeTab({Name = "情報", Icon = "rbxassetid://4483345998", PremiumOnly = false})

InfoTab:AddParagraph("ねこなのはぶ 統合版",
    "全部の機能を一つのUIに直接表示\n" ..
    "・ラグ＆Kick All\n" ..
    "・ドリフトキック (Orbit)\n" ..
    "・バリア破壊\n" ..
    "・固定オプション\n" ..
    "・無限ジャンプ\n" ..
    "いもはぶ / lemon / ドリフトの主要機能を統合"
)

InfoTab:AddButton({
    Name = "UIを閉じる",
    Callback = function() OrionLib:Destroy() end
})

OrionLib:Init()
OrionLib:MakeNotification({Name = "ねこなのはぶ", Content = "統合版読み込み完了\n全部の機能が直接使えます", Time = 4})
