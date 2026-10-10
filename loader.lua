-- Arriva Core Hub V1.4.5 - maintenance revision of the supplied hub.
-- Packet/Line Lag flooders removed. Gameplay features retain their original scope.
local Hub = {alive = true, connections = {}, threads = {}, cleanups = {}, ready = false}
Hub.env = (getgenv and getgenv()) or shared
if Hub.env.ArrivaCoreMaintenance then
    pcall(Hub.env.ArrivaCoreMaintenance)
end
Hub.instances = setmetatable({}, {__mode = "k"})
Hub.assetTargets = setmetatable({}, {__mode = "k"})
function Hub.new(class, parent)
    local instance = Instance.new(class)
    Hub.instances[instance] = true
    if parent then Hub.assetTargets[instance] = parent end
    if parent then instance.Parent = parent end
    return instance
end
Hub.propertyBackup = {}
function Hub.backup(instance, properties)
    local saved = Hub.propertyBackup[instance]
    if not saved then saved = {}; Hub.propertyBackup[instance] = saved end
    for _, property in ipairs(properties) do
        if saved[property] == nil then saved[property] = instance[property] end
    end
end
function Hub.restore(instance)
    local saved = Hub.propertyBackup[instance]
    if not saved then return end
    for property, value in pairs(saved) do pcall(function() instance[property] = value end) end
    Hub.propertyBackup[instance] = nil
end
Hub.nativeTask = task
local task = setmetatable({}, {__index = Hub.nativeTask})
function Hub.schedule(method, delay, callback, ...)
    if not Hub.alive then return nil end
    local args = table.pack(...)
    local thread = coroutine.create(function()
        local ok, err = xpcall(function() callback(table.unpack(args, 1, args.n)) end, debug.traceback)
        Hub.threads[coroutine.running()] = nil
        if not ok and Hub.alive then warn("[Arriva] " .. tostring(err)) end
    end)
    Hub.threads[thread] = true
    if method == "delay" then Hub.nativeTask.delay(delay, thread)
    else Hub.nativeTask[method](thread) end
    return thread
end
function task.spawn(callback, ...) return Hub.schedule("spawn", nil, callback, ...) end
function task.defer(callback, ...) return Hub.schedule("defer", nil, callback, ...) end
function task.delay(delay, callback, ...) return Hub.schedule("delay", delay, callback, ...) end
function Hub.connect(signal, callback)
    local connection = signal:Connect(function(...)
        if not Hub.alive then return end
        local args = table.pack(...)
        local thread = coroutine.running()
        Hub.threads[thread] = true
        local ok, err = xpcall(function() callback(table.unpack(args, 1, args.n)) end, debug.traceback)
        Hub.threads[thread] = nil
        if not ok and Hub.alive then warn("[Arriva callback] " .. tostring(err)) end
    end)
    Hub.connections[connection] = true
    return connection
end
function Hub.cleanup(callback) table.insert(Hub.cleanups, callback) end
function Hub.stop()
    if not Hub.alive then return end
    if Hub.ready and Hub.storage and Hub.saveManager then Hub.persistSettings() end
    Hub.alive = false
    for connection in pairs(Hub.connections) do pcall(function() connection:Disconnect() end) end
    for thread in pairs(Hub.threads) do
        if thread ~= coroutine.running() then pcall(Hub.nativeTask.cancel, thread) end
    end
    for i = #Hub.cleanups, 1, -1 do pcall(Hub.cleanups[i]) end
    for instance in pairs(Hub.propertyBackup) do Hub.restore(instance) end
    for instance in pairs(Hub.instances) do pcall(function() instance:Destroy() end) end
    _G.AntiInputLag = false; _G.ShurikenAntiKick = false
    table.clear(Hub.connections); table.clear(Hub.threads)
    if Hub.env.ArrivaCoreMaintenance == Hub.unload then Hub.env.ArrivaCoreMaintenance = nil end
end
function Hub.fetch(url)
    local ok, value = pcall(function()
        local fn, err = loadstring(game:HttpGet(url))
        assert(fn, err)
        return fn()
    end)
    assert(ok, "[Arriva dependency] " .. url .. ": " .. tostring(value))
    return value
end
-- SETTINGS PERSISTENCE CORE
function Hub.canonical(value)
    local kind = type(value)
    if kind == "table" then
        local entries = {}
        for key, item in pairs(value) do
            table.insert(entries, Hub.canonical(key) .. Hub.canonical(item))
        end
        table.sort(entries)
        return "T" .. table.concat(entries, "|") .. ";"
    end
    local text = tostring(value)
    return kind:sub(1, 1) .. #text .. ":" .. text
end
function Hub.captureSettings()
    if not Hub.saveManager then return nil, "Save manager is unavailable" end
    local ok, content, success, err = pcall(function() return Hub.saveManager:SaveJSON("AutoSave") end)
    if not ok then return nil, tostring(content) end
    if not success then return nil, tostring(err) end
    local decoded, data = pcall(function() return game:GetService("HttpService"):JSONDecode(content) end)
    if not decoded then return nil, tostring(data) end
    data.timestamp = nil -- A clock change is not a settings change.
    if type(data.objects) == "table" then
        table.sort(data.objects, function(a, b)
            return tostring(a.tabIdx or "") .. ":" .. tostring(a.idx) < tostring(b.tabIdx or "") .. ":" .. tostring(b.idx)
        end)
    end
    return Hub.canonical(data)
end
function Hub.persistSettings()
    if not Hub.storage or not Hub.saveManager then
        Hub.lastSaveError = "File storage is unavailable"
        return false, Hub.lastSaveError
    end
    local ok, success, err = pcall(function() return Hub.saveManager:Save("AutoSave") end)
    if not ok or not success then
        Hub.lastSaveError = tostring(ok and err or success)
        return false, Hub.lastSaveError
    end
    Hub.lastSaveError = nil
    Hub.lastSaveAt = os.date("%H:%M:%S")
    Hub.lastSettings = Hub.captureSettings()
    return true
end
function Hub.pollSettings()
    if not Hub.ready or not Hub.storage then return end
    local fingerprint, err = Hub.captureSettings()
    if not fingerprint then
        if Hub.lastSnapshotError ~= err then warn("[Arriva settings] " .. tostring(err)) end
        Hub.lastSnapshotError = err
        return
    end
    Hub.lastSnapshotError = nil
    if fingerprint ~= Hub.lastSettings then
        Hub.lastSettings = fingerprint
        Hub.requestSave()
    end
end
function Hub.requestSave()
    if not Hub.ready or not Hub.storage then return end
    if Hub.saveThread then pcall(Hub.nativeTask.cancel, Hub.saveThread); Hub.threads[Hub.saveThread] = nil end
    Hub.saveThread = task.delay(1, function()
        Hub.saveThread = nil
        local ok, err = Hub.persistSettings()
        if not ok then warn("[Arriva autosave] " .. tostring(err)) end
    end)
end
function Hub.installConfigLoading(saveManager)
    local original = saveManager.LoadJSON
    saveManager:SetLoadingOrder(false)
    saveManager.LoadJSON = function(self, content)
        local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(content) end)
        if not ok or type(data) ~= "table" or type(data.objects) ~= "table" then
            return original(self, content)
        end
        local function rank(option)
            if option.idx == "ThemeManager_ThemeList" then return 0 end
            if option.idx == "ThemeManager_CustomThemeList" then return 1 end
            if option.type == "Dropdown" then return 10 end
            if option.type == "Slider" or option.type == "Input" or option.type == "KeyPicker" then return 20 end
            if option.type == "ColorPicker" then return 30 end
            if option.idx == "WhitelistFriends" then return 35 end
            if option.type == "Toggle" then return 40 end
            return 25
        end
        table.sort(data.objects, function(a, b)
            local ar, br = rank(a), rank(b)
            if ar ~= br then return ar < br end
            return tostring(a.idx) < tostring(b.idx)
        end)
        local encoded, result = pcall(function() return game:GetService("HttpService"):JSONEncode(data) end)
        if not encoded then return false, tostring(result) end
        return original(self, result)
    end
end
-- END SETTINGS PERSISTENCE CORE

--=====================================================
-- ARRIVA CORE HUB – OWNER COMMAND CORE (ALWAYS FIRST)
--=====================================================

--// Services
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Workspace = workspace

--// Player
local LocalPlayer = Players.LocalPlayer
local character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
Hub.characterGeneration = 0
Hub.connect(LocalPlayer.CharacterRemoving, function(oldCharacter)
    Hub.characterGeneration += 1
    if character == oldCharacter then character = nil end
end)
Hub.connect(LocalPlayer.CharacterAdded, function(newCharacter)
    Hub.characterGeneration += 1
    character = newCharacter
end)

-- SAFETY WHITELIST CORE (separate from the hub access whitelist)
Hub.manualWhitelist = {}
Hub.friendCache = {}
Hub.friendChecks = {}
Hub.characterOwners = setmetatable({}, {__mode = "k"})
Hub.playerNames = {}
function Hub.trackPlayerOwnership(player)
    Hub.playerNames[player.Name] = player
    if player.Character then Hub.characterOwners[player.Character] = player end
    Hub.connect(player.CharacterAdded, function(char) Hub.characterOwners[char] = player end)
end
for _, player in ipairs(Players:GetPlayers()) do Hub.trackPlayerOwnership(player) end
Hub.whitelistFriends = true
Hub.safetyPath = "ArrivaCoreHub/SafetyWhitelist.json"
function Hub.readSafety()
    if not isfile or not readfile then return end
    if not isfile(Hub.safetyPath) then
        -- Migrate the old username labels before SaveManager can reject renamed dropdown values.
        local legacy = "ArrivaCoreHub/Configs/settings/AutoSave.json"
        if not isfile(legacy) then return end
        local ok, data = pcall(function() return game:GetService("HttpService"):JSONDecode(readfile(legacy)) end)
        if ok and type(data) == "table" and type(data.objects) == "table" then
            for _, option in ipairs(data.objects) do
                if option.idx == "MultiWhitelist" and type(option.value) == "table" then
                    for label, selected in pairs(option.value) do
                        if selected and type(label) == "string" then
                            local id = label:match("%[(%d+)%]$")
                            local name = label:match("%(@?([^()]*)%)$")
                            local player = name and Players:FindFirstChild(name)
                            if not id and player then id = tostring(player.UserId) end
                            if id then Hub.manualWhitelist[id] = label
                            elseif name then Hub.manualWhitelist["name:" .. name:lower()] = label end
                        end
                    end
                end
            end
        end
        return
    end
    local ok, data = pcall(function()
        return game:GetService("HttpService"):JSONDecode(readfile(Hub.safetyPath))
    end)
    if ok and type(data) == "table" and type(data.manual) == "table" then
        Hub.manualWhitelist = {}
        for id, label in pairs(data.manual) do
            if type(id) == "string" and type(label) == "string" then Hub.manualWhitelist[id] = label end
        end
    elseif not ok then warn("[Arriva whitelist] Could not read saved whitelist: " .. tostring(data)) end
end
Hub.readSafety()
function Hub.saveSafety()
    if not writefile or not makefolder or not isfolder then return end
    local ok, err = pcall(function()
        if not isfolder("ArrivaCoreHub") then makefolder("ArrivaCoreHub") end
        writefile(Hub.safetyPath, game:GetService("HttpService"):JSONEncode({manual = Hub.manualWhitelist}))
    end)
    if not ok then warn("[Arriva whitelist] Could not save whitelist: " .. tostring(err)) end
end
function Hub.queueSafetySave()
    if Hub.safetySaveThread then pcall(Hub.nativeTask.cancel, Hub.safetySaveThread); Hub.threads[Hub.safetySaveThread] = nil end
    Hub.safetySaveThread = task.delay(0.5, function() Hub.safetySaveThread = nil; Hub.saveSafety() end)
end
function Hub.checkFriend(player)
    if not player or player == LocalPlayer or Hub.friendChecks[player.UserId] then return end
    local userId = player.UserId
    Hub.friendChecks[userId] = true
    task.spawn(function()
        local ok, result = pcall(function() return LocalPlayer:IsFriendsWithAsync(userId) end)
        Hub.friendCache[userId] = {friend = ok and result == true, failed = not ok, expires = os.clock() + (ok and 60 or 15)}
        Hub.friendChecks[userId] = nil
        if Hub.reconcileProtection then Hub.reconcileProtection() end
        if not ok then warn("[Arriva whitelist] Friend lookup failed; target stays protected: " .. tostring(result)) end
    end)
end
function Hub.isProtected(player)
    if not player then return false end
    if player == LocalPlayer then return true end
    if Hub.manualWhitelist[tostring(player.UserId)] or Hub.manualWhitelist["name:" .. player.Name:lower()] then return true end
    if not Hub.whitelistFriends then return false end
    local state = Hub.friendCache[player.UserId]
    if not state or state.expires <= os.clock() then
        Hub.checkFriend(player)
        state = Hub.friendCache[player.UserId]
    end
    -- Do not guess that someone is a nonfriend during a pending or failed lookup.
    if Hub.friendChecks[player.UserId] or not state or state.failed then return true end
    return state.friend
end
function Hub.canHarm(player)
    return player ~= nil and player ~= LocalPlayer and player.Parent ~= nil and not Hub.isProtected(player)
end
function Hub.playerOf(instance)
    if typeof(instance) ~= "Instance" then return nil end
    if instance:IsA("Player") then return instance end
    local current = instance
    while current do
        if current.Name == "GrabParts" and current:IsA("Model") then
            local grab = current:FindFirstChild("GrabPart")
            local weld = grab and grab:FindFirstChild("WeldConstraint")
            if weld and weld.Part1 and not weld.Part1:IsDescendantOf(current) then
                local attachedPlayer = Hub.playerOf(weld.Part1)
                if attachedPlayer then return attachedPlayer end
            end
        end
        if current:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(current) or Hub.characterOwners[current]
            if player then return player end
        end
        if current.Parent == Workspace then
            local name = current.Name:match("^(.-)SpawnedInToys$")
            if name then return Players:FindFirstChild(name) or Hub.playerNames[name] end
        end
        current = current.Parent
    end
    -- GrabParts is outside the character, but its weld identifies the affected player.
    local grab = instance.Name == "GrabParts" and instance:FindFirstChild("GrabPart")
    local weld = grab and grab:FindFirstChild("WeldConstraint")
    if weld and weld.Part1 and not weld.Part1:IsDescendantOf(instance) then return Hub.playerOf(weld.Part1) end
    return nil
end
function Hub.canAffect(instance)
    -- A drop remote can receive only a weld in our toy; inspect its attached character too.
    if typeof(instance) == "Instance" and (instance:IsA("Weld") or instance:IsA("WeldConstraint")) then
        if instance.Part0 and not Hub.canAffect(instance.Part0) then return false end
        if instance.Part1 and not Hub.canAffect(instance.Part1) then return false end
    end
    local owner = Hub.playerOf(instance)
    return not owner or owner == LocalPlayer or Hub.canHarm(owner)
end
function Hub.reconcileProtection()
    for asset, target in pairs(Hub.assetTargets) do
        if asset:IsA("BodyMover") or asset:IsA("BodyVelocity") or asset:IsA("BodyAngularVelocity") or asset:IsA("BodyGyro") then
            if not Hub.canAffect(target) then pcall(function() asset:Destroy() end) end
        end
    end
    for instance in pairs(Hub.propertyBackup) do
        if not Hub.canAffect(instance) then Hub.restore(instance) end
    end
end
function Hub.remoteAllowed(remote, ...)
    if not remote or not Hub.canAffect(remote) then return false end
    for index = 1, select("#", ...) do
        if not Hub.canAffect(select(index, ...)) then return false end
    end
    return true
end
function Hub.fire(remote, ...)
    if Hub.remoteAllowed(remote, ...) then remote:FireServer(...) end
end
function Hub.invoke(remote, ...)
    if Hub.remoteAllowed(remote, ...) then return remote:InvokeServer(...) end
    return nil
end
Hub.cleanup(function() if Hub.safetySaveThread then Hub.saveSafety() end end)
Hub.connect(Players.PlayerAdded, function(player)
    Hub.trackPlayerOwnership(player)
    if Hub.whitelistFriends then Hub.checkFriend(player) end
    if Hub.refreshWhitelistUI then task.defer(Hub.refreshWhitelistUI) end
end)
Hub.connect(Players.PlayerRemoving, function()
    if Hub.refreshWhitelistUI then task.defer(Hub.refreshWhitelistUI) end
end)
-- END SAFETY WHITELIST CORE

--// Owner
local HUB_OWNER_ID = 1325117607

--// Whitelist
local WHITELIST = {
	[1325117607] = "arrivabus415",
	[115211703] = "00FSwedish",
	[9225934804] = "imagine2v1_L",
	[9224990669] = "EZTCU4",
	[9742385779] = "j_91auratuffboi13",
	[9016653597] = "Lotokoto777",
	[4163542745] = "Auri_lubieplacki22",
	[1310436801] = "Danielrbl21",
	[9668498177] = "ezzz_FO",
	[1187171573] = "XxkubaxX1075",
	[3892170520] = "VulgoMenta",
	[10081518368] = "ThriIl3Rz",
	[2312155753] = "ellojaydin",
}

--// Whitelist check
if WHITELIST[LocalPlayer.UserId] == nil then
	LocalPlayer:Kick("Nah not today bruh. find ur own shit to use.")
	return
end

--// Debounce for sysMsg to prevent spam
local lastMessages = {}
local DEBOUNCE_TIME = 0.5

local function sysMsg(text)
	-- Check if this exact message was sent recently
	local now = tick()
	if lastMessages[text] and (now - lastMessages[text]) < DEBOUNCE_TIME then
		return -- Ignore duplicate
	end
	lastMessages[text] = now

	pcall(function()
		local chatVersion = TextChatService.ChatVersion

		if chatVersion == Enum.ChatVersion.TextChatService then
			local channels = TextChatService:FindFirstChild("TextChannels")
			if channels then
				local generalChannel = channels:FindFirstChild("RBXGeneral")
				if generalChannel and generalChannel:IsA("TextChannel") then
					generalChannel:SendAsync(text)
				end
			end
		end
	end)
end

--// Get all whitelisted players currently in-game
--// Get all players currently in-game
local function getAllPlayers()
	return Players:GetPlayers()
end

--// Enhanced player finder
local function findTarget(targetStr)
	if not targetStr then return nil end

	targetStr = targetStr:lower()

	-- "me" = LocalPlayer
	if targetStr == "me" then
		return {LocalPlayer}
	end

	-- "all" = all players
	if targetStr == "all" then
		return getAllPlayers()
	end

	-- Partial match (username or display name)
	local matches = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Name:lower():find(targetStr, 1, true) or plr.DisplayName:lower():find(targetStr, 1, true) then
			table.insert(matches, plr)
		end
	end

	return #matches > 0 and matches or nil
end

--// Actions
local function bringSelfToOwner()
	local owner = Players:GetPlayerByUserId(HUB_OWNER_ID)
	if not owner or not owner.Character then return end

	local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	local ownerRoot = owner.Character:FindFirstChild("HumanoidRootPart")

	if myRoot and ownerRoot then
		myRoot.CFrame = ownerRoot.CFrame * CFrame.new(0, 5, 0)
		sysMsg("Brought to hub owner")
	end
end

local function revealSelf()
	sysMsg("I'm using Arriva Core Hub V1.4!")
end

local function killSelf()
	local char = LocalPlayer.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.Health = 0
			sysMsg("You were killed by hub owner")
		end
	end
end

local function kickSelf()
	sysMsg("You were removed by hub owner")
	task.wait(0.5)
	LocalPlayer:Kick("Removed by hub owner")
end

--// Command handler
local function processCommand(speaker, text)
	if speaker.UserId ~= HUB_OWNER_ID then return end

	-- Only process messages that start with ":" to prevent loops
	if not text:match("^:") then
		return
	end

	local args = text:split(" ")
	local cmd = args[1] and args[1]:lower()

	if cmd == ":bring" then
		local targetStr = args[2]
		local targets = findTarget(targetStr)

		if targets then
			for _, target in ipairs(targets) do
				if target == LocalPlayer then
					bringSelfToOwner()
					break
				end
			end
		end

	elseif cmd == ":reveal" then
		local targetStr = args[2]
		local targets = findTarget(targetStr)

		if targets then
			for _, target in ipairs(targets) do
				if target == LocalPlayer then
					revealSelf()
					break
				end
			end
		end

	elseif cmd == ":kill" then
		local targetStr = args[2]
		local targets = findTarget(targetStr)

		if targets then
			for _, target in ipairs(targets) do
				if target == LocalPlayer then
					killSelf()
					break
				end
			end
		end

	elseif cmd == ":kick" then
		local targetStr = args[2]
		local targets = findTarget(targetStr)

		if targets then
			for _, target in ipairs(targets) do
				if target == LocalPlayer then
					kickSelf()
					break
				end
			end
		end

	elseif cmd == ":announce" then
		local msg = table.concat(args, " ", 2)
		if msg ~= "" then
			sysMsg("[Hub Owner] " .. msg)
		end
	end
