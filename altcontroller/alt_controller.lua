if _G.AltControllerConnections then
    for _, conn in ipairs(_G.AltControllerConnections) do
        pcall(function() conn:Disconnect() end)
    end
end
_G.AltControllerConnections = {}

local function TrackConnection(conn)
    table.insert(_G.AltControllerConnections, conn)
    return conn
end

local function IsAuthorized(name)
    if not name then return false end
    name = string.lower(name)
    if name == string.lower(Config.MainAccount) then return true end
    if Config.Alts[name] then return true end
    -- Fallback for display names or variations
    for altName, _ in pairs(Config.Alts) do
        if string.lower(altName) == name then return true end
    end
    return false
end

local Config = {
    MainAccount = "Ali736u1", 
    Alts = {
        ["ali736u6"] = true,
        ["ahmed736u1"] = true,
        ["ali736u4"] = true,
        ["ahmed736u"] = true,
        ["Ali736u12"] = true,
        ["roblox_user_5535477487"] = true,
        ["ali736u_ceohelper"] = true,
        ["ali736u2"] = true
    },
    Prefix = ";"
}

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

local CurrentMode = "none"
local CommandLeader = Config.MainAccount
local MyFollowTarget = nil
local MyIndex = 1
local wasMoving = false
local ScatterTarget = nil
local TargetBreadcrumbs = {}
local FOLLOW_DISTANCE = 3
local TotalAlts = 0
for _ in pairs(Config.Alts) do TotalAlts = TotalAlts + 1 end
local ControlMoveDir = Vector3.zero

local SingleFlingTarget = nil
local ActiveBurnout = false
local hauntedPhase = "idle"
local hauntedTimer = math.random() * 5 + 2

local MOTO_SLOTS = {
    {x=0,    y=-3,    z=-4.5, type="wheel"},
    {x=0,    y=-3,    z=3.5,  type="wheel"},
    {x=0,    y=-1.2,  z=-2.5, type="frame", angle=60},
    {x=0,    y=-1.5,  z=2,    type="frame", angle=20},
    {x=0,    y=-2.5,  z=-0.5, type="engine"},
    {x=0,    y=-3.2,  z=1,    type="engine"},
    {x=0,    y=-0.3,  z=-3.5, type="frame", angle=70},
    {x=1.2,  y=-2.5,  z=2.5,  type="side_right"},
}

local MathCache = {}

local function UpdateMathCache()
    local altIndexOffset = math.max(1, MyIndex - 1)
    local numAlts = math.max(1, TotalAlts)
    
    MathCache.divisor = numAlts
    MathCache.angle = ((altIndexOffset - 1) * (math.pi * 2 / numAlts))
    MathCache.swarmAngleOffset = (altIndexOffset * (math.pi * 2 / numAlts))
    MathCache.swarmRadius = 3 + (altIndexOffset % 2) * 1.5
    MathCache.spinRadius = math.max(6, (TotalAlts * 3) / (math.pi * 2))
    
    MathCache.rowHalf = math.ceil(altIndexOffset / 2)
    MathCache.isLeft = (altIndexOffset % 2 == 1)
    MathCache.isLastRowHalf = (MathCache.rowHalf == math.ceil(TotalAlts / 2))
    MathCache.altsInLastRowHalf = (TotalAlts % 2 == 1) and 1 or 2
    
    MathCache.armyRow = math.floor((altIndexOffset - 1) / 3) + 1
    MathCache.armyColIndex = ((altIndexOffset - 1) % 3)
    MathCache.totalArmyRows = math.ceil(TotalAlts / 3)
    MathCache.isLastArmyRow = (MathCache.armyRow == MathCache.totalArmyRows)
    MathCache.altsInLastArmyRow = (TotalAlts % 3 == 0) and 3 or (TotalAlts % 3)
    
    MathCache.innerCount = math.ceil(TotalAlts / 2)
    MathCache.outerCount = TotalAlts - MathCache.innerCount
    MathCache.isInner = (altIndexOffset <= MathCache.innerCount)
    if MathCache.isInner then
        MathCache.posInRing = altIndexOffset
        MathCache.ringCount = MathCache.innerCount
    else
        MathCache.posInRing = altIndexOffset - MathCache.innerCount
        MathCache.ringCount = MathCache.outerCount
    end
    MathCache.jumbaPhaseOffset = ((MathCache.posInRing - 1) / MathCache.ringCount) * (math.pi * 2)
    
    MathCache.inclination = (altIndexOffset - 1) * math.pi / numAlts
    MathCache.azimuth = (altIndexOffset - 1) * math.pi * 2 / numAlts
    MathCache.auraPhaseOffset = ((altIndexOffset - 1) / numAlts) * (math.pi * 2)
end

local function UpdateFollowTarget()
    local ordered = {CommandLeader}
    local altNames = {}
    
    for name, _ in pairs(Config.Alts) do
        if string.lower(name) ~= string.lower(CommandLeader) then
            local actualName = nil
            for _, p in ipairs(Players:GetPlayers()) do
                if string.lower(p.Name) == string.lower(name) then
                    actualName = p.Name
                    break
                end
            end
            if actualName then
                table.insert(altNames, actualName)
            end
        end
    end
    table.sort(altNames)
    
    TotalAlts = #altNames
    
    for i, name in ipairs(altNames) do
        table.insert(ordered, name)
    end
    
    for i, name in ipairs(ordered) do
        if name == LocalPlayer.Name then
            MyIndex = i
            if i > 1 then
                if MyFollowTarget ~= ordered[i - 1] then
                    MyFollowTarget = ordered[i - 1]
                    TargetBreadcrumbs = {}
                end
                return
            end
        end
    end
    MyFollowTarget = nil
    TargetBreadcrumbs = {}
    UpdateMathCache()
end

local function FindPlayer(searchStr)
    searchStr = string.lower(searchStr)
    for _, p in ipairs(Players:GetPlayers()) do
        if string.lower(p.Name) == searchStr or string.lower(p.DisplayName) == searchStr then
            return p
        end
    end
    for _, p in ipairs(Players:GetPlayers()) do
        if string.find(string.lower(p.Name), searchStr, 1, true) or string.find(string.lower(p.DisplayName), searchStr, 1, true) then
            return p
        end
    end
    return nil
end

local OriginalHipHeight = 0
do
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then OriginalHipHeight = hum.HipHeight end
end

local HeliSpeed = 3.0
local HeliRadius = 6

local function StopAllActions(incomingMode)
    local wasActive = (CurrentMode ~= "none")
    CurrentMode = "none"
    ScatterTarget = nil
    TargetBreadcrumbs = {}
    wasMoving = false
    ControlMoveDir = Vector3.zero

    if not wasActive then return end
    
    local myCharacter = LocalPlayer.Character
    if myCharacter then
        for _, child in ipairs(myCharacter:GetChildren()) do
            if child:IsA("BasePart") then
                child.CanCollide = true
            elseif child:IsA("Accessory") then
                local handle = child:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    handle.CanCollide = true
                end
            end
        end
        local myRoot = myCharacter:FindFirstChild("HumanoidRootPart")
        if myRoot then
            myRoot.Anchored = false
            if incomingMode ~= "ufo" and incomingMode ~= "carpet" and incomingMode ~= "elevator" and incomingMode ~= "motorcycle" and incomingMode ~= "orbit" and incomingMode ~= "mech" and incomingMode ~= "altmech" and incomingMode ~= "tornado" and incomingMode ~= "stack" and incomingMode ~= "pillar" and incomingMode ~= "heli" and incomingMode ~= "aura" and incomingMode ~= "jumba" then
                for _, obj in ipairs(myRoot:GetChildren()) do
                    if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") or obj.Name == "FlingSpin" or obj.Name == "WheelSpin" or obj.Name == "MotoAntiGravity" then
                        obj:Destroy()
                    end
                end
            elseif incomingMode == "motorcycle" then
                for _, obj in ipairs(myRoot:GetChildren()) do
                     if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") or obj.Name == "FlingSpin" or obj.Name == "WheelSpin" then
                         obj:Destroy()
                     end
                end
            elseif incomingMode then
                 for _, obj in ipairs(myRoot:GetChildren()) do
                     if obj.Name == "FlingSpin" or obj.Name == "WheelSpin" or obj.Name == "MotoAntiGravity" then
                         obj:Destroy()
                     end
                 end
            end
            
            myRoot:SetAttribute("MotoCollOff", nil)
        end
        local myHumanoid = myCharacter:FindFirstChildOfClass("Humanoid")
        if myHumanoid and myRoot then
            if incomingMode ~= "ufo" and incomingMode ~= "carpet" and incomingMode ~= "elevator" and incomingMode ~= "motorcycle" and incomingMode ~= "orbit" and incomingMode ~= "mech" and incomingMode ~= "altmech" and incomingMode ~= "tornado" and incomingMode ~= "stack" and incomingMode ~= "pillar" and incomingMode ~= "heli" and incomingMode ~= "aura" and incomingMode ~= "jumba" then
                myHumanoid.PlatformStand = false
            end
            myHumanoid.WalkSpeed = 16
            myHumanoid.HipHeight = OriginalHipHeight
            myHumanoid.AutoRotate = true
            myHumanoid:MoveTo(myRoot.Position)
            myHumanoid:Move(Vector3.zero, false)
            if myHumanoid:GetState() == Enum.HumanoidStateType.PlatformStanding and not myHumanoid.PlatformStand then
                myHumanoid:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
    end
end




local function ParseArg(cmd, idx)
    return string.match(string.sub(cmd, idx), "^%s*(.-)%s*$")
end

local function ApplyModeSetup(modeName)
    CurrentMode = modeName
    local char = LocalPlayer.Character
    if char then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("BasePart") then
                child.CanCollide = false
            elseif child:IsA("Accessory") then
                local handle = child:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") then
                    handle.CanCollide = false
                end
            end
        end
    end
end

local function SetupFloatingBody(useHighForce)
    local myCharacter = LocalPlayer.Character
    local myRoot = myCharacter and myCharacter:FindFirstChild("HumanoidRootPart")
    local myHumanoid = myCharacter and myCharacter:FindFirstChildOfClass("Humanoid")
    if myRoot and myHumanoid then
        myHumanoid.PlatformStand = true
        if not myRoot:FindFirstChildOfClass("BodyPosition") then
            local bp = Instance.new("BodyPosition")
            if useHighForce then
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
            else
                bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
                bp.D = 500
                bp.P = 5000
            end
            bp.Position = myRoot.Position
            bp.Parent = myRoot
        end
        if not myRoot:FindFirstChildOfClass("BodyGyro") then
            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            bg.CFrame = myRoot.CFrame
            bg.Parent = myRoot
        end
    end
end

local function SetupFormation(cmd, modeName, argStartIdx, logMsg)
    StopAllActions(modeName)
    ApplyModeSetup(modeName)
    
    local myCharacter = LocalPlayer.Character
    if myCharacter then
        local myHumanoid = myCharacter:FindFirstChildOfClass("Humanoid")
        if myHumanoid then
            local animator = myHumanoid:FindFirstChildOfClass("Animator")
            if animator then 
                for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
                    track:Stop()
                end
            end
            myHumanoid.AutoRotate = false
        end
    end
    local argStr = ParseArg(cmd, argStartIdx)
    if argStr == "" then CommandLeader = Config.MainAccount else
        local targetPlayer = FindPlayer(argStr)
        if targetPlayer then CommandLeader = targetPlayer.Name end
    end
    UpdateFollowTarget()
    UpdateMathCache()
    print("[Alt Controller] " .. logMsg)
end

local ExactCommands = {}





ExactCommands["jump"] = function(cmd)
    local humanoid = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then humanoid:ChangeState(Enum.HumanoidStateType.Jumping) end
    print("[Alt Controller] Jumped!")
end

ExactCommands["equip1"] = function(cmd)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        local firstTool = LocalPlayer.Backpack:FindFirstChildOfClass("Tool")
        if firstTool then
            hum:EquipTool(firstTool)
            print("[Alt Controller] Equipped first tool.")
        else
            print("[Alt Controller] No tool found in hotbar.")
        end
    end
end

ExactCommands["stop"] = function(cmd)
    StopAllActions(nil)
    print("[Alt Controller] Stopped all actions.")
end

ExactCommands["reset"] = function(cmd)
    StopAllActions(nil)
    if LocalPlayer.Character then
        local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if humanoid then humanoid.Health = 0 end
    end
    print("[Alt Controller] Resetting character...")
end

ExactCommands["heli"] = function(cmd)
    SetupFormation(cmd, "heli", 5, "Heli ON.")
    -- No SetupFloatingBody needed: heli uses direct CFrame now
end

ExactCommands["elevator"] = function(cmd)
    SetupFormation(cmd, "elevator", 9, "Elevator ON.")  
    SetupFloatingBody(true)
end

ExactCommands["carpet"] = function(cmd)
    SetupFormation(cmd, "carpet", 7, "Carpet ON.")  
    SetupFloatingBody(true)
end
ExactCommands["aladdin"] = ExactCommands["carpet"]

ExactCommands["ufo"] = function(cmd)
    SetupFormation(cmd, "ufo", 4, "UFO ON.")  
    SetupFloatingBody(true)
end

ExactCommands["pillar"] = function(cmd)
    SetupFormation(cmd, "pillar", 7, "Pillar ON.")
    SetupFloatingBody(true)
end

ExactCommands["jumba"] = function(cmd)
    SetupFormation(cmd, "jumba", 6, "Jumba ON.")
    SetupFloatingBody(true)
end

ExactCommands["aura"] = function(cmd)
    SetupFormation(cmd, "aura", 5, "Aura ON.")
    SetupFloatingBody(true)
end


local PrefixCommands = {}





PrefixCommands["bring"] = function(cmd, cmdLower)
    StopAllActions(nil)
    local argStr = ParseArg(cmd, 7)
    local targetName = Config.MainAccount
    if argStr ~= "" then
        local targetPlayer = FindPlayer(argStr)
        if targetPlayer then
            targetName = targetPlayer.Name
        end
    end

    print("[Alt Controller] Bringing alt to " .. targetName .. "...")
    local leaderPlayer = FindPlayer(targetName)
    if leaderPlayer and leaderPlayer.Character and leaderPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local leaderRoot = leaderPlayer.Character.HumanoidRootPart
        if LocalPlayer.Character then
            local offset = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
            LocalPlayer.Character:PivotTo(leaderRoot.CFrame * CFrame.new(offset))
        end
    else
        print("[Alt Controller] Target not found or missing character: " .. targetName)
    end
end

PrefixCommands["goto"] = function(cmd, cmdLower)
    StopAllActions("goto")
    local argStr = ParseArg(cmd, 5)
    if argStr == "" then
        print("[Alt Controller] goto requires a target name.")
        return
    end
    
    local targetPlayer = FindPlayer(argStr)
    if not targetPlayer then
        print("[Alt Controller] goto target not found.")
        return
    end
    
    print("[Alt Controller] Going to " .. targetPlayer.Name .. "...")
    
    CurrentMode = "goto" 

    task.spawn(function()
        while CurrentMode == "goto" do
            if targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local targetPos = targetPlayer.Character.HumanoidRootPart.Position
                local myChar = LocalPlayer.Character
                local hum = myChar and myChar:FindFirstChildOfClass("Humanoid")
                
                if hum then
                    hum.AutoRotate = true
                    hum.WalkSpeed = 16
                    hum:MoveTo(targetPos)
                end
            end
            task.wait(0.2)
        end
    end)
end

PrefixCommands["worm"] = function(cmd, cmdLower)
    SetupFormation(cmd, "worm", 5, "Worm ON.")
end

PrefixCommands["vform"] = function(cmd, cmdLower)
    SetupFormation(cmd, "vform", 6, "V-Formation ON.")
end

PrefixCommands["vshape"] = function(cmd, cmdLower)
    SetupFormation(cmd, "vform", 7, "V-Formation ON.")
end

PrefixCommands["army"] = function(cmd, cmdLower)
    SetupFormation(cmd, "army", 5, "Army March ON.")
end

PrefixCommands["flank"] = function(cmd, cmdLower)
    SetupFormation(cmd, "flank", 6, "Flank Formation ON.")
end

PrefixCommands["circlein"] = function(cmd, cmdLower)
    SetupFormation(cmd, "circlein", 9, "Circle In ON.")
end

PrefixCommands["circleout"] = function(cmd, cmdLower)
    SetupFormation(cmd, "circleout", 10, "Circle Out ON.")
end

PrefixCommands["spin"] = function(cmd, cmdLower)
    SetupFormation(cmd, "spin", 5, "Spinning around -> " .. tostring(CommandLeader))
end

PrefixCommands["swarm"] = function(cmd, cmdLower)
    SetupFormation(cmd, "swarm", 6, "Swarming -> " .. tostring(CommandLeader))
end

PrefixCommands["bodyguard"] = function(cmd, cmdLower)
    SetupFormation(cmd, "bodyguard", 10, "Bodyguard mode ON for -> " .. tostring(CommandLeader))
end

PrefixCommands["stack"] = function(cmd, cmdLower)
    SetupFormation(cmd, "stack", 6, "Stack ON -> " .. tostring(CommandLeader))
    SetupFloatingBody(false)
end

PrefixCommands["stalk"] = function(cmd, cmdLower)
    SetupFormation(cmd, "stalk", 6, "Stalk ON.")
end

PrefixCommands["pillar"] = function(cmd, cmdLower)
    SetupFormation(cmd, "pillar", 8, "Pillar ON.")
end

PrefixCommands["allfling"] = function(cmd, cmdLower)
    SetupFormation(cmd, "allfling", 9, "All Fling ON.")
end

PrefixCommands["heli"] = function(cmd, cmdLower)
    SetupFormation(cmd, "heli", 5, "Heli ON.")
    -- No SetupFloatingBody: heli uses direct CFrame locking now
end

PrefixCommands["helicopter"] = function(cmd, cmdLower)
    SetupFormation(cmd, "heli", 11, "Heli ON.")
    -- No SetupFloatingBody: heli uses direct CFrame locking now
end

PrefixCommands["helispeed"] = function(cmd, cmdLower)
    local val = tonumber(string.match(cmd, "helispeed%s+([%d%.]+)"))
    if val then
        HeliSpeed = math.clamp(val, 0.5, 30)
        print("[Alt Controller] HeliSpeed set to: " .. HeliSpeed)
    end
end

PrefixCommands["heliradius"] = function(cmd, cmdLower)
    local val = tonumber(string.match(cmd, "heliradius%s+([%d%.]+)"))
    if val then
        HeliRadius = math.clamp(val, 2, 30)
        print("[Alt Controller] HeliRadius set to: " .. HeliRadius)
    end
end

PrefixCommands["fling"] = function(cmd, cmdLower)
    local argStr = ParseArg(cmd, 6)
    if argStr ~= "" then
        local targetPlayer = FindPlayer(argStr)
        if targetPlayer then
            SingleFlingTarget = targetPlayer.Name
            print("[Alt Controller] Assassin Fling sent against: " .. targetPlayer.Name)
        end
    else
        SingleFlingTarget = nil
        print("[Alt Controller] Assassin Fling cancelled.")
    end
end

PrefixCommands["scatter"] = function(cmd, cmdLower)
    StopAllActions("scatter")
    ApplyModeSetup("scatter")
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
        local pos = LocalPlayer.Character.HumanoidRootPart.Position
        ScatterTarget = pos + Vector3.new(math.random(-500, 500), 0, math.random(-500, 500))
    end
    print("[Alt Controller] Scattering!")
end

PrefixCommands["panic"] = PrefixCommands["scatter"]

PrefixCommands["orbit"] = function(cmd, cmdLower)
    SetupFormation(cmd, "orbit", 6, "Orbit ON -> " .. tostring(CommandLeader))
    SetupFloatingBody(true)
end

PrefixCommands["jumba"] = function(cmd, cmdLower)
    SetupFormation(cmd, "jumba", 6, "Jumba ON.")
    SetupFloatingBody(true)
end

PrefixCommands["aura"] = function(cmd, cmdLower)
    SetupFormation(cmd, "aura", 5, "Aura ON.")
    SetupFloatingBody(true)
end

PrefixCommands["pulse"] = function(cmd, cmdLower)
    SetupFormation(cmd, "aura", 6, "Aura ON.")
    SetupFloatingBody(true)
end

PrefixCommands["tornado"] = function(cmd, cmdLower)
    SetupFormation(cmd, "tornado", 8, "Tornado ON -> " .. tostring(CommandLeader))
    local myCharacter = LocalPlayer.Character
    local myHumanoid = myCharacter and myCharacter:FindFirstChildOfClass("Humanoid")
    if myHumanoid then
        myHumanoid.WalkSpeed = 50
        myHumanoid.HipHeight = 0.5
    end
end

PrefixCommands["haunted"] = function(cmd, cmdLower)
    SetupFormation(cmd, "haunted", 8, "Haunted ON -> " .. tostring(CommandLeader))
    hauntedPhase = "idle"
    hauntedTimer = math.random() * 5 + 2
end

PrefixCommands["haunt"] = function(cmd, cmdLower)
    SetupFormation(cmd, "haunted", 7, "Haunted ON -> " .. tostring(CommandLeader))
    hauntedPhase = "idle"
    hauntedTimer = math.random() * 5 + 2
end



PrefixCommands["mech"] = function(cmd, cmdLower)
    SetupFormation(cmd, "mech", 5, "Mech ON.")
    local myOffset = math.max(1, MyIndex - 1)
    if myOffset <= 7 then SetupFloatingBody(true) end
end

PrefixCommands["motorcycle"] = function(cmd, cmdLower)
    SetupFormation(cmd, "motorcycle", 11, "Motorcycle ON.")
    SetupFloatingBody(true)
end

PrefixCommands["bike"] = function(cmd, cmdLower)
    SetupFormation(cmd, "motorcycle", 5, "Bike ON.")
    SetupFloatingBody(true)
end

PrefixCommands["moto_burnout"] = function(cmd, cmdLower)
    local state = string.match(cmdLower, "moto_burnout%s+(%w+)")
    if state == "true" then
        ActiveBurnout = true
    elseif state == "false" then
        ActiveBurnout = false
    end
end

local function ProcessCommand(cmd, sender)
    -- If sender is provided, verify it
    if sender and not IsAuthorized(sender) then
        print("[Alt Controller] Ignoring unauthorized command from: " .. tostring(sender))
        return 
    end
    
    cmd = string.match(cmd, "^%s*(.-)%s*$")
    if cmd == "" then return end
    local cmdLower = string.lower(cmd)

    -- Try to see if this is an exact match for a command
    local exactHandler = ExactCommands[cmdLower]
    if exactHandler then
        exactHandler(cmd)
        return
    end

    -- If not, split into first word and the rest
    local firstWord = string.match(cmdLower, "^(%S+)")
    if not firstWord then return end
    
    local rest = string.match(cmd, "^%S+%s+(.*)$")
    
    -- If there's an argument, check if it's a player
    if rest and rest ~= "" then
        local targetPlayer = FindPlayer(rest)
        if targetPlayer then
            -- Update leader to the targeted player
            CommandLeader = targetPlayer.Name
            UpdateFollowTarget()
            UpdateMathCache()
            
            -- Now try to see if the first word alone is an exact command (e.g. "jump PlayerX")
            local baseExactHandler = ExactCommands[firstWord]
            if baseExactHandler then
                baseExactHandler(cmd)
                return
            end
        end
    end

    -- Handle special multi-word prefixes
    if firstWord == "alt" then
        if string.sub(cmdLower, 1, 8) == "alt mech" or string.sub(cmdLower, 1, 7) == "altmech" then
            SetupFormation(cmd, "altmech", cmdLower:find("^alt mech") and 9 or 8, "Alt Mech ON.")
            local myOffset = math.max(1, MyIndex - 1)
            if myOffset <= 7 then SetupFloatingBody(true) end
            return
        end
    elseif firstWord == "altmech" then
        SetupFormation(cmd, "altmech", 8, "Alt Mech ON.")
        local myOffset = math.max(1, MyIndex - 1)
        if myOffset <= 7 then SetupFloatingBody(true) end
        return
    elseif firstWord == "all" and (cmdLower == "all fling" or string.sub(cmdLower, 1, 9) == "all fling") then
        PrefixCommands["allfling"](cmd, cmdLower)
        return
    elseif firstWord == "circle" then
        if string.sub(cmdLower, 1, 9) == "circle in" then
            SetupFormation(cmd, "circlein", 10, "Circle In ON.")
            return
        elseif string.sub(cmdLower, 1, 10) == "circle out" then
            SetupFormation(cmd, "circleout", 11, "Circle Out ON.")
            return
        end
    end

    -- Regular prefix handlers
    local prefixHandler = PrefixCommands[firstWord]
    if prefixHandler then
        prefixHandler(cmd, cmdLower)
        return
    end

    print("[Alt Controller] Received command:", cmdLower)