end

-- Owner commands: subscribe without replacing the game's chat formatting callback.
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
    Hub.connect(TextChatService.MessageReceived, function(message)
        local speaker = message.TextSource and Players:GetPlayerByUserId(message.TextSource.UserId)
        if speaker then processCommand(speaker, message.Text) end
    end)
else
    local function hookPlayer(plr)
        Hub.connect(plr.Chatted, function(msg) processCommand(plr, msg) end)
    end
    for _, player in ipairs(Players:GetPlayers()) do hookPlayer(player) end
    Hub.connect(Players.PlayerAdded, hookPlayer)
end

print("Arriva Core Hub owner command core loaded")
--=====================================================

-- Main script continues
-- Infinite Yield is available from a manual button below; not auto-loaded.

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = Hub.fetch(repo .. "Library.lua")
local ThemeManager = Hub.fetch(repo .. "addons/ThemeManager.lua")
local SaveManager = Hub.fetch(repo .. "addons/SaveManager.lua")

Hub.library = Library
Hub.connect(RunService.Heartbeat, function()
    -- Snapshot SaveManager's complete supported schema, including keybinds, themes and UI state.
    if not Hub.ready then return end
    local now = os.clock()
    if now < (Hub.nextSettingsCheck or 0) then return end
    Hub.nextSettingsCheck = now + 0.5
    for connection in pairs(Hub.connections) do if not connection.Connected then Hub.connections[connection] = nil end end
    Hub.pollSettings()
end)

Hub.unload = function() Library:Unload() end
Hub.env.ArrivaCoreMaintenance = Hub.unload
Library:OnUnload(Hub.stop)
Hub.saveManager = SaveManager
local Options = Library.Options
local Toggles = Library.Toggles
Library.ForceCheckbox = false

local Window = Library:CreateWindow({
	Title = "Arriva Core Hub V1.4.5",
	Footer = "Made by Arriva",
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Defense = Window:AddTab("Defense", "shield"),
	Target = Window:AddTab("Loop Players", "crosshair"),
	Aura = Window:AddTab("Auras", "align-vertical-space-around"),
	Grab = Window:AddTab("Grab Settings", "hand"),
	Player = Window:AddTab("Player Options", "user"),
	Misc = Window:AddTab("Misc", "box"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

--// Core Variables
local Player = LocalPlayer -- Consistent naming
local Camera = Workspace.CurrentCamera
local CE = ReplicatedStorage:WaitForChild("CharacterEvents", 10)
local grabEventsFolder = ReplicatedStorage:WaitForChild("GrabEvents", 10)
if not CE or not grabEventsFolder then
    Library:Notify({Title = "Unsupported game", Description = "CharacterEvents / GrabEvents did not load within 10 seconds.", Time = 8})
    Library:Unload()
    return
end
local BeingHeld = Player:FindFirstChild("IsHeld")
local StruggleEvent = CE:FindFirstChild("Struggle")
local characterEventsFolder = CE
local createGrabLineEvent = grabEventsFolder:FindFirstChild("CreateGrabLine")
local destroyGrabLineEvent = grabEventsFolder:FindFirstChild("DestroyGrabLine")
local setNetworkOwnerEvent = grabEventsFolder:FindFirstChild("SetNetworkOwner")
local extendGrabLineRemoteEvent = grabEventsFolder:FindFirstChild("ExtendGrabLine")
local ragdollRemoteEvent = CE:FindFirstChild("RagdollRemote")
local playerScriptsFolder = Player:WaitForChild("PlayerScripts", 10)
-- Anti Lag resolves and watches CharacterAndBeamMove when enabled; no cached startup reference.
local spawnedInToysFolder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
Hub.connect(Workspace.ChildAdded, function(child)
    if child.Name == Player.Name .. "SpawnedInToys" then spawnedInToysFolder = child end
end)
Hub.cameraOriginal = {mode = Player.CameraMode, min = Player.CameraMinZoomDistance, max = Player.CameraMaxZoomDistance}
Hub.cameraFOV = setmetatable({}, {__mode = "k"})
Hub.connect(Workspace:GetPropertyChangedSignal("CurrentCamera"), function()
    Camera = Workspace.CurrentCamera
    if Camera and Options.FOVSlider then
        Hub.cameraFOV[Camera] = Camera.FieldOfView
        Camera.FieldOfView = Options.FOVSlider.Value
    end
end)
Hub.cleanup(function()
    Player.CameraMaxZoomDistance = math.max(Player.CameraMaxZoomDistance, Hub.cameraOriginal.max)
    Player.CameraMinZoomDistance = Hub.cameraOriginal.min
    Player.CameraMaxZoomDistance = Hub.cameraOriginal.max
    Player.CameraMode = Hub.cameraOriginal.mode
    for cam, value in pairs(Hub.cameraFOV) do pcall(function() cam.FieldOfView = value end) end
end)

-- Helper Functions
local function notify(title, content, duration)
	Library:Notify({
		Title = title or "Notification",
		Description = content or "",
		Time = duration or 5,
	})
end

local function sendHubLoadedMessage()
	local message = "Arriva Core Hub V1.4 Loaded..."
	local sent = false
	pcall(function()
		local chatVersion = TextChatService.ChatVersion
		if chatVersion == Enum.ChatVersion.TextChatService then
			local channels = TextChatService:FindFirstChild("TextChannels")
			if channels then
				local generalChannel = channels:FindFirstChild("RBXGeneral")
				if generalChannel and generalChannel:IsA("TextChannel") then
					generalChannel:SendAsync(message)
					sent = true
				end
			end
		end
	end)

	if not sent then
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = message;
				Color = Color3.fromRGB(255, 170, 0);
				Font = Enum.Font.SourceSansBold;
				FontSize = Enum.FontSize.Size18;
			})
		end)
	end
end

-- Paint Parts Management
local paintPartsBackup = {}
local paintConnections = {}
local function hidePaint(obj)
    if not obj:IsA("BasePart") or obj.Name ~= "PaintPlayerPart" then return end
    if not paintPartsBackup[obj] then
        paintPartsBackup[obj] = {Transparency = obj.Transparency, CanTouch = obj.CanTouch, CanQuery = obj.CanQuery}
    end
    obj.Transparency = 1; obj.CanTouch = false; obj.CanQuery = false
end
local function deleteAllPaintParts()
    for _, obj in ipairs(Workspace:GetDescendants()) do hidePaint(obj) end
end
local function restorePaintParts()
    for obj, props in pairs(paintPartsBackup) do
        pcall(function() for property, value in pairs(props) do obj[property] = value end end)
    end
    table.clear(paintPartsBackup)
end
local function watchNewPaintParts()
    for _, connection in ipairs(paintConnections) do connection:Disconnect() end
    table.clear(paintConnections)
    table.insert(paintConnections, Hub.connect(Workspace.DescendantAdded, hidePaint))
end
local function disconnectWatchers()
    for _, connection in ipairs(paintConnections) do connection:Disconnect() end
    table.clear(paintConnections)
end

local function setTouchQuery(state)
	local char = Workspace:FindFirstChild(Player.Name)
	if not char then return end
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Part") or v:IsA("BasePart") then if not state then Hub.backup(v, {"CanTouch", "CanQuery"}); v.CanTouch = false; v.CanQuery = false else Hub.restore(v) end end
	end
end

-- Anti-Gucci Systems
local antiGucciConnection
local safePosition
local restoreFrames = 0

local function spawnBlobman()
	local args = {[1] = "CreatureBlobman", [2] = CFrame.new(0, 5000000, 0), [3] = Vector3.new(0, 60, 0)}
	pcall(function() Hub.invoke(ReplicatedStorage.MenuToys.SpawnToyRemoteFunction, unpack(args)) end)
	local folder = Workspace:WaitForChild(Player.Name.."SpawnedInToys", 5)
	if folder and folder:FindFirstChild("CreatureBlobman") then
		local blob = folder.CreatureBlobman
		if blob:FindFirstChild("Head") then blob.Head.CFrame = CFrame.new(0, 50000, 0) blob.Head.Anchored = true end
		notify("Success", "Blobman Spawned!", 3)
	end
end

local function startAntiGucci()
    Hub.blobGeneration = (Hub.blobGeneration or 0) + 1
    local generation = Hub.blobGeneration
    if Hub.blobJump then Hub.blobJump:Disconnect(); Hub.blobJump = nil end
	local character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoid or not rootPart or character ~= Player.Character or humanoid.Health <= 0 then return end
	safePosition = rootPart.Position
	local folder = Workspace:FindFirstChild(Player.Name.."SpawnedInToys")
	local blob = folder and folder:FindFirstChild("CreatureBlobman")
	local seat = blob and blob:FindFirstChild("VehicleSeat")

	if not blob then 
		spawnBlobman() 
		task.wait(1) 
		folder = Workspace:FindFirstChild(Player.Name.."SpawnedInToys") 
		blob = folder and folder:FindFirstChild("CreatureBlobman") 
		seat = blob and blob:FindFirstChild("VehicleSeat") 
	end

	if character ~= Player.Character or generation ~= Hub.blobGeneration then return end
    if seat and seat:IsA("VehicleSeat") then 
		rootPart.CFrame = seat.CFrame + Vector3.new(0, 2, 0) 
		seat:Sit(humanoid) 
	end

	Hub.blobJump = Hub.connect(humanoid:GetPropertyChangedSignal("Jump"), function() 
		if humanoid.Jump and humanoid.Sit then 
			restoreFrames = 60 
			safePosition = rootPart.Position 
		end 
	end)

	if antiGucciConnection then antiGucciConnection:Disconnect() end
	antiGucciConnection = Hub.connect(RunService.Heartbeat, function()
		if character ~= Player.Character or not rootPart.Parent or not humanoid.Parent or humanoid.Health <= 0 or generation ~= Hub.blobGeneration then return end
		local now = os.clock()
        if ragdollRemoteEvent and now >= (Hub.blobNextRagdoll or 0) then
            Hub.blobNextRagdoll = now + 0.1
            Hub.fire(ragdollRemoteEvent, rootPart, 0)
        end
		if restoreFrames > 0 then 
			rootPart.CFrame = CFrame.new(safePosition) 
			restoreFrames = restoreFrames - 1 
		end
	end)

	task.spawn(function() 
		while humanoid.Sit and humanoid.Parent and character == Player.Character and generation == Hub.blobGeneration do 
			task.wait(1) 
		end 
		task.wait(1) 
        if character == Player.Character and rootPart.Parent and generation == Hub.blobGeneration then rootPart.CFrame = CFrame.new(safePosition) end
	end)
end

local function stopAntiGucci()
    Hub.blobGeneration = (Hub.blobGeneration or 0) + 1
    if Hub.blobJump then Hub.blobJump:Disconnect(); Hub.blobJump = nil end
	if antiGucciConnection then 
		antiGucciConnection:Disconnect() 
		antiGucciConnection = nil 
	end
	local blobFolder = Workspace:FindFirstChild(Player.Name.."SpawnedInToys")
	if blobFolder and blobFolder:FindFirstChild("CreatureBlobman") then 
		blobFolder.CreatureBlobman:Destroy() 
	end
end

-- Anti-Gucci Train System
local antiGucciConnectionTrain
local safePositionTrain
local restoreFramesTrain = 0

local function startAntiGucciTrain()
    Hub.trainGeneration = (Hub.trainGeneration or 0) + 1
    local generation = Hub.trainGeneration
    if Hub.trainJump then Hub.trainJump:Disconnect(); Hub.trainJump = nil end
	local character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	local rootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoid or not rootPart or character ~= Player.Character or humanoid.Health <= 0 then return end
	safePositionTrain = rootPart.Position
	local map = workspace:FindFirstChild("Map")
    local folder = map and map:FindFirstChild("AlwaysHereTweenedObjects")
	local train = folder and folder:FindFirstChild("Train")
	local seat

	if train then
		for _, d in ipairs(train:GetDescendants()) do
			if d:IsA("Seat") then
				seat = d
				break
			end
		end
	end

	if seat then 
		rootPart.CFrame = seat.CFrame + Vector3.new(0, 2, 0) 
		seat:Sit(humanoid) 
	end

	Hub.trainJump = Hub.connect(humanoid:GetPropertyChangedSignal("Jump"), function() 
		if humanoid.Jump and humanoid.Sit then 
			restoreFramesTrain = 15 
			safePositionTrain = rootPart.Position 
		end 
	end)

	if antiGucciConnectionTrain then antiGucciConnectionTrain:Disconnect() end
	antiGucciConnectionTrain = Hub.connect(RunService.Heartbeat, function()
		if character ~= Player.Character or not rootPart.Parent or not humanoid.Parent or humanoid.Health <= 0 or generation ~= Hub.trainGeneration then return end
		local now = os.clock()
        if ragdollRemoteEvent and now >= (Hub.trainNextRagdoll or 0) then
            Hub.trainNextRagdoll = now + 0.1
            Hub.fire(ragdollRemoteEvent, rootPart, 0)
        end
		if restoreFramesTrain > 0 then 
			rootPart.CFrame = CFrame.new(safePositionTrain) 
			restoreFramesTrain = restoreFramesTrain - 1 
		end
	end)

	task.spawn(function() 
		while humanoid.Sit and humanoid.Parent and character == Player.Character and generation == Hub.trainGeneration do 
			task.wait(1) 
		end 
		task.wait(0.5) 
        if character == Player.Character and rootPart.Parent and generation == Hub.trainGeneration then rootPart.CFrame = CFrame.new(safePositionTrain) end
	end)
end

local function stopAntiGucciTrain()
    Hub.trainGeneration = (Hub.trainGeneration or 0) + 1
    if Hub.trainJump then Hub.trainJump:Disconnect(); Hub.trainJump = nil end
	if antiGucciConnectionTrain then 
		antiGucciConnectionTrain:Disconnect() 
		antiGucciConnectionTrain = nil 
	end
end

Hub.connect(Player.CharacterRemoving, function()
    Hub.blobGeneration = (Hub.blobGeneration or 0) + 1
    Hub.trainGeneration = (Hub.trainGeneration or 0) + 1
    if antiGucciConnection then antiGucciConnection:Disconnect(); antiGucciConnection = nil end
    if antiGucciConnectionTrain then antiGucciConnectionTrain:Disconnect(); antiGucciConnectionTrain = nil end
    if Hub.blobJump then Hub.blobJump:Disconnect(); Hub.blobJump = nil end
    if Hub.trainJump then Hub.trainJump:Disconnect(); Hub.trainJump = nil end
end)
Hub.connect(Player.CharacterAdded, function(char)
    local root = char:WaitForChild("HumanoidRootPart", 5)
    local hum = char:WaitForChild("Humanoid", 5)
    if not root or not hum or Player.Character ~= char then return end
    if Toggles.AutoGucciBlobToggle and Toggles.AutoGucciBlobToggle.Value then task.spawn(startAntiGucci) end
    if Toggles.AutoGucciTrainToggle and Toggles.AutoGucciTrainToggle.Value then task.spawn(startAntiGucciTrain) end
end)

-- Defense Tab
local DefenseGroup = Tabs.Defense:AddLeftGroupbox("Defense Main")
local DefenseExtra = Tabs.Defense:AddRightGroupbox("Extra Defense")

-- Remotes
local CharacterEvents = ReplicatedStorage:FindFirstChild("CharacterEvents")
local Struggle = CharacterEvents and CharacterEvents:FindFirstChild("Struggle")
local StopVelocity = ReplicatedStorage:FindFirstChild("GameCorrectionEvents")
	and ReplicatedStorage.GameCorrectionEvents:FindFirstChild("StopAllVelocity")

-- State
local antiGrabEnabled = false
local connections = {}
local freezeConn
local hardFreeze = false
local savedCF

--------------------------------------------------
-- Helpers
--------------------------------------------------

local function disconnectAll()
	for _, c in ipairs(connections) do
		pcall(function() c:Disconnect() end)
	end
	table.clear(connections)
end

local function anchorAll(char, state)
	for _, p in ipairs(char:GetChildren()) do
		if p:IsA("BasePart") then
			if state then Hub.backup(p, {"Anchored"}); p.Anchored = true else Hub.restore(p) end
		end
	end
end

--------------------------------------------------
-- Hard freeze (stronger than Anchored spam)
--------------------------------------------------

local function freezeChar(char)
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	savedCF = hrp.CFrame
	hardFreeze = true

	if freezeConn then freezeConn:Disconnect() end
	freezeConn = Hub.connect(RunService.Heartbeat, function()
		if hardFreeze and hrp then
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.CFrame = savedCF
		end
	end)
end

local function unfreezeChar(char)
	hardFreeze = false
	if freezeConn then
		freezeConn:Disconnect()
		freezeConn = nil
	end
	if char then
		anchorAll(char, false)
	end
end

--------------------------------------------------
-- Core grab breaker
--------------------------------------------------

local grabGeneration = 0
local function onGrabDetected()
    if not antiGrabEnabled then return end
    local char = Player.Character
    if not char then return end
    grabGeneration += 1
    local generation = grabGeneration
    pcall(function()
        if Struggle then Hub.fire(Struggle, Player) end
        if StopVelocity then Hub.fire(StopVelocity) end
    end)
    anchorAll(char, true)
    freezeChar(char)
    task.spawn(function()
        local deadline = os.clock() + 2
        repeat task.wait(0.05)
            local held = Player:FindFirstChild("IsHeld")
            if not held or not held.Value then break end
        until not antiGrabEnabled or not char.Parent or os.clock() >= deadline or generation ~= grabGeneration
        if generation == grabGeneration then unfreezeChar(char) end
    end)
end

--------------------------------------------------
-- Character hook
--------------------------------------------------

local function hookCharacter(char)
	local head = char:WaitForChild("Head", 5)
    if not antiGrabEnabled or Player.Character ~= char then return end
	local hum = char:WaitForChild("Humanoid", 5)
	if not (head and hum) then return end

	-- detect grab instantly
	table.insert(connections,
		Hub.connect(head.ChildAdded, function(child)
			if antiGrabEnabled and child.Name == "PartOwner" then
				onGrabDetected()
			end
		end)
	)

	-- prevent non-blob seating
	table.insert(connections,
		Hub.connect(hum.Changed, function(prop)
			if prop == "Sit" and hum.Sit then
				if not (hum.SeatPart and hum.SeatPart.Parent
					and hum.SeatPart.Parent.Name == "CreatureBlobman") then
					hum.Sit = false
				end
			end
		end)
	)

	-- already held case
	local isHeld = Player:FindFirstChild("IsHeld")
	if isHeld and isHeld.Value then
		onGrabDetected()
	end
end

--------------------------------------------------
-- UI Toggle
--------------------------------------------------



DefenseGroup:AddToggle("AntiGrabObsidian", {
	Text = "Anti Grab",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		antiGrabEnabled = on
		disconnectAll()
        unfreezeChar(Player.Character)

			if on then
			if Player.Character then
				hookCharacter(Player.Character)
			end

			table.insert(connections,
				Hub.connect(Player.CharacterAdded, function(char)
					task.wait(0.1)
					hookCharacter(char)
				end)
			)
		else
			unfreezeChar(Player.Character)
		end
	end
})


Hub.blobParts = {}
local function anti(Descendant)
    for _, name in ipairs({"LeftDetector", "RightDetector"}) do
        local detector = Descendant:FindFirstChild(name)
        if detector then
            if detector:IsA("BasePart") then
                Hub.blobParts[detector] = true
                Hub.backup(detector, {"CanTouch", "CanCollide"})
                detector.CanTouch = false; detector.CanCollide = false
            end
            for _, constraint in ipairs(detector:GetDescendants()) do
                if constraint:IsA("Constraint") then
                    Hub.blobParts[constraint] = true
                    Hub.backup(constraint, {"Enabled"})
                    constraint.Enabled = false
                end
            end
        end
    end
end

local antiBlob1T=false
local antiBlobWatcher
local function antiBlob1F()
	antiBlob1T=true

	if antiBlob1T then
		for _, Descendant in pairs(workspace:GetDescendants()) do
			if Descendant.Name == "CreatureBlobman" and Descendant.Parent ~= Workspace:FindFirstChild(Player.Name .. "SpawnedInToys") then
				anti(Descendant)
			end
		end

		if antiBlobWatcher then antiBlobWatcher:Disconnect() end
        antiBlobWatcher = Hub.connect(workspace.DescendantAdded, function(Descendant)
			if antiBlob1T and Descendant.Name == "CreatureBlobman" and Descendant.Parent ~= Workspace:FindFirstChild(Player.Name .. "SpawnedInToys") then
				task.wait(0.1)
                if not antiBlob1T then return end
				anti(Descendant)
			end
		end)
	end
end