end

local WS_URL = "ws://localhost:8080/"
local WS_CONN = nil
pcall(function()
    WS_CONN = WebSocket.connect(WS_URL)
end)

local function BroadcastCmdInvisible(cmd, sender)
    if WS_CONN then
        task.spawn(function()
            pcall(function()
                local prefix = sender or LocalPlayer.Name
                WS_CONN:Send(prefix .. "|" .. cmd)
            end)
        end)
    else
        warn("[Alt Controller] WebSocket not connected or unsupported. Commands will not work.")
    end
end


local function CreateCommandBar()
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "AltControllerCommandBar"
    screenGui.ResetOnSpawn = false
    pcall(function() screenGui.Parent = CoreGui end)
    if not screenGui.Parent then
        screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, 400, 0, 50)
    frame.Position = UDim2.new(0.5, -200, 1, 50)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = screenGui

    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
    local stroke = Instance.new("UIStroke", frame)
    stroke.Color = Color3.fromRGB(100, 100, 100)
    stroke.Thickness = 1

    local textBox = Instance.new("TextBox")
    textBox.Size = UDim2.new(1, -20, 1, 0)
    textBox.Position = UDim2.new(0, 10, 0, 0)
    textBox.BackgroundTransparency = 1
    textBox.Font = Enum.Font.GothamMedium
    textBox.TextSize = 18
    textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
    textBox.PlaceholderText = "Enter command (e.g. worm, stack, jump)..."
    textBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
    textBox.TextXAlignment = Enum.TextXAlignment.Left
    textBox.ClearTextOnFocus = true
    textBox.Parent = frame

    local isVisible = false

    local function ToggleCommandBar()
        isVisible = not isVisible
        if isVisible then
            frame:TweenPosition(UDim2.new(0.5, -200, 1, -100), Enum.EasingDirection.Out, Enum.EasingStyle.Quart, 0.3, true, function()
                textBox:CaptureFocus()
            end)
        else
            textBox:ReleaseFocus()
            frame:TweenPosition(UDim2.new(0.5, -200, 1, 50), Enum.EasingDirection.In, Enum.EasingStyle.Quart, 0.3, true, function()
                textBox.Text = ""
            end)
        end
    end

    local isHiding = false
    local function HideCommandBar()
        if isHiding then return end
        isHiding = true
        isVisible = false
        textBox:ReleaseFocus()
        frame:TweenPosition(UDim2.new(0.5, -200, 1, 50), Enum.EasingDirection.In, Enum.EasingStyle.Quart, 0.3, true, function()
            textBox.Text = ""
            isHiding = false
        end)
    end

    UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed and not textBox:IsFocused() then return end
        if input.KeyCode == Enum.KeyCode.N and not textBox:IsFocused() then
            ToggleCommandBar()
        end
    end)

    return textBox, ToggleCommandBar, HideCommandBar
end


local isAlt = false
for altName, _ in pairs(Config.Alts) do
    if string.lower(altName) == string.lower(LocalPlayer.Name) then
        isAlt = true
        break
    end
end