DefenseGroup:AddToggle("AntiBlobmanToggle", {
	Text="Anti Blobman", 
	Default=false,
	Callback=function(on)
		Hub.requestSave()
		if on then antiBlob1F()
        else
            antiBlob1T = false
            if antiBlobWatcher then antiBlobWatcher:Disconnect(); antiBlobWatcher = nil end
            for obj in pairs(Hub.blobParts or {}) do Hub.restore(obj) end
            Hub.blobParts = {}
        end
	end
})

local antiExplodeT=false
local antiExplodeConnection
local function antiExplodeF()
    antiExplodeT = true
    if antiExplodeConnection then antiExplodeConnection:Disconnect() end
    antiExplodeConnection = Hub.connect(workspace.ChildAdded, function(model)
        if not antiExplodeT or not model:IsA("BasePart") or model.Name ~= "Part" then return end
        local char = Player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp or (model.Position - hrp.Position).Magnitude > 20 then return end
        local original = hrp.Anchored
        hrp.Anchored = true
        task.delay(0.15, function() if hrp.Parent then hrp.Anchored = original end end)
        Hub.explosionAnchor = {hrp, original}
    end)
end
Hub.cleanup(function()
    if Hub.explosionAnchor then Hub.explosionAnchor[1].Anchored = Hub.explosionAnchor[2] end
end)

DefenseGroup:AddToggle("AntiExplosionToggle", {
	Text="Anti Explosion", 
	Default=false,
	Callback=function(on)
		Hub.requestSave()
		if on then antiExplodeF() else antiExplodeT=false; if antiExplodeConnection then antiExplodeConnection:Disconnect(); antiExplodeConnection=nil end end
	end
})

do
-- Anti Burn: late-spawned fire parts, bounded retries, no startup map mutation.
local antiBurnEnabled = false
local burnThreadToken = 0
local function getExtinguisher()
    local map = workspace:FindFirstChild("Map")
    local hole = map and map:FindFirstChild("Hole")
    local poison = hole and hole:FindFirstChild("PoisonBigHole")
    return poison and poison:FindFirstChild("ExtinguishPart")
end
local function hookBurn(char)
    burnThreadToken += 1
    local token = burnThreadToken
    task.spawn(function()
        while antiBurnEnabled and char.Parent and token == burnThreadToken do
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            local firePart = root and root:FindFirstChild("FirePlayerPart")
            local debounce = hum and hum:FindFirstChild("FireDebounce") or firePart and firePart:FindFirstChild("FireDebounce")
            local extinguisher = getExtinguisher()
            if debounce and debounce.Value and firePart and extinguisher then
                Hub.burnOriginal = Hub.burnOriginal or {part = extinguisher, cf = extinguisher.CFrame}
                extinguisher.CFrame = firePart.CFrame
                if firetouchinterest then
                    pcall(firetouchinterest, firePart, extinguisher, 0)
                    task.wait(0.05)
                    pcall(firetouchinterest, firePart, extinguisher, 1)
                end
            end
            task.wait(0.2)
        end
    end)
end
local function restoreBurn()
    burnThreadToken += 1
    if Hub.burnOriginal then
        pcall(function() Hub.burnOriginal.part.CFrame = Hub.burnOriginal.cf end)
        Hub.burnOriginal = nil
    end
end
Hub.cleanup(restoreBurn)
Hub.connect(Player.CharacterAdded, function(char) if antiBurnEnabled then hookBurn(char) end end)
DefenseGroup:AddToggle("AntiBurnToggle", {Text = "Anti Burn", Default = false,
    Callback = function(on)
        antiBurnEnabled = on
        Hub.requestSave()
        if on then
            if not getExtinguisher() then notify("Anti Burn", "Extinguisher not found in this map.", 5) end
            if Player.Character then hookBurn(Player.Character) end
        else restoreBurn() end
    end})

end

do
-- Anti-Void
local antiVoidConn
local VOID_THRESHOLD = -50
local SAFE_HEIGHT = 100

DefenseGroup:AddToggle("AntiVoidToggle", {
	Text = "Anti Void",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		if on then
			if antiVoidConn then antiVoidConn:Disconnect() end
			antiVoidConn = Hub.connect(RunService.Heartbeat, function()
				local char = Player.Character
				if char and char.PrimaryPart then
					local pos = char.PrimaryPart.Position
					if pos.Y < VOID_THRESHOLD then
						local safePos = Vector3.new(pos.X, pos.Y + SAFE_HEIGHT, pos.Z)
						char:SetPrimaryPartCFrame(CFrame.new(safePos))
						char.PrimaryPart.AssemblyLinearVelocity = Vector3.zero
					end
				end
			end)
		else
			if antiVoidConn then antiVoidConn:Disconnect() antiVoidConn = nil end
		end
	end
})

end

-- Anti-Sticky
local antiStickyT = false
DefenseGroup:AddToggle("AntiStickyToggle", {
	Text = "Anti Sticky",
	Default = false,
	Callback = function(Value)
		antiStickyT = Value
		if Player.PlayerScripts:FindFirstChild("StickyPartsTouchDetection") then
			local script = Player.PlayerScripts.StickyPartsTouchDetection
            if Value then Hub.backup(script, {"Disabled"}); script.Disabled = true
            else Hub.restore(script) end
		end
	end,
})


local function isFromLocalPlayer(inst)
	return Player.Character and inst:IsDescendantOf(Player.Character)
end

do
-- Anti Lag: continuously disable the actual line script and prune foreign beams locally.
local state = {on = false, generation = 0, scripts = {}, scriptConnections = {}, listeners = {}, removed = 0}
Hub.antiLag = state
local function listen(signal, callback)
    -- Avoid the general callback wrapper on the potentially flooded Workspace signal.
    local connection = signal:Connect(callback)
    state.listeners[connection] = true
    Hub.connections[connection] = true
    return connection
end
local function isOwnBeam(obj)
    local char = Player.Character
    if char and obj:IsDescendantOf(char) then return true end
    local toys = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
    if toys and obj:IsDescendantOf(toys) then return true end
    local current = obj.Parent
    while current and current ~= Workspace do
        if current.Name == "GrabParts" and current.Parent == Workspace then return true end
        current = current.Parent
    end
    return false
end
local function pruneBeam(obj)
    if not state.on or not obj:IsA("Beam") or not obj.Parent or isOwnBeam(obj) then return end
    local ok = pcall(function() obj:Destroy() end)
    if ok then state.removed += 1 end
end
local function enforceScript(script)
    if not state.on or not script:IsA("LocalScript") or script.Name ~= "CharacterAndBeamMove" then return end
    if state.scripts[script] == nil then
        state.scripts[script] = script.Disabled
        local disabledConnection = listen(script:GetPropertyChangedSignal("Disabled"), function()
            if state.on and script.Parent and not script.Disabled then script.Disabled = true end
        end)
        local destroyingConnection = listen(script.Destroying, function()
            state.scripts[script] = nil
            for _, connection in ipairs(state.scriptConnections[script] or {}) do
                connection:Disconnect(); state.listeners[connection] = nil; Hub.connections[connection] = nil
            end
            state.scriptConnections[script] = nil
        end)
        state.scriptConnections[script] = {disabledConnection, destroyingConnection}
    end
    if not script.Disabled then script.Disabled = true end
end
local function scanScripts(container)
    if not container or not state.on then return end
    for _, obj in ipairs(container:GetDescendants()) do enforceScript(obj) end
end
local function restore()
    state.on = false
    state.generation += 1
    for connection in pairs(state.listeners) do
        connection:Disconnect()
        Hub.connections[connection] = nil
    end
    table.clear(state.listeners)
    for script, disabled in pairs(state.scripts) do
        pcall(function() if script.Parent then script.Disabled = disabled end end)
    end
    table.clear(state.scripts)
    table.clear(state.scriptConnections)
    state.characterConnection = nil
end
local function hookCharacter(char)
    if state.characterConnection then
        state.characterConnection:Disconnect()
        state.listeners[state.characterConnection] = nil
        Hub.connections[state.characterConnection] = nil
    end
    scanScripts(char)
    state.characterConnection = listen(char.DescendantAdded, enforceScript)
end
local function enable()
    restore()
    state.on = true
    local generation = state.generation
    -- Attach watchers before scanning, so late scripts and beams are not missed.
    listen(Player.DescendantAdded, function(obj)
        enforceScript(obj)
        if obj:IsA("PlayerScripts") then scanScripts(obj) end
    end)
    listen(Player.CharacterAdded, hookCharacter)
    listen(Workspace.DescendantAdded, pruneBeam)
    scanScripts(Player:FindFirstChildOfClass("PlayerScripts"))
    if Player.Character then hookCharacter(Player.Character) end
    task.spawn(function()
        for index, obj in ipairs(Workspace:GetDescendants()) do
            if not state.on or generation ~= state.generation then return end
            pruneBeam(obj)
            if index % 200 == 0 then task.wait() end
        end
    end)
end
Hub.cleanup(restore)
DefenseGroup:AddToggle("AntiLagToggle", {
    Text = "Anti Lag", Default = false,
    Callback = function(on)
        if on then enable() else restore() end
        Hub.requestSave()
    end,
})
DefenseGroup:AddButton({Text = "Anti Lag status", Func = function()
    local scripts, disabled = 0, 0
    for script in pairs(state.scripts) do
        if script.Parent then scripts += 1; if script.Disabled then disabled += 1 end end
    end
    local message = string.format("%s | Line scripts disabled: %d/%d | Foreign beams removed: %d",
        state.on and "On" or "Off", disabled, scripts, state.removed)
    if state.on and scripts == 0 then message ..= " | CharacterAndBeamMove not found yet; watching for it." end
    notify("Anti Lag", message, 8)
end})
end

-- WARNING MONITOR BEGIN: notification only; no character or enforcement changes.
do
    local gui, observed, connections = nil, {}, {}
    local count, lastAlert, alive = 0, -math.huge, false
local function visible(label)
    if label.TextTransparency >= 1 then return false end
    local current = label
    while current and current ~= gui do
        if current:IsA("GuiObject") and not current.Visible then return false end
        if current:IsA("LayerCollector") and not current.Enabled then return false end
        current = current.Parent
    end
    return current == gui
end

local function evaluate(label)
    local state = observed[label]
    if not alive or not state then return end
    local message = string.lower(label.Text):gsub("%s+", " ")
    local matches = message:find("the game thinks you may be flying", 1, true)
        and message:find("put you on the ground", 1, true)
    local active = matches ~= nil and visible(label)
    if active and not state.active and os.clock() - lastAlert >= 1 then
        lastAlert = os.clock()
        count += 1
        local notice = "Anti-flight warning observed (" .. count .. " this session)."
        warn("[Warning Monitor] " .. notice .. " This is not the server's strike count.")
        notify("Movement warning", notice, 8)
 		local char = Player.Character
	    local hum = char and char:FindFirstChild("Humanoid")

		 if hum and hum.Health > 0 then
			hum.Health = 0
		 end
    end
    state.active = active
end

local function observe(label)
    if observed[label] or not (label:IsA("TextLabel") or label:IsA("TextBox") or label:IsA("TextButton")) then return end
    local state = { active = false, connections = {} }
    observed[label] = state
    local function listen(signal, callback)
        table.insert(state.connections, signal:Connect(callback))
    end
    listen(label:GetPropertyChangedSignal("Text"), function() evaluate(label) end)
    listen(label:GetPropertyChangedSignal("TextTransparency"), function() evaluate(label) end)
    -- Watch ancestor visibility because games often reuse the same warning label.
    local function bindAncestors()
        for _, connection in ipairs(state.ancestors or {}) do connection:Disconnect() end
        state.ancestors = {}
        local current = label
        while current and current ~= gui do
            local property = current:IsA("GuiObject") and "Visible"
                or current:IsA("LayerCollector") and "Enabled"
            if property then
                table.insert(state.ancestors, current:GetPropertyChangedSignal(property):Connect(function() evaluate(label) end))
            end
            current = current.Parent
        end
        evaluate(label)
    end
    listen(label.AncestryChanged, bindAncestors)
    listen(label.Destroying, function()
        for _, connection in ipairs(state.connections) do connection:Disconnect() end
        for _, connection in ipairs(state.ancestors or {}) do connection:Disconnect() end
        observed[label] = nil
    end)
    bindAncestors()
end


    local function stop()
        alive = false
        for _, connection in ipairs(connections) do connection:Disconnect() end
        for _, state in pairs(observed) do
            for _, connection in ipairs(state.connections) do connection:Disconnect() end
            for _, connection in ipairs(state.ancestors or {}) do connection:Disconnect() end
        end
        table.clear(connections)
        table.clear(observed)
    end
    local function start()
        if alive then return end
        gui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
        if not gui then notify("Movement warning", "PlayerGui is unavailable; enable the monitor again when loaded.", 8); return end
        alive = true
        table.insert(connections, gui.DescendantAdded:Connect(observe))
        for _, descendant in ipairs(gui:GetDescendants()) do observe(descendant) end
    end
    Hub.cleanup(stop)
    DefenseGroup:AddToggle("MovementWarningMonitor", {
        Text = "Movement warning monitor", Default = false,
        Callback = function(on)
            if on then start() else stop() end
            Hub.requestSave()
        end,
    })
    DefenseGroup:AddButton({Text = "Movement warning count", Func = function()
        notify("Movement warning", tostring(count) .. " observed this session | " .. (alive and "Monitoring" or "Off") .. " | Not the server strike count.", 8)
    end})
    DefenseGroup:AddButton({Text = "Clear observed warning count", Func = function()
        count = 0
        notify("Movement warning", "Local display counter cleared. Server state is unchanged.", 6)
    end})
end
-- WARNING MONITOR END

-- Extra Defense Toggles
DefenseExtra:AddToggle("PaintDeleteToggle", {
	Text = "Anti Paint",
	Default = false,
	Callback = function(state)
		if state then 
			deleteAllPaintParts() 
			watchNewPaintParts() 
			setTouchQuery(false)
		else 
			restorePaintParts() 
			disconnectWatchers() 
			setTouchQuery(true) 
		end
	end
})

-- Auto Gucci System (Blobman)
local autoGucciActive = false
DefenseExtra:AddToggle("AutoGucciBlobToggle", {
	Text = "Anti Gucci",
	Default = false,
	Callback = function(Value)
		autoGucciActive = Value

		if Value then
			startAntiGucci()
			notify("system", "auto gucci active (monitoring)", 3)

			task.spawn(function()
				while autoGucciActive do
					local toysFolder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
					local blobExists = toysFolder and toysFolder:FindFirstChild("CreatureBlobman")

					if not blobExists then
						stopAntiGucci() 
						spawnBlobman() 
						notify("System", "blobman lost", 3)

						local retries = 0
						repeat
							task.wait(0.2)
							retries = retries + 1
							toysFolder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
						until (toysFolder and toysFolder:FindFirstChild("CreatureBlobman")) or retries > 25 or not autoGucciActive

						if autoGucciActive and toysFolder and toysFolder:FindFirstChild("CreatureBlobman") then
							startAntiGucci()
							notify("System", "blobman restored.", 3)
						end
					end
					task.wait(0.5) 
				end
			end)
		else
			autoGucciActive = false
			stopAntiGucci()
			notify("System", "auto gucci disabled.", 3)
		end
	end
})

-- De-Sync System (Train)
local autoGucciActiveTrain = false
DefenseExtra:AddToggle("AutoGucciTrainToggle", {
	Text = "De-Sync",
	Default = false,
	Callback = function(Value)
		autoGucciActiveTrain = Value

		if Value then
			startAntiGucciTrain()
			notify("system", "De-Sync active (monitoring)", 3)

			task.spawn(function()
				while autoGucciActiveTrain do
					local trainFolder = workspace.Map.AlwaysHereTweenedObjects
					local trainExists = trainFolder and trainFolder:FindFirstChild("Train")

					if not trainExists then
						stopAntiGucciTrain() 
						notify("System", "Train lost", 3)

						local retries = 0
						repeat
							task.wait(0.2)
							retries = retries + 1
							trainFolder = workspace.Map.AlwaysHereTweenedObjects
						until (trainFolder and trainFolder:FindFirstChild("Train")) or retries > 25 or not autoGucciActiveTrain

						if autoGucciActiveTrain and trainFolder and trainFolder:FindFirstChild("Train") then
							startAntiGucciTrain()
							notify("System", "Train restored.", 3)
						end
					end
					task.wait(0.5) 
				end
			end)
		else
			autoGucciActiveTrain = false
			stopAntiGucciTrain()
			notify("System", "De-Sync disabled.", 3)
		end
	end
})

-- Anti-Input Lag
DefenseExtra:AddToggle("AntiInputLag", {
	Text = "Anti Input Lag",
	Default = false,
	Callback = function(Value)
		if Value then
			_G.AntiInputLag = true

			task.spawn(function()
				local plr = Player
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then return end

				local ToyName = "FoodHamburger"
				local Workspace = game:GetService("Workspace")
				local SpawnRemote = ReplicatedStorage.MenuToys.SpawnToyRemoteFunction

				while _G.AntiInputLag do
                    task.wait(0.15)
                    char = plr.Character
                    hrp = char and char:FindFirstChild("HumanoidRootPart")
                    if not hrp then continue end
					local toysFolder = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
					local burger = toysFolder and toysFolder:FindFirstChild(ToyName)

					if not burger then
						task.spawn(function()
							pcall(function()
								local spawnCF = hrp.CFrame * CFrame.new(0, 5, 0)
								Hub.invoke(SpawnRemote, ToyName, spawnCF, Vector3.new(0,0,0))
							end)
						end)

						local startWait = tick()
						repeat 
							RunService.Heartbeat:Wait()
							toysFolder = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
							burger = toysFolder and toysFolder:FindFirstChild(ToyName)
						until burger or tick() - startWait > 1 or not _G.AntiInputLag
					end

					if burger and burger.Parent then
						local holdPart = burger:FindFirstChild("HoldPart")
						if holdPart then
							local holdingPlayer = holdPart:FindFirstChild("HoldingPlayer") and holdPart.HoldingPlayer.Value

							if holdingPlayer and holdingPlayer ~= plr then
								pcall(function()
									Hub.invoke(holdPart.DropItemRemoteFunction, burger, hrp.CFrame * CFrame.new(0, 2000, 0), Vector3.new(0,0,0))
								end)
								if Hub.canAffect(burger) then burger:Destroy() end
							else
								pcall(function()
									Hub.invoke(holdPart.HoldItemRemoteFunction, burger, char)
								end)
								task.wait()

								pcall(function()
									Hub.invoke(holdPart.DropItemRemoteFunction, burger, hrp.CFrame * CFrame.new(0, 2000, 0), Vector3.new(0,0,0))
								end)
								task.wait()
							end
						end
					end
				end
			end)
		else
			_G.AntiInputLag = false
		end
	end
})

-- Anti-Kick System
DefenseExtra:AddToggle("ShurikenAntiKick", {
	Text = "Anti Kick",
	Default = false,
	Callback = function(Value)
		_G.ShurikenAntiKick = Value

		local function ClearKunai()
			local plr = Player
			local inv = workspace:FindFirstChild(plr.Name.."SpawnedInToys")
			local destroyrem = ReplicatedStorage:FindFirstChild("MenuToys") and ReplicatedStorage.MenuToys:FindFirstChild("DestroyToy")

			if inv and destroyrem then
				for _, v in pairs(inv:GetChildren()) do
					if v.Name == "AntiKick" or v.Name == "NinjaShuriken" then
						pcall(function() Hub.fire(destroyrem, v) end)
					end
				end
			end
		end

		if Value then
			task.spawn(function()
				local plr = Player
				local setOwner = ReplicatedStorage:WaitForChild("GrabEvents"):WaitForChild("SetNetworkOwner")
				local stickyEvent = ReplicatedStorage:WaitForChild("PlayerEvents"):WaitForChild("StickyPartEvent")
				local spawnRemote = ReplicatedStorage.MenuToys.SpawnToyRemoteFunction
				local destroyrem = ReplicatedStorage:WaitForChild("MenuToys"):WaitForChild("DestroyToy")
				local canSpawn = plr:WaitForChild("CanSpawnToy")

				local function getHRP()
					if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
						return plr.Character.HumanoidRootPart
					else
						local character = plr.CharacterAdded:Wait()
						return character:WaitForChild("HumanoidRootPart")
					end
				end

				local function CheckForHome()
					if not workspace.PlotItems.PlayersInPlots:FindFirstChild(plr.Name) then 
						return false
					end
					for _, v in pairs(workspace.Plots:GetChildren()) do
						local sign = v:FindFirstChild("PlotSign")
						local owners = sign and sign:FindFirstChild("ThisPlotsOwners")
						if owners then
							for _, b in pairs(owners:GetChildren()) do
								if b.Value == plr.Name then
									local folder = workspace.PlotItems:FindFirstChild(v.Name)
									if folder then return true, folder end
								end
							end
						end
					end
					return false
				end

				local function StickKunai(kunai)
					if not kunai or not kunai:FindFirstChild("StickyPart") then return end
					local currentHRP = getHRP()
					if not currentHRP then return end

					if kunai:FindFirstChild("SoundPart") then
						if not kunai.SoundPart:FindFirstChild("PartOwner") or kunai.SoundPart.PartOwner.Value ~= plr.Name then 
							Hub.fire(setOwner, kunai.SoundPart, kunai.SoundPart.CFrame)
						end
					end

					local firePart = currentHRP:FindFirstChild("FirePlayerPart") or currentHRP:WaitForChild("FirePlayerPart", 5)
					if firePart then
						Hub.fire(stickyEvent, kunai.StickyPart, firePart, CFrame.new(0,0,0) * CFrame.Angles(0,math.rad(90),math.rad(90)))
					end

					for _, obj in pairs(kunai:GetChildren()) do
						if obj.Name == "Pyramid" then
							obj.CanTouch = false; obj.CanCollide = false; obj.CanQuery = false; obj.Transparency = 0
							if not obj:FindFirstChild("Highlight") then
								local high = Hub.new("Highlight", obj)
								high.FillColor = Color3.fromRGB(0, 0, 0)
							end
						elseif obj.Name == "Main" then
							obj.CanTouch = false; obj.CanCollide = false; obj.CanQuery = false; obj.Transparency = 0
							if not obj:FindFirstChild("Highlight") then
								local high = Hub.new("Highlight", obj)
								high.FillColor = Color3.fromRGB(255, 255, 255)
							end
						elseif obj:IsA("BasePart") then
							obj.CanTouch = false; obj.CanCollide = false; obj.CanQuery = false; obj.Transparency = 1
						end
					end
				end

				local function SpawnToy(name)
					local t = tick()
					while not canSpawn.Value do
						if not _G.ShurikenAntiKick or tick() - t > 5 then return nil end
						task.wait(0.1)
					end

					local currentHRP = getHRP()
					if currentHRP then
						task.spawn(function()
							pcall(function()
								Hub.invoke(spawnRemote, name, currentHRP.CFrame * CFrame.new(0, 12, 20), Vector3.new(0,0,0))
							end)
						end)
					end

					local boolik, house = CheckForHome()
					local inv = workspace:FindFirstChild(plr.Name.."SpawnedInToys")

					if boolik and house then 
						return house:WaitForChild(name, 2)
					elseif not workspace.PlotItems.PlayersInPlots:FindFirstChild(plr.Name) and inv then 
						return inv:WaitForChild(name, 2)
					end
					return nil
				end

				while _G.ShurikenAntiKick do 
					task.wait(0.005)

					if not plr.Character or not plr.Character:FindFirstChild("Humanoid") or plr.Character.Humanoid.Health <= 0 then 
						continue 
					end

					local inv = workspace:FindFirstChild(plr.Name.."SpawnedInToys")
					local kunai = inv and inv:FindFirstChild("NinjaShuriken")

					if workspace.PlotItems.PlayersInPlots:FindFirstChild(plr.Name) then 
						local boolik, house = CheckForHome()
						if boolik and house and workspace.Plots:FindFirstChild(house.Name) then
							local sign = workspace.Plots[house.Name]:FindFirstChild("PlotSign")
							if sign and sign.ThisPlotsOwners.Value.TimeRemainingNum.Value > 89 then 
								kunai = SpawnToy("NinjaShuriken")
								if kunai == nil then continue end
								kunai.Name = "AntiKick" 
								StickKunai(kunai)
							end
						end
					end

					if not kunai then
						if workspace.PlotItems.PlayersInPlots:FindFirstChild(plr.Name) then continue end 
						kunai = SpawnToy("NinjaShuriken")
						if kunai == nil then continue end 
						kunai.Name = "AntiKick"
						if not kunai then continue end 
					end

					repeat
						if kunai and kunai:FindFirstChild("StickyPart") and kunai.StickyPart.CanTouch == true then
							StickKunai(kunai)
							kunai.Name = "AntiKick"
						end
						task.wait(0.3)
					until not kunai or not _G.ShurikenAntiKick
						or not kunai:FindFirstChild("StickyPart")
						or kunai.StickyPart.CanTouch == false 
						or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") 
						or not kunai:FindFirstChild("StickyPart") 
						or (plr.Character.HumanoidRootPart.Position - kunai.StickyPart.Position).Magnitude >= 20

					if not kunai or not kunai:FindFirstChild("StickyPart") or not plr.Character or not plr.Character:FindFirstChild("HumanoidRootPart") or (plr.Character.HumanoidRootPart.Position - kunai.StickyPart.Position).Magnitude >= 20 then 
						ClearKunai()
					end 

					pcall(function()
						repeat
							task.wait(0.05)
						until not _G.ShurikenAntiKick or not plr.Character or not plr.Character:FindFirstChild("Humanoid") or not kunai or not kunai:FindFirstChild("StickyPart") or not kunai.StickyPart:FindFirstChild("StickyWeld") or not kunai.StickyPart.StickyWeld.Part1

						if not kunai or not kunai:FindFirstChild("StickyPart") or (plr.Character and plr.Character:FindFirstChild("Humanoid") and plr.Character.Humanoid.Health <= 0) or not kunai["StickyPart"]:FindFirstChild("StickyWeld").Part1 then 
							ClearKunai()
						end
					end)
				end
			end)
		else
			_G.ShurikenAntiKick = false
			ClearKunai()
		end
	end
})

do
-- Loop TP: one worker, current-character lookup, reversible PlatformStand.
local tpActive = false
local tpGeneration = 0
local affectedHumanoids = {}
local function restoreTP()
    for humanoid, original in pairs(affectedHumanoids) do
        pcall(function() humanoid.PlatformStand = original end)
    end
    table.clear(affectedHumanoids)
end
Hub.cleanup(restoreTP)
DefenseExtra:AddToggle("LoopTP", {Text = "Loop TP", Default = false,
    Callback = function(on)
        tpActive = on
        tpGeneration += 1
        local generation = tpGeneration
        restoreTP()
        if on then task.spawn(function()
            while tpActive and generation == tpGeneration do
                local current = Player.Character
                local root = current and current:FindFirstChild("HumanoidRootPart")
                local hum = current and current:FindFirstChildOfClass("Humanoid")
                if root and hum and hum.Health > 0 then
                    if affectedHumanoids[hum] == nil then affectedHumanoids[hum] = hum.PlatformStand end
                    hum.PlatformStand = true
                    root.CFrame = CFrame.new(math.random(-500, 500), math.random(30, 480), math.random(-500, 500))
                end
                task.wait(0.03)
            end
        end) end
        Hub.requestSave()
    end})
Hub.connect(Player.CharacterRemoving, restoreTP)
end

-- Auto Attacker
local AutoAttacker = false
local headConnection
DefenseExtra:AddToggle("AutoAttacker", {
	Text = "Auto Attacker",
	Default = false,
	Callback = function(Value)
		AutoAttacker = Value
        if Value and Hub.scanAttacker then Hub.scanAttacker() end
	end
})

function CheckNetworkOwnerShipOnPlayer(potentialPlayer, condition)
	if typeof(potentialPlayer) == "Instance" and (potentialPlayer:IsA("Player") and potentialPlayer.Character) and (potentialPlayer.Character:FindFirstChild("Head") and (potentialPlayer.Character.Head:FindFirstChild("PartOwner") and potentialPlayer.Character.Head.PartOwner.Value == Player.Name)) then
		return not condition and true or potentialPlayer.Character.Head.PartOwner
	end
end

function lookAt(startPosition, targetPosition)
	local directionVector = (targetPosition - startPosition).Unit
	local rightVector = directionVector:Cross((Vector3.new(0, 1, 0)))
	local upVector = rightVector:Cross(directionVector)
	return CFrame.fromMatrix(startPosition, rightVector, upVector)
end

function SNOWshipPermanentPlayer(otherPlayer, callbackFunction)
    if not Hub.canHarm(otherPlayer) then return false end
	if Player.Character and (Player.Character:FindFirstChild("HumanoidRootPart") and (typeof(otherPlayer) == "Instance" and (otherPlayer:IsA("Player") and otherPlayer.Character)) and (otherPlayer.Character:FindFirstChild("HumanoidRootPart") and otherPlayer.Character.HumanoidRootPart:FindFirstChild("FirePlayerPart"))) then
		local firePlayerPart = otherPlayer.Character.HumanoidRootPart.FirePlayerPart
		local distanceFromFirePlayerPart = Player:DistanceFromCharacter(firePlayerPart.Position)
		if type(callbackFunction) == "function" then
			callbackFunction()
		end
		if distanceFromFirePlayerPart <= 30 then
			Hub.fire(setNetworkOwnerEvent, firePlayerPart, lookAt(Player.Character.HumanoidRootPart.Position, firePlayerPart.Position))
			return true
		end
	end
end

function SNOWshipPlayer(otherPlayer, callbackFunction)
    if not Hub.canHarm(otherPlayer) then return false end
	if Player.Character and (Player.Character:FindFirstChild("HumanoidRootPart") and (typeof(otherPlayer) == "Instance" and (otherPlayer:IsA("Player") and otherPlayer.Character)) and otherPlayer.Character:FindFirstChild("HumanoidRootPart")) then
		local otherPlayerHumanoidRootPart = otherPlayer.Character.HumanoidRootPart
		local distanceFromOtherPlayer = Player:DistanceFromCharacter(otherPlayerHumanoidRootPart.Position)
		if CheckNetworkOwnerShipOnPlayer(otherPlayer) then
			if type(callbackFunction) == "function" then
				callbackFunction()
			end
			return true
		end
		if distanceFromOtherPlayer <= 30 then
			Hub.fire(setNetworkOwnerEvent, otherPlayerHumanoidRootPart, lookAt(Player.Character.HumanoidRootPart.Position, otherPlayerHumanoidRootPart.Position))
		end
	end
end

function SNOWship(targetPart)
    if not Hub.canAffect(targetPart) then return false end
	if targetPart and typeof(targetPart) == "Instance" then
		local distanceFromCharacter = Player:DistanceFromCharacter(targetPart.Position)
		if Player.Character and (Player.Character:FindFirstChild("HumanoidRootPart") and distanceFromCharacter <= 30) then
			Hub.fire(setNetworkOwnerEvent, targetPart, lookAt(Player.Character.HumanoidRootPart.Position, targetPart.Position))
		end
	end
end

function CreateSkyVelocity(skyObject)
    if not Hub.canAffect(skyObject) then return end
	if not skyObject or not skyObject.Parent then return end
	if not skyObject:FindFirstChild("SkyVelocity") then
		local skyVelocityBodyVelocity = Hub.new("BodyVelocity", skyObject)
		skyVelocityBodyVelocity.Name = "SkyVelocity"
		skyVelocityBodyVelocity.Velocity = Vector3.new(0, 100000000000000, 0)
		skyVelocityBodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	end
end

local heldObjectName = nil
Hub.attackerBindings = {}
Hub.attackerBusy = {}
local function hookAttackerCharacter(boundCharacter)
    for _, connection in ipairs(Hub.attackerBindings) do connection:Disconnect() end
    table.clear(Hub.attackerBindings)
    Hub.attackerBusy = {}
    local generation = Hub.characterGeneration
    local function isCurrent()
        local hum = boundCharacter:FindFirstChildOfClass("Humanoid")
        return Hub.alive and AutoAttacker and boundCharacter == Player.Character
            and generation == Hub.characterGeneration and hum and hum.Health > 0
    end
    local function handleOwner(hitPart)
        if not isCurrent() or not hitPart:IsDescendantOf(boundCharacter) then return end
        if not hitPart:IsA("StringValue") and not hitPart:IsA("ObjectValue") then return end
	if hitPart.Name == "PartOwner" then
		local value = hitPart.Value
        heldObjectName = typeof(value) == "Instance" and value.Name or tostring(value)
		if AutoAttacker then
			local otherPlayer = Players:FindFirstChild(heldObjectName)
			local otherHumanoid = nil
			local otherHumanoidRootPart = nil
			if otherPlayer and otherPlayer.Character then
				local otherCharacter = otherPlayer.Character
				if otherCharacter then
					otherHumanoid = otherCharacter:FindFirstChildOfClass("Humanoid")
					otherHumanoidRootPart = otherCharacter:FindFirstChild("HumanoidRootPart")
				end
			end

			-- Check if it's not yourself and not authorized (add isAuthorized if you have it)
			if Hub.canHarm(otherPlayer) and otherHumanoid and otherHumanoidRootPart then
                if Hub.attackerBusy[otherPlayer] then return end
                Hub.attackerBusy[otherPlayer] = true
				-- Death mode counter action
				local counterAction = function()
					local humanoidInstance = otherHumanoid
					if isCurrent() and Hub.canHarm(otherPlayer) and humanoidInstance and humanoidInstance.Parent and otherHumanoidRootPart.Parent then
						CreateSkyVelocity(otherHumanoidRootPart)
						for _ = 0, 20 do
							humanoidInstance.BreakJointsOnDeath = false
							humanoidInstance:ChangeState(Enum.HumanoidStateType.Dead)
							humanoidInstance.Jump = true
							humanoidInstance.Sit = true
						end
						task.wait()
						Hub.fire(ReplicatedStorage.GrabEvents.DestroyGrabLine, otherHumanoidRootPart)
					end
				end

				-- Execute SNOWship loop
				for _ = 1, 50 do
                    if not isCurrent() or not Hub.canHarm(otherPlayer) or otherPlayer.Character ~= otherHumanoid.Parent then break end
					if SNOWshipPlayer(otherPlayer, counterAction) then
						break
					end
					task.wait()
				end
                Hub.attackerBusy[otherPlayer] = nil
			end
		end 
	end
    end
    local function watchOwner(instance)
        if instance.Name ~= "PartOwner" then return end
        if not instance:IsA("StringValue") and not instance:IsA("ObjectValue") then return end
        table.insert(Hub.attackerBindings, Hub.connect(instance.Changed, function()
            task.spawn(function() handleOwner(instance) end)
        end))
        task.spawn(function() handleOwner(instance) end)
    end
    headConnection = Hub.connect(boundCharacter.DescendantAdded, function(instance)
        watchOwner(instance)
        if instance:IsA("Humanoid") or instance.Name == "HumanoidRootPart" then
            task.defer(function() if Hub.scanAttacker then Hub.scanAttacker() end end)
        end
    end)
    table.insert(Hub.attackerBindings, headConnection)
    Hub.scanAttacker = function()
        if not isCurrent() then return end
        for _, instance in ipairs(boundCharacter:GetDescendants()) do
            if instance.Name == "PartOwner" then task.spawn(function() handleOwner(instance) end) end
        end
    end
    for _, instance in ipairs(boundCharacter:GetDescendants()) do watchOwner(instance) end
end
if character then hookAttackerCharacter(character) end
Hub.connect(Player.CharacterRemoving, function()
    for _, connection in ipairs(Hub.attackerBindings) do connection:Disconnect() end
    table.clear(Hub.attackerBindings)
    table.clear(Hub.attackerBusy)
    Hub.scanAttacker = nil
end)
Hub.connect(Player.CharacterAdded, hookAttackerCharacter)

-- Player Tab
local PlayerView = Tabs.Player:AddLeftGroupbox("View & Movement")
local PlayerESP = Tabs.Player:AddRightGroupbox("ESP")
local PlayerPerf = Tabs.Player:AddRightGroupbox("Performance")

do
-- Third Person: restore the actual original camera mode.
local function enableThirdPerson()
    Player.CameraMode = Enum.CameraMode.Classic
    Player.CameraMaxZoomDistance = math.max(Hub.cameraOriginal.max, 128)
    Player.CameraMinZoomDistance = 0.5
end
local function disableThirdPerson()
    Player.CameraMaxZoomDistance = math.max(Player.CameraMaxZoomDistance, Hub.cameraOriginal.max)
    Player.CameraMinZoomDistance = Hub.cameraOriginal.min
    Player.CameraMaxZoomDistance = Hub.cameraOriginal.max
    Player.CameraMode = Hub.cameraOriginal.mode
end

PlayerView:AddToggle("ThirdPersonToggle", {
	Text = "3rd Person View",
	Default = false,
	Callback = function(Value)
		if Value then enableThirdPerson() else disableThirdPerson() end
	end
})

end

-- Spin Character
local spinningConnection
local spinSpeed = 5
PlayerView:AddToggle("SpinToggle", {
	Text = "Spin Character",
	Default = false,
	Callback = function(Value)
		if Value then
			spinningConnection = Hub.connect(RunService.Heartbeat, function(dt)
				local character = Player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed * dt * 60), 0) end
			end)
		else
			if spinningConnection then spinningConnection:Disconnect() spinningConnection = nil end
		end
	end
})

PlayerView:AddSlider("SpinSpeed", {
	Text = "Spin Speed",
	Default = 5,
	Min = 1,
	Max = 50,
	Rounding = 0,
	Callback = function(Value) spinSpeed = Value end
})



-- Infinite Jump
local infJump = false
PlayerView:AddToggle("infJumpToggle", {
	Text = "Infinite Jump",
	Default = false,
	Callback = function(Value) infJump = Value end
})

-- Speed/Jump Modifiers
local SpeedConnection
local SpeedModConnection
local WalkSpeed = 16
local JumpPower = 50
local speedModifierEnabled = false
local jumpModifierEnabled = false
local speedMultiplier = 1

PlayerView:AddToggle("SpeedModifierToggle", {
	Text = "Enable Speed Modifier",
	Default = false,
	Callback = function(Value)
		speedModifierEnabled = Value
		if Value then
			SpeedModConnection = Hub.connect(RunService.Heartbeat, function(dt)
				local character = Player.Character
				if character then
					local root = character:FindFirstChild("HumanoidRootPart")
					local hum = character:FindFirstChildOfClass("Humanoid")
					if root and hum then
						root.CFrame = root.CFrame + hum.MoveDirection * speedMultiplier * math.min(dt, 0.1) * 60
					end
				end
			end)
		else
			if SpeedModConnection then SpeedModConnection:Disconnect() SpeedModConnection = nil end
		end
	end
})

PlayerView:AddToggle("JumpModifierToggle", {
	Text = "Enable Jump Modifier",
	Default = false,
	Callback = function(Value)
		jumpModifierEnabled = Value
		local character = Player.Character
		if character then
			local hum = character:FindFirstChild("Humanoid")
			if hum then
				if Value then
					Hub.backup(hum, {"JumpPower", "UseJumpPower"})
                    hum.UseJumpPower = true
                    hum.JumpPower = JumpPower
				else
					Hub.restore(hum)
				end
			end
		end
	end
})

PlayerView:AddSlider("SpeedValue", {
	Text = "Walk speed",
	Default = 1,
	Min = 0.1,
	Max = 10,
	Rounding = 1,
	Callback = function(Value)
		speedMultiplier = Value
	end
})

PlayerView:AddSlider("JumpValue", {
	Text = "Jump Power",
	Default = 50,
	Min = 50,
	Max = 500,
	Rounding = 0,
	Callback = function(Value)
		JumpPower = Value
		if jumpModifierEnabled then
			local character = Player.Character
			if character then
				local hum = character:FindFirstChild("Humanoid")
				if hum then
					Hub.backup(hum, {"JumpPower", "UseJumpPower"})
                    hum.UseJumpPower = true
                    hum.JumpPower = Value
				end
			end
		end
	end
})

Hub.connect(Player.CharacterAdded, function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum or Player.Character ~= char then return end
    if jumpModifierEnabled then
        Hub.backup(hum, {"JumpPower", "UseJumpPower"})
        hum.UseJumpPower = true
        hum.JumpPower = JumpPower
    end
end)

Hub.connect(UserInputService.JumpRequest, function()
	if infJump then
		local character = Player.Character
		if character and character:FindFirstChildOfClass("Humanoid") then
			character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
		end
	end
end)

-- ESP System
local espEnabled = false
local espBoxes = {}
local targetNames = {"partesp", "playercharacterlocationdetector"}
local function IsTarget(obj)
	if not obj:IsA("BasePart") then return false end
	for _, name in ipairs(targetNames) do if string.lower(obj.Name) == string.lower(name) then return true end end
	return false
end

local function AddBoxESP(obj)
	if espBoxes[obj] then return end
	local box = Hub.new("BoxHandleAdornment")
	box.Adornee = obj
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Color3 = Color3.fromRGB(255, 255, 255)
	box.Transparency = 0.5
	box.Size = obj.Size
	box.Parent = game.CoreGui
	espBoxes[obj] = box
	Hub.connect(obj.AncestryChanged, function(_, parent)
		if not parent and espBoxes[obj] then espBoxes[obj]:Destroy() espBoxes[obj] = nil end
	end)
end

local function RemoveAllBoxes()
	for obj, box in pairs(espBoxes) do if box then box:Destroy() end end
	espBoxes = {}