if isAlt then
    UpdateFollowTarget()
    print("[Alt Controller] Alt loaded: " .. LocalPlayer.Name)

    local staggerDelay = MyIndex * 0.004
    task.wait(staggerDelay)

    pcall(function()
        if setfpscap then setfpscap(60) end
        settings().Rendering.QualityLevel = 1
        
        local gui = Instance.new("ScreenGui")
        gui.Name = "AltOptimizationUI"
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 9999999
        
        local frame = Instance.new("Frame")
        frame.Size = UDim2.new(1, 0, 1, 0)
        frame.BackgroundColor3 = Color3.new(0.05, 0.05, 0.05)
        frame.Parent = gui
        
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 1, 0)
        label.BackgroundTransparency = 1
        label.TextColor3 = Color3.new(0.8, 0.8, 0.8)
        label.Font = Enum.Font.GothamBold
        label.TextSize = 32
        label.Text = "ALT CONTROLLER - OPTIMIZED\n\nFPS Capped\n3D Rendering Disabled"
        label.Parent = frame
        
        local successParent = pcall(function() gui.Parent = CoreGui end)
        if not successParent then
            gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
        end
        
        RunService:Set3dRenderingEnabled(false)
    end)

    local cachedRoot = nil
    local cachedHumanoid = nil
    
    local function RefreshCharacterCache()
        local char = LocalPlayer.Character
        if char then
            cachedRoot = char:FindFirstChild("HumanoidRootPart")
            cachedHumanoid = char:FindFirstChildOfClass("Humanoid")
        else
            cachedRoot = nil
            cachedHumanoid = nil
        end
    end
    RefreshCharacterCache()
    
    local cachedIntruders = {}
    local lastIntruderScan = 0
    
    local lastPos = Vector3.zero
    local stuckTimer = 0
    local seatWeldConnection = nil

    LocalPlayer.CharacterAdded:Connect(function(character)
        task.wait(0.3)
        RefreshCharacterCache()
        if CurrentMode ~= "none" then
            for _, child in ipairs(character:GetChildren()) do
                if child:IsA("BasePart") then
                    if CurrentMode ~= "allfling" and CurrentMode ~= "carpet" then
                        child.CanCollide = false
                    end
                elseif child:IsA("Accessory") then
                    local handle = child:FindFirstChild("Handle")
                    if handle and handle:IsA("BasePart") then
                        if CurrentMode ~= "allfling" and CurrentMode ~= "carpet" then
                            handle.CanCollide = false
                        end
                    end
                end
            end
            
            local myHumanoid = character:FindFirstChildOfClass("Humanoid")
            if myHumanoid then
                myHumanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
            end
            
            if CurrentMode == "ufo" or CurrentMode == "carpet" or CurrentMode == "elevator" or CurrentMode == "motorcycle" or CurrentMode == "orbit" or CurrentMode == "mech" or CurrentMode == "altmech" or CurrentMode == "tornado" or CurrentMode == "stack" or CurrentMode == "pillar" or CurrentMode == "heli" then return end
            
            if seatWeldConnection then
                seatWeldConnection:Disconnect()
                seatWeldConnection = nil
            end
            
            seatWeldConnection = character.ChildAdded:Connect(function(child)
                if child:IsA("Weld") and child.Name == "SeatWeld" then
                    task.wait()
                    child:Destroy()
                end
            end)
        end
    end)

    if WS_CONN then
        TrackConnection(WS_CONN.OnMessage:Connect(function(message)
            if string.sub(message, 1, 7) == "SERVER|" then
                ProcessCommand(string.sub(message, 8))
            elseif string.sub(message, 1, 6) == "RELAY|" then
                local relayContent = string.sub(message, 7)
                local sender, cmd = string.match(relayContent, "^([^|]+)|(.*)$")
                if sender then
                    ProcessCommand(cmd, sender)
                else
                    ProcessCommand(relayContent) -- Fallback
                end
            end
        end))
        TrackConnection(WS_CONN.OnClose:Connect(function()
            warn("[Alt Controller] WebSocket connection closed.")
        end))
    end

    local lastModeTracked = "none"
    local allFlingBlacklist = {}
    local allFlingBlacklistTime = tick()
    local allFlingTarget = nil
    local allFlingTimer = 0
    
    local myPersistentTarget = nil
    
    local lastUpdate = 0
    local lastGyroTarget = CFrame.new()
    local lastMechGyroTarget = CFrame.new()
    local lastCarpetGyroTarget = CFrame.new()

    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        lastUpdate = lastUpdate + dt
        local throttleRate = 0.03
        if CurrentMode == "orbit" or CurrentMode == "army" or CurrentMode == "aura" or CurrentMode == "jumba" or CurrentMode == "heli" or CurrentMode == "tornado" or CurrentMode == "spin" or CurrentMode == "swarm" or CurrentMode == "circlein" or CurrentMode == "circleout" or CurrentMode == "haunted" then
            throttleRate = 0.05
        end
        if lastUpdate < throttleRate then return end
        lastUpdate = 0
        
        if CurrentMode ~= lastModeTracked then
            lastModeTracked = CurrentMode
            allFlingBlacklist = {}
            allFlingTarget = nil
            allFlingTimer = 0
            myPersistentTarget = nil
        end
        
        local myRoot = cachedRoot
        local myHumanoid = cachedHumanoid
        
        if not myRoot or not myRoot.Parent or not myHumanoid or not myHumanoid.Parent then
            RefreshCharacterCache()
            myRoot = cachedRoot
            myHumanoid = cachedHumanoid
        end
        
        if myRoot then
            if CurrentMode ~= "none" then
                myRoot:SetAttribute("AltMode", CurrentMode)
            elseif not myRoot:GetAttribute("AltMode") or myRoot:GetAttribute("AltMode") == "none" then
                myRoot:SetAttribute("AltMode", "none")
            end
        end
        
        if not (myRoot and myHumanoid) or myHumanoid.Health <= 0 then return end
        
        local altIndexOffset = math.max(1, MyIndex - 1)
        
        if SingleFlingTarget then
            local tPlayer = FindPlayer(SingleFlingTarget)
            if tPlayer and tPlayer.Character and tPlayer.Character:FindFirstChild("HumanoidRootPart") then
                local tRoot = tPlayer.Character.HumanoidRootPart
                local bav = myRoot:FindFirstChild("FlingSpin")
                if not bav then
                    bav = Instance.new("BodyAngularVelocity")
                    bav.Name = "FlingSpin"
                    bav.AngularVelocity = Vector3.new(99999, 99999, 99999)
                    bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                    bav.P = math.huge
                    bav.Parent = myRoot
                end
                
                myRoot.CFrame = tRoot.CFrame
                return
            else
                SingleFlingTarget = nil
                local bav = myRoot:FindFirstChild("FlingSpin")
                if bav then bav:Destroy() end
            end
        elseif altIndexOffset == 1 and not SingleFlingTarget then
            local bav = myRoot:FindFirstChild("FlingSpin")
            if bav and CurrentMode ~= "allfling" and CurrentMode ~= "fling" then bav:Destroy() end
        end

        if CurrentMode == "none" then return end

        if CurrentMode == "controlled" then
            myHumanoid.WalkSpeed = 16
            myHumanoid.AutoRotate = true
            myHumanoid.PlatformStand = false
            if ControlMoveDir and ControlMoveDir.Magnitude > 0 then
                myHumanoid:Move(ControlMoveDir, false)
            else
                myHumanoid:Move(Vector3.zero, false)
            end
            return
        end

        if CurrentMode == "scatter" then
            if ScatterTarget then
                if (myRoot.Position - ScatterTarget).Magnitude < 4 then
                    ScatterTarget = myRoot.Position + Vector3.new(math.random(-50, 50), 0, math.random(-50, 50))
                end
                myHumanoid:MoveTo(ScatterTarget)
                if math.random() < 0.02 then
                    myHumanoid.Jump = true
                end
            end
            return
        end

        local targetName = (CurrentMode == "worm") and MyFollowTarget or CommandLeader
        if not targetName then return end
        
        if targetName == LocalPlayer.Name then return end

        local targetPlayer = Players:FindFirstChild(targetName)
        if not targetPlayer then return end
        
        local targetRoot = targetPlayer.Character and targetPlayer.Character:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = targetPlayer.Character and targetPlayer.Character:FindFirstChildOfClass("Humanoid")
        
        if not targetRoot or not targetHumanoid then return end

        if CurrentMode == "worm" then
            local targetPos = targetRoot.Position
            local isJumping = targetHumanoid.Jump or (targetHumanoid:GetState() == Enum.HumanoidStateType.Jumping) or (targetHumanoid:GetState() == Enum.HumanoidStateType.Freefall)
            
            if #TargetBreadcrumbs == 0 or (TargetBreadcrumbs[1].pos - targetPos).Magnitude > 1.5 then
                table.insert(TargetBreadcrumbs, 1, {pos = targetPos, jump = isJumping})
            else
                if isJumping and #TargetBreadcrumbs > 0 then
                    TargetBreadcrumbs[1].jump = true
                end
            end
            
            local MaxCrumbs = math.max(20, TotalAlts * 4)
            while #TargetBreadcrumbs > MaxCrumbs do
                table.remove(TargetBreadcrumbs)
            end
            
            local idealCrumbIndex = 2
            idealCrumbIndex = math.clamp(idealCrumbIndex, 1, #TargetBreadcrumbs)

            local myCrumb = TargetBreadcrumbs[idealCrumbIndex]

            if not myCrumb then 
                myHumanoid:Move(Vector3.zero, false)
                return 
            end

            local dist2DToCrumb = Vector2.new(myRoot.Position.X - myCrumb.pos.X, myRoot.Position.Z - myCrumb.pos.Z).Magnitude
            
            if dist2DToCrumb > 0.8 then
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(myCrumb.pos)
                
                local checkJumpIndex = math.max(1, idealCrumbIndex - 3)
                for i = idealCrumbIndex, checkJumpIndex, -1 do
                    if TargetBreadcrumbs[i] and TargetBreadcrumbs[i].jump then
                        local crumbDist = Vector2.new(myRoot.Position.X - TargetBreadcrumbs[i].pos.X, myRoot.Position.Z - TargetBreadcrumbs[i].pos.Z).Magnitude
                        if crumbDist < 3.0 then
                            myHumanoid.Jump = true
                            break
                        end
                    end
                end
            else
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)
                
                local lookPos
                if idealCrumbIndex > 1 then
                    lookPos = TargetBreadcrumbs[idealCrumbIndex - 1].pos
                else
                    lookPos = targetPos
                end
                
                local lookTarget = Vector3.new(lookPos.X, myRoot.Position.Y, lookPos.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end

        elseif CurrentMode == "vform" then
            local row = MathCache.rowHalf
            local isLeft = MathCache.isLeft
            
            local isLastRow = MathCache.isLastRowHalf
            local altsInLastRow = MathCache.altsInLastRowHalf
            
            local xOffset = 0
            if isLastRow and altsInLastRow == 1 then
                xOffset = 0
            else
                xOffset = (isLeft and -1 or 1) * (row * 4)
            end
            
            local zOffset = row * 4
            
            local targetPos = (targetRoot.CFrame * CFrame.new(xOffset, 0, zOffset)).Position
            myHumanoid.WalkSpeed = 16
            
            local distFromTarget = (targetPos - myRoot.Position).Magnitude
            if distFromTarget > 1 then
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(targetPos)
            else
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)
                local lookTarget = myRoot.Position + targetRoot.CFrame.LookVector * 10
                lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end

        elseif CurrentMode == "army" then
            local row = MathCache.armyRow
            local colIndex = MathCache.armyColIndex
            
            local totalRows = MathCache.totalArmyRows
            local isLastRow = MathCache.isLastArmyRow
            local altsInLastRow = MathCache.altsInLastArmyRow
            
            local col = 0
            if isLastRow and altsInLastRow == 1 then
                col = 0
            elseif isLastRow and altsInLastRow == 2 then
                col = (colIndex == 0) and -0.5 or 0.5
            else
                col = colIndex - 1
            end
            
            local xOffset = col * 4
            local zOffset = row * 4
            
            local targetPos = (targetRoot.CFrame * CFrame.new(xOffset, 0, zOffset)).Position
            myHumanoid.WalkSpeed = 16
            
            local distFromTarget = (targetPos - myRoot.Position).Magnitude
            if distFromTarget > 1 then
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(targetPos)
            else
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)
                local lookTarget = myRoot.Position + targetRoot.CFrame.LookVector * 10
                lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end

        elseif CurrentMode == "flank" then
            local row = MathCache.rowHalf
            local isLeft = MathCache.isLeft
            
            local isLastRow = MathCache.isLastRowHalf
            local altsInLastRow = MathCache.altsInLastRowHalf
            
            local xOffset = 0
            if isLastRow and altsInLastRow == 1 then
                xOffset = 0
            else
                xOffset = (isLeft and -12 or 12)
            end
            
            local zOffset = (row - 1) * 4
            
            local targetPos = (targetRoot.CFrame * CFrame.new(xOffset, 0, zOffset)).Position
            myHumanoid.WalkSpeed = 16
            
            local distFromTarget = (targetPos - myRoot.Position).Magnitude
            if distFromTarget > 1 then
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(targetPos)
            else
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)
                local lookTarget = myRoot.Position + targetRoot.CFrame.LookVector * 10
                lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end

        elseif CurrentMode == "swarm" then
            local timeSec = tick()
            local angle = MathCache.swarmAngleOffset + (timeSec * 4)
            local radius = MathCache.swarmRadius
            local xOffset = math.cos(angle) * radius
            local zOffset = math.sin(angle) * radius
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, 0, zOffset)
            
            myHumanoid.AutoRotate = true
            myHumanoid:MoveTo(targetPos)
            
            if math.random() < 0.05 then
                myHumanoid.Jump = true
            end
            
        elseif CurrentMode == "circlein" or CurrentMode == "circleout" then
            local angle = MathCache.angle
            local radius = 8
            local xOffset = math.cos(angle) * radius
            local zOffset = math.sin(angle) * radius
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, 0, zOffset)
            
            local distFromTarget = (Vector3.new(targetPos.X, myRoot.Position.Y, targetPos.Z) - myRoot.Position).Magnitude
            
            if distFromTarget > 1 then
                myHumanoid.WalkSpeed = 16
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(targetPos)
            else
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)
                
                local lookTarget
                if CurrentMode == "circlein" then
                    lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
                else
                    local awayDir = (myRoot.Position - targetRoot.Position).Unit
                    lookTarget = myRoot.Position + (awayDir * 5)
                    lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                end
                
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end

        elseif CurrentMode == "spin" then
            local angle = MathCache.angle
            local radius = MathCache.spinRadius
            
            local timeSec = tick()
            local spinSpeed = 16 / radius
            local currentAngle = angle + (timeSec * spinSpeed)

            local xOffset = math.cos(currentAngle) * radius
            local zOffset = math.sin(currentAngle) * radius
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, 0, zOffset)
            
            myHumanoid.AutoRotate = true
            myHumanoid:MoveTo(targetPos)

        elseif CurrentMode == "tornado" then
            local radius = 4
            local angle = MathCache.angle
            
            local timeSec = tick()
            local spinSpeed = 10
            local currentAngle = angle + (timeSec * spinSpeed)
            
            local xOffset = math.cos(currentAngle) * radius
            local zOffset = math.sin(currentAngle) * radius
            
            local verticalWave = math.sin(timeSec * 2 + altIndexOffset) * 6
            local yOffset = verticalWave + 6
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, yOffset, zOffset)
            
            myHumanoid.PlatformStand = true
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 1000
                bp.P = 20000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local lookTarget = Vector3.new(targetRoot.Position.X, targetPos.Y, targetRoot.Position.Z)
            if (lookTarget - targetPos).Magnitude > 0.01 then
                local bg = myRoot:FindFirstChildOfClass("BodyGyro")
                local faceCFrame = CFrame.lookAt(targetPos, lookTarget)
                if bg then
                    bg.CFrame = faceCFrame
                else
                    bg = Instance.new("BodyGyro")
                    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                    bg.CFrame = faceCFrame
                    bg.Parent = myRoot
                end
            end

        elseif CurrentMode == "haunted" then
            local distToTarget = (myRoot.Position - targetRoot.Position).Magnitude

            local cycleDuration = 8
            local currentCycle = math.floor(tick() / cycleDuration)
            local timeInCycle = tick() % cycleDuration

            -- Staggered creeping: each alt creeps on its own offset cycle
            local altPhaseOffset = (altIndexOffset - 1) / math.max(TotalAlts, 1) * cycleDuration
            local myTimeInCycle = (tick() + altPhaseOffset) % cycleDuration
            local amICreeping = myTimeInCycle < 5.5

            if amICreeping then
                hauntedPhase = "creeping"
            else
                hauntedPhase = "idle"
            end

            -- Idle radius shrinks over time so alts drift closer
            local baseIdleRadius = math.clamp(distToTarget * 0.45, 3, 8)
            local idleAngle = MathCache.auraPhaseOffset
            idleAngle = idleAngle + math.sin(tick() * 0.15 + altIndexOffset) * 0.3
            local idlePos = targetRoot.Position + Vector3.new(math.cos(idleAngle) * baseIdleRadius, 0, math.sin(idleAngle) * baseIdleRadius)

            if distToTarget > 20 then
                -- Far away: sprint to close the gap
                myHumanoid.WalkSpeed = 24
                myHumanoid.AutoRotate = true
                myHumanoid:MoveTo(targetRoot.Position)

            elseif distToTarget < 3 then
                -- Very close: stop and stare creepily
                myHumanoid.WalkSpeed = 16
                myHumanoid.AutoRotate = false
                myHumanoid:MoveTo(myRoot.Position)

                local lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end

            elseif hauntedPhase == "creeping" then
                -- Creeping: slowly close the distance toward the target
                local creepSpeed = math.clamp(distToTarget * 0.6, 4, 10)
                myHumanoid.WalkSpeed = creepSpeed
                myHumanoid.AutoRotate = false

                -- Walk toward a point slightly offset from the target (not all stacking on top)
                local creepAngle = MathCache.auraPhaseOffset
                local creepOffset = Vector3.new(math.cos(creepAngle) * 1.5, 0, math.sin(creepAngle) * 1.5)
                myHumanoid:MoveTo(targetRoot.Position + creepOffset)

                local lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end

            else
                -- Idle pause: hold position briefly but stay close, face target
                local distToIdlePos = (myRoot.Position - idlePos).Magnitude
                if distToIdlePos > 1.5 then
                    local catchUpSpeed = math.clamp(distToIdlePos * 2, 8, 20)
                    myHumanoid.WalkSpeed = catchUpSpeed
                    myHumanoid.AutoRotate = false
                    myHumanoid:MoveTo(idlePos)
                else
                    myHumanoid.WalkSpeed = 0
                    myHumanoid:MoveTo(myRoot.Position)
                end

                local lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
                if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                    myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                end
            end
            
        elseif CurrentMode == "bodyguard" then
            local numAttackers = math.clamp(math.ceil(TotalAlts / 2), 2, 6)
            local isAttacker = (altIndexOffset <= numAttackers)
            
            if tick() - lastIntruderScan > 0.25 then
                lastIntruderScan = tick()
                cachedIntruders = {}
                
                local myTPlayer = Players:FindFirstChild(CommandLeader)
                local myTRoot = myTPlayer and myTPlayer.Character and myTPlayer.Character:FindFirstChild("HumanoidRootPart")

                for _, p in ipairs(Players:GetPlayers()) do
                    if p.Character then
                        local pRoot = p.Character:FindFirstChild("HumanoidRootPart")
                        local pHum = p.Character:FindFirstChildOfClass("Humanoid")
                        if pRoot and pHum and pHum.Health > 0 then
                            local pNameLower = string.lower(p.Name)
                            local isPAlt = Config.Alts[p.Name] or Config.Alts[pNameLower]
                            
                            if not isPAlt and pNameLower ~= string.lower(CommandLeader) and myTRoot then
                                local distToLeader = (pRoot.Position - myTRoot.Position).Magnitude
                                if distToLeader <= 15 then
                                    table.insert(cachedIntruders, {part = pRoot, dist = distToLeader})
                                end
                            end
                        end
                    end
                end
                
                table.sort(cachedIntruders, function(a, b) return a.dist < b.dist end)
            end
            
            myHumanoid.WalkSpeed = 16
            myHumanoid.AutoRotate = true
            
            if #cachedIntruders > 0 and isAttacker then
                local targetIndex = ((altIndexOffset - 1) % #cachedIntruders) + 1
                local intruder = cachedIntruders[targetIndex].part
                
                local pairIndex = 0
                for i = 1, altIndexOffset do
                    if ((i - 1) % #cachedIntruders) + 1 == targetIndex then
                        pairIndex = pairIndex + 1
                    end
                end
                
                local isFront = (pairIndex % 2 == 1)
                local intruderLook = intruder.CFrame.LookVector
                local offsetDir = isFront and intruderLook or -intruderLook
                
                local sideOffset = Vector3.new(0, 0, 0)
                if pairIndex > 2 then
                    local sideAngle = ((pairIndex - 2) * 0.5) * (pairIndex % 2 == 1 and 1 or -1)
                    local rightVec = intruder.CFrame.RightVector
                    sideOffset = rightVec * sideAngle
                end
                
                local combatPos = intruder.Position + (offsetDir * 2.5) + sideOffset
                myHumanoid:MoveTo(combatPos)
                
                local distToPos = (myRoot.Position - combatPos).Magnitude
                if distToPos < 1.5 then
                    myHumanoid.AutoRotate = false
                    local facePos = Vector3.new(intruder.Position.X, myRoot.Position.Y, intruder.Position.Z)
                    if (facePos - myRoot.Position).Magnitude > 0.01 then
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, facePos)
                    end
                end
                
                if (myRoot.Position - intruder.Position).Magnitude < 4.5 then
                    local tool = myRoot.Parent and myRoot.Parent:FindFirstChildOfClass("Tool")
                    if tool then
                        tool:Activate()
                    end
                end
            else
                local row = math.ceil(altIndexOffset / 2)
                local isRight = (altIndexOffset % 2 == 1)
                local xOffset = isRight and 4 or -4
                local zOffset = (row - 1) * 4 - 2
                
                local guardPos = (targetRoot.CFrame * CFrame.new(xOffset, 0, zOffset)).Position
                
                myHumanoid:MoveTo(guardPos)
                
                if (guardPos - myRoot.Position).Magnitude < 1.5 then
                    local outDir = (myRoot.Position - targetRoot.Position)
                    if outDir.Magnitude > 0.01 then
                        local lookTarget = myRoot.Position + outDir.Unit * 5
                        lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                        myHumanoid.AutoRotate = false
                        myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                    end
                end
            end

        elseif CurrentMode == "stack" then
            local stackHeight = altIndexOffset * 6
            local targetPos = targetRoot.Position + Vector3.new(0, stackHeight, 0)
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(1e6, 1e6, 1e6)
                bp.D = 500
                bp.P = 5000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            if bg then
                bg.CFrame = targetRoot.CFrame
            else
                bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                bg.CFrame = targetRoot.CFrame
                bg.Parent = myRoot
            end
            
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "pillar" then
            local remaining = TotalAlts
            local tiers = {}
            local targetSize = 1
            
            while remaining > 0 do
                if remaining >= targetSize then
                    table.insert(tiers, 1, targetSize)
                    remaining = remaining - targetSize
                    targetSize = targetSize + 1
                else
                    table.insert(tiers, 1, remaining)
                    remaining = 0
                end
            end
            
            local BASE_SPREAD = 4
            local BASE_Y = 0
            local TIER_HEIGHT = 6
            
            local slotOffset = Vector3.new(0, 0, 0)
            local altCounter = 0
            local assigned = false
            
            for tierIndex, tierSize in ipairs(tiers) do
                for posInTier = 1, tierSize do
                    altCounter = altCounter + 1
                    if altCounter == altIndexOffset then
                        local xOffset = (posInTier - (tierSize + 1) / 2) * BASE_SPREAD
                        local yOffset = BASE_Y + (tierIndex - 1) * TIER_HEIGHT
                        local zOffset = 0
                        
                        if tierIndex == 1 and math.abs(xOffset) < 1.0 then
                            zOffset = 3
                        end
                        
                        slotOffset = Vector3.new(xOffset, yOffset, zOffset)
                        assigned = true
                        break
                    end
                end
                if assigned then break end
            end
            
            local velocity = targetRoot.AssemblyLinearVelocity
            local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
            local forwardOffset = Vector3.zero
            if horizontalVel.Magnitude > 0.5 then
                forwardOffset = horizontalVel * 0.41
            end
            
            local rawTargetPos = targetRoot.CFrame * CFrame.new(slotOffset.X, slotOffset.Y, slotOffset.Z)
            local targetPos = rawTargetPos.Position + forwardOffset
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = bp.Position:Lerp(targetPos, 0.3)
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            if bg then
                 if (targetRoot.CFrame.LookVector - lastGyroTarget.LookVector).Magnitude > 0.05 then
                     bg.CFrame = targetRoot.CFrame
                     lastGyroTarget = targetRoot.CFrame
                 end
            else
                bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                bg.CFrame = targetRoot.CFrame
                bg.Parent = myRoot
                lastGyroTarget = targetRoot.CFrame
            end
            
            myRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "heli" then
            -- FIX: Use direct CFrame teleport instead of BodyPosition/BodyGyro.
            -- This locks alts precisely to their rotor position at ANY HeliSpeed,
            -- preventing the "drift to center" issue caused by physics lag at high speeds.
            local angle = MathCache.auraPhaseOffset
            local currentAngle = angle + (tick() * HeliSpeed)
            
            local xOffset = math.cos(currentAngle) * HeliRadius
            local zOffset = math.sin(currentAngle) * HeliRadius
            local yOffset = 1.5
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, yOffset, zOffset)
            
            local outDir = Vector3.new(xOffset, 0, zOffset)
            if outDir.Magnitude < 0.01 then outDir = Vector3.new(1, 0, 0) end
            outDir = outDir.Unit
            
            local targetCFrame = CFrame.lookAt(targetPos, targetPos + outDir) * CFrame.Angles(math.rad(90), 0, 0)
            
            -- Destroy any leftover physics objects from previous modes
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then bp:Destroy() end
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            if bg then bg:Destroy() end
            
            -- Hard-lock position and orientation every frame
            myRoot.CFrame = targetCFrame
            myRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "mech" or CurrentMode == "altmech" then
            
            local mechCenter = targetRoot.CFrame
            if CurrentMode == "altmech" then
                mechCenter = targetRoot.CFrame * CFrame.new(0, 5, 4)
            end
            
            local velocity = targetRoot.AssemblyLinearVelocity
            local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
            local isMoving = horizontalVel.Magnitude > 0.5
            
            local forwardOffset = Vector3.zero
            if isMoving then
                local predictFactor = 0.41
                forwardOffset = horizontalVel * predictFactor
            end
            
            local swingSpeed = 8
            local swingAmount = 2
            local t = tick() * swingSpeed
            local swing = isMoving and math.sin(t) * swingAmount or 0
            local headBob = isMoving and math.sin(t * 2) * 0.3 or 0
            
            local slotOffset
            if altIndexOffset == 1 then
                slotOffset = Vector3.new(4.5, 0, swing)
            elseif altIndexOffset == 2 then
                slotOffset = Vector3.new(-4.5, 0, -swing)
            elseif altIndexOffset == 3 then
                slotOffset = Vector3.new(1.5, -5, -swing)
            elseif altIndexOffset == 4 then
                slotOffset = Vector3.new(-1.5, -5, swing)
            elseif altIndexOffset == 5 then
                slotOffset = Vector3.new(0, 5 + headBob, 0)
            elseif altIndexOffset == 6 then
                slotOffset = Vector3.new(0, 0, 1.5)
            elseif altIndexOffset == 7 then
                slotOffset = Vector3.new(0, 5 + headBob, 1.5)
            end
            
            if altIndexOffset <= 7 and slotOffset then
                local targetPos = (mechCenter * CFrame.new(slotOffset)).Position + forwardOffset
                
                local bp = myRoot:FindFirstChildOfClass("BodyPosition")
                if bp then
                    bp.Position = targetPos
                else
                    bp = Instance.new("BodyPosition")
                    bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    bp.D = 2000
                    bp.P = 50000
                    bp.Position = targetPos
                    bp.Parent = myRoot
                end
                
                local bg = myRoot:FindFirstChildOfClass("BodyGyro")
                if bg then
                    if (targetRoot.CFrame.LookVector - lastMechGyroTarget.LookVector).Magnitude > 0.05 then
                        bg.CFrame = targetRoot.CFrame
                        lastMechGyroTarget = targetRoot.CFrame
                    end
                else
                    bg = Instance.new("BodyGyro")
                    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                    bg.CFrame = targetRoot.CFrame
                    bg.Parent = myRoot
                    lastMechGyroTarget = targetRoot.CFrame
                end
                
                myHumanoid.PlatformStand = true
            else
                myHumanoid.PlatformStand = false
                myHumanoid.AutoRotate = true
                local followPos = (mechCenter * CFrame.new(0, 0, 4 + ((altIndexOffset - 7) * 3))).Position
                myHumanoid:MoveTo(followPos)
            end

        elseif CurrentMode == "elevator" or CurrentMode == "carpet" then
            local cols = math.ceil(math.sqrt(TotalAlts))
            if TotalAlts >= 5 and TotalAlts <= 9 then cols = 3 end
            
            local spacingX = 4.2
            local spacingZ = 5.2
            
            local gridIndex = altIndexOffset - 1
            local row = math.floor(gridIndex / cols)
            local colInRow = gridIndex % cols
            
            local itemsInThisRow = cols
            local totalFullRows = math.floor(TotalAlts / cols)
            if row == totalFullRows then
                itemsInThisRow = TotalAlts % cols
            end
            if itemsInThisRow == 0 then itemsInThisRow = cols end
            
            local totalRows = math.ceil(TotalAlts / cols)
            
            local xOffset = (colInRow - (itemsInThisRow - 1) / 2) * spacingX
            local zOffset = (row - (totalRows - 1) / 2) * spacingZ
            
            local yOffset = (CurrentMode == "carpet") and -4.5 or -3
            
            local velocity = targetRoot.AssemblyLinearVelocity
            local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
            local forwardOffset = Vector3.zero
            if horizontalVel.Magnitude > 0.5 then
                forwardOffset = horizontalVel * 0.41
            end
            
            local targetPos = (targetRoot.CFrame * CFrame.new(xOffset, yOffset, zOffset)).Position + forwardOffset
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local layingCFrame = targetRoot.CFrame * CFrame.Angles(math.rad(90), 0, 0)
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            if bg then
                if (layingCFrame.LookVector - lastCarpetGyroTarget.LookVector).Magnitude > 0.05 then
                    bg.CFrame = layingCFrame
                    lastCarpetGyroTarget = layingCFrame
                end
            else
                bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                bg.CFrame = layingCFrame
                bg.Parent = myRoot
                lastCarpetGyroTarget = layingCFrame
            end
            
            if targetRoot and not myRoot:FindFirstChild("CarpetNoCollide") then
                local ncc = Instance.new("NoCollisionConstraint")
                ncc.Name = "CarpetNoCollide"
                ncc.Part0 = myRoot
                ncc.Part1 = targetRoot
                ncc.Parent = myRoot
            end
            
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "stalk" or CurrentMode == "allfling" then
            
            if altIndexOffset == 1 and CurrentMode == "stalk" then
                local behindPos = (targetRoot.CFrame * CFrame.new(0, 0, 4)).Position
                myHumanoid.AutoRotate = true
                myHumanoid.WalkSpeed = 16
                myHumanoid:MoveTo(behindPos)
            else
                local function isTargetValid(player)
                    if not player or not player.Parent then return false end
                    if not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return false end
                    local hum = player.Character:FindFirstChildOfClass("Humanoid")
                    if not hum or hum.Health <= 0 then return false end
                    local pNameLower = string.lower(player.Name)
                    local isAltOrLeader = (pNameLower == string.lower(CommandLeader))
                    if not isAltOrLeader then
                        for aName, _ in pairs(Config.Alts) do
                            if string.lower(aName) == pNameLower then
                                isAltOrLeader = true
                                break
                            end
                        end
                    end
                    if isAltOrLeader then return false end
                    local tRoot = player.Character:FindFirstChild("HumanoidRootPart")
                    if tRoot then
                        local isFlung = tRoot.AssemblyLinearVelocity.Magnitude > 150 or tRoot.Position.Y > 500 or tRoot.Position.Y < -500
                        if isFlung or allFlingBlacklist[player.Name] then return false end
                    end
                    return true
                end

                local needsNewTarget = false
                if CurrentMode == "stalk" then
                    if not isTargetValid(myPersistentTarget) then needsNewTarget = true end
                elseif CurrentMode == "allfling" then
                    if not isTargetValid(allFlingTarget) then needsNewTarget = true end
                end

                if needsNewTarget then
                    local targets = {}
                    for _, p in ipairs(Players:GetPlayers()) do
                        if isTargetValid(p) then
                            table.insert(targets, p)
                        end
                    end
                    
                    table.sort(targets, function(a, b) return a.Name < b.Name end)
                    
                    if #targets > 0 then
                        local indexOffset = (CurrentMode == "stalk") and 2 or 1
                        local assignedIndex = ((altIndexOffset - indexOffset) % #targets) + 1
                        
                        if CurrentMode == "stalk" then
                            myPersistentTarget = targets[assignedIndex]
                        else
                            allFlingTarget = targets[assignedIndex]
                            allFlingTimer = 0
                        end
                    else
                        if CurrentMode == "stalk" then
                            myPersistentTarget = nil
                        else
                            allFlingBlacklist = {}
                            allFlingTarget = nil
                            local bav = myRoot:FindFirstChild("FlingSpin")
                            if bav then bav:Destroy() end
                        end
                    end
                end

                local activeTargetPlayer = (CurrentMode == "stalk") and myPersistentTarget or allFlingTarget

                if activeTargetPlayer and activeTargetPlayer.Character and activeTargetPlayer.Character:FindFirstChild("HumanoidRootPart") then
                    local assignedRoot = activeTargetPlayer.Character.HumanoidRootPart
                    if CurrentMode == "stalk" then
                        local angle = (altIndexOffset * math.pi * 0.5)
                        local xOff = math.cos(angle) * 3
                        local zOff = math.sin(angle) * 3

                        local behindPos = (assignedRoot.CFrame * CFrame.new(xOff, 0, 3 + zOff)).Position
                        myHumanoid.AutoRotate = true
                        myHumanoid.WalkSpeed = 16
                        myHumanoid:MoveTo(behindPos)
                        
                        local dist = (myRoot.Position - behindPos).Magnitude
                        if dist < 2 then
                            myHumanoid.AutoRotate = false
                            local lookTarget = assignedRoot.Position + assignedRoot.CFrame.LookVector * 10
                            lookTarget = Vector3.new(lookTarget.X, myRoot.Position.Y, lookTarget.Z)
                            if (lookTarget - myRoot.Position).Magnitude > 0.01 then
                                myRoot.CFrame = CFrame.lookAt(myRoot.Position, lookTarget)
                            end
                        end
                    elseif CurrentMode == "allfling" then
                        allFlingTimer = allFlingTimer + dt
                        
                        if tick() - allFlingBlacklistTime > 30 then
                            allFlingBlacklist = {}
                            allFlingBlacklistTime = tick()
                        end
                        
                        if allFlingTimer >= 3 then
                            allFlingBlacklist[activeTargetPlayer.Name] = true
                            allFlingTarget = nil
                            allFlingTimer = 0
                        else
                            local bav = myRoot:FindFirstChild("FlingSpin")
                            if not bav then
                                bav = Instance.new("BodyAngularVelocity")
                                bav.Name = "FlingSpin"
                                bav.AngularVelocity = Vector3.new(99999, 99999, 99999)
                                bav.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
                                bav.P = math.huge
                                bav.Parent = myRoot
                            end
                            
                            myRoot.CFrame = assignedRoot.CFrame
                        end
                    end
                else
                    local behindPos = (targetRoot.CFrame * CFrame.new(0, 0, 4 + altIndexOffset)).Position
                    myHumanoid.AutoRotate = true
                    myHumanoid.WalkSpeed = 16
                    myHumanoid:MoveTo(behindPos)
                end
            end

        elseif CurrentMode == "orbit" then
            local radius = 10
            local orbitSpeed = 1.75
            
            local inclination = MathCache.inclination
            local azimuth     = MathCache.azimuth
            
            local phaseOffset = MathCache.auraPhaseOffset
            local theta = tick() * orbitSpeed + phaseOffset
            
            local x = radius * math.cos(theta)
            local y = radius * math.sin(theta) * math.sin(inclination)
            local z = radius * math.sin(theta) * math.cos(inclination)
            
            local finalX = x * math.cos(azimuth) - z * math.sin(azimuth)
            local finalZ = x * math.sin(azimuth) + z * math.cos(azimuth)
            local finalY = y
            
            local targetPos = targetRoot.Position + Vector3.new(finalX, finalY, finalZ)
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            local faceCFrame = CFrame.lookAt(myRoot.Position, targetRoot.Position)
            if bg then
                 if (faceCFrame.LookVector - lastGyroTarget.LookVector).Magnitude > 0.05 then
                     bg.CFrame = faceCFrame
                     lastGyroTarget = faceCFrame
                 end
            else
                bg = Instance.new("BodyGyro")
                bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                bg.CFrame = faceCFrame
                bg.Parent = myRoot
                lastGyroTarget = faceCFrame
            end
            
            myRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "ufo" then
            
            local radius = (TotalAlts > 6) and 4 or 3
                local ring = 1
                local capacityInRing = (TotalAlts <= 8) and TotalAlts or 6
                local indexInRing = altIndexOffset - 1
                
                while indexInRing >= capacityInRing do
                    indexInRing = indexInRing - capacityInRing
                    ring = ring + 1
                    radius = radius + 3
                    capacityInRing = math.floor(radius * 2 * math.pi / 2.5)
                end
                
                local angle = (indexInRing / capacityInRing) * (math.pi * 2)
                local timeSec = tick()
                local spinSpeed = 1.5
                local currentAngle = angle + (timeSec * spinSpeed)
                
                local xOffset = math.cos(currentAngle) * radius
                local zOffset = math.sin(currentAngle) * radius
                local yOffset = -4.5
                
                local velocity = targetRoot.AssemblyLinearVelocity
                local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
                local forwardOffset = Vector3.zero
                if horizontalVel.Magnitude > 0.5 then
                    forwardOffset = horizontalVel * 0.41
                end
                
                local targetPos = targetRoot.Position + Vector3.new(xOffset, yOffset, zOffset) + forwardOffset
                
                local bp = myRoot:FindFirstChildOfClass("BodyPosition")
                if bp then
                    bp.Position = targetPos
                else
                    bp = Instance.new("BodyPosition")
                    bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                    bp.D = 2000
                    bp.P = 50000
                    bp.Position = targetPos
                    bp.Parent = myRoot
                end
                local dirOut = Vector3.new(xOffset, 0, zOffset)
                if dirOut.Magnitude < 0.01 then dirOut = Vector3.new(0, 0, -1) end
                dirOut = dirOut.Unit
                local layingCFrame = CFrame.lookAt(targetPos, targetPos - dirOut) * CFrame.Angles(math.rad(90), 0, 0)
                
                local bg = myRoot:FindFirstChildOfClass("BodyGyro")
                if bg then
                     if (layingCFrame.LookVector - lastGyroTarget.LookVector).Magnitude > 0.05 then
                         bg.CFrame = layingCFrame
                         lastGyroTarget = layingCFrame
                     end
                else
                    bg = Instance.new("BodyGyro")
                    bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                    bg.CFrame = layingCFrame
                    bg.Parent = myRoot
                    lastGyroTarget = layingCFrame
                end
                
                myHumanoid.PlatformStand = true

        elseif CurrentMode == "motorcycle" then
            local slotIndex = altIndexOffset
            if slotIndex > #MOTO_SLOTS then slotIndex = ((slotIndex - 1) % #MOTO_SLOTS) + 1 end
            local slot = MOTO_SLOTS[slotIndex]
            
            if slot then
                if myRoot.Anchored then
                    myRoot.Anchored = false
                end
                local antiGravity = myRoot:FindFirstChild("MotoAntiGravity")
                if not antiGravity then
                    antiGravity = Instance.new("BodyVelocity")
                    antiGravity.Name = "MotoAntiGravity"
                    antiGravity.MaxForce = Vector3.new(0, 1e6, 0)
                    antiGravity.Velocity = Vector3.zero 
                    antiGravity.P = 1250
                    antiGravity.Parent = myRoot
                end

                local rawCF = targetRoot.CFrame
                local lookDir = rawCF.LookVector
                local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
                local velocity = targetRoot.AssemblyLinearVelocity
                local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
                
                if antiGravity then
                    antiGravity.Velocity = horizontalVel
                end
                
                local forwardOffset = Vector3.zero
                if horizontalVel.Magnitude > 1 then
                    local predictFactor = 0.41
                    forwardOffset = horizontalVel * predictFactor
                end
                
                local predictedPos = rawCF.Position + forwardOffset
                
                local leaderCF
                if flatLook.Magnitude > 0.01 then
                    leaderCF = CFrame.lookAt(predictedPos, predictedPos + flatLook)
                else
                    leaderCF = CFrame.new(predictedPos)
                end
                
                local slotCF = leaderCF * CFrame.new(slot.x, slot.y, slot.z)
                local targetPos = slotCF.Position
                
                local bp = myRoot:FindFirstChildOfClass("BodyPosition")
                if bp then bp:Destroy() end
                local bg = myRoot:FindFirstChildOfClass("BodyGyro")
                if bg then bg:Destroy() end
                local bav = myRoot:FindFirstChild("WheelSpin")
                if bav then bav:Destroy() end
                
                if slot.type == "wheel" then
                    local wheelAngle = myRoot:GetAttribute("WheelAngle") or 0
                    local speed = horizontalVel.Magnitude
                    
                    if ActiveBurnout and slotIndex == 2 then
                        wheelAngle = wheelAngle - 50 * dt
                    elseif speed > 1 then
                        wheelAngle = wheelAngle - (speed / 2.5) * dt
                    end
                    myRoot:SetAttribute("WheelAngle", wheelAngle)
                    
                    local baseCF = CFrame.lookAt(slotCF.Position, slotCF.Position + leaderCF.LookVector)
                    myRoot.CFrame = baseCF * CFrame.Angles(wheelAngle, 0, 0)
                    
                    if not myRoot:GetAttribute("MotoCollOff") then
                        myRoot:SetAttribute("MotoCollOff", true)
                        for _, child in ipairs(myRoot.Parent:GetChildren()) do
                            if child:IsA("BasePart") then
                                child.CanCollide = false
                            elseif child:IsA("Accessory") then
                                local handle = child:FindFirstChild("Handle")
                                if handle and handle:IsA("BasePart") then handle.CanCollide = false end
                            end
                        end
                    end
                    
                elseif slot.type == "frame" then
                    myRoot.CFrame = CFrame.lookAt(targetPos, targetPos + leaderCF.LookVector) * CFrame.Angles(math.rad(slot.angle), 0, 0)
                    
                elseif slot.type == "engine" then
                    myRoot.CFrame = CFrame.lookAt(targetPos, targetPos + leaderCF.LookVector) * CFrame.Angles(math.rad(90), 0, 0)
                    
                elseif slot.type == "side_right" then
                    myRoot.CFrame = CFrame.lookAt(targetPos, targetPos + leaderCF.LookVector) * CFrame.Angles(0, 0, math.rad(90))
                    
                elseif slot.type == "side_left" then
                    myRoot.CFrame = CFrame.lookAt(targetPos, targetPos + leaderCF.LookVector) * CFrame.Angles(0, 0, math.rad(-90))
                end
            end
            
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "jumba" then
            local INNER_RADIUS = 5
            local OUTER_RADIUS = 8
            local JUMBA_SPEED = 2.0
            local INNER_Y = 0
            local OUTER_Y = 0
            
            local isInner = MathCache.isInner
            local phaseOffset = MathCache.jumbaPhaseOffset
            
            local currentAngle
            if isInner then
                currentAngle = phaseOffset - (tick() * JUMBA_SPEED)
            else
                currentAngle = phaseOffset + (tick() * JUMBA_SPEED)
            end
            
            local radius = isInner and INNER_RADIUS or OUTER_RADIUS
            local yOffset = isInner and INNER_Y or OUTER_Y
            
            local xOffset = math.cos(currentAngle) * radius
            local zOffset = math.sin(currentAngle) * radius
            
            local velocity = targetRoot.AssemblyLinearVelocity
            local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
            local forwardOffset = Vector3.zero
            if horizontalVel.Magnitude > 0.5 then
                forwardOffset = horizontalVel * 0.4
            end
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, yOffset, zOffset) + forwardOffset
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            local faceCFrame = CFrame.lookAt(myRoot.Position, lookTarget)
            
            if bg then
                 if (faceCFrame.LookVector - lastGyroTarget.LookVector).Magnitude > 0.05 then
                     bg.CFrame = faceCFrame
                     lastGyroTarget = faceCFrame
                 end
            else
                 bg = Instance.new("BodyGyro")
                 bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                 bg.CFrame = faceCFrame
                 bg.Parent = myRoot
                 lastGyroTarget = faceCFrame
            end
            
            myRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
            myHumanoid.PlatformStand = true

        elseif CurrentMode == "aura" then
            local MIN_RADIUS = 3
            local MAX_RADIUS = 12
            local BREATHE_SPEED = 1.0
            
            local phaseOffset = MathCache.auraPhaseOffset
            
            local sineWave = (math.sin(tick() * BREATHE_SPEED) + 1) / 2
            local radius = MIN_RADIUS + (sineWave * (MAX_RADIUS - MIN_RADIUS))
            
            local xOffset = math.cos(phaseOffset) * radius
            local zOffset = math.sin(phaseOffset) * radius
            
            local velocity = targetRoot.AssemblyLinearVelocity
            local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
            local forwardOffset = Vector3.zero
            if horizontalVel.Magnitude > 0.5 then
                forwardOffset = horizontalVel * 0.4
            end
            
            local targetPos = targetRoot.Position + Vector3.new(xOffset, 0, zOffset) + forwardOffset
            
            local bp = myRoot:FindFirstChildOfClass("BodyPosition")
            if bp then
                bp.Position = targetPos
            else
                bp = Instance.new("BodyPosition")
                bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                bp.D = 2000
                bp.P = 50000
                bp.Position = targetPos
                bp.Parent = myRoot
            end
            
            local lookTarget = Vector3.new(targetRoot.Position.X, myRoot.Position.Y, targetRoot.Position.Z)
            local bg = myRoot:FindFirstChildOfClass("BodyGyro")
            local faceCFrame = CFrame.lookAt(myRoot.Position, lookTarget)
            
            if bg then
                 if (faceCFrame.LookVector - lastGyroTarget.LookVector).Magnitude > 0.05 then
                     bg.CFrame = faceCFrame
                     lastGyroTarget = faceCFrame
                 end
            else
                 bg = Instance.new("BodyGyro")
                 bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
                 bg.CFrame = faceCFrame
                 bg.Parent = myRoot
                 lastGyroTarget = faceCFrame
            end
            
            myRoot.AssemblyLinearVelocity = targetRoot.AssemblyLinearVelocity
            myHumanoid.PlatformStand = true
            
        elseif CurrentMode == "controlled" then
            myHumanoid.WalkSpeed = 16
            myHumanoid.AutoRotate = false
            myHumanoid.PlatformStand = false
            myHumanoid:Move(ControlMoveDir, false)
            
            if ControlMoveDir.Magnitude > 0.01 then
                local targetLook = myRoot.Position + ControlMoveDir
                myRoot.CFrame = myRoot.CFrame:Lerp(CFrame.lookAt(myRoot.Position, targetLook), 0.4)
            end
        end
        
        if CurrentMode ~= "none" and CurrentMode ~= "elevator" and CurrentMode ~= "carpet" and CurrentMode ~= "ufo" and CurrentMode ~= "controlled" then
            if lastPos ~= Vector3.zero and (myRoot.Position - lastPos).Magnitude < 0.2 then
                local currentPos = myRoot.Position
                local distMoved = Vector3.new(currentPos.X - lastPos.X, 0, currentPos.Z - lastPos.Z).Magnitude
                local expectedMove = myHumanoid.WalkSpeed * dt * 0.2
                
                if distMoved < expectedMove then
                    stuckTimer = stuckTimer + dt
                    if stuckTimer > 0.25 then
                        myHumanoid.Jump = true
                        stuckTimer = 0
                    end
                else
                    stuckTimer = 0
                end
                lastPos = currentPos
            else
                stuckTimer = 0
                lastPos = myRoot.Position
            end
        end
    end))