end

local function Scan()
	for _, obj in ipairs(workspace:GetDescendants()) do if espEnabled and IsTarget(obj) then AddBoxESP(obj) end end
end

Hub.connect(workspace.DescendantAdded, function(obj) if espEnabled and IsTarget(obj) then AddBoxESP(obj) end end)

PlayerESP:AddToggle("BoxESPWhite", {
	Text = "PCLD View",
	Default = false,
	Callback = function(Value)
		espEnabled = Value
		if espEnabled then Scan() else RemoveAllBoxes() end
	end
})

-- Nickname ESP
PlayerESP:AddToggle("NicknameESP", {
	Text = "Esp",
	Default = false,
	Callback = function(Value)
        Hub.nameESPConnections = Hub.nameESPConnections or {}
        for _, connection in ipairs(Hub.nameESPConnections) do connection:Disconnect() end
        table.clear(Hub.nameESPConnections)
        local function espConnect(signal, callback)
            local connection = Hub.connect(signal, callback)
            table.insert(Hub.nameESPConnections, connection)
            return connection
        end
		local function createESP(plr)
            if not Toggles.NicknameESP.Value then return end
			if plr == Player then return end
			if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
				local hrp = plr.Character.HumanoidRootPart
				if hrp:FindFirstChild("NameESP") then return end

				local billboard = Hub.new("BillboardGui")
				billboard.Name = "NameESP"
				billboard.Adornee = hrp
				billboard.Size = UDim2.new(0, 120, 0, 70)
				billboard.StudsOffset = Vector3.new(0, 3.5, 0)
				billboard.AlwaysOnTop = true
				billboard.Parent = hrp

				local container = Hub.new("Frame")
				container.Size = UDim2.new(1, 0, 1, 0)
				container.BackgroundTransparency = 1
				container.Parent = billboard

				local pfpFrame = Hub.new("Frame")
				pfpFrame.Size = UDim2.new(0, 40, 0, 40)
				pfpFrame.Position = UDim2.new(0.5, 0, 0, 0)
				pfpFrame.AnchorPoint = Vector2.new(0.5, 0)
				pfpFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
				pfpFrame.BorderSizePixel = 0
				pfpFrame.Parent = container

				local pfpCorner = Hub.new("UICorner")
				pfpCorner.CornerRadius = UDim.new(1, 0)
				pfpCorner.Parent = pfpFrame

				local pfpImage = Hub.new("ImageLabel")
				pfpImage.Size = UDim2.new(1, 0, 1, 0)
				pfpImage.BackgroundTransparency = 1
				pfpImage.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. plr.UserId .. "&width=150&height=150&format=png"
				pfpImage.Parent = pfpFrame

				local pfpImageCorner = Hub.new("UICorner")
				pfpImageCorner.CornerRadius = UDim.new(1, 0)
				pfpImageCorner.Parent = pfpImage

				local textLabel = Hub.new("TextLabel")
				textLabel.Size = UDim2.new(1, 0, 0, 25)
				textLabel.Position = UDim2.new(0, 0, 0, 45)
				textLabel.BackgroundTransparency = 1
				textLabel.Text = plr.DisplayName
				textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
				textLabel.TextStrokeTransparency = 0
				textLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
				textLabel.Font = Enum.Font.GothamBold
				textLabel.TextSize = 16
				textLabel.TextScaled = true
				textLabel.TextXAlignment = Enum.TextXAlignment.Center
				textLabel.Parent = container
			end
		end

		if Value then
			for _, plr in pairs(Players:GetPlayers()) do 
				createESP(plr) 
				espConnect(plr.CharacterAdded, function() 
					task.wait(0.1)
					createESP(plr) 
				end) 
			end
			espConnect(Players.PlayerAdded, function(plr) 
				espConnect(plr.CharacterAdded, function() 
					task.wait(0.1)
					createESP(plr) 
				end) 
			end)
		else
			for _, plr in pairs(Players:GetPlayers()) do
				if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
					local hrp = plr.Character.HumanoidRootPart
					if hrp:FindFirstChild("NameESP") then 
						hrp.NameESP:Destroy() 
					end
				end
			end
		end
	end
})

-- Performance
local oldProperties = {}
PlayerPerf:AddButton({
	Text = "boost fps",
	Func = function()
		local Lighting = game:GetService("Lighting")
		for _, v in pairs(Workspace:GetDescendants()) do
			if v:IsA("BasePart") then
				if not oldProperties[v] then oldProperties[v] = {Material = v.Material, Reflectance = v.Reflectance, CastShadow = v.CastShadow} end
				v.Material = Enum.Material.Plastic v.Reflectance = 0 v.CastShadow = false
			elseif v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") then
				if not oldProperties[v] then oldProperties[v] = {Enabled = v.Enabled} end
				v.Enabled = false
			end
		end
		for _, plr in pairs(Players:GetPlayers()) do
			if plr.Character then
				for _, part in pairs(plr.Character:GetDescendants()) do
					if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
						if not oldProperties[part] then oldProperties[part] = {Material = part.Material, Reflectance = part.Reflectance, CastShadow = part.CastShadow} end
						part.Material = Enum.Material.Plastic part.Reflectance = 0 part.CastShadow = false
					end
				end
			end
		end
		if not oldProperties["Lighting"] then oldProperties["Lighting"] = {GlobalShadows = Lighting.GlobalShadows, FogEnd = Lighting.FogEnd, Brightness = Lighting.Brightness} end
		Lighting.GlobalShadows = false Lighting.FogEnd = 100000 Lighting.Brightness = 2
	end
})

PlayerPerf:AddButton({
	Text = "delete boost fps",
	Func = function()
		local Lighting = game:GetService("Lighting")
		for obj, props in pairs(oldProperties) do
			if typeof(obj) == "Instance" and obj.Parent then
				for prop, value in pairs(props) do obj[prop] = value end
			elseif obj == "Lighting" then
				for prop, value in pairs(props) do Lighting[prop] = value end
			end
		end
		oldProperties = {}
	end
})

-- Self Noclip
local noclipEnabled = false
local noclipConn
local charConn
local savedCollision = {}

local function applyNoclip(character)
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if savedCollision[part] == nil then
				savedCollision[part] = part.CanCollide
			end
			part.CanCollide = false
		end
	end
end

local function restoreCollision()
	for part, state in pairs(savedCollision) do
		if part and part.Parent then
			part.CanCollide = state
		end
	end
	table.clear(savedCollision)
end

local function startNoclip()
	if noclipConn then return end

	noclipConn = Hub.connect(RunService.Stepped, function()
		if not noclipEnabled then return end
		local char = Player.Character
		if char then
			applyNoclip(char)
		end
	end)

	charConn = Hub.connect(Player.CharacterAdded, function()
		task.wait(0.2)
		if noclipEnabled then
			restoreCollision()
		end
	end)
end

local function stopNoclip()
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
	if charConn then
		charConn:Disconnect()
		charConn = nil
	end
	restoreCollision()
end

PlayerView:AddToggle("SelfNoclipToggle", {
	Text = "Noclip",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		noclipEnabled = on
		if on then
			startNoclip()
		else
			stopNoclip()
		end
	end
})

-- Target Tab
local TargetGroup = Tabs.Target:AddLeftGroupbox("Target Interaction")
local BlobGroup = Tabs.Target:AddRightGroupbox("Blobman Control")
local WhitelistGroup = Tabs.Target:AddRightGroupbox("whitelist")

local SelectedPlayer = nil
local kickLoopEnabled = false
local loopKillEnabled = false
local loopKillEnabledAll = false

local function getPlayerList()
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= Player then
			table.insert(list, plr.DisplayName .. " (" .. plr.Name .. ")")
		end
	end
	return list
end

local function getPlayerFromSelection(selection)
	if not selection then return nil end
	local username = selection:match("%((.-)%)")
	if username then
		return Players:FindFirstChild(username)
	end
	return nil
end

local function autoblob()
	local plr = Player
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChild("Humanoid")

	if not hrp or not hum then return end

	local folderName = plr.Name .. "SpawnedInToys"
	local folder = workspace:FindFirstChild(folderName)
	local blob = folder and folder:FindFirstChild("CreatureBlobman")

	if not blob then
		task.spawn(function()
			pcall(function()
				Hub.invoke(ReplicatedStorage.MenuToys.SpawnToyRemoteFunction, "CreatureBlobman", hrp.CFrame, Vector3.zero)
			end)
		end)

		if not folder then
			folder = workspace:WaitForChild(folderName, 5)
		end

		if folder then
			blob = folder:WaitForChild("CreatureBlobman", 5)
		end
	end

	if blob then
		local seat = blob:WaitForChild("VehicleSeat", 5)
		if seat then
			local t = tick()
			repeat
				if not hum.SeatPart then
					hrp.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
					hrp.Velocity = Vector3.zero
					seat:Sit(hum)
				end
				RunService.Heartbeat:Wait()
			until hum.SeatPart == seat or tick() - t > 1.5
		end
	end
end

TargetGroup:AddDropdown("KickPlayerDropdown", {
	Values = getPlayerList(),
	Default = 1,
	Multi = false,
	Text = "select Player",
	Callback = function(Value)
		SelectedPlayer = getPlayerFromSelection(Value)
	end,
})

TargetGroup:AddButton({
	Text = "refresh player list",
	Func = function()
		Options.KickPlayerDropdown:SetValues(getPlayerList())
		Options.KickPlayerDropdown:SetValue(nil)
		SelectedPlayer = nil
	end
})

TargetGroup:AddToggle("LoopKickToggle", {
	Text = "Kick (spam grab)",
	Default = false,
	Callback = function(on)
		kickLoopEnabled = on

		local target = SelectedPlayer
		while on and not target do
			task.wait(0.5)
			target = SelectedPlayer
		end

		if not on then    
			kickLoopEnabled = false    
			return    
		end

		task.spawn(function()    
			local RS = ReplicatedStorage
			local RunService = game:GetService("RunService")    
			local GE = RS:WaitForChild("GrabEvents")    

			local myChar = Player.Character    
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")    
			if not myRoot then return end    

			local savedPos = myRoot.CFrame    
			local dragging = false    
			local grabStartTime = 0    

			while kickLoopEnabled do    
				while on and not target do
					task.wait(0.5)
					target = SelectedPlayer
				end

				local tChar = Hub.canHarm(target) and target.Character or nil    
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")    
				local tHum = tChar and tChar:FindFirstChild("Humanoid")    

				myChar = Player.Character    
				myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")    

				if tRoot and tHum and tHum.Health > 0 and myRoot then    

					if Hub.canAffect(tRoot) then tRoot.AssemblyLinearVelocity = Vector3.zero end
					if Hub.canAffect(tRoot) then tRoot.AssemblyAngularVelocity = Vector3.zero end
					if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end

					if not dragging then    
						if Hub.canAffect(tRoot) then myRoot.CFrame = tRoot.CFrame end
						myRoot.Velocity = Vector3.zero    

						pcall(function()    
							if Hub.canAffect(tHum) then tHum.PlatformStand = true end
							if Hub.canAffect(tHum) then tHum.Sit = true end
							Hub.fire(GE.SetNetworkOwner, tRoot, myRoot.CFrame)    
							Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)    
						end)    

						if grabStartTime == 0 then grabStartTime = tick() end    
						if tick() - grabStartTime > 0.35 then    
							dragging = true    
							grabStartTime = 0    
						end    
					else    
						myRoot.CFrame = savedPos    
						myRoot.Velocity = Vector3.zero    

						local lockPos = savedPos * CFrame.new(0, 17, 0)    

						if Hub.canAffect(tRoot) then tRoot.CFrame = lockPos end
						if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end
						if Hub.canAffect(tRoot) then tRoot.RotVelocity = Vector3.zero end

						if Hub.canAffect(tHum) then tHum.PlatformStand = true end
						if Hub.canAffect(tHum) then tHum.Sit = false end

						pcall(function()    
							Hub.fire(GE.SetNetworkOwner, tRoot, lockPos)    
							Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)    
							Hub.fire(GE.DestroyGrabLine, tRoot)    
							Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)    
						end)    
					end    
				else    
					dragging = false    
					grabStartTime = 0    
					if myRoot then    
						myRoot.CFrame = savedPos    
						myRoot.Velocity = Vector3.zero    
					end    
				end    

				RunService.Heartbeat:Wait()    
			end    

			if myRoot then    
				myRoot.CFrame = savedPos    
				myRoot.Velocity = Vector3.zero    
			end    
		end)    
	end
})

-- Loop Kill Single
TargetGroup:AddToggle("LoopKillToggle", {
	Text = "Loop kill",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		loopKillEnabled = on
		if on then
			local target = SelectedPlayer
			if not target then 
				notify("System", "Select target first", 3)
				Toggles.LoopKillToggle:SetValue(false)
				return 
			end

			task.spawn(function()
				local RS = ReplicatedStorage
				local GE = RS:WaitForChild("GrabEvents")

				while loopKillEnabled do
					if not Hub.canHarm(target) or not target.Character then
						loopKillEnabled = false
						Toggles.LoopKillToggle:SetValue(false)
						break
					end

					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
					local tChar = Hub.canHarm(target) and target.Character or nil
					local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
					local tHum = tChar and tChar:FindFirstChild("Humanoid")
					local tHead = tChar and tChar:FindFirstChild("Head")

					if tRoot and tHum and tHead and myRoot then
						local currentPos = myRoot.CFrame

						for _ = 0, 50 do
							if not loopKillEnabled or not Hub.canHarm(target) or not tRoot.Parent then break end

							applyNoclip(myChar)
							SNOWship(tRoot)

							-- Check if SNOWship was successful
							if not loopKillEnabled or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
								Hub.fire(GE.DestroyGrabLine, tRoot)
								CreateSkyVelocity(tRoot)
								break
							end

							task.wait()

							-- Teleport to target
							if tRoot.Position.Y <= -12 then
								if Hub.canAffect(tRoot) then myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 5, -15)) end
							else
								if Hub.canAffect(tRoot) then myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, -10, -10)) end
							end
							myRoot.Velocity = Vector3.zero

							-- Apply death state
							if Hub.canAffect(tHum) then tHum.BreakJointsOnDeath = false end
							if Hub.canAffect(tHum) then tHum:ChangeState(Enum.HumanoidStateType.Dead) end
							if Hub.canAffect(tHum) then tHum.Jump = true end
							if Hub.canAffect(tHum) then tHum.Sit = false end
						end

						if myRoot then
							restoreCollision()
							myRoot.CFrame = currentPos
							myRoot.Velocity = Vector3.zero
						end

						task.wait(0.2) 
					else
						task.wait(0.5)
					end
				end

				restoreCollision()
				local char = Player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then root.Velocity = Vector3.zero end
			end)
		else
			loopKillEnabled = false
		end
	end
})

-- Loop Kill All
TargetGroup:AddToggle("LoopKillToggleAll", {
	Text = "Loop kill All",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		loopKillEnabledAll = on
		if on then
			task.spawn(function()
				local RS = ReplicatedStorage
				local PS = Players
				local GE = RS:WaitForChild("GrabEvents")

				while loopKillEnabledAll do
					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

					if myRoot then
						local currentPos = myRoot.CFrame

						for _, target in pairs(PS:GetPlayers()) do
							if not loopKillEnabledAll then break end
							if not Hub.canHarm(target) then continue end

							if not Hub.canHarm(target) or not target.Character then
								continue
							end

							local tChar = Hub.canHarm(target) and target.Character or nil
							local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
							local tHum = tChar and tChar:FindFirstChild("Humanoid")
							local tHead = tChar and tChar:FindFirstChild("Head")

							-- Check if player is not in their plot
							local inPlotValue = target:FindFirstChild("InPlot")
							local isInPlot = inPlotValue and inPlotValue.Value

							if tRoot and tHum and tHead and tHum.Health > 0 and not isInPlot then
								for _ = 0, 50 do
									if not loopKillEnabledAll or not Hub.canHarm(target) or not tRoot.Parent then break end

									applyNoclip(myChar)
									SNOWship(tRoot)

									-- Check if SNOWship was successful
									if not loopKillEnabledAll or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
										Hub.fire(GE.DestroyGrabLine, tRoot)
										CreateSkyVelocity(tRoot)
										break
									end

									task.wait()

									-- Teleport to target
									if tRoot.Position.Y <= -12 then
										if Hub.canAffect(tRoot) then myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 5, -15)) end
									else
										if Hub.canAffect(tRoot) then myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, -10, -10)) end
									end
									myRoot.Velocity = Vector3.zero

									-- Apply death state
									if Hub.canAffect(tHum) then tHum.BreakJointsOnDeath = false end
									if Hub.canAffect(tHum) then tHum:ChangeState(Enum.HumanoidStateType.Dead) end
									if Hub.canAffect(tHum) then tHum.Jump = true end
									if Hub.canAffect(tHum) then tHum.Sit = false end
								end

								task.wait()
							end
						end

						if myRoot then
							restoreCollision()
							myRoot.CFrame = currentPos
							myRoot.Velocity = Vector3.zero
						end
					end

					task.wait(5)
				end

				restoreCollision()
				local char = Player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart")
				if root then root.Velocity = Vector3.zero end
			end)
		else
			loopKillEnabledAll = false
		end
	end
})

TargetGroup:AddToggle("LoopKickToggle2", {
	Text = "Loop Kick (grab + blob)",
	Default = false,
	Callback = function(on)
		kickLoopEnabled = on
		Hub.requestSave()

		local target = SelectedPlayer
		while on and not target do
			task.wait(0.5)
			target = SelectedPlayer
		end

		local char = Player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local seat = hum and hum.SeatPart

		if not on then 
			kickLoopEnabled = false 
			return 
		end

		if spawnedInToysFolder and spawnedInToysFolder:FindFirstChild("CreatureBlob") then
			notify("No blob found!","Spawning blob!")
		else
			autoblob()
		end

		task.spawn(function()
			local RS = ReplicatedStorage
			local GE = RS:WaitForChild("GrabEvents")
			local RunService = game:GetService("RunService")

			local blob = seat.Parent
			local blobRoot = blob:FindFirstChild("HumanoidRootPart") or blob.PrimaryPart
			local scriptObj = blob:FindFirstChild("BlobmanSeatAndOwnerScript")

			local CG = scriptObj and scriptObj:FindFirstChild("CreatureGrab")
			local CD = scriptObj and scriptObj:FindFirstChild("CreatureDrop")

			local R_Det = blob:FindFirstChild("RightDetector")
			local R_Weld = R_Det and (R_Det:FindFirstChild("RightWeld") or R_Det:FindFirstChildWhichIsA("Weld"))

			local SavedPos = blobRoot.CFrame 

			local tChar = Hub.canHarm(target) and target.Character or nil
			local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")

			if tRoot and blobRoot then
				local bringStart = tick()
				while tick() - bringStart < 0.35 do
					if not kickLoopEnabled then break end

					if Hub.canAffect(tRoot) then blobRoot.CFrame = tRoot.CFrame end
					blobRoot.Velocity = Vector3.zero

					pcall(function()
						if CG and R_Det then Hub.fire(CG, R_Det, tRoot, R_Weld) end
						Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
						Hub.fire(GE.SetNetworkOwner, tRoot, blobRoot.CFrame)
					end)
					RunService.Heartbeat:Wait()
				end

				blobRoot.CFrame = SavedPos
				blobRoot.Velocity = Vector3.zero
				task.wait(0.05)
			end

			local packetTimer = 0

			while kickLoopEnabled do
				if not Hub.canHarm(target) or not target.Character then
					task.wait(0.5)
					target = SelectedPlayer
				end

				local tChar = Hub.canHarm(target) and target.Character or nil
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
				local tHum = tChar and tChar:FindFirstChild("Humanoid")

				if tRoot and tHum and tHum.Health > 0 and blobRoot then

					blobRoot.CFrame = SavedPos
					blobRoot.Velocity = Vector3.zero

					local lockPos = SavedPos * CFrame.new(0, 23, 0)

					if Hub.canAffect(tRoot) then tRoot.CFrame = lockPos end
					if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end
					if Hub.canAffect(tRoot) then tRoot.RotVelocity = Vector3.zero end

					if tick() - packetTimer > 0.05 then
						packetTimer = tick()
						pcall(function()
							if Hub.canAffect(tHum) then tHum.PlatformStand = true end
							if Hub.canAffect(tHum) then tHum.Sit = true end

							Hub.fire(GE.SetNetworkOwner, tRoot, lockPos)

							if R_Det then
								local weld = R_Det:FindFirstChild("RightWeld") or R_Det:FindFirstChildWhichIsA("Weld")
								if weld then Hub.fire(CD, weld) end
							end
							Hub.fire(GE.DestroyGrabLine, tRoot)

							if R_Det then Hub.fire(CG, R_Det, tRoot, R_Weld) end
							Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
						end)
					end
				else
					blobRoot.CFrame = SavedPos
					blobRoot.Velocity = Vector3.zero
				end

				if not kickLoopEnabled then break end
				RunService.Heartbeat:Wait()
			end

			kickLoopEnabled = false
			if Toggles.LoopKickToggle2 then Toggles.LoopKickToggle2:SetValue(false) end

			if blobRoot then
				blobRoot.CFrame = SavedPos
				blobRoot.Velocity = Vector3.zero
			end
		end)
	end
})

local loopKickDualActive = false
TargetGroup:AddToggle("DualHandLoopKick", {
	Text = "Loop Kick",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		loopKickDualActive = on
		if on then
			if not Hub.canHarm(SelectedPlayer) then 
				notify("Error", "Select target first", 3)
				Toggles.DualHandLoopKick:SetValue(false)
				return 
			end
			if spawnedInToysFolder and spawnedInToysFolder:FindFirstChild("CreatureBlob") then
				notify("No blob found!","Spawning blob!")
			else
				autoblob()
			end
			task.spawn(function()
				local lastTargetCharDual = nil
				local bp = nil

				while loopKickDualActive do
					local target = SelectedPlayer
					local char = Player.Character
					local hum = char and char:FindFirstChild("Humanoid")
					local seat = hum and hum.SeatPart

					if not seat or not target or not target.Parent then
						task.wait(0.5)
						continue
					end

					local seatParent = seat.Parent
					local grab = seatParent:FindFirstChild("BlobmanSeatAndOwnerScript") and seatParent.BlobmanSeatAndOwnerScript:FindFirstChild("CreatureGrab")
					local drop = seatParent:FindFirstChild("BlobmanSeatAndOwnerScript") and seatParent.BlobmanSeatAndOwnerScript:FindFirstChild("CreatureDrop")

					if not grab or not drop then task.wait(0.5) continue end

					local leftDet = seatParent:FindFirstChild("LeftDetector")
					local rightDet = seatParent:FindFirstChild("RightDetector")
					local leftWeld = leftDet and leftDet:FindFirstChild("LeftWeld")
					local rightWeld = rightDet and rightDet:FindFirstChild("RightWeld")

					local hrp = char:FindFirstChild("HumanoidRootPart")

					local targetChar = Hub.canHarm(target) and target.Character or nil
					local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
					local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

					if targetHRP and targetHum and targetHum.Health > 0 then
						if targetChar ~= lastTargetCharDual then
							lastTargetCharDual = targetChar
							if bp then bp:Destroy() bp = nil end
							if hrp then hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 25, 0) end
							task.wait(0.2)
							Hub.fire(grab, leftDet, targetHRP, leftWeld)
							task.wait(0.3)
							Hub.fire(drop, leftWeld, targetHRP)
							task.wait(0.1)
							bp = Hub.new("BodyPosition")
							bp.Position = Vector3.new(0, 999999, 0)
							bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
							bp.Parent = targetHRP
							Hub.fire(grab, leftDet, targetHRP, leftWeld)
							task.wait(0.2)
							Hub.fire(drop, leftWeld, targetHRP)
						end

						Hub.fire(grab, leftDet, targetHRP, leftWeld)
						task.wait()
						Hub.fire(drop, leftWeld, targetHRP)
						task.wait()
						Hub.fire(grab, rightDet, targetHRP, rightWeld)
						task.wait()
						Hub.fire(drop, rightWeld, targetHRP)
						task.wait()
						Hub.fire(grab, leftDet, targetHRP, leftWeld)
						Hub.fire(grab, rightDet, targetHRP, rightWeld)
						task.wait()
						Hub.fire(drop, leftWeld, targetHRP)
						Hub.fire(drop, rightWeld, targetHRP)
						task.wait()
					else
						task.wait(0.1)
					end
				end
				if bp then bp:Destroy() end
			end)
		else
			loopKickDualActive = false
		end
	end
})

-- Player Fling
local playerFlingActive = false
local flingBAV = nil
local originalPos = nil

TargetGroup:AddToggle("PlayerFlingBtn", {
	Text = "Fling",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		playerFlingActive = on

		if on then
			if not SelectedPlayer then
				notify("System", "Select target first!", 3)
				Toggles.PlayerFlingBtn:SetValue(false)
				return
			end

			local RunService = game:GetService("RunService")
			local MyChar = Player.Character
			local MyRoot = MyChar and MyChar:FindFirstChild("HumanoidRootPart")

			if MyRoot then originalPos = MyRoot.CFrame end

			notify("Maestro", "Fling Mode Activated. DO NOT MOVE.", 3)

			task.spawn(function()
				while playerFlingActive do
					local target = SelectedPlayer

					local char = Player.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					local hum = char and char:FindFirstChild("Humanoid")

					if not hrp or not hum then 
						task.wait(0.5) 
						continue 
					end

					if target and target.Parent then
						local tChar = Hub.canHarm(target) and target.Character or nil
						local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
						local tHum = tChar and tChar:FindFirstChild("Humanoid")

						if tRoot and tHum and tHum.Health > 0 then
							if not flingBAV or flingBAV.Parent ~= hrp then
								if flingBAV then flingBAV:Destroy() end
								flingBAV = Hub.new("BodyAngularVelocity")
								flingBAV.Name = "MaestroSpin"
								flingBAV.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
								flingBAV.AngularVelocity = Vector3.new(0, 10000, 0)
								flingBAV.P = 10000
								flingBAV.Parent = hrp
                            Hub.assetTargets[flingBAV] = tRoot
							end

							for _, part in pairs(char:GetDescendants()) do
								if part:IsA("BasePart") then
									if Hub.canAffect(part) then part.CanCollide = false end
								end
							end

							local loop = Hub.connect(RunService.Heartbeat, function()
								if not playerFlingActive or not Hub.canHarm(target) or not tRoot or not tRoot.Parent then return end
								if Hub.canAffect(tRoot) then hrp.CFrame = tRoot.CFrame end
								hrp.Velocity = Vector3.zero 
							end)

							local startTime = tick()
							while tick() - startTime < 1.5 do
								if not playerFlingActive or not Hub.canHarm(target) or not tRoot.Parent then break end
								task.wait(0.1)
							end

							if loop then loop:Disconnect() end
						else
							task.wait(0.2)
						end
					else
						playerFlingActive = false
						Toggles.PlayerFlingBtn:SetValue(false)
					end

					task.wait(0.1)
				end

				if flingBAV then flingBAV:Destroy() flingBAV = nil end

				local char = Player.Character
				if char then
					for _, part in pairs(char:GetDescendants()) do
						if part:IsA("BasePart") then
							if Hub.canAffect(part) then part.CanCollide = true end
						end
					end
					local hrp = char:FindFirstChild("HumanoidRootPart")
					if hrp then
						hrp.RotVelocity = Vector3.zero
						hrp.Velocity = Vector3.zero
						if originalPos then hrp.CFrame = originalPos end
					end
				end
			end)
		else
			playerFlingActive = false
			if flingBAV then flingBAV:Destroy() flingBAV = nil end

			local char = Player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				hrp.RotVelocity = Vector3.zero
				hrp.Velocity = Vector3.zero
			end
		end
	end
})

-- Blobman Controls
_G.AutoSitBlobZ = true
BlobGroup:AddToggle("AutoSitZ", {
	Text = "Auto Sit Blobman [B]",
	Default = true,
	Callback = function(Value)
		_G.AutoSitBlobZ = Value
	end
})

Hub.connect(UserInputService.InputBegan, function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B and _G.AutoSitBlobZ then
		local plr = Player
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		local hum = char and char:FindFirstChild("Humanoid")

		if not hrp or not hum then return end

		local folderName = plr.Name .. "SpawnedInToys"
		local folder = workspace:FindFirstChild(folderName)
		local blob = folder and folder:FindFirstChild("CreatureBlobman")

		if not blob then
			task.spawn(function()
				pcall(function()
					Hub.invoke(ReplicatedStorage.MenuToys.SpawnToyRemoteFunction, "CreatureBlobman", hrp.CFrame, Vector3.zero)
				end)
			end)

			if not folder then
				folder = workspace:WaitForChild(folderName, 5)
			end

			if folder then
				blob = folder:WaitForChild("CreatureBlobman", 5)
			end
		end

		if blob then
			local seat = blob:WaitForChild("VehicleSeat", 5)
			if seat then
				local t = tick()
				repeat
					if not hum.SeatPart then
						hrp.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
						hrp.Velocity = Vector3.zero
						seat:Sit(hum)
					end
					RunService.Heartbeat:Wait()
				until hum.SeatPart == seat or tick() - t > 1.5
			end
		end
	end
end)

-- Blob Fly System
local blobMasterSwitch = true
local blobFlyActive = false
local blobFlySpeed = 50
local bvInstance, bgInstance

Hub.connect(UserInputService.InputBegan, function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.R then
		if blobMasterSwitch then
			blobFlyActive = not blobFlyActive
			if not blobFlyActive then
				if bvInstance then bvInstance:Destroy() bvInstance = nil end
				if bgInstance then bgInstance:Destroy() bgInstance = nil end
			end
		end
	end
end)

local function GetBlobRoot()
	local char = Player.Character
	local hum = char and char:FindFirstChild("Humanoid")

	if hum and hum.SeatPart and hum.SeatPart.Parent and hum.SeatPart.Parent.Name == "CreatureBlobman" then
		return hum.SeatPart.Parent:FindFirstChild("HumanoidRootPart") or hum.SeatPart.Parent.PrimaryPart
	end

	local folder = workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
	if folder then
		local blob = folder:FindFirstChild("CreatureBlobman")
		if blob then
			return blob:FindFirstChild("HumanoidRootPart") or blob.PrimaryPart
		end
	end

	return nil
end

Hub.connect(RunService.Heartbeat, function()
	if not blobFlyActive or not blobMasterSwitch then 
		if bvInstance then bvInstance:Destroy() bvInstance = nil end
		if bgInstance then bgInstance:Destroy() bgInstance = nil end
		return 
	end

	local root = GetBlobRoot()
	if root then
		if not root:FindFirstChild("BlobFlyVelocity") then
			bvInstance = Hub.new("BodyVelocity")
			bvInstance.Name = "BlobFlyVelocity"
			bvInstance.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bvInstance.P = 10000
			bvInstance.Parent = root
		else
			bvInstance = root.BlobFlyVelocity
		end

		if not root:FindFirstChild("BlobFlyGyro") then
			bgInstance = Hub.new("BodyGyro")
			bgInstance.Name = "BlobFlyGyro"
			bgInstance.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
			bgInstance.P = 20000
			bgInstance.D = 100
			bgInstance.Parent = root
		else
			bgInstance = root.BlobFlyGyro
		end

		local cam = workspace.CurrentCamera
		local moveDir = Vector3.zero

		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - cam.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + cam.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0, 1, 0) end

		if bvInstance then 
			bvInstance.Velocity = moveDir * blobFlySpeed 
		end

		if bgInstance then 
			bgInstance.CFrame = cam.CFrame 
		end
	else
		if bvInstance then bvInstance:Destroy() bvInstance = nil end
		if bgInstance then bgInstance:Destroy() bgInstance = nil end
	end
end)

-- Destroy Target Gucci
local DestroyTargetGucciActive = false
TargetGroup:AddToggle("DestroyTargetGucci", {
	Text = "Destroy Gucci (sit)",
	Default = false,
	Callback = function(Value)
		DestroyTargetGucciActive = Value

		if Value then
			if not SelectedPlayer then
				notify("Error", "Select a target", 3)
				Toggles.DestroyTargetGucci:SetValue(false)
				return
			end

			local char = Player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end

			local SafeSpot = root.CFrame
			local RunService = game:GetService("RunService")

			local folderName = SelectedPlayer.Name .. "SpawnedInToys"
			notify("System", "Awaiting folder " .. folderName, 3)

			task.spawn(function()
				while DestroyTargetGucciActive do
					if not Hub.canHarm(SelectedPlayer) then
						notify("System", "Player left", 3)
						DestroyTargetGucciActive = false
						Toggles.DestroyTargetGucci:SetValue(false)
						break
					end

					local toysFolder = workspace:FindFirstChild(folderName)

					if not toysFolder then
						task.wait(1)
					else
						local foundBlob = false

						for _, obj in ipairs(toysFolder:GetChildren()) do
							if not DestroyTargetGucciActive or not Hub.canAffect(toysFolder) then break end

							if obj.Name == "CreatureBlobman" then
								foundBlob = true
								local seat = obj:FindFirstChild("VehicleSeat") or obj:FindFirstChildWhichIsA("VehicleSeat", true)

								if seat and Hub.canAffect(seat) then
									local myChar = Player.Character
									local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
									local myHum = myChar and myChar:FindFirstChild("Humanoid")

									if myRoot and myHum then
										if myHum.SeatPart ~= seat then
											notify("Target", "Reset", 1)

											local magnetConnection
											magnetConnection = Hub.connect(RunService.Stepped, function()
												if myRoot and seat and Hub.canAffect(seat) then
													myRoot.CFrame = seat.CFrame
													myRoot.Velocity = Vector3.zero
													if obj.PrimaryPart then
														obj.PrimaryPart.Velocity = Vector3.zero
														obj.PrimaryPart.RotVelocity = Vector3.zero
													end
												end
											end)

											local sitStart = tick()
											while tick() - sitStart < 1 do
												if not DestroyTargetGucciActive or not Hub.canAffect(toysFolder) then break end
												if myHum.SeatPart == seat then break end

												if Hub.canAffect(seat) then seat:Sit(myHum) end
												task.wait()
											end

											if magnetConnection then magnetConnection:Disconnect() end

											if myHum.SeatPart == seat then
												task.wait(0.3) 
												myHum.Sit = false
												myHum.Jump = true

												task.wait(0.05)
												myRoot.CFrame = SafeSpot
												myRoot.Velocity = Vector3.zero

												notify("Success", "Removal complete", 1)
												task.wait(0.5)
											else
												myRoot.CFrame = SafeSpot
											end
										end
									end
								end
							end
						end
					end
					task.wait(1)
				end
			end)
		else
			DestroyTargetGucciActive = false
			notify("System", "Gucci disabled", 2)
		end
	end
})

-- Target Buttons
TargetGroup:AddButton({
	Text = "bring (blob)",
	Func = function()
		if not Hub.canHarm(SelectedPlayer) then return end

		local char = Player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local seat = hum and hum.SeatPart

		if spawnedInToysFolder and spawnedInToysFolder:FindFirstChild("CreatureBlob") then
			notify("No blob found!","Spawning blob!")
		else
			autoblob()
		end

		if not seat or seat.Parent.Name ~= "CreatureBlobman" then return end

		local blob = seat.Parent
		local blobRoot = blob:FindFirstChild("HumanoidRootPart")
		local scriptObj = blob:FindFirstChild("BlobmanSeatAndOwnerScript")
		if not blobRoot or not scriptObj then return end

		local CG = scriptObj:FindFirstChild("CreatureGrab")
		local CD = scriptObj:FindFirstChild("CreatureDrop")
		local R_Det = blob:FindFirstChild("RightDetector")
		local R_Weld = R_Det and R_Det:FindFirstChild("RightWeld")

		local tChar = Hub.canHarm(SelectedPlayer) and SelectedPlayer.Character or nil
		local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if not tRoot then return end

		local home = blobRoot.CFrame
		if Hub.canAffect(tRoot) then blobRoot.CFrame = tRoot.CFrame end
		blobRoot.Velocity = Vector3.new()
		blobRoot.RotVelocity = Vector3.new()
		task.wait(0.3)

		pcall(function()
			Hub.fire(CG, R_Det, tRoot, R_Weld)
		end)

		task.wait(0.5)
		blobRoot.CFrame = home
		blobRoot.Velocity = Vector3.new()
		blobRoot.RotVelocity = Vector3.new()
		task.wait(0.05)

		for i = 1, 12 do
			if Hub.canAffect(tRoot) then tRoot.CFrame = home * CFrame.new(0,3,0) end
			if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.new() end
			if Hub.canAffect(tRoot) then tRoot.RotVelocity = Vector3.new() end
			task.wait(0.03)
		end

		for i = 1, 8 do
			local weld = R_Det:FindFirstChild("RightWeld")
			if weld then
				pcall(function()
					Hub.fire(CD, weld)
				end)
			end
			task.wait(0.03)
		end
	end
})

TargetGroup:AddButton({
	Text = "Bring All (grab)",
	Func = function()
		task.spawn(function()
			local RS = ReplicatedStorage
			local RunService = game:GetService("RunService")
			local Players = game:GetService("Players")
			local GE = RS:WaitForChild("GrabEvents")
			local myChar = Player.Character
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myRoot then return end

			local savedPos = myRoot.CFrame
			local lockOffset = CFrame.new(0, 17, 0)

			-- Process ALL players at once
			local coroutines = {}
			for _, target in ipairs(Players:GetPlayers()) do
				if not Hub.canHarm(target) then continue end

				local inPlot = target:FindFirstChild("InPlot")
				if inPlot and inPlot.Value == true then continue end

				local tChar = Hub.canHarm(target) and target.Character or nil
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
				local tHum = tChar and tChar:FindFirstChild("Humanoid")

				if tRoot and tHum and tHum.Health > 0 then
					-- Create a coroutine for each player
					table.insert(coroutines, coroutine.create(function()
						local dragging = false
						local grabStartTime = 0
						local start = tick()

						while Hub.canHarm(target) and tRoot.Parent and tHum.Health > 0 and tick() - start < 0.9 do
							if Hub.canAffect(tRoot) then tRoot.AssemblyLinearVelocity = Vector3.zero end
							if Hub.canAffect(tRoot) then tRoot.AssemblyAngularVelocity = Vector3.zero end
							if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end

							if not dragging then
								if Hub.canAffect(tRoot) then myRoot.CFrame = tRoot.CFrame end
								myRoot.Velocity = Vector3.zero
								pcall(function()
									if Hub.canAffect(tHum) then tHum.PlatformStand = true end
									if Hub.canAffect(tHum) then tHum.Sit = true end
									Hub.fire(GE.SetNetworkOwner, tRoot, CFrame.new(myRoot.Position, tRoot.Position))
									Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
								end)

								if grabStartTime == 0 then
									grabStartTime = tick()
								end
								if tick() - grabStartTime > 0.35 then
									dragging = true
									grabStartTime = 0
								end
							else
								myRoot.CFrame = savedPos
								myRoot.Velocity = Vector3.zero
								local lockPos = savedPos * lockOffset
								if Hub.canAffect(tRoot) then tRoot.CFrame = lockPos end
								if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end
								if Hub.canAffect(tRoot) then tRoot.RotVelocity = Vector3.zero end
								if Hub.canAffect(tHum) then tHum.PlatformStand = true end
								if Hub.canAffect(tHum) then tHum.Sit = false end
								pcall(function()
									Hub.fire(GE.SetNetworkOwner, tRoot, lockPos)
									Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
								end)
							end

							coroutine.yield()
						end

						pcall(function()
							if Hub.canAffect(tHum) then tHum.PlatformStand = false end
							if Hub.canAffect(tHum) then tHum.Sit = false end
							Hub.fire(GE.DestroyGrabLine, tRoot)
						end)
					end))
				end
			end

			-- Run all coroutines simultaneously each frame
			while #coroutines > 0 do
				for i = #coroutines, 1, -1 do
					local success, err = coroutine.resume(coroutines[i])
					if coroutine.status(coroutines[i]) == "dead" then
						table.remove(coroutines, i)
					end
				end
				RunService.Heartbeat:Wait()
			end

			-- Return to original position
			if myRoot then
				myRoot.CFrame = savedPos
				myRoot.Velocity = Vector3.zero
			end
		end)
	end
})