elseif string.lower(LocalPlayer.Name) == string.lower(Config.MainAccount) then
    print("[Alt Controller] Main Account loaded.")
    local commandBarInput, toggleBar, hideBar = CreateCommandBar()
    
    local LastSentCommand = "none"

    local mechActive = false
    local MECH_ELEVATION = 8
    local MECH_SPEED = 16
    local mechMoveDir = Vector3.zero
    
    local nextStrikeAltIndex = 1
    
    local mechRayParams = RaycastParams.new()
    mechRayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local function RefreshMechRayFilter()
        local filterList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            if p.Character then
                table.insert(filterList, p.Character)
            end
        end
        mechRayParams.FilterDescendantsInstances = filterList
    end
    RefreshMechRayFilter()
    
    local function ActivateMechOnSelf()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root and hum then
            hum.PlatformStand = true
            RefreshMechRayFilter()
            
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            
            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bp.D = 2000
            bp.P = 50000
            bp.Position = root.Position + Vector3.new(0, MECH_ELEVATION, 0)
            bp.Parent = root
            
            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            bg.CFrame = root.CFrame
            bg.Parent = root
            
            mechActive = true
            print("[Alt Controller] Mech: Owner elevated.")
        end
    end
    
    local function DeactivateMechOnSelf()
        mechActive = false
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root then
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            root.Anchored = false
        end
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
            hum.AutoRotate = true
            if hum:GetState() == Enum.HumanoidStateType.PlatformStanding then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        print("[Alt Controller] Mech: Owner grounded.")
    end
    
    local lastRayFilterRefresh = 0
    
    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        if not mechActive then return end
        
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return end
        
        local bp = root:FindFirstChildOfClass("BodyPosition")
        local bg = root:FindFirstChildOfClass("BodyGyro")
        if not bp or not bg then return end
        
        if tick() - lastRayFilterRefresh > 1 then
            lastRayFilterRefresh = tick()
            RefreshMechRayFilter()
        end
        
        local moveDir = Vector3.zero
        if not commandBarInput:IsFocused() then
            local cam = workspace.CurrentCamera
            local camLook = cam.CFrame.LookVector
            local camRight = cam.CFrame.RightVector
            
            camLook = Vector3.new(camLook.X, 0, camLook.Z)
            if camLook.Magnitude > 0 then camLook = camLook.Unit end
            camRight = Vector3.new(camRight.X, 0, camRight.Z)
            if camRight.Magnitude > 0 then camRight = camRight.Unit end
            
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camLook end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camLook end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camRight end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camRight end
        end
        
        if moveDir.Magnitude > 0 then
            moveDir = moveDir.Unit
        end
        
        local rayOrigin = Vector3.new(bp.Position.X, bp.Position.Y + 20, bp.Position.Z)
        local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), mechRayParams)
        local groundY = rayResult and rayResult.Position.Y or 0
        
        local currentPos = bp.Position
        local newX = currentPos.X + (moveDir.X * MECH_SPEED * dt)
        local newZ = currentPos.Z + (moveDir.Z * MECH_SPEED * dt)
        local newY = groundY + MECH_ELEVATION
        
        bp.Position = Vector3.new(newX, newY, newZ)
        
        if moveDir.Magnitude > 0 then
            bg.CFrame = CFrame.lookAt(root.Position, root.Position + moveDir)
        end
        
        hum.PlatformStand = true
    end))
    
    local elevatorActive = false
    local carpetActive = false
    local ELEVATOR_RISE_SPEED = 3
    local CARPET_SPEED = 35
    local elevatorElevation = 0
    
    local function ActivateElevatorOnSelf(isCarpet)
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root and hum then
            hum.PlatformStand = true
            
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            
            elevatorElevation = 0
            
            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bp.D = 2000
            bp.P = 50000
            bp.Position = root.Position + (isCarpet and Vector3.new(0, 5, 0) or Vector3.new(0, 0, 0))
            bp.Parent = root
            
            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            bg.CFrame = root.CFrame
            bg.Parent = root
            
            if isCarpet then
                carpetActive = true
                print("[Alt Controller] Carpet: Flying mode engaged.")
            else
                elevatorActive = true
                print("[Alt Controller] Elevator: Rising!")
            end
        end
    end
    
    local function DeactivateElevatorOnSelf()
        elevatorActive = false
        carpetActive = false
        elevatorElevation = 0
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root then
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            root.Anchored = false
        end
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
            hum.AutoRotate = true
            hum:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
            if hum:GetState() == Enum.HumanoidStateType.PlatformStanding or hum.Sit then
                hum.Sit = false
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        print("[Alt Controller] Elevator/Carpet: Grounded.")
    end
    
    local motoActive = false
    local MOTO_SPEED = 40
    local MOTO_ACCEL = 30
    local MOTO_BRAKE = 50
    local MOTO_FRICTION = 12
    local MOTO_TURN_SPEED = 3
    local motoCurrentSpeed = 0
    local motoYaw = 0
    
    local function ActivateMotorcycleOnSelf()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root and hum then
            hum.PlatformStand = true
            hum.AutoRotate = false
            
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            
            local look = root.CFrame.LookVector
            motoYaw = math.atan2(-look.X, -look.Z)
            motoCurrentSpeed = 0
            
            local bp = Instance.new("BodyPosition")
            bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bp.D = 2000
            bp.P = 50000
            bp.Position = root.Position
            bp.Parent = root
            
            local bg = Instance.new("BodyGyro")
            bg.MaxTorque = Vector3.new(1e6, 1e6, 1e6)
            bg.CFrame = root.CFrame
            bg.Parent = root
            
            -- Apply standing lean pose to leader
            hum.PlatformStand = true
            
            motoActive = true
            RefreshMechRayFilter()
            print("[Alt Controller] Motorcycle: Riding mode engaged.")
        end
    end
    
    local function DeactivateMotorcycleOnSelf()
        motoActive = false
        motoCurrentSpeed = 0
        motoYaw = 0
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if root then
            for _, obj in ipairs(root:GetChildren()) do
                if obj:IsA("BodyPosition") or obj:IsA("BodyGyro") then obj:Destroy() end
            end
            root.Anchored = false
        end
        if hum then
            hum.PlatformStand = false
            hum.WalkSpeed = 16
            hum.AutoRotate = true
            if hum:GetState() == Enum.HumanoidStateType.PlatformStanding then
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
        end
        print("[Alt Controller] Motorcycle: Dismounted.")
    end
    
    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        if not elevatorActive and not carpetActive then return end
        
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return end
        
        local bp = root:FindFirstChildOfClass("BodyPosition")
        local bg = root:FindFirstChildOfClass("BodyGyro")
        if not bp or not bg then return end
        
        if elevatorActive then
            elevatorElevation = elevatorElevation + (ELEVATOR_RISE_SPEED * dt)
            
            if tick() - lastRayFilterRefresh > 1 then
                lastRayFilterRefresh = tick()
                RefreshMechRayFilter()
            end
            local rayOrigin = Vector3.new(root.Position.X, root.Position.Y + 20, root.Position.Z)
            local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), mechRayParams)
            local groundY = rayResult and rayResult.Position.Y or 0
            
            bp.Position = Vector3.new(root.Position.X, groundY + elevatorElevation + 3, root.Position.Z)
        
        elseif carpetActive then
            local moveDir = Vector3.zero
            local verticalDir = 0
            
            if not commandBarInput:IsFocused() then
                local cam = workspace.CurrentCamera
                local camLook = cam.CFrame.LookVector
                local camRight = cam.CFrame.RightVector
                
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camLook end
                if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camLook end
                if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camRight end
                if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camRight end
                
                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then verticalDir = verticalDir + 1 end
                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then verticalDir = verticalDir - 1 end
            end
            
            if moveDir.Magnitude > 0 then
                moveDir = moveDir.Unit
            end
            
            local currentPos = bp.Position
            local newPos = currentPos + (moveDir * CARPET_SPEED * dt) + Vector3.new(0, verticalDir * CARPET_SPEED * dt, 0)
            bp.Position = newPos
            
            if moveDir.Magnitude > 0 then
                local flatLook = Vector3.new(moveDir.X, 0, moveDir.Z)
                if flatLook.Magnitude > 0 then
                    bg.CFrame = CFrame.lookAt(root.Position, root.Position + flatLook)
                end
            end
        end
        
        hum.PlatformStand = true
    end))
    
    TrackConnection(RunService.Heartbeat:Connect(function(dt)
        if not motoActive then return end
        
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 then return end
        
        local bp = root:FindFirstChildOfClass("BodyPosition")
        local bg = root:FindFirstChildOfClass("BodyGyro")
        if not bp or not bg then return end
        
        local wKey = false
        local sKey = false
        local aKey = false
        local dKey = false
        
        if not commandBarInput:IsFocused() then
            wKey = UserInputService:IsKeyDown(Enum.KeyCode.W)
            sKey = UserInputService:IsKeyDown(Enum.KeyCode.S)
            aKey = UserInputService:IsKeyDown(Enum.KeyCode.A)
            dKey = UserInputService:IsKeyDown(Enum.KeyCode.D)
        end
        
        local isBurnout = wKey and sKey
        
        if isBurnout then
            motoCurrentSpeed = motoCurrentSpeed - MOTO_BRAKE * dt
            if motoCurrentSpeed < 0 then motoCurrentSpeed = 0 end
        elseif wKey then
            motoCurrentSpeed = motoCurrentSpeed + MOTO_ACCEL * dt
            if motoCurrentSpeed > MOTO_SPEED then motoCurrentSpeed = MOTO_SPEED end
        elseif sKey then
            motoCurrentSpeed = motoCurrentSpeed - MOTO_BRAKE * dt
            if motoCurrentSpeed < -MOTO_SPEED * 0.3 then motoCurrentSpeed = -MOTO_SPEED * 0.3 end
        else
            if motoCurrentSpeed > 0 then
                motoCurrentSpeed = motoCurrentSpeed - MOTO_FRICTION * dt
                if motoCurrentSpeed < 0 then motoCurrentSpeed = 0 end
            elseif motoCurrentSpeed < 0 then
                motoCurrentSpeed = motoCurrentSpeed + MOTO_FRICTION * dt
                if motoCurrentSpeed > 0 then motoCurrentSpeed = 0 end
            end
        end
        
        if math.abs(motoCurrentSpeed) > 1 then
            local turnFactor = math.clamp(math.abs(motoCurrentSpeed) / MOTO_SPEED, 0.3, 1)
            if aKey then motoYaw = motoYaw + MOTO_TURN_SPEED * turnFactor * dt end
            if dKey then motoYaw = motoYaw - MOTO_TURN_SPEED * turnFactor * dt end
        end
        
        local forwardDir = Vector3.new(-math.sin(motoYaw), 0, -math.cos(motoYaw))
        
        if tick() - lastRayFilterRefresh > 1 then
            lastRayFilterRefresh = tick()
            RefreshMechRayFilter()
        end
        local rayOrigin = Vector3.new(bp.Position.X, bp.Position.Y + 20, bp.Position.Z)
        local rayResult = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), mechRayParams)
        local groundY = rayResult and rayResult.Position.Y or 0
        
        local currentPos = bp.Position
        local newX = currentPos.X + (forwardDir.X * motoCurrentSpeed * dt)
        local newZ = currentPos.Z + (forwardDir.Z * motoCurrentSpeed * dt)
        local newY = groundY + 6
        
        bp.Position = Vector3.new(newX, newY, newZ)
        
        local lookTarget = Vector3.new(root.Position.X + forwardDir.X, root.Position.Y, root.Position.Z + forwardDir.Z)
        bg.CFrame = CFrame.lookAt(root.Position, lookTarget) * CFrame.Angles(math.rad(-10), 0, 0)
        
        hum.PlatformStand = true
    end))
    

    
    TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
        if mechActive then
            mechActive = false
            print("[Alt Controller] Mech: Respawned, mech deactivated.")
        end
        if elevatorActive or carpetActive then
            elevatorActive = false
            carpetActive = false
            elevatorElevation = 0
            print("[Alt Controller] Elevator/Carpet: Respawned, deactivated.")
        end
        if motoActive then
            motoActive = false
            motoCurrentSpeed = 0
            motoYaw = 0
            print("[Alt Controller] Motorcycle: Respawned, deactivated.")
        end
    end))
    
    local function ShowNotification(msg)
        print("[Alt Controller] " .. msg)
        local screenGui = commandBarInput.Parent and commandBarInput.Parent.Parent
        if not screenGui then return end
        
        local existing = screenGui:FindFirstChild("AltNotify")
        if existing then existing:Destroy() end
        
        local label = Instance.new("TextLabel")
        label.Name = "AltNotify"
        label.Size = UDim2.new(0, 400, 0, 30)
        label.Position = UDim2.new(0.5, -200, 1, -140)
        label.BackgroundTransparency = 0.3
        label.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
        label.TextColor3 = Color3.fromRGB(100, 255, 100)
        label.Font = Enum.Font.GothamMedium
        label.TextSize = 14
        label.Text = msg
        label.Parent = screenGui
        Instance.new("UICorner", label).CornerRadius = UDim.new(0, 6)
        
        task.delay(3, function()
            if label.Parent then label:Destroy() end
        end)
    end
    local function HandleMainCmd(cmdText)
        local cmdLower = string.lower(string.match(cmdText, "^%s*(.-)%s*$"))
        
        if string.sub(cmdLower, 1, 8) == "alt mech" or string.sub(cmdLower, 1, 7) == "altmech" then
            DeactivateElevatorOnSelf()
            DeactivateMotorcycleOnSelf()
            DeactivateMechOnSelf()
            local argStr = cmdLower:find("^alt mech") and string.match(string.sub(cmdLower, 9), "^%s*(.-)%s*$") or string.match(string.sub(cmdLower, 8), "^%s*(.-)%s*$")
            if argStr and argStr ~= "" then
                ShowNotification("Alt Mech: Formation following " .. argStr)
            else
                ShowNotification("Alt Mech: Formation following behind you.")
            end
            return false
        end
        
        
        if string.sub(cmdLower, 1, 4) == "mech" then
            DeactivateElevatorOnSelf()
            DeactivateMotorcycleOnSelf()
            if cmdLower ~= "mech p" then
                ActivateMechOnSelf()
            else
                DeactivateMechOnSelf()
                ShowNotification("Mech Passive: Alts forming around you.")
            end
            return false
        end
        
        if cmdLower == "elevator" then
            DeactivateMechOnSelf()
            DeactivateMotorcycleOnSelf()
            ActivateElevatorOnSelf(false)
            return false
        end
        
        if cmdLower == "carpet" or cmdLower == "aladdin" then
            DeactivateMechOnSelf()
            DeactivateMotorcycleOnSelf()
            ActivateElevatorOnSelf(true)
            return false
        end

        if cmdLower == "ufo" then
            DeactivateMechOnSelf()
            DeactivateMotorcycleOnSelf()
            ActivateElevatorOnSelf(true)
            CurrentMode = "ufo"
            return false
        end
        
        if string.sub(cmdLower, 1, 10) == "motorcycle" or string.sub(cmdLower, 1, 4) == "bike" then
            DeactivateMechOnSelf()
            DeactivateElevatorOnSelf()
            ActivateMotorcycleOnSelf()
            ShowNotification("Motorcycle: WASD to drive, W+S for burnout")
            return false
        end
        
        if cmdLower == "stop" then
            DeactivateMechOnSelf()
            DeactivateElevatorOnSelf()
            DeactivateMotorcycleOnSelf()
            -- Do not return true here, because we WANT the command to fall through and broadcast "stop" to the alts
        end
        
        if string.sub(cmdLower, 1, 9) == "moto goto" or string.sub(cmdLower, 1, 9) == "bike goto" then
            local targetName = string.match(string.sub(cmdLower, 10), "^%s*(.-)%s*$")
            if targetName and targetName ~= "" then
                BroadcastCmdInvisible("moto_goto " .. targetName)
                ShowNotification("Motorcycle: Sent go-to command for " .. targetName)
                return true
            end
        end
        
        return false
    end
    
    TrackConnection(commandBarInput.FocusLost:Connect(function(enterPressed)
        local cmd = commandBarInput.Text
        hideBar()
        
        if enterPressed and cmd ~= "" then
            task.spawn(function()
                if not HandleMainCmd(cmd) then
                    BroadcastCmdInvisible(cmd)
                    LastSentCommand = string.split(string.lower(string.match(cmd, "^%s*(.-)%s*$")), " ")[1]
                end
            end)
        end
    end))

    local wHeld = false
    local sHeld = false
    local burnoutSent = false

    TrackConnection(UserInputService.InputBegan:Connect(function(input, gameProcessed)
        if gameProcessed then return end
        if input.KeyCode == Enum.KeyCode.W then wHeld = true end
        if input.KeyCode == Enum.KeyCode.S then sHeld = true end
        
        if wHeld and sHeld and not burnoutSent then
            burnoutSent = true
            BroadcastCmdInvisible("moto_burnout true")
        end
    end))

    TrackConnection(UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.W then wHeld = false end
        if input.KeyCode == Enum.KeyCode.S then sHeld = false end
        
        if burnoutSent and (not wHeld or not sHeld) then
            burnoutSent = false
            BroadcastCmdInvisible("moto_burnout false")
        end
    end))

    local lastPlayerSync = 0
    TrackConnection(RunService.Heartbeat:Connect(function()
        if tick() - lastPlayerSync > 5 then
            lastPlayerSync = tick()
            local syncData = {}
            for _, p in ipairs(Players:GetPlayers()) do
                table.insert(syncData, p.Name .. ":" .. p.DisplayName)
            end
            local syncMsg = "SYNC_PLAYERS|" .. table.concat(syncData, ",")
            task.spawn(function()
                pcall(function()
                    BroadcastCmdInvisible(syncMsg)
                end)
            end)
        end
    end))

    if WS_CONN then
        TrackConnection(WS_CONN.OnMessage:Connect(function(message)
            local cmdText = message
            if string.sub(message, 1, 7) == "SERVER|" then
                cmdText = string.sub(message, 8)
            elseif string.sub(message, 1, 6) == "RELAY|" then
                local relayContent = string.sub(message, 7)
                local sender, cmd = string.match(relayContent, "^([^|]+)|(.*)$")
                if sender and IsAuthorized(sender) then
                    cmdText = cmd
                else
                    return -- Ignore unauthorized relays
                end
            end

            local cmdLower = string.lower(string.match(cmdText, "^%s*(.-)%s*$"))
            if not string.find(cmdLower, "sync_players") then 
                task.spawn(function()
                    HandleMainCmd(cmdText)
                end)
            end
        end))
        
        TrackConnection(WS_CONN.OnClose:Connect(function()
            warn("[Alt Controller] WebSocket connection closed on main account.")
        end))
    end

else
    warn("[Alt Controller] Account (" .. LocalPlayer.Name .. ") not in config. Script dormant.")
end

local function OnChatRelay(sender, message)
    if IsAuthorized(sender.Name) then
        if string.sub(message, 1, #Config.Prefix) == Config.Prefix then
            local cmd = string.sub(message, #Config.Prefix + 1)
            ProcessCommand(cmd, sender.Name)
        end
    end
end

for _, p in ipairs(Players:GetPlayers()) do
    TrackConnection(p.Chatted:Connect(function(msg) OnChatRelay(p, msg) end))
end
TrackConnection(Players.PlayerAdded:Connect(function(p)
    TrackConnection(p.Chatted:Connect(function(msg) OnChatRelay(p, msg) end))
end))

local VirtualUser = game:GetService("VirtualUser")
TrackConnection(LocalPlayer.Idled:Connect(function()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
    print("[Alt Controller] Anti-AFK triggered.")
end))