TargetGroup:AddButton({
	Text = "Bring (grab)",
	Func = function()
		task.spawn(function()
			local target = SelectedPlayer
			if not target then return end

			local inPlot = target:FindFirstChild("InPlot")
			if inPlot and inPlot.Value == true then
				return
			end

			local RS = ReplicatedStorage
			local RunService = game:GetService("RunService")
			local GE = RS:WaitForChild("GrabEvents")

			local myChar = Player.Character
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myRoot then return end

			local tChar = Hub.canHarm(target) and target.Character or nil
			local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
			local tHum = tChar and tChar:FindFirstChild("Humanoid")
			if not (tRoot and tHum and tHum.Health > 0) then return end

			local savedPos = myRoot.CFrame
			local dragging = false
			local grabStartTime = 0

			local start = tick()
			while Hub.canHarm(target) and tRoot.Parent and tHum.Health > 0 and tick() - start < 0.9 do
				if Hub.canAffect(tRoot) then tRoot.AssemblyLinearVelocity = Vector3.zero end
				if Hub.canAffect(tRoot) then tRoot.AssemblyAngularVelocity = Vector3.zero end
				if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end

				if not dragging then
					if Hub.canAffect(tRoot) then myRoot.CFrame = tRoot.CFrame end
					myRoot.Velocity = Vector3.zero

					pcall(function()
						if Hub.canAffect(tHum) then tHum.PlatformStand = true end
						if Hub.canAffect(tHum) then tHum.Sit = true end
						Hub.fire(GE.SetNetworkOwner, tRoot, CFrame.new(myRoot.Position, tRoot.Position))
						Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
					end)

					if grabStartTime == 0 then
						grabStartTime = tick()
					end

					if tick() - grabStartTime > 0.35 then
						dragging = true
						grabStartTime = 0
					end
				else
					myRoot.CFrame = savedPos
					myRoot.Velocity = Vector3.zero

					local lockPos = savedPos * CFrame.new(0, 17, 0)

					if Hub.canAffect(tRoot) then tRoot.CFrame = lockPos end
					if Hub.canAffect(tRoot) then tRoot.Velocity = Vector3.zero end
					if Hub.canAffect(tRoot) then tRoot.RotVelocity = Vector3.zero end

					if Hub.canAffect(tHum) then tHum.PlatformStand = true end
					if Hub.canAffect(tHum) then tHum.Sit = false end

					pcall(function()
						Hub.fire(GE.SetNetworkOwner, tRoot, lockPos)
						Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
					end)
				end

				RunService.Heartbeat:Wait()
			end

			pcall(function()
				if Hub.canAffect(tHum) then tHum.PlatformStand = false end
				if Hub.canAffect(tHum) then tHum.Sit = false end
				Hub.fire(GE.DestroyGrabLine, tRoot)
			end)

			if myRoot then
				myRoot.CFrame = savedPos
				myRoot.Velocity = Vector3.zero
			end
		end)
	end
})

-- Anti Anti-Kick
local antiAntiKickActive = false
TargetGroup:AddToggle("DestroyAntiKickToggle", {
	Text = "Grab Anti Kick",
	Default = false,
	Callback = function(Value)
		antiAntiKickActive = Value

		if Value then
			task.spawn(function()
				local SetNetOwner = ReplicatedStorage.GrabEvents.SetNetworkOwner

				local function invis_touch(part, cf)
					Hub.fire(SetNetOwner, part, cf)
				end

				local function CheckAndYeet(toy)
                    if not Hub.canAffect(toy) then return end
					local part = toy:FindFirstChild("SoundPart")
					if part then
						invis_touch(part, part.CFrame)
						if Hub.canAffect(part) and part:FindFirstChild("PartOwner") and part.PartOwner.Value == Player.Name then
							if Hub.canAffect(part) then part.CFrame = CFrame.new(0, 1000, 0) end
						end
					end
				end

				while antiAntiKickActive do
					local target = SelectedPlayer
					if Hub.canHarm(target) then
						local spawned = workspace:FindFirstChild(target.Name.."SpawnedInToys")
						if spawned then
							if spawned:FindFirstChild("NinjaKunai") then
								CheckAndYeet(spawned.NinjaKunai)
							end
							if spawned:FindFirstChild("NinjaShuriken") then
								CheckAndYeet(spawned.NinjaShuriken)
							end
							if spawned:FindFirstChild("AntiKick") then
								CheckAndYeet(spawned.AntiKick)
							end
						end
					end
					task.wait(0.1)
				end
			end)
		else
			antiAntiKickActive = false
		end
	end
})

-- Anti Anti Input Lag
local antiAntiLagEnabled = false
TargetGroup:AddToggle("AntiAntiInputLag", {
	Text = "Anti Anti Input Lag",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		antiAntiLagEnabled = on

		if not on then
			antiAntiLagEnabled = false
			return
		end

		task.spawn(function()
			local plr = Player
			local char = plr.Character
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end

			local burgers = {}

			for _, v in ipairs(workspace:GetDescendants()) do
				if v.Name == "FoodHamburger" and v:IsA("Model") and v:FindFirstChild("HoldPart") then
					burgers[#burgers+1] = v
				end
			end

			Hub.connect(workspace.DescendantAdded, function(obj)
				if obj.Name == "FoodHamburger" and obj:IsA("Model") then
					task.spawn(function()
						local hp = obj:WaitForChild("HoldPart", 3)
						if hp then
							burgers[#burgers+1] = obj
						end
					end)
				end
			end)

			while antiAntiLagEnabled do
				for i = #burgers, 1, -1 do
					local b = burgers[i]
					if not b or not b.Parent or not b:FindFirstChild("HoldPart") then
						table.remove(burgers, i)
					else
						if not Hub.canAffect(b) then continue end
                        local hp = b.HoldPart

						pcall(function()
							Hub.invoke(hp.HoldItemRemoteFunction, b, char)
						end)

						task.wait()

						pcall(function()
							Hub.invoke(hp.DropItemRemoteFunction, b, CFrame.new(hrp.Position + Vector3.new(0,-2000,0)), Vector3.new(0,0,0))
						end)
					end
				end

				task.wait()
			end
		end)
	end
})

-- Whitelist System: selected players are protected, never automatically targeted.
do
local refreshing = false
local function labelFor(player)
    return player.DisplayName .. " (@" .. player.Name .. ") [" .. player.UserId .. "]"
end
local function valuesAndSelected()
    local values, selected, seen = {}, {}, {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= Player then
            local id = tostring(player.UserId)
            local label = labelFor(player)
            table.insert(values, label); seen[id] = true
            if Hub.manualWhitelist[id] or Hub.manualWhitelist["name:" .. player.Name:lower()] then
                Hub.manualWhitelist["name:" .. player.Name:lower()] = nil
                Hub.manualWhitelist[id] = label
                selected[label] = true
            end
        end
    end
    for id, label in pairs(Hub.manualWhitelist) do
        if not seen[id] then table.insert(values, label); selected[label] = true end
    end
    table.sort(values)
    return values, selected
end
local values, initial = valuesAndSelected()
refreshing = true
WhitelistGroup:AddDropdown("MultiWhitelist", {
    Values = values, Default = {}, Multi = true, Text = "Whitelist people (protected)",
    Callback = function(selection)
        if refreshing then return end
        local manual = {}
        for label, chosen in pairs(selection) do
            if chosen then
                local id = label:match("%[(%d+)%]$")
                local name = label:match("%(@?(.-)%)")
                local player = name and Players:FindFirstChild(name)
                if not id and player then id = tostring(player.UserId) end
                if id then manual[id] = label
                elseif name then manual["name:" .. name:lower()] = label end
            end
        end
        Hub.manualWhitelist = manual
        Hub.reconcileProtection()
        Hub.queueSafetySave()
        Hub.requestSave()
    end,
})
Hub.refreshWhitelistUI = function()
    local values, selected = valuesAndSelected()
    refreshing = true
    Options.MultiWhitelist:SetValues(values)
    Options.MultiWhitelist:SetValue(selected)
    refreshing = false
end
Hub.refreshWhitelistUI()
WhitelistGroup:AddToggle("WhitelistFriends", {
    Text = "Whitelist friends", Default = true,
    Callback = function(on)
        Hub.whitelistFriends = on
        table.clear(Hub.friendCache)
        Hub.reconcileProtection()
        if on then for _, player in ipairs(Players:GetPlayers()) do Hub.checkFriend(player) end end
        Hub.requestSave()
    end,
})
WhitelistGroup:AddButton({Text = "Refresh list / friend checks", Func = function()
    table.clear(Hub.friendCache)
    Hub.refreshWhitelistUI()
    if Hub.whitelistFriends then for _, player in ipairs(Players:GetPlayers()) do Hub.checkFriend(player) end end
end})
WhitelistGroup:AddLabel("Protected players are skipped by hub actions. Pending friend checks also block targeting.", true)
WhitelistGroup:AddLabel("Roblox may cache friendship results. Manual selections apply immediately.", true)
end

-- Joined Notify
local notifyActive = false
local notifyConnection = nil
WhitelistGroup:AddToggle("JoinedNotifyBtn", {
	Text = "Target Joined Notify",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		notifyActive = on

		if on then
			notify("Radar", "Tracking targets. Waiting for targets that have returned / re-entered…", 3)

			if notifyConnection then notifyConnection:Disconnect() end

			notifyConnection = Hub.connect(Players.PlayerAdded, function(newPlayer)
				if not notifyActive then return end

				local detected = false
				local reason = ""

                if Hub.isProtected(newPlayer) then detected = true; reason = "[Protected]" end

				if not detected and Options.KickPlayerDropdown and Options.KickPlayerDropdown.Value then
					local selection = Options.KickPlayerDropdown.Value
					local selectedName = selection:match("%((.-)%)")

					if selectedName and selectedName == newPlayer.Name then
						detected = true
						reason = "[Main Target]"
					end
				end

				if detected then
					notify("Target Returned!" .. reason .. " | Player: " .. newPlayer.Name, 8)
					if Hub.canHarm(newPlayer) then SelectedPlayer = newPlayer end
					local sound = Hub.new("Sound", workspace)
					sound.SoundId = "rbxassetid://4590662766"
					sound.Volume = 2
					sound:Play()
					Debris:AddItem(sound, 3)
				end
			end)
		else
			if notifyConnection then notifyConnection:Disconnect() notifyConnection = nil end
			notify("Radar", "Tracking Disabled", 2)
		end
	end
})

local respawnNotifyActive = false
local respawnConnections = {}

local function isTrackedPlayer(player)
    if Hub.isProtected(player) then return true, "[Protected]" end
    if Options.KickPlayerDropdown and Options.KickPlayerDropdown.Value then
        local name = Options.KickPlayerDropdown.Value:match("%((.-)%)")
        if name == player.Name then return true, "[Main Target]" end
    end
    return false, nil
end

local function trackRespawn(player)
	if respawnConnections[player] then return end

	respawnConnections[player] = Hub.connect(player.CharacterAdded, function()
		if not respawnNotifyActive then return end

		local tracked, reason = isTrackedPlayer(player)
		if not tracked then return end

		notify("Target Respawned! " .. reason .. " | Player: " .. player.Name, 8)
		if Hub.canHarm(player) then SelectedPlayer = player end

		local sound = Hub.new("Sound")
		sound.SoundId = "rbxassetid://4590662766"
		sound.Volume = 2
		sound.Parent = workspace
		sound:Play()
		Debris:AddItem(sound, 3)
	end)
end

WhitelistGroup:AddToggle("RespawnNotifyBtn", {
	Text = "Target Respawn Notify",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		respawnNotifyActive = on

		if on then
			notify("Radar", "Tracking target respawns…", 3)

			-- Hook all current players
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= Player then
					trackRespawn(plr)
				end
			end

			-- Hook new players too
			respawnConnections["_PlayerAdded"] = Hub.connect(Players.PlayerAdded, function(plr)
				trackRespawn(plr)
			end)
		else
			-- Cleanup
			for _, conn in pairs(respawnConnections) do
				pcall(function()
					conn:Disconnect()
				end)
			end
			respawnConnections = {}
			notify("Radar", "Respawn tracking disabled", 2)
		end
	end
})

local AuraGroup = Tabs.Aura:AddLeftGroupbox("Auras")

AuraGroup:AddToggle("Deathaura", {
	Text = "Death Aura",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		deathAuraEnabled = on
		if on then
			task.spawn(function()
				local RS = ReplicatedStorage
				local PS = Players
				local GE = RS:WaitForChild("GrabEvents")

				while deathAuraEnabled do
					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

					if myRoot then
						-- Find all players within 50 studs
						for _, target in pairs(PS:GetPlayers()) do
							if not deathAuraEnabled then break end
							if not Hub.canHarm(target) then continue end

							if not Hub.canHarm(target) or not target.Character then
								continue
							end

							local tChar = Hub.canHarm(target) and target.Character or nil
							local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
							local tHum = tChar and tChar:FindFirstChild("Humanoid")

							-- Check if player is within 50 studs and alive
							if tRoot and tHum and tHum.Health > 0 then
								local distance = (myRoot.Position - tRoot.Position).Magnitude

								if distance <= 50 then
									-- Death counter action
									local counterAction = function()
										if tHum and Hub.canHarm(target) then
											CreateSkyVelocity(tRoot)
											for _ = 0, 20 do
												if Hub.canAffect(tHum) then tHum.BreakJointsOnDeath = false end
												if Hub.canAffect(tHum) then tHum:ChangeState(Enum.HumanoidStateType.Dead) end
												if Hub.canAffect(tHum) then tHum.Jump = true end
												if Hub.canAffect(tHum) then tHum.Sit = true end
											end
											task.wait()
											Hub.fire(GE.DestroyGrabLine, tRoot)
										end
									end

									-- Execute SNOWship loop
									for _ = 1, 50 do
										if not deathAuraEnabled then break end
										if SNOWshipPlayer(target, counterAction) then
											break
										end
										task.wait()
									end

									task.wait(0.1) -- Small delay between targets
								end
							end
						end
					end

					task.wait(0.5) -- Check for new targets every 0.5 seconds
				end
			end)
		else
			deathAuraEnabled = false
		end
	end
})

-- Grab Tab
local GrabGroup = Tabs.Grab:AddLeftGroupbox("Grab Customization")

_G.strength = 750
local strengthConnection

GrabGroup:AddSlider("ThrowPowerSlider", {
	Text = "Power",
	Default = 750,
	Min = 1,
	Max = 20000,
	Rounding = 0,
	Callback = function(value)
		_G.strength = value
	end
})

GrabGroup:AddToggle("ThrowStrengthToggle", {
	Text = "Strength",
	Default = false,
	Callback = function(enabled)
		if enabled then
			strengthConnection = Hub.connect(workspace.ChildAdded, function(model)
				if model.Name == "GrabParts" then
					local grab = model:WaitForChild("GrabPart", 2)
                    local weld = grab and grab:WaitForChild("WeldConstraint", 2)
                    if not weld or not model.Parent then return end
                    local partToImpulse = weld.Part1
					if partToImpulse and Hub.canAffect(partToImpulse) then
						local velocityObj = Hub.new("BodyVelocity", partToImpulse)
                        velocityObj.MaxForce = Vector3.zero
						Hub.connect(model:GetPropertyChangedSignal("Parent"), function()
							if not model.Parent then
								if Hub.canAffect(partToImpulse) and UserInputService:GetLastInputType() == Enum.UserInputType.MouseButton2 then
									velocityObj.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
									velocityObj.Velocity = workspace.CurrentCamera.CFrame.LookVector * _G.strength
									game:GetService("Debris"):AddItem(velocityObj, 1)
								else
									velocityObj:Destroy()
								end
							end
						end)
					end
				end
			end)
		elseif strengthConnection then
			strengthConnection:Disconnect()
		end
	end
})

-- Noclip Grab
local noclipGrabEnabled = false
local noclipConnection

local function startNoclipGrab()
	if noclipConnection then return end

	noclipConnection = Hub.connect(workspace.ChildAdded, function(v)
		if not noclipGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local grabPart = v:FindFirstChild("GrabPart")
			local weld = grabPart and grabPart:FindFirstChild("WeldConstraint")
			local targetChar = weld and weld.Part1 and weld.Part1.Parent

			if not (grabPart and targetChar and targetChar:IsA("Model")) or not Hub.canAffect(targetChar) then
				return
			end

			local parts = {}
			local originalCollision = {}

			for _, d in ipairs(targetChar:GetDescendants()) do
				if d:IsA("BasePart") and not d.Anchored then
					table.insert(parts, d)
					originalCollision[d] = d.CanCollide
                    Hub.backup(d, {"CanCollide"})
				end
			end

			while noclipGrabEnabled and Hub.canAffect(targetChar) and grabPart.Parent do
				for _, part in ipairs(parts) do
					if part and part.Parent and not part.Anchored then
						if Hub.canAffect(part) then part.CanCollide = false end
					end
				end
				task.wait(0.2)
			end

			for part, state in pairs(originalCollision) do
				if part and part.Parent then
					if Hub.canAffect(part) then part.CanCollide = state end
                    Hub.propertyBackup[part] = nil
				end
			end
		end)
	end)
end

local function stopNoclipGrab()
	if noclipConnection then
		noclipConnection:Disconnect()
		noclipConnection = nil
	end
end

GrabGroup:AddToggle("NoclipGrabToggle", {
	Text = "Noclip Grab",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		noclipGrabEnabled = on
		if on then
			startNoclipGrab()
		else
			stopNoclipGrab()
		end
	end
})

-- Massless Grab
local masslessGrabEnabled = false
local masslessConnection

local function startMasslessGrab()
	if masslessConnection then return end

	masslessConnection = Hub.connect(workspace.ChildAdded, function(v)
		if not masslessGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local dragPart = v:FindFirstChild("DragPart1") or v:FindFirstChild("DragPart")
			for i = 1, 10 do
				dragPart = v:FindFirstChild("DragPart1") or v:FindFirstChild("DragPart")
				if dragPart then break end
				task.wait(0.05)
			end

			if not dragPart or not Hub.canAffect(v) then return end

			local alignOri = dragPart:FindFirstChild("AlignOrientation")
			local alignPos = dragPart:FindFirstChild("AlignPosition")
			if not (alignOri and alignPos) then return end

			Hub.backup(alignOri, {"MaxTorque", "Responsiveness"})
            Hub.backup(alignPos, {"MaxForce", "Responsiveness"})
            local oriTorque = alignOri.MaxTorque
			local oriOriResp = alignOri.Responsiveness
			local oriForce = alignPos.MaxForce
			local oriPosResp = alignPos.Responsiveness

			while masslessGrabEnabled and Hub.canAffect(v) and v.Parent do
				alignOri.MaxTorque = 1e9
				alignOri.Responsiveness = 200
				alignPos.MaxForce = 1e9
				alignPos.Responsiveness = 200
				task.wait(0.25)
			end

			if alignOri then
				alignOri.MaxTorque = oriTorque
				alignOri.Responsiveness = oriOriResp
			end
			if alignPos then
				alignPos.MaxForce = oriForce
				alignPos.Responsiveness = oriPosResp
			end
		end)
	end)
end

local function stopMasslessGrab()
	if masslessConnection then
		masslessConnection:Disconnect()
		masslessConnection = nil
	end
end

GrabGroup:AddToggle("MasslessGrabToggle", {
	Text = "Massless Grab",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		masslessGrabEnabled = on
		if on then
			startMasslessGrab()
		else
			stopMasslessGrab()
		end
	end
})


function IsMobile()
	if LocalPlayer.PlayerGui:FindFirstChild("ContextActionGui") then
		return true
	end
end

function GetPlayerCharacter()
	if LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")) then
		return LocalPlayer.Character
	end
end

do
local IncreaseLineExtend = 5
local LastSet = 5
local pcDistance = 11
local extendEnabled = false
local extendconnection
local extendGeneration = 0
local extendActive = {}
local function restoreExtend(model)
    local state = extendActive[model]
    if not state then return end
    pcall(function() state.original.Enabled = state.enabled end)
    pcall(function() state.clone:Destroy() end)
    extendActive[model] = nil
end
Hub.cleanup(function() for model in pairs(extendActive) do restoreExtend(model) end end)
Hub.connect(UserInputService.InputChanged, function(input)
    if not extendEnabled or UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        pcDistance = math.clamp(pcDistance + input.Position.Z * IncreaseLineExtend, 11, 1000)
    end
end)
local function extendGrab(model)
    if not extendEnabled or model.Name ~= "GrabParts" or not model:IsA("Model") then return end
    task.spawn(function()
        local generation = extendGeneration
        local drag = model:WaitForChild("DragPart", 2)
        local align = drag and drag:FindFirstChildOfClass("AlignPosition")
        if not Hub.canAffect(model) or not drag or not align or not extendEnabled or generation ~= extendGeneration or not model.Parent then return end
        local clone = drag:Clone()
        local cloneAlign = clone:FindFirstChildOfClass("AlignPosition")
        local attachment = clone:FindFirstChild("DragAttach")
        if not cloneAlign or not attachment then clone:Destroy(); return end
        clone.Name = "DragPart1"
        cloneAlign.Attachment1 = attachment
        cloneAlign.Enabled = true
        local orientation = clone:FindFirstChildOfClass("AlignOrientation")
        if orientation then orientation.Enabled = false end
        extendActive[model] = {original = align, enabled = align.Enabled, clone = clone}
        align.Enabled = false
        clone.Parent = model
        local cam = workspace.CurrentCamera
        if cam then pcDistance = math.clamp((clone.Position - cam.CFrame.Position).Magnitude, 11, 1000) end
        while extendEnabled and Hub.canAffect(model) and generation == extendGeneration and model.Parent and clone.Parent do
            cam = workspace.CurrentCamera
            if cam then clone.Position = cam.CFrame.Position + cam.CFrame.LookVector * pcDistance end
            RunService.Heartbeat:Wait()
        end
        restoreExtend(model)
    end)
end
GrabGroup:AddToggle("ExtendToggle", {Text = "Further Extend", Default = false,
    Callback = function(on)
        extendEnabled = on
        extendGeneration += 1
        if extendconnection then extendconnection:Disconnect(); extendconnection = nil end
        for model in pairs(extendActive) do restoreExtend(model) end
        if on then
            IncreaseLineExtend = LastSet
            extendconnection = Hub.connect(workspace.ChildAdded, extendGrab)
            local existing = workspace:FindFirstChild("GrabParts")
            if existing then extendGrab(existing) end
        end
        Hub.requestSave()
    end})
GrabGroup:AddSlider("extendvalue", {Text = "Extend Amount", Default = 5, Min = 1, Max = 100, Rounding = 0,
    Callback = function(value) LastSet = value; IncreaseLineExtend = value; Hub.requestSave() end})

end

-- Kill Grab
local killGrabEnabled = false
local grabConnection

local function startKillGrab()
	if grabConnection then return end

	grabConnection = Hub.connect(workspace.ChildAdded, function(v)
		if not killGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local grabPart = v:FindFirstChild("GrabPart")
			local weld = grabPart and grabPart:FindFirstChild("WeldConstraint")
			local targetChar = weld and weld.Part1 and weld.Part1.Parent

			if not (grabPart and targetChar and targetChar ~= Player.Character) or not Hub.canAffect(targetChar) then
				return
			end

			local hum = targetChar:FindFirstChildOfClass("Humanoid")
			local root = targetChar:FindFirstChild("HumanoidRootPart")
			local myRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")

			if not (hum and root and myRoot) then return end

			while killGrabEnabled and Hub.canAffect(targetChar) and grabPart.Parent and hum.Health > 0 do
				pcall(function()
					Hub.fire(ReplicatedStorage.GrabEvents.SetNetworkOwner, root, myRoot.CFrame)
					hum.BreakJointsOnDeath = false
					hum:ChangeState(Enum.HumanoidStateType.Dead)
					hum.Health = 0
					targetChar:BreakJoints()
				end)
				RunService.Heartbeat:Wait()
			end
		end)
	end)
end

local function stopKillGrab()
	if grabConnection then
		grabConnection:Disconnect()
		grabConnection = nil
	end
end

GrabGroup:AddToggle("KillGrabToggle", {
	Text = "Kill Grab",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		killGrabEnabled = on
		if on then
			startKillGrab()
		else
			stopKillGrab()
		end
	end
})

-- Misc Tab
local MiscGroup = Tabs.Misc:AddLeftGroupbox("Miscellaneous")
Hub.playerListOriginal = StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
Hub.cleanup(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, Hub.playerListOriginal) end)
local mouse = Player:GetMouse()
local tpToolConn

-- Click TP
MiscGroup:AddToggle("TPToggle", {
	Text = "Click TP (Z)",
	Default = false,
	Callback = function(Value)
		if Value then
			if tpToolConn then tpToolConn:Disconnect() end
			tpToolConn = Hub.connect(UserInputService.InputBegan, function(input, gameProcessed)
				if gameProcessed then return end
				if input.KeyCode == Enum.KeyCode.Z then
					local character = Player.Character
					if character and character:FindFirstChild("HumanoidRootPart") then
						local hrp = character.HumanoidRootPart
						local targetPos = mouse.Hit.Position
						hrp.Velocity = Vector3.zero
						hrp.CFrame = CFrame.new(targetPos + Vector3.new(0,3,0))
					end
				end
			end)
		else
			if tpToolConn then tpToolConn:Disconnect() tpToolConn = nil end
		end
	end
})

MiscGroup:AddToggle("PlayerList", {
	Text = "Playerlist Visible",
	Default = false,
	Callback = function(Value)
		if Value then
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,true)
		else
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,false)
		end
	end
})


local enabled = false
local freeMouseGui
local mouseOriginal
local function setFreeMouse(on)
    if on == enabled then return end
    enabled = on
    if on then
        mouseOriginal = {UserInputService.MouseBehavior, UserInputService.MouseIconEnabled}
        freeMouseGui = Hub.new("ScreenGui")
        freeMouseGui.Name = "ArrivaCoreMouseUnlock"
        freeMouseGui.ResetOnSpawn = false
        local button = Hub.new("TextButton")
        button.BackgroundTransparency = 1
        button.Size = UDim2.fromOffset(1, 1)
        button.Text = ""
        button.Modal = true
        button.Parent = freeMouseGui
        freeMouseGui.Parent = Player:FindFirstChildOfClass("PlayerGui")
        UserInputService.MouseBehavior = Enum.MouseBehavior.Default
        UserInputService.MouseIconEnabled = true
    else
        if freeMouseGui then freeMouseGui:Destroy(); freeMouseGui = nil end
        if mouseOriginal then
            UserInputService.MouseBehavior = mouseOriginal[1]
            UserInputService.MouseIconEnabled = mouseOriginal[2]
            mouseOriginal = nil
        end
    end
end
Hub.cleanup(function() setFreeMouse(false) end)
Hub.connect(UserInputService.InputBegan, function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.F then setFreeMouse(not enabled) end
end)

-- Water Walk
local waterParts = {}
task.spawn(function()
	if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("AlwaysHereTweenedObjects") then
		local ocean = workspace.Map.AlwaysHereTweenedObjects:FindFirstChild("Ocean")
        local object = ocean and ocean:FindFirstChild("Object")
        local oceanModel = object and object:FindFirstChild("ObjectModel")
        if not oceanModel then return end
		for _, v in pairs(oceanModel:GetChildren()) do
			if v:IsA("Part") or v:IsA("UnionOperation") or v:IsA("BasePart") or v:IsA("MeshPart") then
				table.insert(waterParts, {part = v, originalCollide = v.CanCollide})
			end
		end
	end
end)

MiscGroup:AddToggle("WaterWalkToggle", {
	Text = "water walk",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		for _, item in pairs(waterParts) do
			if item.part then item.part.CanCollide = on and true or item.originalCollide end
		end
	end
})

-- Triggerbot System
local Triggerbot = {
	Enabled = false,
	Connection = nil,
	canGrab = true,
	maxDistance = 20,
	preGrabDelay = 0.00001,
	postGrabDelay = 0.05, 
	lastTarget = nil,
	lastHitTime = 0,
	targetMemoryDuration = 0.1,
	checkThrottle = 0.008,
	lastCheck = 0
}

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

task.spawn(function()
	local success, result = pcall(function() return Hub.invoke(ReplicatedStorage.GamepassEvents.CheckForGamepass, 20837132) end)
	if success and result then Triggerbot.maxDistance = 29.3 end
end)

if ReplicatedStorage:FindFirstChild("GamepassEvents") and ReplicatedStorage.GamepassEvents:FindFirstChild("FurtherReachBoughtNotifier") then
	Hub.connect(ReplicatedStorage.GamepassEvents.FurtherReachBoughtNotifier.OnClientEvent, function() Triggerbot.maxDistance = 29.3 end)
end

function Triggerbot:GetTarget()
	local c = Player.Character
	if not c or not c:FindFirstChild("HumanoidRootPart") then return end
	if Workspace:FindFirstChild("GrabParts") then return end

	local origin, dir = Camera.CFrame.Position, Camera.CFrame.LookVector
	rayParams.FilterDescendantsInstances = { c, Workspace.Terrain }

	local result = Workspace:Raycast(origin, dir * 1000, rayParams)
	if not result then
		local dirs = { dir, (dir + Vector3.new(0, 0.075, 0)).Unit, (dir - Vector3.new(0, 0.075, 0)).Unit }
		for _, d in ipairs(dirs) do
			result = Workspace:Raycast(origin, d * 1000, rayParams)
			if result then break end
		end
	end

	if not result then return end
	local hit = result.Instance
	local model = hit:FindFirstAncestorOfClass("Model")
	if not model or not model:FindFirstChildOfClass("Humanoid") or model == c or not Hub.canAffect(model) then return end

	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum.Health <= 0 then return end

	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local dist = (c.HumanoidRootPart.Position - root.Position).Magnitude
	if dist > self.maxDistance then return end

	return model
end

function Triggerbot:OnHeartbeat()
	if not self.Enabled or not self.canGrab then return end
	if UserInputService:GetFocusedTextBox() then return end

	if tick() - self.lastCheck < self.checkThrottle then return end
	self.lastCheck = tick()

	local t = self:GetTarget()
	if t then 
		self.lastTarget = t 
		self.lastHitTime = tick()
	elseif self.lastTarget and tick() - self.lastHitTime > self.targetMemoryDuration then 
		self.lastTarget = nil 
	end

	local c = Player.Character
	local root = self.lastTarget and self.lastTarget:FindFirstChild("HumanoidRootPart")

	if not (self.lastTarget and c and c:FindFirstChild("HumanoidRootPart") and root) then return end

	if (c.HumanoidRootPart.Position - root.Position).Magnitude > self.maxDistance then 
		self.lastTarget = nil 
		return 
	end

	if self.lastTarget and Hub.canAffect(self.lastTarget) then
		self.canGrab = false
		task.spawn(function()
			task.wait(self.preGrabDelay)
			if self.Enabled and self.lastTarget and Hub.canAffect(self.lastTarget) then pcall(mouse1press) end
			local t0 = tick()
			repeat 
				task.wait(0.02) 
			until not Workspace:FindFirstChild("GrabParts") or tick() - t0 > 1.6
			task.wait(self.postGrabDelay)
			self.canGrab = true
			self.lastTarget = nil
		end)
	end
end

-- Network flooders intentionally excluded from this maintenance revision.

-- Auto Reset
local autoResetEnabled = false
MiscGroup:AddToggle("AutoResetToggle", {
	Text = "Auto Reset",
	Default = false,
	Callback = function(on)
		Hub.requestSave()
		autoResetEnabled = on

		if not on then
			autoResetEnabled = false
			return
		end

		task.spawn(function()
			local plr = Player
			while autoResetEnabled do
				local char = plr.Character
				local hum = char and char:FindFirstChild("Humanoid")

				if hum and hum.Health > 0 then
					hum.Health = 0
				end

				task.wait(0.5)
			end
		end)
	end
})

-- Triggerbot Toggle
MiscGroup:AddToggle("TriggerbotToggle", {
	Text = "Trigger Bot",
	Default = Triggerbot.Enabled,
	Callback = function(value)
		Hub.requestSave()
		Triggerbot.Enabled = value
		if Triggerbot.Enabled and not Triggerbot.Connection then
			Triggerbot.Connection = Hub.connect(RunService.Heartbeat, function() Triggerbot:OnHeartbeat() end)
		elseif not Triggerbot.Enabled and Triggerbot.Connection then
			Triggerbot.Connection:Disconnect() 
			Triggerbot.Connection = nil
		end
	end
})

-- FOV Slider
MiscGroup:AddSlider("FOVSlider", {
	Text = "FOV",
	Default = 90,
	Min = 1,
	Max = 120,
	Rounding = 0,
	Suffix = "°",
	Callback = function(value)
        local cam = workspace.CurrentCamera
        if cam then
            if Hub.cameraFOV[cam] == nil then Hub.cameraFOV[cam] = cam.FieldOfView end
            cam.FieldOfView = value
        end
        Hub.requestSave()
    end
})

do
-- Black Hole Detection
local variants = {
	"BlackHole",
	"Black_Hole",
	"Blackhole",
	"Black-Hole",
	"BHole",
	"BH",
	"VoidHole",
	"Void",
	"VoidSphere",
	"DarkHole",
	"DarkSphere",
	"DarkOrb",
	"GravityHole",
	"GravityOrb",
	"SpaceHole",
	"SpaceOrb",
	"Singularity",
	"SingularityOrb",
	"EventHorizon",
	"BlackSphere",
	"Anomaly",
	"AnomalyHole",
	"SupermassiveHole",
	"QuantumHole"
}

local function isBlackHole(obj)
	local name = obj.Name:lower()
	for _, v in ipairs(variants) do
		if name:find(v:lower(), 1, true) then
			return true
		end
	end
	return false
end

local function getBHPosition(obj)
	if obj:IsA("BasePart") then 
		return obj.Position 
	end
	local part = obj:FindFirstChildWhichIsA("BasePart", true)
	if part then 
		return part.Position 
	end
	return nil
end

local function getClosestPlayer(pos)
	local closest = nil
	local dist = math.huge
	for _, plr in pairs(Players:GetPlayers()) do
		if plr ~= Player then
			local char = plr.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local d = (hrp.Position - pos).Magnitude
				if d < dist then
					dist = d
					closest = plr.Name
				end
			end
		end
	end
	return closest or "Unknown"
end

Hub.connect(workspace.ChildAdded, function(obj)
	task.wait(0.1)
	if isBlackHole(obj) then
		local pos = getBHPosition(obj)
		if not pos then 
			notify("Error", "Black hole position not found!", 3) 
			return 
		end
		local closest = getClosestPlayer(pos)
		notify("Black Hole Alert", closest .. " is nearest; source is unconfirmed.", 5)
	end
end)

for _, obj in pairs(workspace:GetChildren()) do
	if isBlackHole(obj) then
		local pos = getBHPosition(obj)
		if pos then
			local closest = getClosestPlayer(pos)
			notify("Black Hole Detected", closest .. " is nearest!", 5)
		end
	end
end

end

-- Anchor Object
MiscGroup:AddLabel("Anchor Object Bind"):AddKeyPicker("AnchorObjectKey", {
	Default = "G",
	Text = "Anchor Object",
	NoUI = false,
	Callback = function()
		local original = workspace:FindFirstChild("GrabParts")
		if not original then return end

		local grabPart = original:FindFirstChild("GrabPart", true)
		if not grabPart or not grabPart:IsA("BasePart") then return end

		local wasCollide = grabPart.CanCollide
		grabPart.CanCollide = true
		task.wait(0.1)

		local targetModel = nil
		local touchingParts = grabPart:GetTouchingParts()

		if #touchingParts == 0 then
			grabPart.CanCollide = wasCollide
			return
		end

		for _, part in ipairs(touchingParts) do
			if not part:IsDescendantOf(original) then
				local current = part
				while current and current ~= workspace do
					if current:IsA("Model") then
						targetModel = current
						break
					end
					current = current.Parent
				end
				if targetModel then break end
			end
		end

		grabPart.CanCollide = wasCollide

		if not targetModel or not Hub.canAffect(targetModel) then return end

		if not targetModel.Parent then
			local found = false
			local connection
			connection = Hub.connect(targetModel.AncestryChanged, function(_, parent)
				if parent then
					found = true
					connection:Disconnect()
				end
			end)

			local startTime = tick()
			while not found and tick() - startTime < 2 do
				task.wait(0.1)
			end

			if not found then return end
		end

		local existing = targetModel:FindFirstChild("CleanedGrabParts")
		if existing then
			local existingHighlight = targetModel:FindFirstChild("AnchorHighlight")
			if existingHighlight then
				existingHighlight:Destroy()
			end
			existing:Destroy()
			return
		end

		local clone = original:Clone()
		clone.Name = "CleanedGrabParts"

		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1
				desc.CanCollide = false

				local beam = desc:FindFirstChild("GrabBeam")
				if beam then beam:Destroy() end

				for _, sName in ipairs({"AttachSound1", "AttachSound", "BeamSound", "BeamSound1"}) do
					local sound = desc:FindFirstChild(sName)
					if sound then sound:Destroy() end
				end
			end
		end

		clone.Parent = targetModel

		local hl = Hub.new("Highlight")
		hl.Name = "AnchorHighlight"
		hl.FillColor = Color3.fromRGB(0, 85, 255)
		hl.FillTransparency = 0.4
		hl.OutlineColor = Color3.fromRGB(0, 170, 255)
		hl.OutlineTransparency = 0.7
		hl.Adornee = targetModel
		hl.Parent = targetModel

		local connection
		connection = Hub.connect(RunService.Heartbeat, function()
			if not clone or not clone.Parent or not targetModel or not targetModel.Parent then
				if connection then connection:Disconnect() end
				return
			end

			if hl and hl.Parent then
				hl.Adornee = targetModel
			else
				connection:Disconnect()
			end
		end)
	end
})



-- UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddButton("Unload", function() Library:Unload() end)
MenuGroup:AddLabel("Emergency unload: End (restores tracked properties)", true)
Hub.connect(UserInputService.InputBegan, function(input, processed)
    if processed or UserInputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.End then Library:Unload() end
end)
MenuGroup:AddButton({Text = "Diagnostics", Func = function()
    local listeners, workers = 0, 0
    for connection in pairs(Hub.connections) do if connection.Connected then listeners += 1 end end
    for thread in pairs(Hub.threads) do if coroutine.status(thread) ~= "dead" then workers += 1 end end
    notify("Diagnostics", string.format("%d listeners / %d active workers. Config storage: %s. Touch API: %s.",
        listeners, workers, Hub.storage and "available" or "unavailable", firetouchinterest and "available" or "unavailable"), 8)
end})
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", { Default = "M", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

Hub.storage = isfile and readfile and writefile and isfolder and makefolder and listfiles
if Hub.storage then
    local ok, err = pcall(function()
        ThemeManager:SetLibrary(Library)
        SaveManager:SetLibrary(Library)
        SaveManager:SetIgnoreIndexes({"MultiWhitelist"})
        Hub.installConfigLoading(SaveManager)
        ThemeManager:SetFolder("ArrivaCoreHub")
        SaveManager:SetFolder("ArrivaCoreHub/Configs")
        SaveManager:BuildConfigSection(Tabs["UI Settings"])
        ThemeManager:ApplyToTab(Tabs["UI Settings"])
        if isfile("ArrivaCoreHub/Configs/settings/AutoSave.json") then
            local success, loadError = SaveManager:Load("AutoSave")
            if success then notify("Config", "Your saved settings were loaded.")
            else notify("Config", "Could not load settings: " .. tostring(loadError)) end
        end
    end)
    if not ok then Hub.storage = false; notify("Config", tostring(err)) end
else
    notify("Config", "File storage unavailable. Settings work for this session.")
end
-- Defer until SaveManager's deferred load callbacks have finished.
task.defer(function()
    Hub.readSafety()
    if Hub.refreshWhitelistUI then Hub.refreshWhitelistUI() end
    Hub.ready = true
end)
MenuGroup:AddButton({Text = "Save now", Func = function()
    if not Hub.storage then notify("Config", "File storage is unavailable."); return end
    local ok, err = Hub.persistSettings()
    notify("Config", ok and "All supported settings saved." or "Save failed: " .. tostring(err))
end})
MenuGroup:AddButton({Text = "Save status", Func = function()
    local message = "Storage: " .. (Hub.storage and "available" or "unavailable")
        .. " | Last successful save: " .. (Hub.lastSaveAt or "none this session")
    if Hub.lastSaveError then message ..= " | Save error: " .. Hub.lastSaveError end
    if Hub.lastSnapshotError then message ..= " | Snapshot error: " .. Hub.lastSnapshotError end
    notify("Config", message, 8)
end})
MenuGroup:AddLabel("Saved toggles restore their previous state. Whitelist selections use their separate safety file.", true)
MenuGroup:AddButton({Text = "Load Infinite Yield (external)", Func = function()
    task.spawn(function() Hub.fetch("https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source") end)
end})
Hub.cleanup(function()
    -- Explicit restoration, since remaining tasks are canceled on unload.
    unfreezeChar(Player.Character)
    stopNoclip()
    RemoveAllBoxes()
    disconnectWatchers()
    restorePaintParts()
    if bvInstance then bvInstance:Destroy() end
    if bgInstance then bgInstance:Destroy() end
    for _, item in ipairs(waterParts) do
        pcall(function() item.part.CanCollide = item.originalCollide end)
    end
    for obj, props in pairs(oldProperties) do
        pcall(function()
            local instance = obj == "Lighting" and game:GetService("Lighting") or obj
            for prop, value in pairs(props) do instance[prop] = value end
        end)
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
        local esp = root and root:FindFirstChild("NameESP")
        if esp then esp:Destroy() end
    end
end)

Hub.connect(Player.CharacterAdded, function(char)
    char:WaitForChild("HumanoidRootPart", 5)
    if not Hub.alive or Player.Character ~= char then return end
    if Toggles.PaintDeleteToggle and Toggles.PaintDeleteToggle.Value then setTouchQuery(false) end
end)

-- Player Events
Hub.connect(Players.PlayerRemoving, function(player)
	if player:IsFriendsWith(Player.UserId) then
		notify("Friend Notification", player.Name .. " left", 5)
	else
		notify("Leave Notification", (player and player.Name or "Unknown") .. " Left", 5)
	end
end)

Hub.connect(Players.PlayerAdded, function(plr)
	if plr:IsFriendsWith(Player.UserId) then
		notify("Friend Notification", plr.Name .. " joined", 5)
	end
end)

-- Autosave is scheduled after setting changes; no permanent polling loop.

-- Send loaded message

notify("Arriva Core Hub", "Maintenance revision loaded. Your original tabs and gameplay controls are retained.", 5)
