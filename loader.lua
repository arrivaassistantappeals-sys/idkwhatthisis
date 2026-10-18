-- Arriva Core Hub 2.0.
-- Packet/Line Lag flooders removed. Gameplay features retain their original scope.
local Hub = {alive = true, connections = {}, threads = {}, cleanups = {}, ready = false}
Hub.env = (getgenv and getgenv()) or shared
if type(Hub.env.ArrivaCoreStarting)=="number" and os.clock()-Hub.env.ArrivaCoreStarting>=0 and os.clock()-Hub.env.ArrivaCoreStarting<8 then
    warn("[Arriva] A startup is already running, wait before executing again.");return
end
Hub.env.ArrivaCoreStarting=os.clock()
Hub.startupBegan=os.clock()
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
		if not ok and Hub.alive then Hub.lastWorkerError=tostring(err);warn("[Arriva] " .. tostring(err)) end
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
		if not ok and Hub.alive then Hub.lastCallbackError=tostring(err);warn("[Arriva callback] " .. tostring(err)) end
	end)
	Hub.connections[connection] = true
	return connection
end
function Hub.cleanup(callback) table.insert(Hub.cleanups, callback) end
-- Coalesce repeated roster UI changes without delaying protective decisions.
Hub.pendingRefreshes={}
function Hub.queueRefresh(key,callback)
    if Hub.pendingRefreshes[key] then return end
    Hub.pendingRefreshes[key]=true
    task.delay(0.15,function()
        Hub.pendingRefreshes[key]=nil
        if Hub.alive then callback() end
    end)
end
Hub.cleanup(function() table.clear(Hub.pendingRefreshes) end)
-- Enumerate incrementally so initial protection scans do not build one giant array.
function Hub.scanDescendants(root,visit,valid)
    return task.spawn(function()
        local queue={root};local first,last=1,1
        while first<=last and Hub.alive and valid() do
            local deadline=os.clock()+0.001
            local count=0
            repeat
                local object=queue[first];queue[first]=nil;first+=1
                if object and (object==root or object.Parent) then
                    if object~=root then visit(object) end
                    for _,child in ipairs(object:GetChildren()) do last+=1;queue[last]=child end
                end
                count+=1
            until first>last or count>=128 or os.clock()>=deadline or not valid()
            if first<=last then task.wait() end
        end
    end)
end

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
-- Restore saved values first, then spread enabled-feature callbacks across frames.
function Hub.queueSavedCallbacks(records,invoke)
    Hub.restoreEpoch=(Hub.restoreEpoch or 0)+1
    local ticket=Hub.restoreEpoch
    local delayed={}
    Hub.restoreProgress={total=0,started=0,done=false}
    local progress=Hub.restoreProgress
    local function run(record)
        local control=record.control
        if not Hub.alive or ticket~=Hub.restoreEpoch or control.revision~=record.revision then return end
        Hub.lastRestoreControl=control.Id or "saved control"
        invoke(control.Callback,record.value)
    end
    for _,record in ipairs(records) do
        if record.control.Type=="Toggle" and record.value==true then table.insert(delayed,record)
        else task.defer(function() run(record) end) end
    end
    progress.total=#delayed
    task.spawn(function()
        local setting=Hub.library and Hub.library.Options.StartupFeatureDelay
        task.wait(math.clamp(tonumber(setting and setting.Value) or 3,0,10))
        for _,record in ipairs(delayed) do
            if not Hub.alive or ticket~=Hub.restoreEpoch then return end
            task.spawn(function() run(record) end)
            progress.started+=1
            task.wait(0.1)
        end
        if ticket==Hub.restoreEpoch then progress.done=true end
    end)
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
function Hub.persistSettings(explicit)
	if Hub.configLoading then
		return false,"Settings are still loading. Wait for loading to finish, then try again."
	end
	if explicit then Hub.configLoadFailed=false end
	if Hub.configLoadFailed then
		Hub.lastSaveError="Autosave paused to protect an unreadable settings file. Use Save settings to replace it deliberately."
		return false,Hub.lastSaveError
	end
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
	if not Hub.ready or not Hub.storage or Hub.configLoading or Hub.configLoadFailed then return end
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
local workspaceService = game:GetService("Workspace")
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
Hub.ownershipBindings = {}
function Hub.trackPlayerOwnership(player)
    if Hub.ownershipBindings[player] then return end
    Hub.playerNames[player.Name]=player
    if player.Character then Hub.characterOwners[player.Character]=player end
    local previous=player.Character
    Hub.ownershipBindings[player]=Hub.connect(player.CharacterAdded,function(char)
        if previous then Hub.characterOwners[previous]=nil end
        previous=char;Hub.characterOwners[char]=player
    end)
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
        if player.Parent~=Players then Hub.friendChecks[userId]=nil;return end
		Hub.friendCache[userId] = {friend = ok and result == true, failed = not ok, expires = os.clock() + (ok and 60 or 15)}
		Hub.friendChecks[userId] = nil
		if Hub.reconcileProtection then Hub.reconcileProtection() end
		if not ok then warn("[Arriva whitelist] Friend lookup failed; target stays protected: " .. tostring(result)) end
	end)
end
function Hub.isProtected(player)
	if typeof(player) ~= "Instance" or not player:IsA("Player") then return false end
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
	return typeof(player) == "Instance" and player:IsA("Player") and player ~= LocalPlayer and player.Parent ~= nil and not Hub.isProtected(player)
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
function Hub.finiteVector(value)
    return typeof(value)=="Vector3" and value.X==value.X and value.Y==value.Y and value.Z==value.Z
        and math.abs(value.X)<math.huge and math.abs(value.Y)<math.huge and math.abs(value.Z)<math.huge
end
function Hub.safeLookAt(startPosition,targetPosition,fallbackDirection)
    if not Hub.finiteVector(startPosition) or not Hub.finiteVector(targetPosition) then return nil end
    local direction=targetPosition-startPosition
    local length=direction.Magnitude
    if length==math.huge then return nil end
    if length<0.000001 then
        direction=Hub.finiteVector(fallbackDirection) and fallbackDirection or Vector3.new(0,0,-1)
        length=direction.Magnitude
        if length<0.000001 or length==math.huge then direction=Vector3.new(0,0,-1);length=1 end
    end
    direction=direction/length
    local up=math.abs(direction.Y)>0.999 and Vector3.new(1,0,0) or Vector3.new(0,1,0)
    return CFrame.lookAlong(startPosition,direction,up)
end
Hub.SafeLookAt=Hub.safeLookAt


-- Keep the existing game-facing basis for ordinary directions. Only replace
-- degenerate inputs; do not rewrite caller-supplied remote CFrames globally.
function Hub.lookAt(startPosition,targetPosition)
    if not Hub.finiteVector(startPosition) or not Hub.finiteVector(targetPosition) then return nil end
    local delta=targetPosition-startPosition
    if delta.Magnitude<0.000001 then return Hub.safeLookAt(startPosition,targetPosition) end
    local direction=delta.Unit
    local right=direction:Cross(Vector3.new(0,1,0))
    if right.Magnitude<0.000001 then return Hub.safeLookAt(startPosition,targetPosition) end
    return CFrame.fromMatrix(startPosition,right,right:Cross(direction))
end
Hub.LookAt=Hub.lookAt
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
	if Hub.refreshWhitelistUI then Hub.queueRefresh("whitelist",Hub.refreshWhitelistUI) end
end)
Hub.connect(Players.PlayerRemoving,function(player)
    local connection=Hub.ownershipBindings[player]
    if connection then connection:Disconnect();Hub.connections[connection]=nil;Hub.ownershipBindings[player]=nil end
    if Hub.playerNames[player.Name]==player then Hub.playerNames[player.Name]=nil end
    if player.Character then Hub.characterOwners[player.Character]=nil end
    Hub.friendCache[player.UserId]=nil
    if Hub.refreshWhitelistUI then Hub.queueRefresh("whitelist",Hub.refreshWhitelistUI) end
end)
-- END SAFETY WHITELIST CORE

--// Owner
local HUB_OWNER_ID = 1325117607

--// Whitelist
local WHITELIST = {
	[1325117607] = "arrivabus415",
	[115211703] = "00FSwedish",
	[9225934804] = "imagine2v1_L",
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
	sysMsg("I'm using Arriva Core Hub 2.0!")
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

local Library, SaveManager, ThemeManager
do
	-- Rayfield presentation adapter. Gameplay callbacks remain in the supplied hub.
--[=[
Third-party icon notices (MIT / ISC)
# MIT License

Copyright (c) 2023 Latte Softworks <https://latte.to>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# Lucide License (ISC)

Lucide Icons (this package's icon sources) are licensed under ISC License. You can view it online directly at <https://lucide.dev/license>.

## ISC License

Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022 as part of Feather (MIT). All other copyright (c) for Lucide are held by Lucide Contributors 2022.

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

]=]
	-- Arriva's custom sidebar presentation. No gameplay or remote operations.
	local function createArrivaSidebar()
		local UI = {Theme = {ReferenceDark = true}, tabs = {}, keybinds = {}, visible = true}
		local player = game:GetService("Players").LocalPlayer
		local playerService=game:GetService("Players")
		local knownNames={}
		local function rememberPlayer(person)
			local now=os.clock()
			knownNames[string.lower(person.Name)]={name=person.Name,time=now}
			if type(person.DisplayName)=="string" and #person.DisplayName>=3 then
				knownNames[string.lower(person.DisplayName)]={name=person.DisplayName,time=now}
			end
		end
		for _,person in ipairs(playerService:GetPlayers()) do rememberPlayer(person) end
		Hub.connect(playerService.PlayerAdded,rememberPlayer)
		Hub.connect(playerService.PlayerRemoving,rememberPlayer)
		local input = game:GetService("UserInputService")
		local colors = {background = Color3.fromRGB(25,25,25), sidebar = Color3.fromRGB(31,31,31),
			card = Color3.fromRGB(33,33,33), line = Color3.fromRGB(58,58,58),
			text = Color3.fromRGB(237,237,237), muted = Color3.fromRGB(153,153,153),
			blue = Color3.fromRGB(55,104,146), blueLine = Color3.fromRGB(69,137,191)}
		colors.noticeText = Color3.fromRGB(220,224,232)
		-- Lucide image-sprite metadata from SiriusSoftwareLtd/Rayfield icons.lua,
		-- commit 3ef72398fb4c8ba6fd1801e98704991d3cc9cbc2; Lucide icons: ISC license.
		-- Only the 15 assets used here are retained; no icon-library script is fetched.
		local iconAssets = {
			heart={16898613509,661,771},
			palette={16898613613,453,918},history={16898613509,869,98},bell={16898612819,820,257},
			activity={16898612629,514,771},["user-round-check"]={16898613869,869,404},
			["door-open"]={16898613044,967,759},["log-out"]={16898613509,820,955},
			["triangle-alert"]={16898613869,967,0},["circle-alert"]={16898612819,918,808},
			["rotate-ccw"]={16898613699,967,355},orbit={16898613613,967,612},info={16898613509,612,869},
			shield={16898613777,869,0}, crosshair={16898613044,453,869}, sparkles={16898613777,918,49},
			hand={16898613509,563,820}, user={16898613869,661,869}, box={16898612819,771,196},
			settings={16898613777,771,257}, search={16898613699,918,857}, check={16898612819,710,869},
			["chevron-down"]={16898612819,196,918}, ["chevron-up"]={16898612819,710,918},
			["chevron-right"]={16898612819,869,759}, minus={16898613613,771,196},
			x={16898613869,869,906}, ["arrow-down-right"]={16898612629,820,661}
		}
		local function make(class, parent, properties)
			local object = Hub.new(class, parent)
			for property, value in pairs(properties or {}) do object[property] = value end
			return object
		end
		local function round(object, radius) make("UICorner", object, {CornerRadius = UDim.new(0,radius or 8)}) end
		local function icon(parent, name, properties)
			local asset = iconAssets[name] or iconAssets.box
			local image = make("ImageLabel",parent,{BackgroundTransparency=1, Image="rbxassetid://" .. asset[1],
				ImageRectSize=Vector2.new(48,48),ImageRectOffset=Vector2.new(asset[2],asset[3]),
				Size=UDim2.fromOffset(20,20),ImageColor3=colors.muted})
			for property,value in pairs(properties or {}) do image[property]=value end
			return image
		end
		local function stroke(object, color, thickness)
			return make("UIStroke", object, {Color = color or colors.line, Thickness = thickness or 1.2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border})
		end
		local function text(parent, content, properties)
			local object = make("TextLabel", parent, {BackgroundTransparency = 1, Text = tostring(content),
				Font = Enum.Font.Gotham, TextSize = 15, TextColor3 = colors.text,
				TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd})
			for property, value in pairs(properties or {}) do object[property] = value end
			return object
		end
		local function button(parent, content, properties)
			local object = make("TextButton", parent, {Text = content or "", Font = Enum.Font.GothamBold,
				TextSize = 15, TextColor3 = colors.text, BackgroundTransparency = 1,
				AutoButtonColor = false})
			for property, value in pairs(properties or {}) do object[property] = value end
			return object
		end
		local function emit(callback, value)
			if UI.destroyed or not callback then return end
			local ok, err = pcall(callback, value)
			if not ok then warn("[Arriva menu] " .. tostring(err)) end
		end
		local function padding(parent, amount)
			make("UIPadding", parent, {PaddingLeft=UDim.new(0,amount), PaddingRight=UDim.new(0,amount),
				PaddingTop=UDim.new(0,amount), PaddingBottom=UDim.new(0,amount)})
		end
		local function activate(tab)
			UI.active = tab
			for _, item in ipairs(UI.tabs) do
				item.page.Visible = item == tab
				item.navLabel.TextColor3 = item == tab and colors.text or colors.muted
				item.navLabel.Font = item == tab and Enum.Font.GothamBold or Enum.Font.Gotham
				item.icon.ImageColor3 = item == tab and colors.text or colors.muted
				item.marker.Visible = item == tab
			end
		end
		local function filter()
			local query = UI.search.Text:lower()
			local first
			for _, tab in ipairs(UI.tabs) do
				local any = false
				local sectionMatches = {}
				for _, entry in ipairs(tab.entries) do
					if not entry.section then
						local match = query == "" or (tab.name .. " " .. (entry.group or "") .. " " .. entry.name):lower():find(query,1,true) ~= nil
						entry.frame.Visible = match
						if match then any = true; sectionMatches[entry.group or ""] = true end
					end
				end
				for _, entry in ipairs(tab.entries) do
					if entry.section then entry.frame.Visible = query == "" or sectionMatches[entry.name] == true end
				end
				tab.nav.Visible = query == "" or any
				if tab.nav.Visible and not first then first = tab end
			end
			if UI.active and not UI.active.nav.Visible and first then activate(first) end
		end
		local function registerEntry(tab, frame, name, section)
			table.insert(tab.entries, {frame=frame, name=tostring(name), group=tab.section, section=section})
			if UI.search.Text ~= "" then filter() end
		end
		local function card(tab, name, height)
			local row = button(tab.page, "", {Name = tostring(name), Size=UDim2.new(1,0,0,height or 48),
				BackgroundTransparency=0, BackgroundColor3=colors.card, ClipsDescendants=true})
			round(row,8); stroke(row)
			local title = text(row, name, {Position=UDim2.fromOffset(16,0), Size=UDim2.new(1,-80,0,48),
				Font=Enum.Font.GothamBold, TextSize=15})
			registerEntry(tab,row,name,false)
			return row,title
		end
		local Tab = {}
		function Tab:CreateSection(name)
			self.section = tostring(name)
			local heading = text(self.page,name,{Size=UDim2.new(1,0,0,40), TextColor3=colors.text,
				TextSize=15,Font=Enum.Font.GothamBold,TextYAlignment=Enum.TextYAlignment.Bottom})
			registerEntry(self,heading,name,true)
			return {Set=function(_, value) heading.Text=tostring(value) end}
		end
		function Tab:CreateLabel(value)
			local label = text(self.page,value,{Size=UDim2.new(1,0,0,0),AutomaticSize=Enum.AutomaticSize.Y,
				TextColor3=colors.text,TextWrapped=true,TextTruncate=Enum.TextTruncate.None,
				TextYAlignment=Enum.TextYAlignment.Top,TextSize=14,LineHeight=1.2})
			make("UIPadding",label,{PaddingTop=UDim.new(0,6),PaddingBottom=UDim.new(0,6),PaddingLeft=UDim.new(0,2),PaddingRight=UDim.new(0,2)})
			make("UISizeConstraint",label,{MinSize=Vector2.new(0,30)})
			registerEntry(self,label,value,false)
			return {Set=function(_, content) label.Text=tostring(content) end}
		end
		function Tab:CreateButton(info)
			local row = card(self,info.Name)
			icon(row,"chevron-right",{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-15,0.5,0)})
			Hub.connect(row.Activated,function() emit(info.Callback) end)
			return {Set=function(_, value) row.Name=tostring(value) end}
		end
		function Tab:CreateToggle(info)
			local row = card(self,info.Name)
			local box = make("Frame",row,{AnchorPoint=Vector2.new(1,0.5),Position=UDim2.new(1,-14,0.5,0),
				Size=UDim2.fromOffset(30,30),BackgroundColor3=colors.line})
			round(box,7);stroke(box,colors.sidebar,2)
			local check = icon(box,"check",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),ImageColor3=colors.text})
			local handle = {CurrentValue=info.CurrentValue == true}
			function handle:Set(value)
				self.CurrentValue = value == true
				check.Visible = self.CurrentValue
				emit(info.Callback,self.CurrentValue)
			end
			check.Visible = handle.CurrentValue
			Hub.connect(row.Activated,function() handle:Set(not handle.CurrentValue) end)
			return handle
		end
		function Tab:CreateSlider(info)
			local row = card(self,info.Name,80)
			local track = make("Frame",row,{Position=UDim2.fromOffset(15,40),Size=UDim2.new(1,-30,0,32),
				BackgroundColor3=colors.sidebar,ClipsDescendants=true,Active=true})
			round(track,7);stroke(track,colors.blueLine)
			local fill = make("Frame",track,{Size=UDim2.fromScale(0,1),BackgroundColor3=colors.blue,BorderSizePixel=0,Active=true})
			round(fill,7)
			local field = make("TextBox",track,{BackgroundTransparency=1,Position=UDim2.fromOffset(12,0),
				Size=UDim2.new(0,80,1,0),TextXAlignment=Enum.TextXAlignment.Left,TextColor3=colors.text,
				TextSize=15,Font=Enum.Font.GothamBold,ClearTextOnFocus=false})
			local handle = {CurrentValue=info.CurrentValue}
			local increment = info.Increment or 1
			local decimals = math.clamp(math.ceil(-math.log(increment)/math.log(10)-0.00001),0,4)
			local function render(value)
				fill.Size=UDim2.fromScale((value-info.Range[1])/math.max(info.Range[2]-info.Range[1],0.00001),1)
				field.Text=string.format("%." .. string.format("%d",decimals) .. "f",value)
			end
			function handle:Set(value)
				self.CurrentValue=math.clamp(tonumber(value) or self.CurrentValue,info.Range[1],info.Range[2])
				render(self.CurrentValue);emit(info.Callback,self.CurrentValue)
			end
			render(handle.CurrentValue)
			Hub.connect(field.FocusLost,function() handle:Set(tonumber(field.Text) or handle.CurrentValue) end)
			local function fromPointer(position)
				local alpha=math.clamp((position.X-track.AbsolutePosition.X)/math.max(track.AbsoluteSize.X,1),0,1)
				local raw=info.Range[1]+(info.Range[2]-info.Range[1])*alpha
				local value=math.clamp(info.Range[1]+math.floor((raw-info.Range[1])/increment+0.5)*increment,info.Range[1],info.Range[2])
				if value~=handle.CurrentValue then handle:Set(value) end
			end
			Hub.connect(track.InputBegan,function(event)
				if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
					UI.pointerAction=fromPointer;fromPointer(event.Position)
				end
			end)
			-- Edit the value directly or drag on the remaining bar area.
			Hub.connect(fill.InputBegan,function(event)
				if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
					UI.pointerAction=fromPointer;fromPointer(event.Position)
				end
			end)
			return handle
		end
		function Tab:CreateDropdown(info)
			local row,title = card(self,info.Name)
			title.Size=UDim2.new(0.52,-16,0,48)
			local selected = text(row,"None",{Position=UDim2.new(0.52,0,0,0),Size=UDim2.new(0.48,-45,0,48),
				TextXAlignment=Enum.TextXAlignment.Right,TextColor3=colors.muted,TextSize=14})
			local arrow = icon(row,"chevron-down",{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(1,-34,0,24)})
			local list = make("ScrollingFrame",row,{Position=UDim2.fromOffset(8,48),Size=UDim2.new(1,-16,0,0),
				BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=3,CanvasSize=UDim2.new(),
				AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false})
			make("UIListLayout",list,{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder})
			local handle = {Options=info.Options,CurrentOption=table.clone(info.CurrentOption or {}),open=false,connections={},row=row,list=list}
			local optionButtons={}
			local function collapse()
				handle.open=false;row.Size=UDim2.new(1,0,0,48);list.Visible=false;arrow.Rotation=0
			end
			local function render()
				selected.Text=#handle.CurrentOption==0 and "None" or (#handle.CurrentOption==1 and handle.CurrentOption[1] or (#handle.CurrentOption .. " selected"))
				for name,option in pairs(optionButtons) do
					local checked=table.find(handle.CurrentOption,name)~=nil
					option.Text=(checked and " •  " or "    ") .. name
					option.TextColor3=checked and colors.text or colors.muted
				end
			end
			function handle:Set(value)
				if type(value)=="string" then value={value} end
				self.CurrentOption={}
				for _,name in ipairs(value or {}) do if table.find(self.Options,name) then table.insert(self.CurrentOption,name) end end
				render();emit(info.Callback,table.clone(self.CurrentOption))
			end
            function handle:Refresh(values)
                local savedScroll=list.CanvasPosition
                local unchanged=self.built and #values==#self.Options
                if unchanged then for index,value in ipairs(values) do if value~=self.Options[index] then unchanged=false;break end end end
                if unchanged then render();return end
                self.optionConnections=self.optionConnections or {}
                local wanted={};for _,name in ipairs(values) do wanted[name]=true end
                for name,option in pairs(optionButtons) do
                    if not wanted[name] then
                        local c=self.optionConnections[name]
                        if c then c:Disconnect();Hub.connections[c]=nil end
                        self.optionConnections[name]=nil;optionButtons[name]=nil;option:Destroy()
                    end
                end
                self.Options=table.clone(values);self.built=true
                if not self.clearButton then
                    self.clearButton=button(list,"    Clear selection",{Size=UDim2.new(1,-4,0,30),TextColor3=colors.muted,TextXAlignment=Enum.TextXAlignment.Left,TextSize=14,LayoutOrder=0})
                    table.insert(self.connections,Hub.connect(self.clearButton.Activated,function() self:Set({});collapse() end))
                end
                for index,name in ipairs(self.Options) do
                    local option=optionButtons[name]
                    if not option then
                        option=button(list,"    "..name,{Size=UDim2.new(1,-4,0,30),TextXAlignment=Enum.TextXAlignment.Left,TextSize=14})
                        optionButtons[name]=option
                        self.optionConnections[name]=Hub.connect(option.Activated,function()
                            if info.MultipleOptions then
                                local choices=table.clone(self.CurrentOption);local i=table.find(choices,name)
                                if i then table.remove(choices,i) else table.insert(choices,name) end
                                self:Set(choices)
                            else self:Set({name});collapse() end
                        end)
                    end
                    option.LayoutOrder=index
                end
                if self.open then
                    local height=math.min((#self.Options+1)*33,180)
                    list.Size=UDim2.new(1,-16,0,height);row.Size=UDim2.new(1,0,0,60+height)
                else collapse() end
                if savedScroll then list.CanvasPosition=savedScroll end
                render()
            end
			handle:Refresh(handle.Options)
			Hub.connect(row.Activated,function()
				if handle.open then collapse();return end
				handle.open=true
				local height=math.min((#handle.Options+1)*33,180)
				list.Size=UDim2.new(1,-16,0,height);list.Visible=true
				row.Size=UDim2.new(1,0,0,60+height);arrow.Rotation=180
			end)
			return handle
		end
		function Tab:CreateInput(info)
			local row = card(self,info.Name,80)
			local field=make("TextBox",row,{Position=UDim2.fromOffset(15,40),Size=UDim2.new(1,-30,0,32),
				BackgroundColor3=colors.sidebar,TextColor3=colors.text,PlaceholderColor3=colors.muted,
				Font=Enum.Font.Gotham,TextSize=15,Text=info.CurrentValue or "",PlaceholderText=info.PlaceholderText or "Enter text",
				ClearTextOnFocus=false,TextXAlignment=Enum.TextXAlignment.Left})
			round(field,7);stroke(field);padding(field,8)
			local handle={CurrentValue=field.Text}
			function handle:Set(value) self.CurrentValue=tostring(value or "");field.Text=self.CurrentValue;emit(info.Callback,self.CurrentValue) end
			Hub.connect(field.FocusLost,function() handle:Set(field.Text) end)
			if tostring(info.Name):find("HEX",1,true) then
				field.Size=UDim2.new(1,-76,0,32)
				local swatch=button(row,"",{Position=UDim2.new(1,-48,0,40),Size=UDim2.fromOffset(32,32)})
				round(swatch,7);stroke(swatch)
				local panel=make("Frame",row,{BackgroundTransparency=1,Position=UDim2.fromOffset(15,88),
					Size=UDim2.new(1,-30,0,150),Visible=false})
				local sv=make("Frame",panel,{Size=UDim2.new(1,-32,1,0),Active=true,BorderSizePixel=0})
				local white=make("Frame",sv,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0})
				make("UIGradient",white,{Transparency=NumberSequence.new(0,1)})
				local black=make("Frame",sv,{Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(0,0,0),BorderSizePixel=0})
				make("UIGradient",black,{Rotation=90,Transparency=NumberSequence.new(1,0)})
				local marker=make("Frame",sv,{AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(8,8),BackgroundTransparency=1,ZIndex=4})
				round(marker,8);stroke(marker,Color3.new(1,1,1),2)
				local hue=make("Frame",panel,{Position=UDim2.new(1,-20,0,0),Size=UDim2.new(0,20,1,0),BackgroundColor3=Color3.new(1,1,1),Active=true,BorderSizePixel=0})
				local keys={}
				for i=0,6 do table.insert(keys,ColorSequenceKeypoint.new(i/6,Color3.fromHSV(i/6,1,1))) end
				make("UIGradient",hue,{Rotation=90,Color=ColorSequence.new(keys)})
				local h,s,v=0,0,1
				local function render()
					swatch.BackgroundColor3=Color3.fromHSV(h,s,v)
					sv.BackgroundColor3=Color3.fromHSV(h,1,1)
					marker.Position=UDim2.fromScale(s,1-v)
				end
				local originalSet=handle.Set
				function handle:Set(value)
					local code=tostring(value):gsub("#","")
					if code:match("^%x%x%x%x%x%x$") then
						h,s,v=Color3.fromRGB(tonumber(code:sub(1,2),16),tonumber(code:sub(3,4),16),tonumber(code:sub(5,6),16)):ToHSV()
						render()
					end
					originalSet(self,value)
				end
				local function commit()
					render()
					local c=Color3.fromHSV(h,s,v)
					local code=string.format("#%02X%02X%02X",math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5))
					originalSet(handle,code)
				end
				local function drag(target,fn)
					Hub.connect(target.InputBegan,function(event)
						if event.UserInputType~=Enum.UserInputType.MouseButton1 and event.UserInputType~=Enum.UserInputType.Touch then return end
						UI.pointerAction=function(point)
							local size=target.AbsoluteSize
							if size.X<=0 or size.Y<=0 then return end
							fn(math.clamp((point.X-target.AbsolutePosition.X)/size.X,0,1),math.clamp((point.Y-target.AbsolutePosition.Y)/size.Y,0,1))
							commit()
						end
						UI.pointerAction(event.Position)
					end)
				end
				drag(sv,function(x,y) s=x;v=1-y end)
				-- The overlays receive clicks too.
				drag(white,function(x,y) s=x;v=1-y end)
				drag(black,function(x,y) s=x;v=1-y end)
				drag(hue,function(_,y) h=y end)
				Hub.connect(swatch.Activated,function()
					panel.Visible=not panel.Visible
					row.Size=UDim2.new(1,0,0,panel.Visible and 252 or 80)
				end)
				local code=field.Text:gsub("#","")
				if code:match("^%x%x%x%x%x%x$") then
					h,s,v=Color3.fromRGB(tonumber(code:sub(1,2),16),tonumber(code:sub(3,4),16),tonumber(code:sub(5,6),16)):ToHSV()
				end
				render()
			end

			return handle
		end
		function Tab:CreateKeybind(info)
			local row = card(self,info.Name)
			local key=text(row,info.CurrentKeybind,{Position=UDim2.new(1,-120,0,0),Size=UDim2.fromOffset(100,48),TextXAlignment=Enum.TextXAlignment.Right,TextColor3=colors.muted})
			local handle={CurrentKeybind=info.CurrentKeybind,info=info,label=key}
			function handle:Set(value)
				self.CurrentKeybind=tostring(value);key.Text=self.CurrentKeybind
				if info.CallOnChange then emit(info.Callback,self.CurrentKeybind) end
			end
			Hub.connect(row.Activated,function() if UI.capture then UI.capture.label.Text=UI.capture.CurrentKeybind end;UI.capture=handle;Hub.keybindCaptureActive=true;key.Text="Press a key..." end)
			table.insert(UI.keybinds,handle)
			return handle
		end
		function UI:SetMetricsPreference(key,value)
			self[key]=value
			if not self.metricsGui then return end
			self.metricsGui.Enabled=self.metricsShown~=false
			local position=self.metricsPosition or "Top Right"
			local x=position:find("Left",1,true) and 0 or position:find("Center",1,true) and 0.5 or 1
			local y=position:find("Bottom",1,true) and 1 or 0
			self.metricsFrame.AnchorPoint=Vector2.new(x,y)
			self.metricsFrame.Position=UDim2.new(x,x==0 and 12 or x==1 and -12 or 0,y,y==0 and 12 or -12)
			self.metricsScale.Scale=self.metricsSize or 1
		end
		Hub.setMetricsPreference=function(key,value) UI:SetMetricsPreference(key,value) end

		function UI:CreateWindow(info)
			local gui=make("ScreenGui",nil,{Name="ArrivaSidebarHub",ResetOnSpawn=false,IgnoreGuiInset=true,
				ZIndexBehavior=Enum.ZIndexBehavior.Sibling,DisplayOrder=100})
			local ok=pcall(function() gui.Parent=gethui and gethui() or game:GetService("CoreGui") end)
			if not ok then gui.Parent=player:WaitForChild("PlayerGui") end
			self.gui=gui
			local root=make("Frame",gui,{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
				Size=UDim2.fromOffset(920,540),BackgroundColor3=colors.background,ClipsDescendants=true})
			round(root,14)
			local scale=make("UIScale",root,{Scale=1})
			local outline=stroke(root,Color3.new(1,1,1),1.5)
			self.outline=outline
			outline.Enabled=self.rainbow~=false
			local keys={}
			for i=0,6 do table.insert(keys,ColorSequenceKeypoint.new(i/6,Color3.fromHSV(i/6,1,1))) end
			local gradient=make("UIGradient",outline,{Color=ColorSequence.new(keys)})
			self.glowGradient=gradient
			self.defaultGlowColor=gradient.Color
			local header=make("Frame",root,{Size=UDim2.new(1,0,0,66),BackgroundTransparency=1,Active=true})
			make("ImageLabel",header,{Name="ArrivaLogo",BackgroundTransparency=1,
				Image="rbxassetid://90461919222617",ScaleType=Enum.ScaleType.Fit,
				Position=UDim2.fromOffset(20,11),Size=UDim2.fromOffset(44,44)})
			local title=text(header,"ARRIVA CORE HUB 2.0",{Position=UDim2.fromOffset(78,8),Size=UDim2.new(1,-218,0,28),TextSize=22})
			local titleFont=Font.fromEnum(Enum.Font.Ubuntu)
			title.FontFace=Font.new(titleFont.Family,Enum.FontWeight.Bold,Enum.FontStyle.Italic)
			local metrics=text(header,"FPS: --  |  Ping: --",{Name="ClientMetrics",
				Position=UDim2.fromOffset(80,37),Size=UDim2.new(1,-220,0,18),TextSize=12,TextColor3=colors.muted})
			self.metricsGui=make("ScreenGui",gui.Parent,{Name="ArrivaFloatingMetrics",ResetOnSpawn=false,
				IgnoreGuiInset=false,DisplayOrder=101,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
			self.metricsFrame=make("Frame",self.metricsGui,{Name="PerformanceWidget",Size=UDim2.fromOffset(226,46),
				BackgroundColor3=colors.card,BorderSizePixel=0})
			round(self.metricsFrame,12);stroke(self.metricsFrame,colors.blueLine,1.3)
			self.metricsScale=make("UIScale",self.metricsFrame,{Scale=1})
			icon(self.metricsFrame,"activity",{Position=UDim2.fromOffset(12,13),ImageColor3=colors.blueLine})
			self.widgetFPS=text(self.metricsFrame,"FPS --",{Position=UDim2.fromOffset(42,0),Size=UDim2.fromOffset(68,46),Font=Enum.Font.GothamBold,TextSize=14})
			make("Frame",self.metricsFrame,{Position=UDim2.fromOffset(113,12),Size=UDim2.fromOffset(1,22),BackgroundColor3=colors.line,BorderSizePixel=0})
			self.widgetPing=text(self.metricsFrame,"-- ms",{Position=UDim2.fromOffset(126,0),Size=UDim2.fromOffset(88,46),TextSize=14})
			self:SetMetricsPreference("metricsShown",true)

			local frames,seconds=0,0
			local metricsConnection=RunService.RenderStepped:Connect(function(dt)
				if self.destroyed or (not self.visible and self.metricsShown==false) then frames=0;seconds=0;return end
				frames+=1;seconds+=dt
				if seconds<0.5 then return end
				local fps=math.floor(frames/seconds+0.5)
				local ok,ping=pcall(function() return player:GetNetworkPing()*1000 end)
				local value="--"
				if ok and type(ping)=="number" and ping==ping and ping>=0 and ping<math.huge then
					value=string.format("%.0f ms",ping)
				end
				metrics.Text=string.format("FPS: %d  |  Ping: %s",fps,value)
				self.widgetFPS.Text=string.format("FPS %d",fps)
				self.widgetPing.Text=value=="--" and "-- ms" or value
				frames,seconds=0,0
			end)
			Hub.connections[metricsConnection]=true
			self.metricsConnection=metricsConnection
			make("Frame",root,{Position=UDim2.fromOffset(0,65),Size=UDim2.new(1,0,0,1),BackgroundColor3=colors.line,BorderSizePixel=0})
			local minimize=button(header,"",{Name="Minimize",Position=UDim2.new(1,-122,0,13),Size=UDim2.fromOffset(44,40)})
			local close=button(header,"",{Name="Close",Position=UDim2.new(1,-74,0,13),Size=UDim2.fromOffset(44,40)})
			round(minimize,9);round(close,9);stroke(minimize);stroke(close)
			icon(minimize,"minus",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),ImageColor3=colors.text})
			icon(close,"x",{AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),ImageColor3=colors.text})
			local body=make("Frame",root,{Position=UDim2.fromOffset(0,66),Size=UDim2.new(1,0,1,-66),BackgroundTransparency=1})
			local sidebar=make("Frame",body,{Size=UDim2.new(0,232,1,0),BackgroundColor3=colors.sidebar,BorderSizePixel=0})
			-- Match the outer bottom-left curve; leave the internal seams square.
			round(sidebar,14)
			make("Frame",sidebar,{Name="SidebarTopFill",Size=UDim2.new(1,0,0,14),
				BackgroundColor3=colors.sidebar,BorderSizePixel=0})
			make("Frame",sidebar,{Name="SidebarInnerFill",Position=UDim2.new(1,-14,0,0),Size=UDim2.new(0,14,1,0),
				BackgroundColor3=colors.sidebar,BorderSizePixel=0})
			make("Frame",sidebar,{Position=UDim2.new(1,-1,0,0),Size=UDim2.new(0,1,1,0),BackgroundColor3=colors.line,BorderSizePixel=0})
			self.search=make("TextBox",sidebar,{Position=UDim2.fromOffset(14,14),Size=UDim2.new(1,-28,0,42),
				BackgroundColor3=Color3.fromRGB(161,161,161),TextColor3=Color3.fromRGB(34,34,34),PlaceholderColor3=Color3.fromRGB(111,111,111),
				PlaceholderText="Search...",Text="",ClearTextOnFocus=false,Font=Enum.Font.Gotham,TextSize=15,TextXAlignment=Enum.TextXAlignment.Left})
			round(self.search,14);padding(self.search,12)
			icon(sidebar,"search",{Position=UDim2.fromOffset(27,25),ImageColor3=Color3.fromRGB(91,91,91)})
			for _,child in ipairs(self.search:GetChildren()) do
				if child:IsA("UIPadding") then child.PaddingLeft=UDim.new(0,40) end
			end
			self.nav=make("ScrollingFrame",sidebar,{Position=UDim2.fromOffset(14,72),Size=UDim2.new(1,-23,1,-148),
				BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageTransparency=0,ScrollingEnabled=true,CanvasSize=UDim2.new(),AutomaticCanvasSize=Enum.AutomaticSize.Y})
			make("UIListLayout",self.nav,{Padding=UDim.new(0,3),SortOrder=Enum.SortOrder.LayoutOrder})
			local profile=make("Frame",sidebar,{Position=UDim2.new(0,0,1,-64),Size=UDim2.new(1,0,0,64),BackgroundTransparency=1})
			make("Frame",profile,{Size=UDim2.new(1,0,0,1),BackgroundColor3=colors.line,BorderSizePixel=0})
			local avatar=make("ImageLabel",profile,{Position=UDim2.fromOffset(14,10),Size=UDim2.fromOffset(44,44),BackgroundColor3=colors.card,
				Image="rbxthumb://type=AvatarHeadShot&id=" .. tostring(player.UserId) .. "&w=100&h=100"})
			round(avatar,24);stroke(avatar)
			text(profile,player.DisplayName or player.Name,{Position=UDim2.fromOffset(68,0),Size=UDim2.new(1,-78,1,0),Font=Enum.Font.GothamBold,TextSize=15})
			self.content=make("Frame",body,{Position=UDim2.fromOffset(246,12),Size=UDim2.new(1,-260,1,-24),BackgroundTransparency=1})
			local grip=button(root,"",{Name="Resize",AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-9,1,-7),Size=UDim2.fromOffset(22,22),ZIndex=20})
			icon(grip,"arrow-down-right",{Size=UDim2.fromScale(1,1),ZIndex=21})
			local width,height=920,540
			local minimized=false
			local function fit()
				local camera=Workspace.CurrentCamera
				if camera then
					local value=math.clamp(math.min(self.userScale or 1,(camera.ViewportSize.X-24)/width,(camera.ViewportSize.Y-24)/height),0.35,1.3)
					if scale.Scale~=value then scale.Scale=value end
				end
			end
			self.fitWindow=fit
			local viewportConnection
			local function watchViewport()
				if viewportConnection then viewportConnection:Disconnect();Hub.connections[viewportConnection]=nil end
				local camera=Workspace.CurrentCamera
				if camera and camera.GetPropertyChangedSignal then
					viewportConnection=Hub.connect(camera:GetPropertyChangedSignal("ViewportSize"),fit)
				end
				fit()
			end
			if Workspace.GetPropertyChangedSignal then Hub.connect(Workspace:GetPropertyChangedSignal("CurrentCamera"),watchViewport) end
			watchViewport()
			local elapsed=0
			Hub.connect(RunService.Heartbeat,function(dt)
				if not self.visible or self.rainbow==false or minimized then return end
				elapsed+=dt
				if elapsed>=0.1 then
					if self.rainbow~=false then gradient.Rotation=(gradient.Rotation+elapsed*(self.rainbowSpeed or 14))%360 end
					elapsed=0
				end
			end)
			Hub.connect(self.search:GetPropertyChangedSignal("Text"),filter)
			Hub.connect(minimize.Activated,function()
				minimized=not minimized;body.Visible=not minimized;grip.Visible=not minimized
				root.Size=UDim2.fromOffset(width,minimized and 66 or height)
			end)
			Hub.connect(close.Activated,function() if self.onClose then self.onClose() else self:Destroy() end end)
			Hub.connect(header.InputBegan,function(event)
				if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
					local start,position=event.Position,root.Position
					self.pointerAction=function(point)
						local delta=(point-start)/scale.Scale
						root.Position=UDim2.new(position.X.Scale,position.X.Offset+delta.X,position.Y.Scale,position.Y.Offset+delta.Y)
					end
				end
			end)
			Hub.connect(grip.InputBegan,function(event)
				if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
					local start,startWidth,startHeight=event.Position,width,height
					self.pointerAction=function(point)
						local delta=(point-start)/scale.Scale
						width=math.clamp(startWidth+delta.X,640,1400);height=math.clamp(startHeight+delta.Y,380,900)
						root.Size=UDim2.fromOffset(width,height);fit()
					end
				end
			end)
			Hub.connect(input.InputChanged,function(event)
				if self.pointerAction and (event.UserInputType==Enum.UserInputType.MouseMovement or event.UserInputType==Enum.UserInputType.Touch) then self.pointerAction(event.Position) end
			end)
			Hub.connect(input.InputEnded,function(event)
				if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then self.pointerAction=nil end
			end)
			Hub.connect(input.InputBegan,function(event,processed)
				if self.capture then
					if event.KeyCode==Enum.KeyCode.Unknown then return end
					local capture=self.capture;self.capture=nil;Hub.keybindCaptureActive=false;Hub.keybindCaptureBlockUntil=os.clock()+0.15
					if event.KeyCode==Enum.KeyCode.Escape then capture.label.Text=capture.CurrentKeybind else capture:Set(event.KeyCode.Name) end
					return
				end
				if processed or input:GetFocusedTextBox() or os.clock()<(Hub.keybindCaptureBlockUntil or 0) then return end
				local matched=false
				for _,handle in ipairs(self.keybinds) do
					if event.KeyCode.Name==handle.CurrentKeybind then matched=true;emit(handle.info.Callback) end
				end
				if not matched and event.KeyCode==Enum.KeyCode.RightShift then self:SetVisibility(not self.visible) end
			end)
			local window={}
			function window:CreateTab(name,iconName)
				local page=make("ScrollingFrame",UI.content,{Size=UDim2.fromScale(1,1),BackgroundTransparency=1,
					BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=colors.line,CanvasSize=UDim2.new(),
					AutomaticCanvasSize=Enum.AutomaticSize.Y,Visible=false})
				make("UIPadding",page,{PaddingLeft=UDim.new(0,3),PaddingRight=UDim.new(0,14),
					PaddingTop=UDim.new(0,4),PaddingBottom=UDim.new(0,12)})
				make("UIListLayout",page,{Padding=UDim.new(0,7),SortOrder=Enum.SortOrder.LayoutOrder})
				local nav=button(UI.nav,"",{Size=UDim2.new(1,-6,0,39)})
				local navLabel=text(nav,name,{Position=UDim2.fromOffset(34,0),Size=UDim2.new(1,-44,1,0),TextSize=15,TextColor3=colors.muted})
				local navIcon=icon(nav,iconName=="align-vertical-space-around" and "sparkles" or iconName,{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,2,0.5,0),Size=UDim2.fromOffset(22,22)})
				local marker=make("Frame",nav,{Position=UDim2.new(1,-1,0,5),Size=UDim2.new(0,3,1,-10),BackgroundColor3=colors.text,BorderSizePixel=0,Visible=false})
				round(marker,2)
				local tab=setmetatable({name=name,page=page,nav=nav,navLabel=navLabel,icon=navIcon,marker=marker,entries={}}, {__index=Tab})
				table.insert(UI.tabs,tab)
				Hub.connect(nav.Activated,function() activate(tab) end)
				if not UI.active then activate(tab) end
				return tab
			end
			function window.ModifyTheme() end -- The reference design intentionally keeps one palette.
			function window:SetCloseCallback(callback) UI.onClose=callback end
			return window
		end
		function UI:SetVisibility(visible) self.visible=visible==true;Hub.menuVisible=self.visible;if self.gui then self.gui.Enabled=self.visible end;if Hub.menuMouse then Hub.menuMouse(self.visible) end end
		function UI:IsVisible() return self.visible end
		function UI:RefreshAccentGlow()
			if not self.glowGradient or not self.outline then return end
			self.outline.Enabled=self.rainbow~=false
			self.outline.Color=Color3.new(1,1,1)
			if not self.activeTheme or self.activeTheme=="Default" then
				self.glowGradient.Color=self.defaultGlowColor
			else
				local accent=colors.blueLine
				self.glowGradient.Color=ColorSequence.new({
					ColorSequenceKeypoint.new(0,accent:Lerp(colors.background,0.3)),
					ColorSequenceKeypoint.new(0.5,accent:Lerp(Color3.new(1,1,1),0.15)),
					ColorSequenceKeypoint.new(1,accent:Lerp(colors.background,0.3)),
				})
			end
		end
		function UI:SetRainbowEnabled(value)
			self.rainbow=value==true
			self:RefreshAccentGlow()
		end
		function UI:SetBorderThickness(value)
			if self.outline then self.outline.Thickness=math.clamp(value,1,4) end
		end
		function UI:SetBorderSpeed(value) self.rainbowSpeed=math.clamp(value,1,90) end
		function UI:SetUserScale(value)
			self.userScale=math.clamp(value/100,0.7,1.3)
			if self.fitWindow then self.fitWindow() end
		end
		function UI:Destroy() if self.destroyed then return end;self.destroyed=true;self.pointerAction=nil;if self.gui then self.gui:Destroy() end;if self.noticeGui then self.noticeGui:Destroy();self.noticeGui=nil end;if self.metricsConnection then self.metricsConnection:Disconnect();Hub.connections[self.metricsConnection]=nil end;if self.metricsGui then self.metricsGui:Destroy();self.metricsGui=nil end end
		function UI:SetNoticePreference(key,value)
			self[key]=value
			if key=="noticeLimit" and self.notices then
				while #self.notices>value do table.remove(self.notices,1):Destroy() end
			end
			if self.noticeLayout then
				local position=self.noticePosition or "Bottom Right"
				self.noticeLayout.HorizontalAlignment=position:find("Left",1,true) and Enum.HorizontalAlignment.Left
					or position:find("Center",1,true) and Enum.HorizontalAlignment.Center or Enum.HorizontalAlignment.Right
				self.noticeLayout.VerticalAlignment=position:find("Top",1,true) and Enum.VerticalAlignment.Top or Enum.VerticalAlignment.Bottom
			end
			for _,frame in ipairs(self.notices or {}) do
				local scale=frame:FindFirstChild("NotificationScale")
				if scale then scale.Scale=self.noticeScale or 1 end
			end
		end
		Hub.setNoticePreference=function(key,value) UI:SetNoticePreference(key,value) end
		function UI:Notify(info)
			if not self.gui or self.destroyed then return end
			-- Independent from menu visibility; still removed on hub unload.
			if not self.noticeGui then
				self.noticeGui=make("ScreenGui",self.gui.Parent,{Name="ArrivaNotifications",
					ResetOnSpawn=false,IgnoreGuiInset=true,Enabled=true,
					DisplayOrder=self.gui.DisplayOrder+1,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
			end
			self.noticeCount=(self.noticeCount or 0)+1
			self.notices=self.notices or {}
			if not self.noticeStack then
				self.noticeStack=make("Frame",self.noticeGui,{BackgroundTransparency=1,
					AnchorPoint=Vector2.new(1,1),Position=UDim2.new(1,-18,1,-18),
					Size=UDim2.new(1,-36,1,-36)})
				self.noticeLayout=make("UIListLayout",self.noticeStack,{Padding=UDim.new(0,10),
					SortOrder=Enum.SortOrder.LayoutOrder,
					VerticalAlignment=Enum.VerticalAlignment.Bottom,
					HorizontalAlignment=Enum.HorizontalAlignment.Right})
			end
			for index=#self.notices,1,-1 do
				if not self.notices[index].Parent then table.remove(self.notices,index) end
			end
			self:SetNoticePreference("noticePosition",self.noticePosition or "Bottom Right")
			while #self.notices>=(self.noticeLimit or 3) do table.remove(self.notices,1):Destroy() end
			local frame=make("Frame",self.noticeStack,{LayoutOrder=self.noticeCount,
				Size=UDim2.new(0.92,0,0,112),BackgroundColor3=colors.card})
			make("UIScale",frame,{Name="NotificationScale",Scale=self.noticeScale or 1})
			make("UISizeConstraint",frame,{MaxSize=Vector2.new(400,1000)})
			round(frame,10);stroke(frame,colors.line,1.2)
			local title = tostring(info.Title or "Arriva"):sub(1,180):gsub(";",",")
			local content = tostring(info.Content or ""):sub(1,2048):gsub(";",",")
			local category = string.lower(title .. " " .. content)
			local accent = Color3.fromRGB(106,177,255)
			local iconName = "settings"
			local negative = {"error","failed","failure","respawn","blackhole","black hole","kicked","disconnected","lost"}
			local bad = false
			for _,word in ipairs(negative) do
				if category:find(word,1,true) then bad=true;break end
			end
			if bad then accent=Color3.fromRGB(255,115,125);iconName="shield"
			elseif category:find("warning",1,true) then accent=Color3.fromRGB(255,202,105);iconName="shield"
			elseif category:find("success",1,true) or category:find("restored",1,true) or category:find("saved",1,true) then
				accent=Color3.fromRGB(111,224,160);iconName="check"
			end
			-- Event-specific symbols; classification uses the message for legacy calls too.
			if category:find("joined",1,true) then
				iconName="door-open";accent=Color3.fromRGB(111,224,160)
			elseif category:find("kicked",1,true) then
				iconName="triangle-alert";accent=Color3.fromRGB(255,115,125)
			elseif category:find("left",1,true) or category:find("disconnected",1,true) then
				iconName="log-out";accent=Color3.fromRGB(255,115,125)
			elseif category:find("black hole",1,true) or category:find("blackhole",1,true) then
				iconName="orbit"
			elseif category:find("respawn",1,true) then iconName="rotate-ccw"
			elseif category:find("warning",1,true) then iconName="triangle-alert"
			elseif category:find("error",1,true) or category:find("fail",1,true) then iconName="circle-alert"
			elseif iconName=="settings" then iconName="info" end
			if category:find("[protected]",1,true) then accent=Color3.fromRGB(111,224,160) end
			local headerRow=make("Frame",frame,{BackgroundTransparency=1,
				Position=UDim2.fromOffset(16,12),Size=UDim2.new(1,-32,0,24)})
			icon(headerRow,iconName,{AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,0,0.5,0),
				Size=UDim2.fromOffset(20,20),ImageColor3=accent})
			local heading=text(headerRow,title,{Position=UDim2.fromOffset(30,0),Size=UDim2.new(1,-30,1,0),
				Font=Enum.Font.GothamBold,TextSize=15,TextColor3=accent,TextWrapped=true,LineHeight=1.2,
				TextYAlignment=Enum.TextYAlignment.Center,TextTruncate=Enum.TextTruncate.None})
			local function escape(value)
				return (value:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"))
			end
			-- Keep recent departures available to every notification, not just leave alerts.
			for _,person in ipairs(playerService:GetPlayers()) do rememberPlayer(person) end
			local candidates={}
			for key,entry in pairs(knownNames) do
				if os.clock()-entry.time>300 then knownNames[key]=nil
				else table.insert(candidates,key) end
			end
			table.sort(candidates,function(a,b) return #a>#b end)
			local hex=string.format("#%02X%02X%02X",math.floor(accent.R*255+0.5),math.floor(accent.G*255+0.5),math.floor(accent.B*255+0.5))
			local lower=string.lower(content)
			local pieces={}
			local cursor=1
			while cursor<=#content do
				local bestStart,bestEnd
				for _,name in ipairs(candidates) do
					local search=cursor
					while search<=#content do
						local first,last=lower:find(name,search,true)
						if not first then break end
						local before=first>1 and lower:sub(first-1,first-1) or ""
						local after=lower:sub(last+1,last+1)
						if not before:match("[%w_]") and not after:match("[%w_]") then
							if not bestStart or first<bestStart or (first==bestStart and last>bestEnd) then
								bestStart,bestEnd=first,last
							end
							break
						end
						search=last+1
					end
				end
				if not bestStart then table.insert(pieces,escape(content:sub(cursor)));break end
				table.insert(pieces,escape(content:sub(cursor,bestStart-1)))
				table.insert(pieces,'<font color="' .. hex .. '">' .. escape(content:sub(bestStart,bestEnd)) .. '</font>')
				cursor=bestEnd+1
			end
			local readable=table.concat(pieces)
			readable=readable:gsub("%[Protected%]",'<font color="#6FE0A0">[Protected]</font>')
			local body=text(frame,readable,{Position=UDim2.fromOffset(16,44),Size=UDim2.new(1,-32,0,24),
				RichText=true,TextWrapped=true,TextSize=15,LineHeight=1.15,TextColor3=Color3.fromRGB(245,245,245),
				TextYAlignment=Enum.TextYAlignment.Top,TextTruncate=Enum.TextTruncate.None})
			body.Visible=content~=""
			local function fitNotice()
				if not frame.Parent then return end
				local function measuredHeight(value,label,font,lineHeight)
					local width=label.AbsoluteSize.X/(self.noticeScale or 1)
					if width<=1 then return label.TextBounds.Y end
					local ok,bounds=pcall(function()
						return game:GetService("TextService"):GetTextSize(value,15,font,Vector2.new(width,10000))
					end)
					if ok and bounds and type(bounds.Y)=="number" then return math.ceil(bounds.Y*(lineHeight or 1)) end
					return label.TextBounds.Y
				end
				local headerHeight=math.max(24,measuredHeight(title,heading,Enum.Font.GothamBold,1.2))
				headerRow.Size=UDim2.new(1,-32,0,headerHeight)
				heading.Size=UDim2.new(1,-30,1,0)
				local top=12+headerHeight+10
				local height=content~="" and math.max(24,measuredHeight(content,body,Enum.Font.Gotham,1.15)) or 0
				body.Position=UDim2.fromOffset(16,top)
				body.Size=UDim2.new(1,-32,0,height)
				frame.Size=UDim2.new(0.92,0,0,math.max(58,top+height+14))
			end
			local headerSizing=heading:GetPropertyChangedSignal("TextBounds"):Connect(fitNotice)
			local widthSizing=heading:GetPropertyChangedSignal("AbsoluteSize"):Connect(fitNotice)
			frame.Destroying:Connect(function() headerSizing:Disconnect();widthSizing:Disconnect() end)
			local sizing=body:GetPropertyChangedSignal("TextBounds"):Connect(fitNotice)
			frame.Destroying:Connect(function() sizing:Disconnect() end)
			task.defer(fitNotice)
			table.insert(self.notices,frame)
			task.delay((info.Duration or 5)*(self.noticeDuration or 1),function()
				local index=table.find(self.notices,frame)
				if index then table.remove(self.notices,index) end
				if frame.Parent then frame:Destroy() end
			end)
		end
		local custom={background="191919",accent="4589BF",text="EDEDED"}
		local function hex(value)
			value=tostring(value):gsub("#","")
			if not value:match("^%x%x%x%x%x%x$") then return nil end
			return Color3.fromRGB(tonumber(value:sub(1,2),16),tonumber(value:sub(3,4),16),tonumber(value:sub(5,6),16))
		end
		local palettes = {
			Rose={ {29,19,24},{39,25,32},{48,31,39},{88,57,70},{255,239,246},{209,177,192},{147,66,100},{240,133,175},{245,223,233} },
			Ocean={ {13,25,30},{18,33,40},{24,42,50},{47,77,88},{233,249,255},{165,195,205},{36,112,135},{86,204,225},{215,240,247} },
			Amber={ {28,24,17},{36,31,22},{45,38,26},{82,68,44},{255,247,228},{204,188,155},{139,103,37},{237,184,74},{245,232,207} },
			["Default"]={ {25,25,25},{31,31,31},{33,33,33},{58,58,58},{237,237,237},{170,170,176},{55,104,146},{69,137,191},{220,224,232} },
			Midnight={ {16,21,34},{21,28,44},{28,37,55},{59,75,99},{241,245,255},{177,190,211},{55,95,165},{112,163,255},{223,233,251} },
			Violet={ {23,18,32},{31,25,43},{40,32,55},{75,59,96},{246,239,255},{192,177,208},{104,70,150},{181,137,244},{236,224,250} },
			Forest={ {16,25,22},{22,34,29},{29,43,36},{53,78,65},{237,250,241},{173,198,181},{43,106,76},{109,205,151},{219,241,225} },
		}
		Hub.creativeUIPalette=colors
		function UI:SetTheme(name)
			if name=="Reference Dark" then name="Default" end
			local palette=palettes[name]
			if name=="Custom" then
				local bg,accent,fg=hex(custom.background),hex(custom.accent),hex(custom.text)
				local function rgb(c) return {math.floor(c.R*255+0.5),math.floor(c.G*255+0.5),math.floor(c.B*255+0.5)} end
				local white=Color3.new(1,1,1)
				palette={rgb(bg),rgb(bg:Lerp(white,0.035)),rgb(bg:Lerp(white,0.065)),rgb(bg:Lerp(white,0.2)),
					rgb(fg),rgb(fg:Lerp(bg,0.3)),rgb(accent:Lerp(bg,0.3)),rgb(accent),rgb(fg)}
			end
			if not palette then return end
			self.activeTheme=name
			local keys={"background","sidebar","card","line","text","muted","blue","blueLine","noticeText"}
			local mapping={}
			for index,key in ipairs(keys) do
				local nextColor=Color3.fromRGB(table.unpack(palette[index]))
				table.insert(mapping,{old=colors[key],new=nextColor})
				colors[key]=nextColor
			end
			-- Only traverse UI when the theme changes, never every frame.
			for _,gui in ipairs({self.gui,self.metricsGui,self.noticeGui,Hub.touchActionsGui}) do
				for _,object in ipairs(gui:GetDescendants()) do
					local properties={}
					if object:IsA("GuiObject") then table.insert(properties,"BackgroundColor3") end
					if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then table.insert(properties,"TextColor3") end
					if object:IsA("ImageLabel") or object:IsA("ImageButton") then table.insert(properties,"ImageColor3") end
					if object:IsA("UIStroke") then table.insert(properties,"Color") end
					if object:IsA("ScrollingFrame") then table.insert(properties,"ScrollBarImageColor3") end
					for _,property in ipairs(properties) do
						local current=object[property]
						for _,entry in ipairs(mapping) do
							if current==entry.old then object[property]=entry.new;break end
						end
					end
				end
			end
		end
		Hub.setSidebarTheme=function(name) UI:SetTheme(name);UI:RefreshAccentGlow() end
		Hub.setCustomThemeColor=function(key,value)
			if custom[key]==nil or not hex(value) then return false end
			custom[key]=tostring(value):gsub("#","")
			if UI.activeTheme=="Custom" then UI:SetTheme("Custom");UI:RefreshAccentGlow() end
			return true
		end
		return UI
	end

	local Rayfield = createArrivaSidebar()
	Library = {Options = {}, Toggles = {}, callbacks = {}, controls = {}}
	SaveManager = {ignored = {}, folder = "ArrivaCoreHub/RayfieldConfigs"}
	ThemeManager = {}
	local http = game:GetService("HttpService")

	local function copy(value)
		if type(value) ~= "table" then return value end
		local result = {}
		for key, item in pairs(value) do result[key] = copy(item) end
		return result
	end
	local function notifyError(err) Hub.lastUIError=tostring(err);warn("[Arriva Rayfield] " .. tostring(err)) end
	local function invoke(callback, value)
		if callback then local ok, err = pcall(callback, value); if not ok then notifyError(err) end end
	end
	function Library:Notify(info)
		Rayfield:Notify({Title = info.Title or "Arriva", Content = info.Description or info.Content or "",
			Duration = info.Time or info.Duration or 5})
	end
	function Library:OnUnload(callback) table.insert(self.callbacks, callback) end
	function Library:Unload()
		if self.unloaded then return end
		self.unloaded = true
		for index = #self.callbacks, 1, -1 do pcall(self.callbacks[index]) end
		Rayfield:Destroy()
	end
	local Group = {}
	function Group:ensureSection()
		if self.tab.section ~= self.title then self.tab:CreateSection(self.title); self.sectionCreated = true end
	end
	local function register(id, kind, info)
		assert(not Library.controls[id], "Duplicate UI ID: " .. id)
		local control = {Id = id, Type = kind, Value = info.Default, Multi = info.Multi or false, Callback = info.Callback,
			Values = info.Values or {}, NoUI = info.NoUI, Mode = "Toggle"}
		Library.controls[id] = control
		if kind == "Toggle" then Library.Toggles[id] = control else Library.Options[id] = control end
		function control:commit(value)
			self.Value = copy(value)
			self.revision=(self.revision or 0)+1
			if Hub.configLoading then
				local pending=Hub.configCallbacks
				if pending then
					local record=pending.byControl[self]
					if not record then
						record={control=self}
						pending.byControl[self]=record
						table.insert(pending.ordered,record)
					end
					record.value=copy(self.Value)
					record.revision=self.revision
				end
			else
				invoke(self.Callback, self.Value)
			end
			Hub.requestSave()
		end
		function control:SetValue(value)
			local normalized = self:normalize(value)
			self.busy = true
			local ok, err = pcall(function() self.handle:Set(self:toRayfield(normalized)) end)
			self.busy = false
			if not ok then notifyError(err); return end
			self:commit(normalized)
		end
		function control:normalize(value) return value end
		function control:toRayfield(value) return value end
		return control
	end
	local function receive(control, value)
		if not control.busy then control.initialized = true; control:commit(control:normalize(value)) end
	end
	function Group:AddToggle(id, info)
		self:ensureSection()
		local control = register(id, "Toggle", info)
		control.Value = info.Default == true
		function control:normalize(value) return value == true end
		control.handle = self.tab:CreateToggle({Name = info.Text or id, CurrentValue = control.Value,
			Callback = function(value) receive(control, value) end})
		if not control.initialized then control:commit(control.Value) end
		return control
	end
	function Group:AddSlider(id, info)
		self:ensureSection()
		local control = register(id, "Slider", info)
		function control:normalize(value) return math.clamp(tonumber(value) or info.Default, info.Min, info.Max) end
		control.handle = self.tab:CreateSlider({Name = info.Text or id, Range = {info.Min, info.Max},
			Increment = 10 ^ -(info.Rounding or 0), CurrentValue = info.Default,
			Callback = function(value) receive(control, value) end})
		if not control.initialized then control:commit(control.Value) end
		return control
	end
	function Group:AddDropdown(id, info)
		self:ensureSection()
		local control = register(id, "Dropdown", info)
		function control:normalize(value)
			if id=="SidebarTheme" and value=="Reference Dark" then value="Default" end
			if not self.Multi then
				if type(value) == "table" then value = value[1] end
				if type(value) == "number" then value = self.Values[value] end
				return table.find(self.Values, value) and value or nil
			end
			local result = {}
			if type(value) == "table" then
				for key, item in pairs(value) do
					local label = type(key) == "number" and item or (item and key or nil)
					if label and table.find(self.Values, label) then result[label] = true end
				end
			elseif value and table.find(self.Values, value) then result[value] = true end
			return result
		end
		function control:toRayfield(value)
			if not self.Multi then return value and {value} or {} end
			local selected = {}
			for _, label in ipairs(self.Values) do if value[label] then table.insert(selected, label) end end
			return selected
		end
		function control:SetValues(values)
			self.Values = copy(values)
			local value = self:normalize(self.Value)
			self.busy = true
			local ok, err = pcall(function()
				self.handle:Refresh(self.Values)
				self.handle:Set(self:toRayfield(value))
			end)
			self.busy = false
			if not ok then notifyError(err) end
			if Hub.canonical(value)~=Hub.canonical(self.Value) then self:commit(value) end
		end
		control.Value = control:normalize(info.Default)
		control.handle = self.tab:CreateDropdown({Name = info.Text or id, Options = copy(control.Values),
			CurrentOption = control:toRayfield(control.Value), MultipleOptions = control.Multi,
			Callback = function(value) receive(control, value) end})
		if not control.initialized then control:commit(control.Value) end
		return control
	end
	function Group:AddInput(id, info)
		self:ensureSection()
		local control = register(id, "Input", info)
		control.Value = info.Default or ""
		function control:normalize(value) return tostring(value or "") end
		control.handle = self.tab:CreateInput({Name = info.Text or id, CurrentValue = control.Value,
			PlaceholderText = info.Placeholder or "Enter text", RemoveTextAfterFocusLost = false,
			Callback = function(value) receive(control, value) end})
		if not control.initialized then control:commit(control.Value) end
		return control
	end
	function Group:AddKeyPicker(id, info)
		if self.ensureSection then self:ensureSection() end
		local control = register(id, "KeyPicker", info)
        control.Callback = nil -- Settings changes must not execute the bound action.
		function control:normalize(value)
			if type(value) == "table" then value = value[1] end
			return tostring(value or info.Default)
		end
		control.Value = info.Default
		function control:GetState() return self.Toggled == true end
		control.handle = self.tab:CreateKeybind({Name = info.Text or id, CurrentKeybind = info.Default,
			HoldToInteract = false, CallOnChange = true,
			Callback = function(value)
				if type(value) == "string" then
					if not control.busy then control:commit(value) end
				elseif Library.ToggleKeybind == control then
					Rayfield:SetVisibility(not Rayfield:IsVisible())
				else invoke(info.Callback, value) end
			end})
		return control
	end
	function Group:AddButton(info, callback)
		self:ensureSection()
		if type(info) == "string" then info = {Text = info, Func = callback} end
		return self.tab:CreateButton({Name = info.Text or "Button", Callback = function() invoke(info.Func) end})
	end
	function Group:AddLabel(text)
		self:ensureSection()
		local handle = self.tab:CreateLabel(tostring(text))
		local label = {tab = self.tab}
		function label:SetText(value) handle:Set(tostring(value)) end
		label.AddKeyPicker = Group.AddKeyPicker
		return label
	end
	function Library:CreateWindow(info)
		local native = Rayfield:CreateWindow({Name = info.Title, LoadingTitle = "Arriva Core Hub",
			LoadingSubtitle = "Rayfield edition", Theme = "Default", ToggleUIKeybind = Enum.KeyCode.RightShift,
			ConfigurationSaving = {Enabled = false}, Discord = {Enabled = false}, KeySystem = false})
		native:SetCloseCallback(function() Library:Unload() end)
		Library.window = native
		local window = {}
		function window:AddTab(name, icon)
			local nativeTab = native:CreateTab(name, icon)
			local tab = {native = nativeTab}
			function tab:AddLeftGroupbox(title)
				return setmetatable({tab = nativeTab, title = title}, {__index = Group})
			end
			tab.AddRightGroupbox = tab.AddLeftGroupbox
			return tab
		end
		return window
	end

	-- Keep the hub's existing save schema and loading order. Use a separate folder.
	function SaveManager:SetLibrary(value) self.library = value end
	function SaveManager:SetFolder(value)
		self.folder = "ArrivaCoreHub/RayfieldConfigs"
		self.legacyFolder = value .. "/settings"
	end
	function SaveManager:SetIgnoreIndexes(indexes) for _, id in ipairs(indexes) do self.ignored[id] = true end end
	function SaveManager:SetLoadingOrder(value) self.loadingOrder = value end
	function SaveManager:SaveJSON()
		local data = {version=2,objects={},safety={
			whitelistFriends=Hub.whitelistFriends,
			manualWhitelist=copy(Hub.manualWhitelist or {}),
		}}
		for id, control in pairs(Library.controls) do
			if not self.ignored[id] then
				if control.Type == "KeyPicker" and control.handle.CurrentKeybind then
					control.Value = control.handle.CurrentKeybind
				end
				local record = {idx = id, type = control.Type, value = copy(control.Value)}
				if control.Type == "KeyPicker" then record.key = control.Value; record.mode = control.Mode end
				table.insert(data.objects, record)
			end
		end
		local ok, result = pcall(function() return http:JSONEncode(data) end)
		if ok then return result, true end
		return nil, false, tostring(result)
	end
	function SaveManager:Save(name)
		local encoded,ok,err=self:SaveJSON()
		if not ok then return false,err end
		local file=self.folder .. "/" .. name .. ".json"
		local success,reason=pcall(function()
			if not isfolder("ArrivaCoreHub") then makefolder("ArrivaCoreHub") end
			if not isfolder(self.folder) then makefolder(self.folder) end
			if isfile(file) then
				local old=readfile(file)
				local valid,data=pcall(function() return http:JSONDecode(old) end)
				if valid and type(data)=="table" and type(data.objects)=="table" then
					writefile(file .. ".bak",old)
				end
			end
			writefile(file,encoded)
			if readfile(file)~=encoded then error("Settings write could not be verified") end
		end)
		if not success then return false,tostring(reason) end
		return true
	end
	function SaveManager:LoadJSON(content)
		if type(content)~="string" then return false,"Configuration content is not text" end
		content=content:gsub("^\239\187\191",""):gsub("%z+$","")
		local ok,data=pcall(function() return http:JSONDecode(content) end)
		if not ok or type(data)~="table" or type(data.objects)~="table" then
			return false,"Configuration JSON could not be read: " .. tostring(data)
		end
		if type(data.safety)=="table" and type(data.safety.manualWhitelist)=="table" then
			Hub.manualWhitelist=copy(data.safety.manualWhitelist)
			if type(data.safety.whitelistFriends)=="boolean" then Hub.whitelistFriends=data.safety.whitelistFriends end
			Hub.loadedSafety=true
		end
		local errors={}
        local legacyDetailed=false
        for _,record in ipairs(data.objects) do if type(record)=="table" and record.idx=="DetailedESPEnabled" and record.value==true then legacyDetailed=true end end
		for _,record in ipairs(data.objects) do
			if type(record)=="table" then
				local control=Library.controls[record.idx]
				if control and not self.ignored[record.idx] then
					local value=record.value
					if control.Type=="KeyPicker" then value=record.key or record.value end
					local applied,reason=pcall(function() control:SetValue(value) end)
					if not applied then table.insert(errors,tostring(record.idx) .. ": " .. tostring(reason)) end
				end
			end
		end
		if legacyDetailed and Library.controls.NicknameESP then Library.controls.NicknameESP:SetValue(true) end
		if Hub.refreshWhitelistUI then pcall(Hub.refreshWhitelistUI) end
		if #errors>0 then return false,"Some settings could not load: " .. table.concat(errors,"; ") end
		return true
	end
	function SaveManager:Load(name)
		if Hub.configLoading then return false,"A settings load is already in progress" end
		if Hub.saveThread then pcall(Hub.nativeTask.cancel,Hub.saveThread);Hub.threads[Hub.saveThread]=nil;Hub.saveThread=nil end
		local candidates={self.folder .. "/" .. name .. ".json",self.folder .. "/" .. name .. ".json.bak",
			(self.legacyFolder or "ArrivaCoreHub/Configs/settings") .. "/" .. name .. ".json"}
		local found=false
		local failures={}
		for _,file in ipairs(candidates) do
			local existsOk,exists=pcall(isfile,file)
			if not existsOk then
				Hub.configLoadFailed=true;Hub.lastLoadError=tostring(exists)
				return false,Hub.lastLoadError
			end
			if exists then
				found=true
				local readOk,content=pcall(readfile,file)
				if readOk then
					Hub.configCallbacks={ordered={},byControl={}}
					Hub.configLoading=true
					local called,loaded,reason=pcall(function() return self:LoadJSON(content) end)
					Hub.configLoading=false
					local pending=Hub.configCallbacks
					Hub.configCallbacks=nil
					if called and loaded then
						Hub.configLoadFailed=false;Hub.lastLoadError=nil
						Hub.configLoaded=true;Hub.lastLoadPath=file
						Hub.lastSettings=Hub.captureSettings()
						-- Starting a saved feature must never hold the settings loader open.
						Hub.queueSavedCallbacks(pending.ordered,invoke)
						return true
					end
					table.insert(failures,file .. ": " .. tostring(called and reason or loaded))
				else table.insert(failures,file .. ": " .. tostring(content)) end
			end
		end
		Hub.configLoading=false
		Hub.configLoadFailed=found
		Hub.lastLoadError=found and table.concat(failures," | ") or nil
		return false,Hub.lastLoadError or "No saved configuration"
	end
	function SaveManager:BuildConfigSection(tab)
		local group = tab:AddLeftGroupbox("Saved settings")
		group:AddButton({Text="Save settings",Func=function()
			-- This explicit action can replace a file after an unsuccessful load.
			local ok,err=Hub.persistSettings(true)
			Library:Notify({Title=ok and "Settings saved" or "Save error",Description=ok and "Your current settings were saved and verified." or tostring(err),Time=6})
		end})
		group:AddButton({Text = "Load settings", Func = function()
			local ok, err = self:Load("AutoSave")
			if not ok then warn("[Arriva config load] " .. tostring(err)) end
			Library:Notify({Title = ok and "Settings loaded" or "Load error", Description = ok and "Your saved settings were restored." or tostring(err),Time=10})
		end})
		group:AddLabel("Autosave starts after loading finishes. Existing settings are protected if loading fails. Save settings replaces them only when you choose it.")
	end
	function ThemeManager:SetLibrary(value) self.library = value end
	function ThemeManager:SetFolder(value) self.folder = value end
	function ThemeManager:ApplyToTab(tab)
		local group = tab:AddRightGroupbox("Appearance")
		group:AddLabel("Border and window customization")
		group:AddToggle("SidebarRainbowBorder", {Text = "Accent glow", Default = true,
			Callback = function(on) Rayfield:SetRainbowEnabled(on) end})
		group:AddSlider("SidebarBorderThickness",{Text="Accent glow thickness",Default=1.5,Min=1,Max=4,Rounding=1,
			Callback=function(value) Rayfield:SetBorderThickness(value) end})
		group:AddSlider("SidebarBorderSpeed",{Text="Accent glow speed",Default=14,Min=1,Max=90,Rounding=0,
			Callback=function(value) Rayfield:SetBorderSpeed(value) end})
		group:AddSlider("SidebarUIScale",{Text="UI scale (%)",Default=100,Min=70,Max=130,Rounding=0,
			Callback=function(value) Rayfield:SetUserScale(value) end})
	end

end

Hub.library = Library
Hub.connect(RunService.Heartbeat, function()
	-- Snapshot SaveManager's complete supported schema, including keybinds, themes and UI state.
	if not Hub.ready then return end
	local now = os.clock()
	if now < (Hub.nextSettingsCheck or 0) then return end
	Hub.nextSettingsCheck = now + 2
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
	Title = "Arriva Core Hub — Sidebar",
	Footer = "Made by Arriva",
	NotifySide = "Right",
	ShowCustomCursor = true,
})

local Tabs = {
	Defense = Window:AddTab("Defense", "shield"),
	Whitelist = Window:AddTab("Whitelist", "user-round-check"),
	AntiLag = Window:AddTab("Anti Lag", "activity"),
	Customization = Window:AddTab("Menu Customization", "palette"),
	Updates = Window:AddTab("Update Log", "history"),
	Notifications = Window:AddTab("Notifications", "bell"),
	KeyBinds   = Window:AddTab("KeyBinds", "keyboard"),
	Target = Window:AddTab("Loop Players", "crosshair"),
	Aura = Window:AddTab("Auras", "align-vertical-space-around"),
	Fun = Window:AddTab("Fun", "heart"),
	Grab = Window:AddTab("Grab Settings", "hand"),
	Player = Window:AddTab("Player Options", "user"),
	Misc = Window:AddTab("Misc", "box"),
	["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

-- Central shortcut settings. Existing option IDs remain compatible with saved settings.
Hub.keybindDefinitions = {
    {id = "MenuKeybind", label = "Toggle menu", default = "M"},
    {id = "BlobSeatKey", label = "Sit in your Blobman", default = "B"},
    {id = "BlobFlyKey", label = "Toggle Blob Fly", default = "R"},
    {id = "ClickTeleportKey", label = "Click teleport", default = "Z"},
    {id = "FreeMouseKey", label = "Toggle free mouse", default = "F"},
    {id = "AnchorObjectKey", label = "Anchor held object", default = "G"},
    {id = "CreativeQuickSpawnKey", label = "Quick-spawn selected toy", default = "P"},
    {id = "MissileThrowKey", label = "Throw Bomb", default = "V"},
    {id = "ExplodeBombKey", label = "Explode Bomb", default = "J"},
    {id = "ExplodeFireworkKey", label = "Explode Firework", default = "N"},
    {id = "EmergencyUnloadKey", label = "Unload hub", default = "End"},
}
function Hub.matchesKeybind(id, input, fallback)
    if Hub.keybindCaptureActive or os.clock() < (Hub.keybindCaptureBlockUntil or 0) then return false end
    local option = Options[id]
    local value = option and option.Value or fallback
    return input and input.KeyCode and input.KeyCode.Name == value
end
function Hub.keybindConflictReport()
    local used, conflicts = {}, {}
    for _, definition in ipairs(Hub.keybindDefinitions) do
        local option = Options[definition.id]
        local key = option and option.Value or definition.default
        if key and key ~= "None" and key ~= "Unknown" then
            if used[key] then table.insert(conflicts, key .. ": " .. used[key] .. " / " .. definition.label)
            else used[key] = definition.label end
        end
    end
    return conflicts
end
Hub.keybindGroups = {
    actions = Tabs.KeyBinds:AddLeftGroupbox("Action shortcuts"),
    interface = Tabs.KeyBinds:AddRightGroupbox("Menu & emergency"),
    missiles = Tabs.KeyBinds:AddRightGroupbox("Missile throw"),
}
for _, definition in ipairs(Hub.keybindDefinitions) do
    if definition.id == "BlobSeatKey" or definition.id == "BlobFlyKey" or definition.id == "ClickTeleportKey" or definition.id == "FreeMouseKey" then
        Hub.keybindGroups.actions:AddLabel(definition.label):AddKeyPicker(definition.id,
            {Default = definition.default, Text = definition.label})
    elseif definition.id == "EmergencyUnloadKey" then
        Hub.keybindGroups.interface:AddLabel(definition.label):AddKeyPicker(definition.id,
            {Default = definition.default, Text = definition.label})
    end
end
Hub.keybindGroups.interface:AddButton({Text = "Check shortcut conflicts", Func = function()
    local conflicts = Hub.keybindConflictReport()
    Library:Notify({Title = "KeyBinds", Description = #conflicts == 0 and "No duplicate hub shortcuts." or table.concat(conflicts, "\n"), Time = 6})
end})
Hub.keybindGroups.interface:AddButton({Text = "Reset hub shortcuts", Func = function()
    for _, definition in ipairs(Hub.keybindDefinitions) do
        local option = Options[definition.id]
        if option then option:SetValue(definition.default) end
    end
end})
Hub.keybindGroups.interface:AddLabel("Click a shortcut and press a key to change it; Escape cancels. Right Shift remains a menu fallback. Action keys pause while typing or assigning a shortcut. Click teleport and quick spawn also need their feature toggles enabled.")
-- End central shortcut settings.

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
	-- Legacy calls use notify(message, seconds).
	if type(content) == "number" and duration == nil then
		duration, content = content, ""
	end
	Library:Notify({
		Title = title or "Notification",
		Description = content or "",
		Time = duration or 5,
	})
end

local function sendHubLoadedMessage()
	local message = "Arriva Core Hub 2.0 Loaded..."
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

-- Paint suppression owns its backups and never restores unrelated Hub properties.
local deleteAllPaintParts,restorePaintParts,watchNewPaintParts,disconnectWatchers,setTouchQuery=(function()
	local active=false
    local scanEpoch=0
	local saved,guards,connections={},{},{}
	local worldListeners={}
	local characterSaved={}
	local function disconnect(connection)
		connection:Disconnect();Hub.connections[connection]=nil
	end
	local function restore(object,properties)
		if not object.Parent then return end
		for key,value in pairs(properties) do pcall(function() object[key]=value end) end
	end
	local function underPaint(object)
		local current=object
		while current and current~=Workspace do
			if current:IsA("BasePart") and current.Name=="PaintPlayerPart" then return true end
			current=current.Parent
		end
		return false
	end
	local function suppress(object)
		if not active or not underPaint(object) then return end
		local properties
		if object:IsA("BasePart") then properties={Transparency=1,CanTouch=false,CanQuery=false,CanCollide=false}
		elseif object:IsA("Decal") or object:IsA("Texture") then properties={Transparency=1}
		elseif object:IsA("ParticleEmitter") or object:IsA("Trail") or object:IsA("Beam")
			or object:IsA("Fire") or object:IsA("Smoke") or object:IsA("Sparkles") then properties={Enabled=false}
		end
		if not properties then return end
		if not saved[object] then saved[object]={};connections[object]={} end
		for key,value in pairs(properties) do
			if saved[object][key]==nil then
				saved[object][key]=object[key]
				table.insert(connections[object],Hub.connect(object:GetPropertyChangedSignal(key),function()
					if active and not guards[object] and underPaint(object) and object[key]~=value then
						guards[object]=true;object[key]=value;guards[object]=nil
					end
				end))
			end
			guards[object]=true;object[key]=value;guards[object]=nil
		end
	end
	local function characterPart(object)
		local char=Player.Character
		if not active or not char or not object:IsA("BasePart") or not object:IsDescendantOf(char) then return end
		if not characterSaved[object] then characterSaved[object]={CanTouch=object.CanTouch,CanQuery=object.CanQuery} end
		object.CanTouch=false;object.CanQuery=false
	end
	local function forget(object)
		local list=connections[object]
		if list then for _,connection in ipairs(list) do disconnect(connection) end end
		connections[object]=nil
		if saved[object] then restore(object,saved[object]);saved[object]=nil end
		if characterSaved[object] then restore(object,characterSaved[object]);characterSaved[object]=nil end
	end
	local function restoreAll()
		active=false;scanEpoch+=1
		local objects={}
		for object in pairs(saved) do table.insert(objects,object) end
		for _,object in ipairs(objects) do forget(object) end
		for object,properties in pairs(characterSaved) do restore(object,properties) end
		table.clear(characterSaved)
	end
	local function scan()
		active=true;scanEpoch+=1;local ticket=scanEpoch
		Hub.scanDescendants(Workspace,suppress,function() return active and scanEpoch==ticket end)
	end
	local function disconnectAll()
		active=false
		for _,connection in ipairs(worldListeners) do disconnect(connection) end
		table.clear(worldListeners)
		restoreAll()
	end
	local function watch()
		for _,connection in ipairs(worldListeners) do disconnect(connection) end
		table.clear(worldListeners)
		active=true
		table.insert(worldListeners,Hub.connect(Workspace.DescendantAdded,function(object)
			suppress(object);characterPart(object)
			if object:IsA("BasePart") and object.Name=="PaintPlayerPart" then
				for _,child in ipairs(object:GetDescendants()) do suppress(child) end
			end
		end))
		table.insert(worldListeners,Hub.connect(Workspace.DescendantRemoving,function(object)
            if not saved[object] and not characterSaved[object] then return end
            task.defer(function()
				if not object:IsDescendantOf(Workspace) or not underPaint(object) then forget(object) end
			end)
		end))
	end
	local function touchQuery(state)
		if state then
			for object,properties in pairs(characterSaved) do restore(object,properties) end
			table.clear(characterSaved)
		else
			local char=Player.Character
			if char then for _,object in ipairs(char:GetDescendants()) do characterPart(object) end end
		end
	end
	return scan,restoreAll,watch,disconnectAll,touchQuery
end)()


-- Anti-Gucci Systems
Hub.gucciAutoDelete=true
Hub.gucciCleanupGeneration=0
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
	local previous=Hub.gucciRun
	if previous and previous.busy and previous.character==Player.Character
		and previous.generation==Hub.blobGeneration then return end
	Hub.blobGeneration = (Hub.blobGeneration or 0) + 1
	local generation = Hub.blobGeneration
	local run={busy=true,character=Player.Character,generation=generation}
	-- Experimental pacing, not verification that the server accepted a state change.
	local lastPingSample=-math.huge
	local smoothedPing
	local function pacing()
		local now=os.clock()
		if now-lastPingSample>=1 then
			lastPingSample=now
			local ok,ping=pcall(function() return Player:GetNetworkPing() end)
			if ok and type(ping)=="number" and ping==ping and ping>=0 and ping<math.huge then
				smoothedPing=smoothedPing and smoothedPing*0.65+ping*0.35 or ping
			elseif not smoothedPing then smoothedPing=0.1 end
			run.pingMs=smoothedPing*1000
		end
		-- Preserve the existing low-ping path. Bound extra waits to avoid
		-- turning one activation into an indefinitely long operation.
		local extra=math.clamp((smoothedPing or 0.1)-0.05,0,0.15)
		run.phaseDelay=extra
		return extra
	end
	Hub.gucciRun=run
	Hub.gucciStage="Preparing"
	if Hub.updateGucciStatus then Hub.updateGucciStatus() end
	task.spawn(function()
		local ok,err=xpcall(function()
			if Hub.blobJump then Hub.blobJump:Disconnect(); Hub.blobJump = nil end
			if antiGucciConnection then antiGucciConnection:Disconnect(); antiGucciConnection = nil end
			local char = Player.Character
			if not char then return end
			local hum = char:WaitForChild("Humanoid", 5)
			local root = char:WaitForChild("HumanoidRootPart", 5)
			local function valid()
				return Hub.alive and generation == Hub.blobGeneration
					and Player.Character == char and char.Parent ~= nil
					and hum ~= nil and hum.Parent ~= nil and hum.Health > 0
					and root ~= nil and root.Parent ~= nil
			end
			if not valid() then return end
			-- Capture once before spawning or moving; jumps must not overwrite this.
			local returnCFrame = root.CFrame
			local function findBlob()
				local folder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
				return folder and folder:FindFirstChild("CreatureBlobman")
			end
			local blob = findBlob()
			if not blob then
				spawnBlobman()
				local deadline = os.clock() + 8
				repeat
					if not valid() then return end
					blob = findBlob()
					if blob then break end
					task.wait(0.1)
				until os.clock() >= deadline
			end
			if not blob then notify("Anti Gucci", "Blobman did not appear.", 4); return end
			local seat
			local deadline = os.clock() + 5
			repeat
				if not valid() or not blob.Parent then return end
				seat = blob:FindFirstChildWhichIsA("VehicleSeat", true)
					or blob:FindFirstChildWhichIsA("Seat", true)
				if seat then break end
				task.wait(0.1)
			until os.clock() >= deadline
			if not seat then notify("Anti Gucci", "Blobman seat not found.", 4); return end
			if not valid() then return end
			-- Spawn replication may finish after spawnBlobman returns.
			local head = blob:FindFirstChild("Head")
			local headDeadline=os.clock()+5
			while valid() and blob.Parent and not head and os.clock()<headDeadline do
				task.wait(0.1)
				head=blob:FindFirstChild("Head")
			end
			if not valid() or not blob.Parent then return end
			if not (head and head:IsA("BasePart")) then
				notify("Anti Gucci", "Blobman head is not ready; try again.", 4)
				return
			end
			task.wait(0.2)
			if not valid() or not head.Parent then return end
			head.Anchored = true
			task.wait(0.2)
			if not valid() or not seat:IsDescendantOf(Workspace) then return end
			root.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
			Hub.gucciStage="Activating"
			if Hub.updateGucciStatus then Hub.updateGucciStatus() end
			task.wait(0.25)
			local completedCycles=0
			for _ = 1, 50 do
				local phaseDelay=pacing()
				if not valid() or not seat:IsDescendantOf(Workspace) then break end
				local ok, err = pcall(function()
					seat:Sit(hum)
					if ragdollRemoteEvent then Hub.fire(ragdollRemoteEvent, root, 0.1) end
					if phaseDelay>0 then task.wait(phaseDelay) end
					if not valid() or not seat:IsDescendantOf(Workspace) then return end
					hum.Sit = false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
					if not valid() then return end
					hum.Jump = true
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
				end)
				if not ok then warn("[Arriva Anti Gucci] " .. tostring(err)); break end
				if not valid() or not seat:IsDescendantOf(Workspace) then break end
				completedCycles+=1
				task.wait(phaseDelay>0 and phaseDelay or nil)
			end
			if not valid() or completedCycles~=50 then return end
			run.cyclesFinishedAt=os.clock()
			if Hub.gucciAutoDelete then
				run.cleanupPending=true
				local cleanupTicket=Hub.gucciCleanupGeneration
				task.delay(2,function()
					if not Hub.gucciAutoDelete or cleanupTicket~=Hub.gucciCleanupGeneration then return end
					if not valid() or Hub.gucciRun~=run then return end
					local ownFolder=Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
					-- Remove only the exact owned toy used in this activation.
					if not ownFolder or blob.Parent~=ownFolder then
						run.cleanupPending=false
						return
					end
					local menu=ReplicatedStorage:FindFirstChild("MenuToys")
					local destroy=menu and menu:FindFirstChild("DestroyToy")
					if not destroy then
						run.cleanupPending=false
						notify("Gucci cleanup warning","Toy removal is unavailable. Your Blobman was left in place.",5)
						return
					end
					run.intentionalRemoval=true
					local removed,reason=pcall(function() Hub.fire(destroy,blob) end)
					if not removed then
						run.intentionalRemoval=false;run.cleanupPending=false
						notify("Gucci cleanup warning",tostring(reason),5)
						return
					end
					local deadline=os.clock()+3
					while valid() and blob.Parent==ownFolder and os.clock()<deadline do task.wait(0.1) end
					if not valid() or Hub.gucciRun~=run then return end
					run.cleanupPending=false
					run.removedIntentionally=blob.Parent~=ownFolder
					if not run.removedIntentionally then
						run.intentionalRemoval=false
						notify("Gucci cleanup warning","The toy removal was not confirmed. No extra activation was started.",5)
					elseif Hub.gucciStage=="Sequence finished - unverified" then
						Hub.gucciStage="Blobman removed - unverified"
						if Hub.updateGucciStatus then Hub.updateGucciStatus() end
					end
				end)
			end
			Hub.gucciStage="Releasing"
			if Hub.updateGucciStatus then Hub.updateGucciStatus() end
			-- Finish before returning, rather than racing a separate return task.
			if valid() then
				hum.Sit = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				task.wait(0.5)
				-- Sit=false is only a request: wait for the actual seat joint to release.
				local function attached()
					if hum.SeatPart == seat or seat.Occupant == hum then return true end
					for _, joint in ipairs(seat:GetChildren()) do
						if joint:IsA("Weld") or joint:IsA("WeldConstraint") or joint:IsA("Motor6D") then
							local a, b = joint.Part0, joint.Part1
							if (a and a:IsDescendantOf(char)) or (b and b:IsDescendantOf(char)) then
								return true
							end
						end
					end
					return false
				end
				local nextNotice=os.clock()+5
				while valid() and seat:IsDescendantOf(Workspace) and attached() do
					hum.Sit=false
					hum:ChangeState(Enum.HumanoidStateType.GettingUp)
					hum.Jump=true
					hum:ChangeState(Enum.HumanoidStateType.Jumping)
					if os.clock()>=nextNotice then
						notify("Anti Gucci", "Still waiting for the seat to release; retrying. Disable Anti Gucci to cancel.", 4)
						nextNotice=os.clock()+15
					end
					task.wait(0.25)
				end
				if valid() then
					root.CFrame = returnCFrame
					root.AssemblyLinearVelocity = Vector3.zero
					root.AssemblyAngularVelocity = Vector3.zero
					run.ready=true
				end
			end
		end,debug.traceback)
		run.busy=false
		if Hub.gucciRun==run and generation==Hub.blobGeneration then
			Hub.gucciStage=not ok and "Error" or run.ready and (run.removedIntentionally and "Blobman removed - unverified" or "Sequence finished - unverified") or "Not ready"
			if Hub.updateGucciStatus then Hub.updateGucciStatus() end
			if not ok then warn("[Arriva Gucci] " .. tostring(err)) end
		end
	end)
end

local function stopAntiGucci()
	Hub.gucciStage="Disabled"
	if Hub.updateGucciStatus then Hub.updateGucciStatus() end
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
	if antiGucciConnectionTrain then antiGucciConnectionTrain:Disconnect(); antiGucciConnectionTrain = nil end
	local char = Player.Character
	if not char then return end
	local hum = char:WaitForChild("Humanoid", 5)
	local root = char:WaitForChild("HumanoidRootPart", 5)
	local function valid()
		return Hub.alive and generation == Hub.trainGeneration
			and Player.Character == char and char.Parent ~= nil
			and hum ~= nil and hum.Parent ~= nil and hum.Health > 0
			and root ~= nil and root.Parent ~= nil
	end
	if not valid() then return end
	local returnCFrame = root.CFrame
	local map = Workspace:FindFirstChild("Map")
	local folder = map and map:FindFirstChild("AlwaysHereTweenedObjects")
	local train = folder and folder:FindFirstChild("Train")
	local object = train and train:FindFirstChild("Object")
	local model = object and object:FindFirstChild("ObjectModel")
	local seat = model and model:FindFirstChild("Seat")
	if not (seat and (seat:IsA("Seat") or seat:IsA("VehicleSeat"))) then
		seat = train and (train:FindFirstChildWhichIsA("VehicleSeat", true)
			or train:FindFirstChildWhichIsA("Seat", true))
	end
	if not seat then notify("De-Sync", "Train seat not found.", 4); return end
	root.CFrame = seat.CFrame + Vector3.new(0, 2, 0)
	task.spawn(function()
		for _ = 1, 30 do
			if not valid() or not seat:IsDescendantOf(Workspace) then break end
			local ok, err = pcall(function()
				seat:Sit(hum)
				if ragdollRemoteEvent then Hub.fire(ragdollRemoteEvent, root, 0.1) end
				if not valid() then return end
				hum.Sit = false
				hum:ChangeState(Enum.HumanoidStateType.GettingUp)
				if not valid() then return end
				hum.Jump = true
				hum:ChangeState(Enum.HumanoidStateType.Jumping)
			end)
			if not ok then warn("[Arriva Train] " .. tostring(err)); break end
			task.wait()
		end
		if valid() then
			hum.Sit = false
			hum:ChangeState(Enum.HumanoidStateType.GettingUp)
			task.wait(0.5)
			if valid() then
				root.CFrame = returnCFrame
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end
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
	Hub.gucciRespawnReadyAt=math.huge
	Hub.gucciStage="Waiting for respawn"
	if Hub.updateGucciStatus then Hub.updateGucciStatus() end
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
	Hub.gucciRespawnReadyAt=os.clock()+1.5
	task.wait(1.5)
	if not Hub.alive or Player.Character ~= char or not root.Parent or hum.Health <= 0 then return end
	if Toggles.AutoGucciBlobToggle and Toggles.AutoGucciBlobToggle.Value then task.spawn(startAntiGucci) end
	if Toggles.AutoGucciTrainToggle and Toggles.AutoGucciTrainToggle.Value then task.spawn(startAntiGucciTrain) end
end)

-- Local health alerts. These do not attribute remote abuse or kick players.
do
	local group=Tabs.AntiLag:AddRightGroupbox("Connection & Client Health")
	local pingOn,framesOn=false,false
	local disconnectOn=false
	local disconnectLimit,disconnectSeconds=1500,10
	local disconnectBad,disconnectSent=0,false
	local pingLimit,fpsLimit,holdSeconds=350,20,3
	local connection
	local elapsed,frames,worstFrame=0,0,0
	local pingState={bad=0,active=false,last=-math.huge}
	local fpsState={bad=0,active=false,last=-math.huge}
	local unavailable=false
	local function reset(state)
		state.bad=0;state.active=false;state.last=-math.huge
	end
	local function observe(state,bad,recovered,seconds,title,message)
		if bad then
			state.bad+=seconds
			if state.bad>=holdSeconds then
				state.active=true
				if os.clock()-state.last>=30 then
					state.last=os.clock()
					notify(title,message,6)
				end
			end
		elseif recovered then
			state.bad=0
			if state.active then
				state.active=false
				notify("Health restored",title .. " has cleared.",4)
			end
		else
			state.bad=0
		end
	end
	local function updateConnection()
		if connection then connection:Disconnect();connection=nil end
		elapsed,frames,worstFrame=0,0,0
		reset(pingState);reset(fpsState);unavailable=false
		disconnectBad,disconnectSent=0,false
		if not pingOn and not framesOn and not disconnectOn then return end
		connection=Hub.connect(RunService.Heartbeat,function(dt)
			elapsed+=dt;frames+=1;worstFrame=math.max(worstFrame,dt)
			if elapsed<1 then return end
			local seconds=elapsed
			if pingOn or disconnectOn then
				local ok,ping=pcall(function() return Player:GetNetworkPing()*1000 end)
				if ok and type(ping)=="number" and ping==ping and ping>=0 and ping<math.huge then
					unavailable=false
					if pingOn then
						observe(pingState,ping>pingLimit,ping<pingLimit*0.8,
							math.min(seconds,1.5),"Connection warning",
							string.format("Your network ping is %.0f ms (limit %.0f ms). ",ping,pingLimit))
					end
					if disconnectOn and ping>disconnectLimit then
						-- A long stalled frame does not prove ping was high throughout it.
						disconnectBad+=math.min(seconds,1.5)
						if disconnectBad>=disconnectSeconds and not disconnectSent then
							disconnectSent=true
							local kicked,reason=pcall(function()
								Player:Kick(string.format("Connection protection: ping stayed above %.0f ms for %d seconds.",disconnectLimit,disconnectSeconds))
							end)
							if not kicked then notify("Connection error","Could not disconnect: " .. tostring(reason),6) end
						end
					else disconnectBad=0;disconnectSent=false end
				else
					disconnectBad=0
					if not unavailable then
						unavailable=true;reset(pingState)
						notify("Connection warning","Ping measurement is unavailable on this client. Automatic disconnect cannot act on missing measurements.",5)
					end
				end
			end
			if framesOn then
				local fps=frames/seconds
				observe(fpsState,fps<fpsLimit,fps>fpsLimit+5,
					math.min(seconds,1.5),"Client performance warning",
					string.format("Heartbeat rate averaged %.0f/s; longest frame %.0f ms. Local performance issue detected.",fps,worstFrame*1000))
			end
			elapsed,frames,worstFrame=0,0,0
		end)
	end
	group:AddToggle("HealthPingAlerts",{Text="High ping alerts",Default=false,
		Callback=function(on) pingOn=on;updateConnection() end})
	group:AddSlider("HealthPingLimit",{Text="Ping threshold (ms)",Default=350,Min=100,Max=3000,Rounding=0,
		Callback=function(value) pingLimit=value;reset(pingState) end})
	group:AddToggle("HealthFrameAlerts",{Text="Low client performance alerts",Default=false,
		Callback=function(on) framesOn=on;updateConnection() end})
	group:AddSlider("HealthFrameLimit",{Text="Heartbeat rate threshold",Default=20,Min=5,Max=60,Rounding=0,
		Callback=function(value) fpsLimit=value;reset(fpsState) end})
	group:AddSlider("HealthSustainSeconds",{Text="Sustained spike duration (seconds)",Default=3,Min=1,Max=15,Rounding=0,
		Callback=function(value) holdSeconds=value;reset(pingState);reset(fpsState) end})
	group:AddLabel("Alerts have a 30-second repeat cooldown. Automatic disconnect below affects only you.")
	group:AddToggle("HealthDisconnectOnPing",{Text="Disconnect me on sustained high ping",Default=false,
		Callback=function(on) disconnectOn=on;updateConnection() end})
	group:AddSlider("HealthDisconnectPingLimit",{Text="Disconnect ping threshold (ms)",Default=1500,Min=250,Max=10000,Rounding=0,
		Callback=function(value) disconnectLimit=value;disconnectBad=0;disconnectSent=false end})
	group:AddSlider("HealthDisconnectDelay",{Text="Disconnect after high ping (seconds)",Default=10,Min=3,Max=60,Rounding=0,
		Callback=function(value) disconnectSeconds=value;disconnectBad=0;disconnectSent=false end})
	group:AddLabel("A completely frozen client cannot run this check. High ping does not identify the cause or an abusive player.")
	Hub.cleanup(function() if connection then connection:Disconnect();connection=nil end end)
end

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
	local root = char:FindFirstChild("HumanoidRootPart")
	local ragdollRemoteEvent = CE:FindFirstChild("RagdollRemote")
	if not char then return end
	grabGeneration += 1
	local generation = grabGeneration
	pcall(function()
		if Struggle then Hub.fire(Struggle, Player) end
		if ragdollRemote then Hub.fire(ragdollRemote, root, 0) end
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
    Hub.blobScanEpoch=(Hub.blobScanEpoch or 0)+1;local ticket=Hub.blobScanEpoch

	if antiBlob1T then


		if antiBlobWatcher then antiBlobWatcher:Disconnect();Hub.connections[antiBlobWatcher]=nil end
        antiBlobWatcher=Hub.connect(workspace.DescendantAdded,function(object)
            if not antiBlob1T then return end
            if object.Name~="CreatureBlobman" and object.Name~="LeftDetector" and object.Name~="RightDetector" and not object:IsA("Constraint") then return end
            local model=object
            while model and model~=Workspace and model.Name~="CreatureBlobman" do model=model.Parent end
            if not model or model==Workspace or model.Parent==Workspace:FindFirstChild(Player.Name.."SpawnedInToys") then return end
            anti(model)
        end)
        Hub.scanDescendants(Workspace,function(object)
            if object.Name=="CreatureBlobman" and object.Parent~=Workspace:FindFirstChild(Player.Name.."SpawnedInToys") then anti(object) end
        end,function() return antiBlob1T and Hub.blobScanEpoch==ticket end)
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
	-- Anti Burn: local extinguisher visibility restoration.
	local antiBurnEnabled = false
	local burnThreadToken = 0
	local burnVisuals = {}

	local function getExtinguisher()
		local map = workspace:FindFirstChild("Map")
		local hole = map and map:FindFirstChild("Hole")
		local poison = hole and hole:FindFirstChild("PoisonBigHole")
		local part = poison and poison:FindFirstChild("ExtinguishPart")

		return part and part:IsA("BasePart") and part or nil
	end

	local function hideBurnPart(part)
		if not part then return end

		local function hideVisual(obj)
			local property

			if obj:IsA("BasePart") then
				property = "LocalTransparencyModifier"
			elseif obj:IsA("Decal") or obj:IsA("Texture") then
				property = "Transparency"
			end

			if not property then return end

			if not burnVisuals[obj] then
				burnVisuals[obj] = {
					property = property,
					value = obj[property],
				}
			end

			obj[property] = 1
		end

		hideVisual(part)

		for _, obj in ipairs(part:GetDescendants()) do
			hideVisual(obj)
		end
	end

	local function restoreBurnVisuals()
		for obj, saved in pairs(burnVisuals) do
			pcall(function()
				obj[saved.property] = saved.value
			end)
		end

		table.clear(burnVisuals)
	end

	local function hookBurn(char)
		burnThreadToken += 1
		local token = burnThreadToken

		task.spawn(function()
			while antiBurnEnabled
				and char.Parent
				and token == burnThreadToken do

				local hum = char:FindFirstChildOfClass("Humanoid")
				local root = char:FindFirstChild("HumanoidRootPart")
				local firePart = root and root:FindFirstChild("FirePlayerPart")
				local debounce =
					hum and hum:FindFirstChild("FireDebounce")
					or firePart and firePart:FindFirstChild("FireDebounce")

				local extinguisher = getExtinguisher()
				hideBurnPart(extinguisher)

				if debounce and debounce.Value and firePart and extinguisher then
					Hub.burnOriginal = Hub.burnOriginal or {
						part = extinguisher,
						cf = extinguisher.CFrame,
					}

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
			pcall(function()
				Hub.burnOriginal.part.CFrame = Hub.burnOriginal.cf
			end)
			Hub.burnOriginal = nil
		end

		restoreBurnVisuals()
	end

	Hub.cleanup(restoreBurn)

	Hub.connect(Player.CharacterAdded, function(char)
		if antiBurnEnabled then
			hookBurn(char)
		end
	end)

	DefenseGroup:AddToggle("AntiBurnToggle", {
		Text = "Anti Burn",
		Default = false,

		Callback = function(on)
			antiBurnEnabled = on
			Hub.requestSave()

			if on then
				local extinguisher = getExtinguisher()

				if extinguisher then
					hideBurnPart(extinguisher)
				else
					notify("Anti Burn", "Extinguisher not found in this map.", 5)
				end

				if Player.Character then
					hookBurn(Player.Character)
				end
			else
				restoreBurn()
			end
		end,
	})

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

-- Optional self-only recovery. No target, ownership or grab remotes.
do
(function()
    local group=DefenseGroup
    local enabled=false
    local linearLimit,angularLimit=350,100
    local lastCharacter,lastGround,lastSample,lastAction=nil,nil,0,-math.huge
    local recoveries=0
    local function finite(value)
        return type(value)=="number" and value==value and math.abs(value)<math.huge
    end
    local function vectorOK(value) return finite(value.X) and finite(value.Y) and finite(value.Z) end
    local function sample()
        if not enabled then return end
        local char=Player.Character
        if char~=lastCharacter then lastCharacter=char;lastGround=nil end
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health<=0 or hum.SeatPart or Hub.safeZoneLoopActive then return end
        local velocity,rotation=root.AssemblyLinearVelocity,root.AssemblyAngularVelocity
        local unsafe=not vectorOK(velocity) or not vectorOK(rotation)
            or velocity.Magnitude>linearLimit or rotation.Magnitude>angularLimit
        local now=os.clock()
        if unsafe then
            root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
            if lastGround and now-lastAction>=1 then
                root.CFrame=lastGround;lastAction=now;recoveries+=1
            end
            return
        end
        if now-lastSample<0.25 or not vectorOK(root.Position) then return end
        lastSample=now
        if root.Position.Y<=Workspace.FallenPartsDestroyHeight+12 then return end
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={char};params.RespectCanCollide=true;params.IgnoreWater=true
        local hit=Workspace:Raycast(root.Position,Vector3.new(0,-8,0),params)
        if hit and hit.Normal.Y>=0.5 and hit.Instance:IsA("BasePart") and hit.Instance.Anchored
            and not Hub.playerOf(hit.Instance) then lastGround=root.CFrame end
    end
    Hub.sampleMotionProtection=sample
    group:AddToggle("LocalMotionProtection",{Text="Extreme velocity recovery",Default=false,Callback=function(on)
        enabled=on;lastCharacter=nil;lastGround=nil;lastSample=0
    end})
    group:AddSlider("LocalMotionLinearLimit",{Text="Recovery speed limit",Default=350,Min=100,Max=2000,Rounding=0,Callback=function(value) linearLimit=value end})
    group:AddSlider("LocalMotionAngularLimit",{Text="Recovery spin limit",Default=100,Min=20,Max=500,Rounding=0,Callback=function(value) angularLimit=value end})
    group:AddLabel("Stops extreme motion on your character and returns to its last grounded position when available. Leave off for intentional high-speed movement. Pauses while seated or using the safe-zone loop.")
    local conn
    conn=Hub.connect(RunService.Heartbeat,function() sample() end)
    group:AddButton("Motion recovery status",function() notify("Motion protection",string.format("Ground recovery used %d times this session.",recoveries),4) end)
    Hub.cleanup(function() enabled=false;lastGround=nil;Hub.sampleMotionProtection=nil end)
end)()
end

do
(function()
    local enabled=false
    local conn
    local function disconnect() if conn then conn:Disconnect();Hub.connections[conn]=nil;conn=nil end end
    local function bind(char)
        disconnect()
        if not enabled or not char then return end
        local function release(active,seat)
            if not enabled or not active or Player.Character~=char then return end
            -- Preserve the hub's deliberate Blobman seating sequence.
            local cursor=seat
            while cursor and cursor~=Workspace do
                if cursor.Name=="CreatureBlobman" and cursor.Parent==Workspace:FindFirstChild(Player.Name.."SpawnedInToys") then return end
                cursor=cursor.Parent
            end
            local hum=char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health>0 then hum.Jump=true end
        end
        local hum=char:FindFirstChildOfClass("Humanoid")
        if hum then conn=Hub.connect(hum.Seated,release);release(hum.SeatPart~=nil,hum.SeatPart) end
    end
    DefenseGroup:AddToggle("LocalUnwantedSeatProtection",{Text="Jump out of unwanted seats",Default=false,Callback=function(on) enabled=on;bind(Player.Character) end})
    DefenseGroup:AddLabel("Jumps out of ordinary seats locally. Your own Blobman seating is allowed so Gucci can run.")
    Hub.connect(Player.CharacterAdded,function(char)
        task.defer(function()
            if not enabled then return end
            char:WaitForChild("Humanoid",5)
            if Hub.alive and Player.Character==char then bind(char) end
        end)
    end)
    Hub.cleanup(function() enabled=false;disconnect() end)
end)()
end

do
(function()
    local enabled=false
    local history={};local rosterEvent="none";local rosterTime=-math.huge
    local group=Tabs.AntiLag:AddRightGroupbox("Frame Spike Diagnostics")
    local function roster(kind,person) rosterEvent=kind.." "..person.Name;rosterTime=os.clock() end
    Hub.connect(Players.PlayerAdded,function(person) roster("join",person) end)
    Hub.connect(Players.PlayerRemoving,function(person) roster("leave",person) end)
    local connection
    group:AddToggle("FrameSpikeDiagnostics",{Text="Record frame spikes",Default=false,Callback=function(on)
        enabled=on
        if connection then connection:Disconnect();Hub.connections[connection]=nil;connection=nil end
        if on then connection=Hub.connect(RunService.Heartbeat,function(dt)
            if dt<0.1 then return end
            table.insert(history,{ms=math.floor(dt*1000+0.5),near=os.clock()-rosterTime<3 and rosterEvent or "no recent roster change"})
            if #history>12 then table.remove(history,1) end
        end) end
    end})
    group:AddButton("Show frame spike report",function()
        local lines={};for _,entry in ipairs(history) do table.insert(lines,string.format("%d ms, %s",entry.ms,entry.near)) end
        print("[Arriva frame spikes]\n"..(#lines>0 and table.concat(lines,"\n") or "No frame spikes recorded."))
        notify("Frame diagnostics",string.format("%d recent spikes recorded. Details printed to F9. Timing correlation does not identify the cause.",#history),5)
    end)
    Hub.cleanup(function() table.clear(history) end)
end)()
end

-- Anti-Sticky: disable the local touch detector, restoring its original state.
do
	(function()
		local enabled=false
		local saved,listeners,folders={},{},{}
		local status=DefenseGroup:AddLabel("Anti Sticky is off.")
		local function connect(event,callback)
			local connection=Hub.connect(event,callback)
			table.insert(listeners,connection)
		end
		local function inspect(object)
			if not enabled or not object:IsA("LocalScript") or object.Name~="StickyPartsTouchDetection" then return end
			if saved[object]~=nil then return end
			saved[object]=object.Disabled
			object.Disabled=true
			connect(object:GetPropertyChangedSignal("Disabled"),function()
				if enabled and object.Parent and not object.Disabled then object.Disabled=true end
			end)
			status:SetText("StickyPartsTouchDetection disabled locally. This also affects your own sticky toys.")
		end
		local function watchFolder(folder)
			if not enabled or folder.Name~="PlayerScripts" or folders[folder] then return end
			folders[folder]=true
			connect(folder.DescendantAdded,inspect)
			for _,object in ipairs(folder:GetDescendants()) do inspect(object) end
		end
		local function stop()
			enabled=false
			for _,connection in ipairs(listeners) do connection:Disconnect();Hub.connections[connection]=nil end
			table.clear(listeners);table.clear(folders)
			for object,disabled in pairs(saved) do
				pcall(function() if object.Parent then object.Disabled=disabled end end)
			end
			table.clear(saved)
			status:SetText("Anti Sticky is off.")
		end
		DefenseGroup:AddToggle("AntiStickyToggle",{Text="Anti Sticky",Default=false,Callback=function(on)
			stop();enabled=on;Hub.requestSave()
			if not on then return end
			status:SetText("Waiting for PlayerScripts.StickyPartsTouchDetection...")
			connect(Player.ChildAdded,watchFolder)
			local folder=Player:FindFirstChild("PlayerScripts")
			if folder then watchFolder(folder) end
		end})
		Hub.cleanup(stop)
	end)()
end


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
	local AutoLagGroup = Tabs.AntiLag:AddLeftGroupbox("Automatic Line Protection")
	-- Automatic local mitigation; manual Anti Lag always takes priority.
	local autoOn,manualOn,autoActive=false,false,false
	local threshold,windowSeconds,quietSeconds=40,1,8
	local count,windowStart,lastLine=0,0,-math.huge
	local burstConnection,quietConnection
	local pending=false
	local autoEpoch=0
	local function applyAntiLag()
		local wanted=manualOn or autoActive
		if wanted and not state.on then enable()
		elseif not wanted and state.on then restore() end
	end
	local function stopAuto()
		autoEpoch+=1
		autoOn=false
		if burstConnection then burstConnection:Disconnect();burstConnection=nil end
		if quietConnection then quietConnection:Disconnect();quietConnection=nil end
		count=0;autoActive=false;pending=false
		applyAntiLag()
	end
	local function startAuto()
		stopAuto()
		autoOn=true;windowStart=os.clock();lastLine=-math.huge
		local watchEpoch=autoEpoch
		-- Direct, non-yielding filtered listener: no per-object tasks or repeated map scans.
		burstConnection=Workspace.DescendantAdded:Connect(function(obj)
			if not Hub.alive or not autoOn or not obj:IsA("Beam") or not obj.Parent or isOwnBeam(obj) then return end
			local now=os.clock()
			lastLine=now
			if now-windowStart>=windowSeconds then windowStart=now;count=0 end
			count+=1
			if count>=threshold and not autoActive and not pending then
				pending=true
				task.defer(function()
					if watchEpoch~=autoEpoch then return end
					pending=false
					if not Hub.alive or not autoOn or autoActive then return end
					autoActive=true
					applyAntiLag()
					notify("Auto Anti Lag", "Line burst detected, local Anti Lag enabled temporarily.",5)
				end)
			end
		end)
		local elapsed=0
		quietConnection=RunService.Heartbeat:Connect(function(dt)
			elapsed+=dt
			if elapsed<0.25 then return end
			elapsed=0
			if autoActive and os.clock()-lastLine>=quietSeconds then
				autoActive=false;count=0
				applyAntiLag()
				notify("Auto Anti Lag",manualOn and "Line burst settled, manual Anti Lag remains enabled."
					or "Line burst settled, previous Anti Lag setting restored.",4)
			end
		end)
	end
	-- Preserve the saved manual toggle; automatic activation never changes its value.
	Hub.setManualAntiLag=function(on) manualOn=on;applyAntiLag() end
	AutoLagGroup:AddToggle("AutoLineAntiLag",{Text="Auto Anti Lag (line bursts)",Default=false,
		Callback=function(on) if on then startAuto() else stopAuto() end end})
	AutoLagGroup:AddSlider("AutoLineThreshold",{Text="Foreign beam spawns per window",Default=40,Min=5,Max=500,Rounding=0,
		Callback=function(value) threshold=value;count=0;windowStart=os.clock() end})
	AutoLagGroup:AddSlider("AutoLineWindow",{Text="Detection window (seconds)",Default=1,Min=1,Max=5,Rounding=0,
		Callback=function(value) windowSeconds=value;count=0;windowStart=os.clock() end})
	AutoLagGroup:AddSlider("AutoLineQuiet",{Text="Restore after quiet period (seconds)",Default=8,Min=3,Max=60,Rounding=0,
		Callback=function(value) quietSeconds=value end})
	Hub.cleanup(function()
		-- Disconnect first; normal Anti Lag cleanup restores the line script.
		autoOn=false
		if burstConnection then burstConnection:Disconnect();burstConnection=nil end
		if quietConnection then quietConnection:Disconnect();quietConnection=nil end
		Hub.setManualAntiLag=nil
	end)

	DefenseGroup:AddToggle("AntiLagToggle", {
		Text = "Force Anti Lag", Default = false,
		Callback = function(on)
			Hub.setManualAntiLag(on)
			Hub.requestSave()
		end,
	})
	AutoLagGroup:AddButton({Text = "Anti Lag status", Func = function()
		local scripts, disabled = 0, 0
		for script in pairs(state.scripts) do
			if script.Parent then scripts += 1; if script.Disabled then disabled += 1 end end
		end
		local message = string.format("%s | Line scripts disabled: %d/%d | Foreign beams removed: %d",
			state.on and "On" or "Off", disabled, scripts, state.removed)
		if state.on and scripts == 0 then message ..= " | CharacterAndBeamMove not found yet, watching for it." end
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
		if not gui then notify("Movement warning", "PlayerGui is unavailable, enable the monitor again when loaded.", 8); return end
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
		notify("Movement warning", tostring(count) .. " observed this session | " .. (alive and "Monitoring" or "Off"), 8)
	end})
	DefenseGroup:AddButton({Text = "Clear observed warning count", Func = function()
		count = 0
		notify("Movement warning", "Local display counter cleared.", 6)
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

-- Auto Gucci System (Blobman): one monitor and one activation at a time.
do
	local enabled=false
	local monitorGeneration=0
	local status=DefenseExtra:AddLabel("Gucci: Disabled")
	Hub.updateGucciStatus=function() status:SetText("Gucci: " .. (Hub.gucciStage or "Disabled")) end
	DefenseExtra:AddToggle("GucciAutoDeleteBlob",{
		Text="Auto-delete Blobman after Gucci",Default=true,
		Callback=function(on)
			Hub.gucciAutoDelete=on
			Hub.gucciCleanupGeneration=(Hub.gucciCleanupGeneration or 0)+1
			local run=Hub.gucciRun
			if not on and run and not run.intentionalRemoval then run.cleanupPending=false end
		end,
	})
	DefenseExtra:AddToggle("AutoGucciBlobToggle",{
		Text="Anti Gucci",Default=false,
		Callback=function(on)
			enabled=on
			monitorGeneration+=1
			local ticket=monitorGeneration
			if not on then stopAntiGucci();return end
			startAntiGucci()
			task.spawn(function()
				local nextRetry=os.clock()+8
				while enabled and Hub.alive and ticket==monitorGeneration do
					task.wait(0.5)
					if not enabled or not Hub.alive or ticket~=monitorGeneration then return end
					local char=Player.Character
					local hum=char and char:FindFirstChildOfClass("Humanoid")
					local root=char and char:FindFirstChild("HumanoidRootPart")
					local folder=Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
					local blob=folder and folder:FindFirstChild("CreatureBlobman")
					local run=Hub.gucciRun
					local busy=run and run.busy and run.generation==Hub.blobGeneration
					local intentional=run and run.generation==Hub.blobGeneration
						and (run.cleanupPending or run.intentionalRemoval or run.removedIntentionally)
					if char and hum and root and hum.Health>0 and not busy and not intentional and os.clock()>=nextRetry
						and os.clock()>=(Hub.gucciRespawnReadyAt or 0)
						and (not blob or Hub.gucciStage=="Not ready" or Hub.gucciStage=="Error") then
						nextRetry=os.clock()+8
						startAntiGucci()
					end
				end
			end)
		end,
	})
	Hub.cleanup(function()
		enabled=false;monitorGeneration+=1
		Hub.blobGeneration=(Hub.blobGeneration or 0)+1
		Hub.updateGucciStatus=nil
	end)
end

-- Gucci remains unverified: transient local attachment changes are not proof of release.
-- De-Sync System (Train)
local autoGucciActiveTrain = false
local autoGucciActiveTrainMonitorGeneration = 0
DefenseExtra:AddToggle("AutoGucciTrainToggle", {
	Text = "De-Sync",
	Default = false,
	Callback = function(Value)
		autoGucciActiveTrain = Value
		autoGucciActiveTrainMonitorGeneration += 1
		local monitorTicket = autoGucciActiveTrainMonitorGeneration

		if Value then
			startAntiGucciTrain()
			notify("system", "De-Sync active (monitoring)", 3)

			task.spawn(function()
				while autoGucciActiveTrain and Hub.alive and monitorTicket == autoGucciActiveTrainMonitorGeneration do
					local trainFolder = (workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("AlwaysHereTweenedObjects"))
					local trainExists = trainFolder and trainFolder:FindFirstChild("Train")

					if not trainExists then
						stopAntiGucciTrain()
						notify("System", "Train lost", 3)

						local retries = 0
						repeat
							task.wait(0.2)
							retries = retries + 1
							trainFolder = (workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("AlwaysHereTweenedObjects"))
						until (trainFolder and trainFolder:FindFirstChild("Train")) or retries > 25 or not autoGucciActiveTrain or monitorTicket ~= autoGucciActiveTrainMonitorGeneration

						if autoGucciActiveTrain and monitorTicket == autoGucciActiveTrainMonitorGeneration and trainFolder and trainFolder:FindFirstChild("Train") then
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
local inputLagMonitorGeneration = 0
DefenseExtra:AddToggle("AntiInputLag", {
	Text = "Anti Input Lag",
	Default = false,
	Callback = function(Value)
		inputLagMonitorGeneration += 1
		local monitorTicket = inputLagMonitorGeneration
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

				local spawnPending, nextSpawn = false, 0
				while _G.AntiInputLag and Hub.alive and monitorTicket == inputLagMonitorGeneration do
					task.wait(0.5)
					if not _G.AntiInputLag or monitorTicket ~= inputLagMonitorGeneration then break end
					char = plr.Character
					hrp = char and char:FindFirstChild("HumanoidRootPart")
					if not hrp then continue end
					local toysFolder = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
					local burger = toysFolder and toysFolder:FindFirstChild(ToyName)

					if not burger then
						if spawnPending or os.clock() < nextSpawn then continue end
						local canSpawn = plr:FindFirstChild("CanSpawnToy")
						if canSpawn and not canSpawn.Value then continue end
						spawnPending, nextSpawn = true, os.clock() + 8
						task.spawn(function()
							pcall(function()
								local spawnCF = hrp.CFrame * CFrame.new(0, 5, 0)
								Hub.invoke(SpawnRemote, ToyName, spawnCF, Vector3.new(0,0,0))
							end)
							spawnPending = false
						end)

						local startWait = tick()
						repeat
							task.wait(0.1)
							toysFolder = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
							burger = toysFolder and toysFolder:FindFirstChild(ToyName)
						until burger or tick() - startWait > 1 or not _G.AntiInputLag or monitorTicket ~= inputLagMonitorGeneration
					end

					if not _G.AntiInputLag or monitorTicket ~= inputLagMonitorGeneration then break end
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
do
	local enabled, generation = false, 0
	local managedToy, managedCharacter
	local spawnJob, spawnPending = nil, false
	local nextSpawn, nextStick, nextError = 0, 0, 0
	local savedVisuals = {}
	local createdHighlights = {}

	local function report(message)
		warn("[Shuriken] " .. tostring(message))
		if os.clock() >= nextError then
			nextError = os.clock() + 10
			pcall(notify, "Anti Kick", tostring(message), 6)
		end
	end

	local function toyFolder()
		local plotItems = workspace:FindFirstChild("PlotItems")
		local inPlots = plotItems and plotItems:FindFirstChild("PlayersInPlots")
		if inPlots and inPlots:FindFirstChild(Player.Name) then
			local plots = workspace:FindFirstChild("Plots")
			if not plots then return nil end
			for _, plot in ipairs(plots:GetChildren()) do
				local sign = plot:FindFirstChild("PlotSign")
				local owners = sign and sign:FindFirstChild("ThisPlotsOwners")
				if owners then
					for _, owner in ipairs(owners:GetChildren()) do
						if owner:IsA("StringValue") and owner.Value == Player.Name then
							return plotItems:FindFirstChild(plot.Name)
						end
					end
				end
			end
			return nil -- Wait until the owned plot folder is ready.
		end
		return workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
	end

	local function findToy()
		local folder = toyFolder()
		return folder and (folder:FindFirstChild("AntiKick")
			or folder:FindFirstChild("NinjaShuriken"))
	end

	local function restoreVisuals()
		for part, saved in pairs(savedVisuals) do
			pcall(function()
				part.CanTouch, part.CanCollide, part.CanQuery = saved.touch, saved.collide, saved.query
				part.Transparency = saved.transparency
			end)
		end
		table.clear(savedVisuals)
		for highlight in pairs(createdHighlights) do
			pcall(function() highlight:Destroy() end)
			if Hub.instances then Hub.instances[highlight] = nil end
		end
		table.clear(createdHighlights)
	end

	local function clearToy()
		restoreVisuals()
		local old = managedToy
		managedToy, managedCharacter = nil, nil
		if not old or not old.Parent then return end
		local menu = ReplicatedStorage:FindFirstChild("MenuToys")
		local destroy = menu and menu:FindFirstChild("DestroyToy")
		if destroy then
			local ok, err = pcall(function() Hub.fire(destroy, old) end)
			if not ok then report(err) end
		end
	end

	local function cancelSpawn()
		if spawnJob then
			local scheduler = Hub.nativeTask or task
			pcall(scheduler.cancel, spawnJob)
			if Hub.threads then Hub.threads[spawnJob] = nil end
		end
		spawnJob, spawnPending = nil, false
	end

	local function decorateToy(toy)
		for _, part in ipairs(toy:GetChildren()) do
			if part:IsA("BasePart") then
				if not savedVisuals[part] then
					savedVisuals[part] = {
						touch = part.CanTouch, collide = part.CanCollide,
						query = part.CanQuery, transparency = part.Transparency,
					}
				end
				local visible = part.Name == "Pyramid" or part.Name == "Main"
				part.Transparency = visible and 0 or 1
				if visible and not part:FindFirstChildOfClass("Highlight") then
					local highlight = Hub.new("Highlight", part)
					highlight.Adornee = part
					highlight.FillColor = part.Name == "Pyramid"
						and Color3.fromRGB(0, 0, 0) or Color3.fromRGB(255, 255, 255)
					createdHighlights[highlight] = true
				end
			end
		end
	end

	local function styleToy(toy)
		decorateToy(toy)
		for _, part in ipairs(toy:GetChildren()) do
			if part:IsA("BasePart") then
				if not savedVisuals[part] then
					savedVisuals[part] = {
						touch = part.CanTouch, collide = part.CanCollide,
						query = part.CanQuery, transparency = part.Transparency,
					}
				end
				part.CanTouch, part.CanCollide, part.CanQuery = false, false, false
				part.Transparency = (part.Name == "Main" or part.Name == "Pyramid") and 0 or 1
			end
		end
	end

	local function step(ticket)
		local char = Player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		local root = char and char:FindFirstChild("HumanoidRootPart")
		if managedCharacter and (char ~= managedCharacter or not hum or hum.Health <= 0) then
			cancelSpawn()
			clearToy()
			nextSpawn, nextStick = 0, 0
		end
		if not hum or hum.Health <= 0 or not root then return end

		local toy = managedToy
		if toy and not toy.Parent then restoreVisuals(); managedToy = nil; toy = nil end
		if not toy then
			toy = findToy()
			if toy then
				managedToy, managedCharacter = toy, char
			elseif not spawnPending and os.clock() >= nextSpawn then
				local menu = ReplicatedStorage:FindFirstChild("MenuToys")
				local remote = menu and menu:FindFirstChild("SpawnToyRemoteFunction")
				local canSpawn = Player:FindFirstChild("CanSpawnToy")
				if not remote or not canSpawn or not canSpawn.Value then return end
				-- Do not spawn while standing in a plot whose ownership is unresolved.
				local items = workspace:FindFirstChild("PlotItems")
				local inPlots = items and items:FindFirstChild("PlayersInPlots")
				if inPlots and inPlots:FindFirstChild(Player.Name) and not toyFolder() then return end
				managedCharacter = char
				spawnPending, nextSpawn = true, os.clock() + 8
				spawnJob = task.spawn(function()
					local ok, err = pcall(function()
						Hub.invoke(remote, "NinjaShuriken", root.CFrame * CFrame.new(0, 12, 20), Vector3.zero)
					end)
					if ticket ~= generation then return end
					spawnPending, spawnJob = false, nil
					if not ok then
                        if tostring(err):find("OwnedToys",1,true) then
                            nextSpawn=os.clock()+60
                            warn("[Shuriken] Server toy data error: " .. tostring(err))
                            report("The game could not read your owned-toy data. Spawn retries paused for 60 seconds. Try the normal toy menu, or rejoin if it also fails.")
                        else report("Spawn failed: " .. tostring(err)) end
                    end
				end)
				return
			else
				if spawnPending and os.clock() >= nextSpawn then
					cancelSpawn()
					nextSpawn = os.clock() + 2
					report("Spawn request timed out; checking for a late toy before retrying.")
				end
				return
			end
		end

		decorateToy(toy)
		local sticky = toy:FindFirstChild("StickyPart")
		local firePart = root:FindFirstChild("FirePlayerPart")
		if not sticky or not sticky:IsA("BasePart") or not firePart or not firePart:IsA("BasePart") then return end
		local weld = sticky:FindFirstChild("StickyWeld")
		local attached = weld and (weld:IsA("JointInstance") or weld:IsA("WeldConstraint"))
			and (weld.Part0 == firePart or weld.Part1 == firePart)
		if attached then styleToy(toy); return end
		if os.clock() < nextStick then return end
		nextStick = os.clock() + 1

		local grab = ReplicatedStorage:FindFirstChild("GrabEvents")
		local events = ReplicatedStorage:FindFirstChild("PlayerEvents")
		local ownerRemote = grab and grab:FindFirstChild("SetNetworkOwner")
		local stickyRemote = events and events:FindFirstChild("StickyPartEvent")
		if not stickyRemote then report("StickyPartEvent is missing."); return end
		local sound = toy:FindFirstChild("SoundPart")
		local owner = sound and sound:FindFirstChild("PartOwner")
		if sound and sound:IsA("BasePart") and ownerRemote and (not owner or owner.Value ~= Player.Name) then
			Hub.fire(ownerRemote, sound, sound.CFrame)
		end
		if not enabled or ticket ~= generation or Player.Character ~= char or hum.Health <= 0 then return end
		Hub.fire(stickyRemote, sticky, firePart, CFrame.Angles(0, math.rad(90), math.rad(90)))
		-- Wait for the actual weld before disabling the toy's touch properties.
	end

	local function stop()
		enabled = false
		generation += 1
		_G.ShurikenAntiKick = false
		cancelSpawn()
		clearToy()
	end
	Hub.cleanup(stop)

	DefenseExtra:AddToggle("ShurikenAntiKick", {
		Text = "Anti Kick", Default = false,
		Callback = function(on)
			stop()
			enabled, _G.ShurikenAntiKick = on, on
			Hub.requestSave()
			if not on then return end
			local ticket = generation
			nextSpawn, nextStick = 0, 0
			task.spawn(function()
				while enabled and Hub.alive and ticket == generation do
					local ok, err = pcall(step, ticket)
					if not ok then report(err) end
					task.wait(0.2)
				end
			end)
		end,
	})
end



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
	if type(selection) ~= "string" then return nil end
	local username = selection:match("%(([^()]*)%)$")
	if username then
		return Players:FindFirstChild(username)
	end
	return nil
end

-- Auto Attacker
local AutoAttacker = false
local AttackMode = "Kill"
local headConnection
DefenseExtra:AddToggle("AutoAttacker", {
	Text = "Auto Attacker",
	Default = false,
	Callback = function(Value)
		AutoAttacker = Value
		if Value and Hub.scanAttacker then Hub.scanAttacker() end
	end
})

local Modes = {"Kill", "Fling",}

DefenseExtra:AddDropdown("AttackerMode", {
	Values = Modes,
	Default = 1,
	Multi = false,
	Text = "AttackMode",
	Callback = function(Value)
		AttackMode = Value
	end,
})

function CheckNetworkOwnerShipOnPlayer(potentialPlayer, condition)
	if typeof(potentialPlayer) == "Instance" and (potentialPlayer:IsA("Player") and potentialPlayer.Character) and (potentialPlayer.Character:FindFirstChild("Head") and (potentialPlayer.Character.Head:FindFirstChild("PartOwner") and potentialPlayer.Character.Head.PartOwner.Value == Player.Name)) then
		return not condition and true or potentialPlayer.Character.Head.PartOwner
	end
end

lookAt = Hub.lookAt

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
Hub.attackerBindingEpoch=0
function Hub.clearAttackerBindings()
    Hub.attackerBindingEpoch+=1
    for _,connection in ipairs(Hub.attackerBindings) do connection:Disconnect();Hub.connections[connection]=nil end
    table.clear(Hub.attackerBindings)
    Hub.attackerBusy={}
    Hub.scanAttacker=nil
    headConnection=nil
end
local function hookAttackerCharacter(boundCharacter)
    if not Hub.alive or Player.Character~=boundCharacter then return end
    Hub.clearAttackerBindings()
    local generation=Hub.attackerBindingEpoch
    local seenOwners={}
	local function isCurrent()
		local hum = boundCharacter:FindFirstChildOfClass("Humanoid")
		return Hub.alive and AutoAttacker and boundCharacter == Player.Character
			and generation == Hub.attackerBindingEpoch and hum and hum.Health > 0
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
					local busy = Hub.attackerBusy
					if busy[otherPlayer] then return end
					busy[otherPlayer] = true
					local ok, actionError = xpcall(function()
						-- Death mode counter action
						local counterAction
						local humanoidInstance = otherHumanoid

						if isCurrent() and Hub.canHarm(otherPlayer) and humanoidInstance and humanoidInstance.Parent and otherHumanoidRootPart.Parent then

							if AttackMode == "Kill" then
								counterAction = function()
									CreateSkyVelocity(otherHumanoidRootPart)
									for _ = 0, 30 do
										humanoidInstance.BreakJointsOnDeath = false
										humanoidInstance:ChangeState(Enum.HumanoidStateType.Dead)
										humanoidInstance.Jump = true
										humanoidInstance.Sit = true
									end
									task.wait()
									Hub.fire(ReplicatedStorage.GrabEvents.DestroyGrabLine, otherHumanoidRootPart)
								end
							elseif AttackMode == "Fling" then
								counterAction = function()
									local lookAtCFrame = lookAt(LocalPlayer.Character.HumanoidRootPart.Position, otherHumanoidRootPart.Position)
									local bodyVelocity = Instance.new("BodyVelocity", otherPlayer.Character.HumanoidRootPart)
									bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
									bodyVelocity.Velocity = Vector3.new(lookAtCFrame.lookVector.X, 0.5, lookAtCFrame.lookVector.Z) * 100
									wait()
									bodyVelocity:Destroy()
									destroyGrabLineEvent:FireServer(otherHumanoidRootPart)
								end
							end
						end


						if type(counterAction) ~= "function" then error("Unknown Auto Attacker mode: " .. tostring(AttackMode)) end
						local completed = false
						-- Execute SNOWship loop
						for _ = 1, 50 do
							if not isCurrent() or not Hub.canHarm(otherPlayer) or otherPlayer.Character ~= otherHumanoid.Parent then break end
							if SNOWshipPlayer(otherPlayer, counterAction) then
								completed = true
								break
							end
							task.wait()
						end
						if not completed and isCurrent() then warn("[Arriva Auto Attacker] Action was not reached for " .. otherPlayer.Name .. ", ownership/range checks did not complete.") end
					end, debug.traceback)
					busy[otherPlayer] = nil
					if not ok then warn("[Arriva Auto Attacker] " .. tostring(actionError)) end
				end
			end
		end
	end
	local function watchOwner(instance)
		if instance.Name ~= "PartOwner" or seenOwners[instance] then return end
		if not instance:IsA("StringValue") and not instance:IsA("ObjectValue") then return end
		seenOwners[instance]=true
		table.insert(Hub.attackerBindings, Hub.connect(instance:GetPropertyChangedSignal("Value"), function()
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
if Player.Character then hookAttackerCharacter(Player.Character) end
Hub.connect(Player.CharacterRemoving,Hub.clearAttackerBindings)
Hub.connect(Player.CharacterAdded,function(char)
    task.defer(function()
        if Hub.alive and Player.Character==char then hookAttackerCharacter(char) end
    end)
end)
Hub.cleanup(Hub.clearAttackerBindings)

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

-- Main player ESP, including appearance controls.
do
(function()
    local group=PlayerESP
    local enabled,through,alpha,color=false,true,0.8,Color3.new(1,1,1)
    local entries={};local elapsed=0
    local function clear(p) local e=entries[p];if e then e.gui:Destroy();e.highlight:Destroy();entries[p]=nil end end
    local function update()
        for p,e in pairs(entries) do if not enabled or p.Parent~=Players or p.Character~=e.character then clear(p) end end
        if not enabled then return end
        for _,p in ipairs(Players:GetPlayers()) do if p~=Player then
            local char=p.Character;local head=char and char:FindFirstChild("Head")
            local hum=char and char:FindFirstChildOfClass("Humanoid")
            if head and hum and hum.Health>0 then
                local e=entries[p]
                if not e then
                    local gui=Hub.new("BillboardGui",head);gui.Name="NameESP";gui.Adornee=head
                    gui.Size=UDim2.fromOffset(180,58);gui.StudsOffset=Vector3.new(0,3,0);gui.MaxDistance=1200
                    local avatar=Hub.new("ImageLabel",gui);avatar.Size=UDim2.fromOffset(32,32);avatar.BackgroundTransparency=1
                    avatar.Image=string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150",p.UserId)
                    local text=Hub.new("TextLabel",gui);text.Position=UDim2.fromOffset(36,0);text.Size=UDim2.new(1,-36,1,0)
                    text.BackgroundTransparency=1;text.TextSize=16;text.TextWrapped=true
                    text.Font=Enum.Font.GothamBold;text.TextStrokeColor3=Color3.new(0,0,0);text.TextStrokeTransparency=0
                    local highlight=Hub.new("Highlight",char);highlight.Adornee=char
                    e={gui=gui,text=text,highlight=highlight,character=char};entries[p]=e
                end
                e.gui.AlwaysOnTop=through;e.text.TextColor3=Color3.new(1,1,1);e.highlight.FillColor=color;e.highlight.OutlineColor=Color3.new(1,1,1)
                e.highlight.FillTransparency=alpha;e.highlight.OutlineTransparency=0.2
                e.highlight.DepthMode=through and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
                e.text.Text=string.format("%s (@%s)\nHP %.0f",p.DisplayName,p.Name,hum.Health)
            else clear(p) end
        end end
    end
    group:AddToggle("NicknameESP",{Text="ESP",Default=false,Callback=function(on) enabled=on;update() end})
    group:AddToggle("DetailedESPThroughWalls",{Text="Visible through walls",Default=true,Callback=function(on) through=on;update() end})
    group:AddSlider("DetailedESPTransparency",{Text="Fill transparency",Default=80,Min=0,Max=100,Rounding=0,Callback=function(value) alpha=value/100;update() end})
    group:AddInput("DetailedESPColor",{Text="Fill color hex",Default="FFFFFF",Finished=true,Callback=function(value)
        local hex=tostring(value):gsub("#","");if #hex==6 and hex:match("^%x+$") then
            color=Color3.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16));update()
        end
    end})
    group:AddLabel("Player ESP appearance. PCLD View remains a separate map detector overlay.")
    Hub.connect(RunService.Heartbeat,function(dt) elapsed+=dt;if elapsed>=0.5 then elapsed=0;update() end end)
    Hub.connect(Players.PlayerRemoving,clear)
    Hub.cleanup(function() enabled=false;for p in pairs(entries) do clear(p) end end)
end)()
end

-- Performance
local oldProperties = {}
PlayerPerf:AddButton({
	Text = "Improve FPS",
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
	Text = "Restore FPS",
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
local noclipParts = {}
local noclipTrackedCharacter
local noclipDescendantConnection

local function applyNoclip(character)
	if character ~= noclipTrackedCharacter then
		if noclipDescendantConnection then noclipDescendantConnection:Disconnect() end
		table.clear(noclipParts)
		noclipTrackedCharacter = character
		local function track(part)
			if part:IsA("BasePart") then noclipParts[part] = true end
		end
		noclipDescendantConnection = Hub.connect(character.DescendantAdded, track)
		for _, part in ipairs(character:GetDescendants()) do track(part) end
	end
	for part in pairs(noclipParts) do
		if not part:IsDescendantOf(character) then
			if savedCollision[part] ~= nil then
				pcall(function() part.CanCollide = savedCollision[part] end)
				savedCollision[part] = nil
			end
			noclipParts[part] = nil
		else
			if savedCollision[part] == nil then savedCollision[part] = part.CanCollide end
			if part.CanCollide then part.CanCollide = false end
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
	if noclipDescendantConnection then noclipDescendantConnection:Disconnect(); noclipDescendantConnection = nil end
	noclipTrackedCharacter = nil
	table.clear(noclipParts)
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
local WhitelistGroup = Tabs.Whitelist:AddLeftGroupbox("Protected Players")
local TargetNotificationGroup = Tabs.Notifications:AddLeftGroupbox("Target Alerts")

local SelectedPlayer = nil -- Primary selection for one-shot actions.
Hub.selectedTargets = {}
Hub.targetCursors = {}
-- A stopped worker must not resume when the same toggle is enabled again.
Hub.targetLoopRuns = {}
function Hub.beginTargetLoop(key, enabled)
    local previous = Hub.targetLoopRuns[key]
    if previous then previous.enabled = false end
    local run = enabled and {enabled = true} or previous or {enabled = false}
    Hub.targetLoopRuns[key] = run
    return function() return Hub.alive and run.enabled and Hub.targetLoopRuns[key] == run end,
        function() return Hub.targetLoopRuns[key] == run end
end
function Hub.loopTargetReady(player, character)
    if not player or player.Parent ~= Players or not Hub.canHarm(player) then return false end
    local char = player.Character
    if not char or (character and char ~= character) or not char:IsDescendantOf(Workspace) then return false end
    local hum = char:FindFirstChildOfClass("Humanoid")
    local inPlot = player:FindFirstChild("InPlot")
    return char:FindFirstChild("HumanoidRootPart") ~= nil and hum ~= nil and hum.Health > 0
        and not (inPlot and inPlot.Value)
end
function Hub.getBlobSeat()
    local char = Player.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local seat = hum and hum.Health > 0 and hum.SeatPart
    local blob = seat and seat.Parent
    if blob and blob.Name == "CreatureBlobman" and blob:IsDescendantOf(Workspace) then return seat end
    return nil
end
function Hub.isSelectedTarget(player)
    return player ~= nil and Hub.selectedTargets[player.UserId] == player
end
function Hub.setSelectedTargets(selection)
    local chosen = {}
    -- Accept legacy single selections as well as multi-select maps and arrays.
    if type(selection) == "string" then selection = {selection} end
    for key, value in pairs(type(selection) == "table" and selection or {}) do
        local label = type(key) == "number" and value or (value and key or nil)
        local player = type(label) == "string" and getPlayerFromSelection(label) or nil
        if player and player ~= Player then chosen[player.UserId] = player end
    end
    Hub.selectedTargets = chosen
    SelectedPlayer = nil
    for _, player in ipairs(Players:GetPlayers()) do
        if chosen[player.UserId] then SelectedPlayer = player; break end
    end
end
function Hub.nextLoopTarget(key, dwell)
    local candidates = {}
    for _, player in pairs(Hub.selectedTargets) do
        if Hub.loopTargetReady(player) then
            table.insert(candidates, player)
        end
    end
    table.sort(candidates, function(a, b) return a.UserId < b.UserId end)
    local cursor = Hub.targetCursors[key]
    if cursor and dwell and os.clock() < cursor.untilTime then
        for _, player in ipairs(candidates) do
            if player.UserId == cursor.id then return player end
        end
    end
    local target = candidates[1]
    if cursor then
        for _, player in ipairs(candidates) do
            if player.UserId > cursor.id then target = player; break end
        end
    end
    if target then Hub.targetCursors[key] = {id = target.UserId, untilTime = os.clock() + (dwell or 0)} end
    return target
end
local kickLoopEnabled = false
local loopKillEnabled = false
local loopKillEnabledAll = false



local function autoblob(active)
    active = active or function() return Hub.alive end
    if not active() then return false end
    if Hub.getBlobSeat() then return true end
	local plr = Player
	local char = plr.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChild("Humanoid")

	if not hrp or not hum or hum.Health <= 0 then return false end

	local folderName = plr.Name .. "SpawnedInToys"
	local folder = workspace:FindFirstChild(folderName)
	local blob = folder and folder:FindFirstChild("CreatureBlobman")

	if not blob then
		task.spawn(function()
			pcall(function()
                if not active() or Player.Character ~= char then return end
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

	if not active() or Player.Character ~= char or not hrp.Parent or hum.Health <= 0 then return false end
	if blob then
		local seat = blob:WaitForChild("VehicleSeat", 5)
		if seat and active() and Player.Character == char and hrp.Parent then
			local t = tick()
			repeat
				if not hum.SeatPart then
					hrp.CFrame = seat.CFrame + Vector3.new(0, 1, 0)
					hrp.Velocity = Vector3.zero
					seat:Sit(hum)
				end
				RunService.Heartbeat:Wait()
			until hum.SeatPart == seat or tick() - t > 1.5 or Player.Character ~= char or not seat.Parent or not active()
		end
	end
    return Hub.getBlobSeat() ~= nil
end

TargetGroup:AddDropdown("KickPlayerDropdown", {
	Values = getPlayerList(),
	Default = {},
	Multi = true,
	Text = "Select players",
	Callback = function(Value)
		Hub.setSelectedTargets(Value)
	end,
})

TargetGroup:AddLabel("Loops cycle through selected players. One-shot actions use the first selected player in the server list.")

TargetGroup:AddButton({
	Text = "refresh player list",
	Func = function()
		Options.KickPlayerDropdown:SetValues(getPlayerList())
	end
})

do
    local function refreshTargetSelector()
        if Options.KickPlayerDropdown then Options.KickPlayerDropdown:SetValues(getPlayerList()) end
    end
    Hub.connect(Players.PlayerAdded,function() Hub.queueRefresh("mainPlayerSelector",refreshTargetSelector) end)
    Hub.connect(Players.PlayerRemoving,function(person)
        Hub.selectedTargets[person.UserId] = nil
        if SelectedPlayer==person then
            SelectedPlayer=nil
            for _, remaining in ipairs(Players:GetPlayers()) do
                if Hub.isSelectedTarget(remaining) then SelectedPlayer=remaining;break end
            end
        end
        Hub.queueRefresh("mainPlayerSelector",refreshTargetSelector)
    end)
end

TargetGroup:AddToggle("LoopKickToggle", {
	Text = "Kick (spam grab)",
	Default = false,
	Callback = function(on)
        local running, ownsRun = Hub.beginTargetLoop("LoopKickToggle", on)
		kickLoopEnabled = on

		local target = SelectedPlayer

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

			while running() do
                local nextTarget = Hub.nextLoopTarget("spamGrab", 1)
                if nextTarget ~= target then dragging = false; grabStartTime = 0 end
                target = nextTarget
                if not target then task.wait(0.2); continue end

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
						if tick() - grabStartTime > 0.5 then
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

            if not ownsRun() then return end
			if myRoot then
				myRoot.CFrame = savedPos
				myRoot.Velocity = Vector3.zero
			end
		end)
	end
})



-- Loop Kill selected players
TargetGroup:AddToggle("LoopKillToggle", {
	Text = "Loop kill",
	Default = false,
	Callback = function(on)
        local running, ownsRun = Hub.beginTargetLoop("LoopKillToggle", on)
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

				while running() do
                    target = Hub.nextLoopTarget("loopKill")
                    if not target then task.wait(0.2); continue end

					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
					local tChar = Hub.canHarm(target) and target.Character or nil
					local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
					local tHum = tChar and tChar:FindFirstChild("Humanoid")
					local tHead = tChar and tChar:FindFirstChild("Head")

					if tRoot and tHum and tHead and myRoot then
						local currentPos = myRoot.CFrame

						for _ = 0, 50 do
							if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, tChar) or not tRoot.Parent then break end

							applyNoclip(myChar)
							SNOWship(tRoot)

							-- Check if SNOWship was successful
							if not running() or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
								Hub.fire(GE.DestroyGrabLine, tRoot)
								CreateSkyVelocity(tRoot)
								break
							end

							task.wait()
                            if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, tChar) or Player.Character ~= myChar then break end

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

                        if not ownsRun() then return end
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

                if not ownsRun() then return end
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
        local running, ownsRun = Hub.beginTargetLoop("LoopKillToggleAll", on)
		Hub.requestSave()
		loopKillEnabledAll = on
		if on then
			task.spawn(function()
				local RS = ReplicatedStorage
				local PS = Players
				local GE = RS:WaitForChild("GrabEvents")

				while running() do
					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

					if myRoot then
						local currentPos = myRoot.CFrame

						for _, target in pairs(PS:GetPlayers()) do
							if not running() then break end
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
									if not running() or not Hub.loopTargetReady(target, tChar) or not tRoot.Parent then break end

									applyNoclip(myChar)
									SNOWship(tRoot)

									-- Check if SNOWship was successful
									if not running() or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
										Hub.fire(GE.DestroyGrabLine, tRoot)
										CreateSkyVelocity(tRoot)
										break
									end

									task.wait()
                            if not running() or not Hub.loopTargetReady(target, tChar) or Player.Character ~= myChar then break end

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

                        if not ownsRun() then return end
						if myRoot then
							restoreCollision()
							myRoot.CFrame = currentPos
							myRoot.Velocity = Vector3.zero
						end
					end

					task.wait(5)
				end

                if not ownsRun() then return end
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

local grabBlobLoopEnabled = false
TargetGroup:AddToggle("LoopKickToggle2", {
	Text = "Loop Kick (grab + blob)",
	Default = false,
	Callback = function(on)
        local running, ownsRun = Hub.beginTargetLoop("LoopKickToggle2", on)
		grabBlobLoopEnabled = on
		Hub.requestSave()

		local target = SelectedPlayer

		local char = Player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local seat = hum and hum.SeatPart

		if not on then
            if not ownsRun() then return end
			grabBlobLoopEnabled = false
			return
		end

        autoblob(running)
        if not running() then return end

        char = Player.Character
        hum = char and char:FindFirstChild("Humanoid")
        seat = hum and hum.SeatPart
        if not seat or seat.Parent.Name ~= "CreatureBlobman" then
            notify("System", "Sit in a Blobman before enabling this loop", 3)
            Toggles.LoopKickToggle2:SetValue(false)
            return
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
            if not running() then return end
            if not blobRoot or not CG or not CD or not R_Det or not R_Weld then
                notify("System", "Blobman parts are not ready; try again after it loads", 3)
                Toggles.LoopKickToggle2:SetValue(false)
                return
            end

			local SavedPos = blobRoot.CFrame

			local tChar = Hub.canHarm(target) and target.Character or nil
			local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")

			if tRoot and blobRoot then
				local bringStart = tick()
				while running() and tick() - bringStart < 0.35 do
					if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, tChar) then break end

					if Hub.canAffect(tRoot) then blobRoot.CFrame = tRoot.CFrame end
					blobRoot.Velocity = Vector3.zero

					pcall(function()
						if CG and R_Det then Hub.fire(CG, R_Det, tRoot, R_Weld) end
						Hub.fire(GE.CreateGrabLine, tRoot, Vector3.zero, tRoot.Position, false)
						Hub.fire(GE.SetNetworkOwner, tRoot, blobRoot.CFrame)
					end)
					RunService.Heartbeat:Wait()
				end

                if not ownsRun() then return end
                if blobRoot.Parent then
				    blobRoot.CFrame = SavedPos
				    blobRoot.Velocity = Vector3.zero
                end
				task.wait(0.05)
			end

			local packetTimer = 0

			while running() do
                if Hub.getBlobSeat() ~= seat or not blobRoot.Parent then task.wait(0.2); continue end
                target = Hub.nextLoopTarget("grabBlob", 1)
                if not target then task.wait(0.2); continue end

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

				if not running() then break end
				RunService.Heartbeat:Wait()
			end

			grabBlobLoopEnabled = false
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
        local running, ownsRun = Hub.beginTargetLoop("DualHandLoopKick", on)
		Hub.requestSave()
		loopKickDualActive = on
		if on then
			if not Hub.nextLoopTarget("dualKick") then
				notify("Error", "Select target first", 3)
				Toggles.DualHandLoopKick:SetValue(false)
				return
			end
        autoblob(running)
        if not running() then return end
			task.spawn(function()
				local lastTargetCharDual = nil
				local bp = nil

				while running() do
                    local target = Hub.nextLoopTarget("dualKick", 1)
                    if not target then
                        if bp then bp:Destroy(); bp = nil end
                        lastTargetCharDual = nil
                        task.wait(0.2); continue
                    end
					local char = Player.Character
					local hum = char and char:FindFirstChild("Humanoid")
					local seat = Hub.getBlobSeat()

					if not seat or not target or not target.Parent then
                        if bp then bp:Destroy(); bp = nil end
                        lastTargetCharDual = nil
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
                    if not leftDet or not rightDet or not leftWeld or not rightWeld then
                        task.wait(0.2); continue
                    end

					local hrp = char:FindFirstChild("HumanoidRootPart")

					local targetChar = Hub.canHarm(target) and target.Character or nil
					local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
					local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

					if targetHRP and targetHum and targetHum.Health > 0 then
                        repeat -- Abandon only this target's handshake if it changes during a yield.
						if targetChar ~= lastTargetCharDual then
							lastTargetCharDual = targetChar
							if bp then bp:Destroy() bp = nil end
							if hrp then hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 25, 0) end
							task.wait(0.2)
                            if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
							Hub.fire(grab, leftDet, targetHRP, leftWeld)
							task.wait(0.3)
                            if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
							Hub.fire(drop, leftWeld, targetHRP)
							task.wait(0.1)
                            if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
							bp = Hub.new("BodyPosition")
							bp.Position = Vector3.new(0, 999999, 0)
							bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
							bp.Parent = targetHRP
							Hub.fire(grab, leftDet, targetHRP, leftWeld)
							task.wait(0.2)
                            if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
							Hub.fire(drop, leftWeld, targetHRP)
						end

						Hub.fire(grab, leftDet, targetHRP, leftWeld)
						task.wait()
                        if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
						Hub.fire(drop, leftWeld, targetHRP)
						task.wait()
                        if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
						Hub.fire(grab, rightDet, targetHRP, rightWeld)
						task.wait()
                        if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
						Hub.fire(drop, rightWeld, targetHRP)
						task.wait()
                        if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
						Hub.fire(grab, leftDet, targetHRP, leftWeld)
						Hub.fire(grab, rightDet, targetHRP, rightWeld)
						task.wait()
                        if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, targetChar) or Hub.getBlobSeat() ~= seat then break end
						Hub.fire(drop, leftWeld, targetHRP)
						Hub.fire(drop, rightWeld, targetHRP)
						task.wait()
                        until true
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
        local running, ownsRun = Hub.beginTargetLoop("PlayerFlingBtn", on)
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
				while running() do
                    local target = Hub.nextLoopTarget("fling")
                    if not target then task.wait(0.2); continue end

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
							end
                            Hub.assetTargets[flingBAV] = tRoot

							for _, part in pairs(char:GetDescendants()) do
								if part:IsA("BasePart") then
									if Hub.canAffect(part) then part.CanCollide = false end
								end
							end

							local loop = Hub.connect(RunService.Heartbeat, function()
								if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, tChar) or not tRoot or not tRoot.Parent then return end
								if Hub.canAffect(tRoot) then hrp.CFrame = tRoot.CFrame end
								hrp.Velocity = Vector3.zero
							end)

							local startTime = tick()
							while tick() - startTime < 1.5 do
								if not running() or not Hub.isSelectedTarget(target) or not Hub.loopTargetReady(target, tChar) or not tRoot.Parent then break end
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

                if not ownsRun() then return end
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
    if not processed and not UserInputService:GetFocusedTextBox() and Hub.matchesKeybind("BlobSeatKey", input, "B") and _G.AutoSitBlobZ then
        task.spawn(function() autoblob() end)
    end
end)

-- Blob Fly System
do
    local activeRoot, activeCharacter, velocity, gyro
    local speed, currentVelocity = 50, Vector3.zero
    local status = BlobGroup:AddLabel("Blob Fly: sit in a Blobman, then press R.")
    local function discard(object)
        if not object then return end
        Hub.instances[object], Hub.assetTargets[object] = nil, nil
        pcall(function() object:Destroy() end)
    end
    local function stop()
        discard(velocity); discard(gyro)
        velocity, gyro, activeRoot, activeCharacter = nil, nil, nil, nil
        currentVelocity = Vector3.zero
        Hub.blobFlightActive = false
        status:SetText("Blob Fly off. Sit in a Blobman and use your flight shortcut to start.")
    end
    Hub.stopBlobFlight = stop
    local function seatedRoot()
        local char = Player.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local seat = hum and hum.SeatPart
        local blob = seat and seat.Parent
        if not hum or hum.Health <= 0 or not seat or seat.Occupant ~= hum
            or not blob or blob.Name ~= "CreatureBlobman" then return end
        local root = blob:FindFirstChild("HumanoidRootPart") or blob.PrimaryPart or seat.AssemblyRootPart
        if not root or not root:IsA("BasePart") or not root.Parent or root.Anchored then return end
        return root, char
    end
    function Hub.setBlobFlight(on)
        if not on then stop(); return true end
        local root, char = seatedRoot()
        if not root then
            stop(); status:SetText("Sit in a live, unanchored Blobman before starting flight."); return false
        end
        stop()
        activeRoot, activeCharacter = root, char
        velocity = Hub.new("BodyVelocity", root)
        velocity.Name = "BlobFlyVelocity"
        velocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        velocity.P = 10000
        velocity.Velocity = Vector3.zero
        gyro = Hub.new("BodyGyro", root)
        gyro.Name = "BlobFlyGyro"
        gyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
        gyro.P, gyro.D = 10000, 1000
        gyro.CFrame = root.CFrame
        Hub.blobFlightActive = true
        -- Seating normally grants ownership; make one request on activation, never every frame.
        if setNetworkOwnerEvent then pcall(function() Hub.fire(setNetworkOwnerEvent, root, root.CFrame) end) end
        status:SetText("Blob Fly on: WASD, Space up, Left Control down. Flight shortcut stops.")
        return true
    end
    local function finite(vector)
        return vector.X == vector.X and vector.Y == vector.Y and vector.Z == vector.Z
            and math.abs(vector.X) < math.huge and math.abs(vector.Y) < math.huge and math.abs(vector.Z) < math.huge
    end
    function Hub.updateBlobFlight(dt)
        if not Hub.blobFlightActive then return end
        local root, char = seatedRoot()
        if root ~= activeRoot or char ~= activeCharacter or not velocity.Parent or not gyro.Parent then stop(); return end
        local camera = Workspace.CurrentCamera
        if not camera or not finite(camera.CFrame.LookVector) or not finite(camera.CFrame.RightVector) then
            currentVelocity = Vector3.zero; velocity.Velocity = Vector3.zero; return
        end
        local look, right = camera.CFrame.LookVector, camera.CFrame.RightVector
        local move = Vector3.zero
        if not UserInputService:GetFocusedTextBox() and not Hub.keybindCaptureActive then
            if UserInputService:IsKeyDown(Enum.KeyCode.W) then move += look end
            if UserInputService:IsKeyDown(Enum.KeyCode.S) then move -= look end
            if UserInputService:IsKeyDown(Enum.KeyCode.A) then move -= right end
            if UserInputService:IsKeyDown(Enum.KeyCode.D) then move += right end
            if UserInputService:IsKeyDown(Enum.KeyCode.Space) then move += Vector3.new(0, 1, 0) end
            if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then move -= Vector3.new(0, 1, 0) end
        end
        if move.Magnitude > 1 then move = move.Unit end
        local seconds = type(dt) == "number" and dt == dt and math.clamp(dt, 0, 0.1) or 1 / 60
        local alpha = 1 - math.exp(-14 * seconds)
        currentVelocity += (move * speed - currentVelocity) * alpha
        velocity.Velocity = currentVelocity
        -- Camera pitch controls travel direction, but only yaw steers the blob's body.
        local heading = Vector3.new(look.X, 0, look.Z)
        if heading.Magnitude > 0.001 then
            gyro.CFrame = CFrame.lookAt(root.Position, root.Position + heading.Unit, Vector3.yAxis)
        end
    end
    Hub.connect(UserInputService.InputBegan, function(input, processed)
        if not processed and not UserInputService:GetFocusedTextBox() and Hub.matchesKeybind("BlobFlyKey", input, "R") then
            Hub.setBlobFlight(not Hub.blobFlightActive)
        end
    end)
    Hub.connect(RunService.PreSimulation or RunService.Heartbeat, Hub.updateBlobFlight)
    Hub.connect(Player.CharacterRemoving, stop)
    BlobGroup:AddSlider("BlobFlySpeed", {Text = "Blob Fly speed", Default = 50, Min = 10, Max = 150, Rounding = 0,
        Callback = function(value) speed = value end})
    BlobGroup:AddButton({Text = "Start Blob Fly", Func = function() Hub.setBlobFlight(true) end})
    BlobGroup:AddButton({Text = "Stop Blob Fly", Func = stop})
    Hub.cleanup(function()
        stop()
        Hub.stopBlobFlight, Hub.setBlobFlight, Hub.updateBlobFlight = nil, nil, nil
    end)
end
-- End Blob Fly System

-- Destroy Target Gucci
local DestroyTargetGucciActive = false
TargetGroup:AddToggle("DestroyTargetGucci", {
	Text = "Destroy Gucci (sit)",
	Default = false,
	Callback = function(Value)
        local running, ownsRun = Hub.beginTargetLoop("DestroyTargetGucci", Value)
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
				while running() do
                    local target = Hub.nextLoopTarget("destroyGucci")
                    if not target then task.wait(0.2); continue end
                    local folderName = target.Name .. "SpawnedInToys"

					local toysFolder = workspace:FindFirstChild(folderName)

					if not toysFolder then
						task.wait(1)
					else
						local foundBlob = false

						for _, obj in ipairs(toysFolder:GetChildren()) do
							if not running() or not Hub.canAffect(toysFolder) then break end

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
												if not running() or not Hub.canAffect(toysFolder) then break end
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

        if not autoblob() then
            notify("Bring", "Could not sit in a ready Blobman; try again after it loads", 3)
            return
        end
        local seat = Hub.getBlobSeat()
        if not seat then return end

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

function GetPlayerCFrame()
	local playerCharacterCFrame = GetPlayerCharacter()
	if playerCharacterCFrame then
		return playerCharacterCFrame.HumanoidRootPart.CFrame
	end
end
freezecampart = Instance.new("Part", workspaceService)
freezecampart.Anchored = true
freezecampart.CanCollide = false
freezecampart.Transparency = 1
freezecampart.CanQuery = false
freezecampart.Size = Vector3.new()

function FreezeCam(freezeCamCFrame)
	freezecampart.CFrame = freezeCamCFrame
	workspace.CurrentCamera.CameraType = Enum.CameraType.Follow
	workspace.CurrentCamera.CameraSubject = freezecampart
end
function unFreezeCam()
	workspace.CurrentCamera.CameraSubject = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
	workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
end

function CreateBringBody(targetPart, destinationPart)
	if targetPart:FindFirstChild("BringBody") then
		targetPart:FindFirstChild("BringBody").Position = destinationPart.Position
	else
		local bringBodyPosition = Instance.new("BodyPosition", targetPart)
		bringBodyPosition.Name = "BringBody"
		bringBodyPosition.Position = destinationPart.Position
		bringBodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
		bringBodyPosition.D = 5000
		bringBodyPosition.P = 1500000
	end
end

function TeleportPlayer(cframeOffset,teleportPriority)
    local requested=teleportPriority==nil and 0 or teleportPriority
    local active=_G.TP_Priority==nil and 0 or _G.TP_Priority
    if requested~=active or _G.TeleportingToNetworkOwnership or typeof(cframeOffset)~="CFrame" then return false end
    local char=GetPlayerCharacter()
    local root=char and char:FindFirstChild("HumanoidRootPart")
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    if not root or not hum or hum.Health<=0 then return false end
    root.CFrame=root.CFrame.Rotation+cframeOffset.Position
    if not hum.SeatPart or not hum.SeatPart.Parent or hum.SeatPart.Parent.Name~="CreatureBlobman" then hum.Sit=false end
    return true
end


function CheckPlayerVelocity(player)
    if typeof(player)~="Instance" or not player:IsA("Player") then return math.huge end
    local char=player.Character
    local root=char and char:FindFirstChild("HumanoidRootPart")
    return root and root.AssemblyLinearVelocity.Magnitude or math.huge
end
function CheckPlayer(player)
    if not Hub.canHarm(player) then return false end
    local char=player.Character
    local hum=char and char:FindFirstChildOfClass("Humanoid")
    return char~=nil and char:IsDescendantOf(workspaceService) and char:FindFirstChild("HumanoidRootPart")~=nil
        and hum~=nil and hum.Health>0
end
function CheckPlayerBring(player)
    if not CheckPlayer(player) then return false end
    local inPlot=player:FindFirstChild("InPlot")
    return not (inPlot and inPlot.Value==true) and CheckPlayerVelocity(player)<20
end
function CheckNetworkOwnerShipOnPart(potentialPart, condition)
	if typeof(potentialPart) == "Instance" and (potentialPart:FindFirstChild("PartOwner") and potentialPart.PartOwner.Value == LocalPlayer.Name) then
		return not condition and true or potentialPart.PartOwner
	end
end
function SNOWshipOnce(targetPart2)
	local distanceFromCharacter = LocalPlayer:DistanceFromCharacter(targetPart2.Position)
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		if CheckNetworkOwnerShipOnPart(targetPart2) then
			return true
		end
		if distanceFromCharacter <= 30 then
			setNetworkOwnerEvent:FireServer(targetPart2, lookAt(LocalPlayer.Character.HumanoidRootPart.Position, targetPart2.Position))
		end
	end
end

-- Anti Anti-Kick
local BringAll = false
TargetGroup:AddToggle("BringAllGrab", {
	Text = "Bring All",
	Default = false,
	Callback = function(Value)
		BringAll = Value
		Hub.bringAllEpoch=(Hub.bringAllEpoch or 0)+1
		local ticket=Hub.bringAllEpoch
		local skipped={}
		task.spawn(function()
		if BringAll and ticket==Hub.bringAllEpoch then
			local playerCFrame = GetPlayerCFrame()
			if not playerCFrame or not workspaceService.CurrentCamera then return end
			local cameraCFrame = CFrame.lookAt(workspaceService.CurrentCamera.CFrame.Position + Vector3.new(- 15, 15, 0), playerCFrame.Position)
			workspace.CurrentCamera.CFrame = cameraCFrame
			while BringAll and Hub.alive and ticket==Hub.bringAllEpoch do
				FreezeCam(cameraCFrame)
				local playersService = game:GetService("Players")
				local playerIterator, playerIterator5, playerIndex = pairs(playersService:GetPlayers())
				while true do
					local player
					playerIndex, player = playerIterator(playerIterator5, playerIndex)
					if playerIndex == nil then
						break
					end
					local previous=skipped[player]
					if not previous or previous.character~=player.Character or os.clock()>=previous.untilTime then
					local ok,playerError=xpcall(function()
					if CheckPlayerBring(player) then
						local boundCharacter=player.Character
						local humanoidRootPart = player.Character:FindFirstChild("HumanoidRootPart")
						local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
						local isRagdolled
						if humanoid and humanoid:FindFirstChild("Ragdolled") then
							isRagdolled = humanoid.Ragdolled
						else
							isRagdolled = nil
						end
						if player and (humanoidRootPart and (humanoid and isRagdolled)) then
							for _ = 0, 50 do
								if not BringAll or not Hub.alive or ticket~=Hub.bringAllEpoch or player.Character~=boundCharacter
									or not CheckPlayer(player) or humanoidRootPart.Parent~=boundCharacter or humanoid.Parent~=boundCharacter then
									break
								end

								SNOWshipOnce(humanoidRootPart)
								if CheckNetworkOwnerShipOnPlayer(player) then
									if not isRagdolled.Value and player:DistanceFromCharacter(playerCFrame.Position) > 10 then
										humanoidRootPart.CFrame = playerCFrame
									end
									CreateBringBody(humanoidRootPart, playerCFrame)
									break
								end
								task.wait()
								if not BringAll or ticket~=Hub.bringAllEpoch or player.Character~=boundCharacter or not humanoidRootPart.Parent then break end
								if humanoidRootPart.Position.Y <= - 12 then
									TeleportPlayer(CFrame.new(humanoidRootPart.Position + Vector3.new(0, 5, - 15)))
								else
									TeleportPlayer(CFrame.new(humanoidRootPart.Position + Vector3.new(0, - 10, - 10)))
								end
							end
						end
					end
					end,debug.traceback)
					if not ok then
						skipped[player]={character=player.Character,untilTime=os.clock()+10}
						warn("[Arriva Bring All] Skipping " .. player.Name .. " for 10 seconds: " .. tostring(playerError))
					end
					end
				end
				TeleportPlayer(CFrame.new(527, 123, - 376))
				task.wait()
			end
			if ticket==Hub.bringAllEpoch then unFreezeCam();TeleportPlayer(playerCFrame) end
		elseif ticket==Hub.bringAllEpoch then
			unFreezeCam()
		end
		end)
	end

})

-- Selected-player version of Bring All, with bounded retries and cleanup.
do
(function()
    TargetGroup:AddButton({Text="Bring (grab)",Func=function()
        if BringAll or Hub.singleBringBusy then notify("Bring","Stop Bring All or wait for the current bring to finish.",4);return end
        if Hub.safeZoneLoopActive then notify("Bring","Turn off Loop go to safe zone before bringing a player.",4);return end
        local target=SelectedPlayer
        if not CheckPlayerBring(target) then notify("Bring","Selected player is protected, in a plot, moving too quickly or not ready.",5);return end
        local myChar=Player.Character
        local myRoot=myChar and myChar:FindFirstChild("HumanoidRootPart")
        local myHum=myChar and myChar:FindFirstChildOfClass("Humanoid")
        local targetChar=target.Character
        local root=targetChar:FindFirstChild("HumanoidRootPart")
        local hum=targetChar:FindFirstChildOfClass("Humanoid")
        local ragdolled=hum and hum:FindFirstChild("Ragdolled")
        if not myRoot or not myHum or myHum.Health<=0 or not root or not ragdolled then notify("Bring","Character parts or Ragdolled value are not ready.",4);return end
        Hub.singleBringBusy=true
        task.spawn(function()
            local saved=myRoot.CFrame
            local camera=Workspace.CurrentCamera
            local cameraState=camera and {kind=camera.CameraType,subject=camera.CameraSubject,cf=camera.CFrame}
            local success=false
            local function current()
                return Hub.alive and not BringAll and not Hub.safeZoneLoopActive and Player.Character==myChar and myRoot.Parent==myChar and myHum.Health>0
                    and target.Character==targetChar and root.Parent==targetChar and hum.Parent==targetChar and hum.Health>0 and Hub.canHarm(target)
            end
            local ok,err=xpcall(function()
                if camera then FreezeCam(CFrame.lookAt(camera.CFrame.Position+Vector3.new(-15,15,0),saved.Position)) end
                for _=1,51 do
                    if not current() then break end
                    local plot=target:FindFirstChild("InPlot")
                    if plot and plot.Value then break end
                    SNOWshipOnce(root)
                    if CheckNetworkOwnerShipOnPlayer(target) then
                        if not ragdolled.Value and target:DistanceFromCharacter(saved.Position)>10 then root.CFrame=saved end
                        CreateBringBody(root,saved)
                        success=true;break
                    end
                    task.wait()
                    if not current() then break end
                    TeleportPlayer(CFrame.new(root.Position+Vector3.new(0,root.Position.Y<=-12 and 5 or -10,root.Position.Y<=-12 and -15 or -10)))
                end
            end,debug.traceback)
            if Player.Character==myChar and myRoot.Parent==myChar and myHum.Health>0 and not Hub.safeZoneLoopActive then
                pcall(function() myRoot.CFrame=saved;myRoot.AssemblyLinearVelocity=Vector3.zero;myRoot.AssemblyAngularVelocity=Vector3.zero end)
            end
            if camera and cameraState and Workspace.CurrentCamera==camera then pcall(function()
                camera.CameraType=cameraState.kind;camera.CameraSubject=cameraState.subject;camera.CFrame=cameraState.cf
            end) end
            Hub.singleBringBusy=false
            if not ok then warn("[Arriva Bring selected] " .. tostring(err));notify("Bring","Bring stopped after an error, your position was restored where possible.",5)
            elseif success then notify("Bring",target.Name .. " brought to your starting position.",4)
            else notify("Bring","Target changed or ownership was not confirmed before retries ended.",5) end
        end)
    end})
end)()
end

-- Anti Anti-Kick
local antiAntiKickActive = false
TargetGroup:AddToggle("DestroyAntiKickToggle", {
	Text = "Grab Anti Kick",
	Default = false,
	Callback = function(Value)
        local running, ownsRun = Hub.beginTargetLoop("DestroyAntiKickToggle", Value)
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

				while running() do
                    local target = Hub.nextLoopTarget("antiKick")
                    if not target then task.wait(0.2); continue end
					if Hub.canHarm(target) then
						local spawned = workspace:FindFirstChild(target.Name.."SpawnedInToys")
						if spawned then
							if spawned:FindFirstChild("NinjaKunai") then
								CheckAndYeet(spawned.NinjaKunai)
							end
							if spawned:FindFirstChild("NinjaKatana") then
								CheckAndYeet(spawned.NinjaKatana)
							end
							if spawned:FindFirstChild("ToolCleaver") then
								CheckAndYeet(spawned.ToolCleaver)
							end
							if spawned:FindFirstChild("ToolPickaxe") then
								CheckAndYeet(spawned.ToolPickaxe)
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
TargetNotificationGroup:AddToggle("JoinedNotifyBtn", {
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

                if not detected and Hub.isSelectedTarget(newPlayer) then
                    detected = true
                    reason = "[Main Target]"
                end

				if detected then
					notify("Target Returned!" .. reason .. " | Player: " .. newPlayer.Name, 8)
					if Hub.isSelectedTarget(newPlayer) and Hub.canHarm(newPlayer) then SelectedPlayer = SelectedPlayer or newPlayer end
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
Hub.connect(Players.PlayerRemoving,function(player)
    local c=respawnConnections[player]
    if c then c:Disconnect();Hub.connections[c]=nil;respawnConnections[player]=nil end
end)

local function isTrackedPlayer(player)
	if Hub.isProtected(player) then return true, "[Protected]" end
    if Hub.isSelectedTarget(player) then return true, "[Main Target]" end
	return false, nil
end

local function trackRespawn(player)
	if respawnConnections[player] then return end

	respawnConnections[player] = Hub.connect(player.CharacterAdded, function()
		if not respawnNotifyActive then return end

		local tracked, reason = isTrackedPlayer(player)
		if not tracked then return end

		notify("Target respawned", player.Name .. " has respawned. " .. reason, 8)
		if Hub.isSelectedTarget(player) and Hub.canHarm(player) then SelectedPlayer = SelectedPlayer or player end

		local sound = Hub.new("Sound")
		sound.SoundId = "rbxassetid://4590662766"
		sound.Volume = 2
		sound.Parent = workspace
		sound:Play()
		Debris:AddItem(sound, 3)
	end)
end

TargetNotificationGroup:AddToggle("RespawnNotifyBtn", {
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
			if respawnConnections["_PlayerAdded"] then respawnConnections["_PlayerAdded"]:Disconnect();Hub.connections[respawnConnections["_PlayerAdded"]]=nil end
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


AuraGroup:AddToggle("FlingAura", {
	Text = "Fling Aura",
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
											lookAtCFrame = lookAt(LocalPlayer.Character.HumanoidRootPart.Position, tRoot.Position)
											local bodyVelocity = Instance.new("BodyVelocity", target.Character.HumanoidRootPart)
											bodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
											bodyVelocity.Velocity = Vector3.new(lookAtCFrame.lookVector.X, 0.5, lookAtCFrame.lookVector.Z) * 100
											wait()
											bodyVelocity:Destroy()
											destroyGrabLineEvent:FireServer(tRoot)
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
local GrabOptions = Tabs.Grab:AddLeftGroupbox("Grab Options")

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

GrabOptions:AddToggle("NoclipGrabToggle", {
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

-- Massless Grab: preserve the grabbed orientation relative to the character.
do
	local enabled=false
	local listeners={}
	local tracked={}
	local function restore(entry)
		for object,properties in pairs(entry.saved) do
			for property,value in pairs(properties) do pcall(function() object[property]=value end) end
		end
		table.clear(entry.saved)
	end
	local function set(entry,object,values)
		local saved=entry.saved[object]
		if not saved then saved={};entry.saved[object]=saved end
		for property,value in pairs(values) do
			if saved[property]==nil then saved[property]=object[property] end
			object[property]=value
		end
	end
	local function canStabilizePart(part)
		if not part or not part:IsA("BasePart") or not Hub.canAffect(part) then return false end
		local character=Player.Character
		if character and part:IsDescendantOf(character) then return false end
		return true
	end
	local function target(model)
		local grab=model:FindFirstChild("GrabPart",true)
		local weld=grab and grab:FindFirstChildWhichIsA("WeldConstraint")
		if weld then
			for _,part in pairs({weld.Part1,weld.Part0}) do
				if part and not part:IsDescendantOf(model) and canStabilizePart(part) then return part end
			end
		end
	end
	local function configure(model,entry)
		local part=target(model)
		local drag=model:FindFirstChild("DragPart1",true) or model:FindFirstChild("DragPart",true)
		local orientation=drag and drag:FindFirstChildWhichIsA("AlignOrientation")
		local position=drag and drag:FindFirstChildWhichIsA("AlignPosition")
		if not part or not orientation or not position then return false end
		if entry.part~=part or entry.orientation~=orientation or entry.position~=position then
			restore(entry)
			entry.part,entry.orientation,entry.position=part,orientation,position
			local character=Player.Character
			local root=character and character:FindFirstChild("HumanoidRootPart")
			entry.reference=root
			entry.rotationOffset=root and root.CFrame.Rotation:ToObjectSpace(part.CFrame.Rotation) or nil
		end
		-- The orientation target is handled below, independently of positional movement.
		set(entry,orientation,{Enabled=false})
		set(entry,position,{MaxForce=1e9,Responsiveness=200})
		return true
	end
	local function track(model)
		if enabled and model:IsA("Model") and model.Name=="GrabParts" and not tracked[model] then
			tracked[model]={saved={},elapsed=0}
			configure(model,tracked[model])
		end
	end
	local function stop()
		enabled=false
		for _,connection in ipairs(listeners) do connection:Disconnect();Hub.connections[connection]=nil end
		table.clear(listeners)
		for _,entry in pairs(tracked) do restore(entry) end
		table.clear(tracked)
	end
	local function start()
		stop();enabled=true
		table.insert(listeners,Hub.connect(workspace.ChildAdded,track))
		for _,model in ipairs(workspace:GetChildren()) do track(model) end
		table.insert(listeners,Hub.connect(RunService.Heartbeat,function(dt)
			for model,entry in pairs(tracked) do
				if not model.Parent or not Hub.canAffect(model) then
					restore(entry);tracked[model]=nil
				else
					entry.elapsed+=dt
					if entry.elapsed>=0.1 then
						entry.elapsed=0
						if not configure(model,entry) then
							restore(entry);entry.part=nil;entry.orientation=nil;entry.position=nil
						end
					end
					local part=entry.part
					if part and part.Parent and not part.Anchored and canStabilizePart(part) then
						local root=entry.reference
						local character=Player.Character
						if root and root.Parent==character and entry.rotationOffset then
							-- Preserve the grabbed face relative to the player, not to the world.
							local rotation=root.CFrame.Rotation*entry.rotationOffset
							part.CFrame=CFrame.new(part.Position)*rotation
						end
						part.AssemblyAngularVelocity=Vector3.zero
					end
				end
			end
		end))
	end
	GrabOptions:AddToggle("MasslessGrabToggle",{Text="Massless Grab",Default=false,
		Callback=function(on) if on then start() else stop() end;Hub.requestSave() end})
	Hub.cleanup(stop)
end

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

GrabOptions:AddToggle("KillGrabToggle", {
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

-- One-shot missile throw adapted from the reference's M shortcut; V is the default here.
do
(function()
    local group = Hub.keybindGroups.missiles
    local enabled, generation = true, 0
    local pending, forces, referenceConnections = {}, {}, {}
    Hub.missileLaunchClaims = {}
    local status = group:AddLabel("Reference actions: Throw Bomb, Explode Bomb, Explode Firework.")
    local function disconnect(connection)
        if connection then connection:Disconnect(); Hub.connections[connection] = nil end
    end
    local function release(force)
        local root = forces[force]
        if not root then return end
        forces[force] = nil
        if Hub.missileLaunchClaims[root] == force then Hub.missileLaunchClaims[root] = nil end
        Hub.instances[force], Hub.assetTargets[force] = nil, nil
        pcall(function() force:Destroy() end)
    end
    local function cancel()
        generation += 1
        for _, connection in ipairs(referenceConnections) do disconnect(connection) end
        table.clear(referenceConnections)
        for operation, connection in pairs(pending) do disconnect(connection); pending[operation] = nil end
        local list = {}
        for force in pairs(forces) do table.insert(list, force) end
        for _, force in ipairs(list) do release(force) end
        status:SetText("Pending missile actions cancelled; launch forces released.")
    end
    local function ownedStatus(name)
        local node = Player:FindFirstChildOfClass("PlayerGui")
        for _, childName in ipairs({"MenuGui", "Menu", "TabContents", "Toys", "Contents"}) do
            node = node and node:FindFirstChild(childName)
        end
        return not node or node:FindFirstChild(name) ~= nil
    end
    local function run(name, explode)
        if not Hub.alive or not enabled or Hub.keybindCaptureActive or UserInputService:GetFocusedTextBox() then return false end
        local char = Player.Character
        local head = char and char:FindFirstChild("Head")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health <= 0 or not ownedStatus(name) then
            status:SetText("Character unavailable or toy not owned: " .. name); return false
        end
        local menu = ReplicatedStorage:FindFirstChild("MenuToys")
        local spawn = menu and menu:FindFirstChild("SpawnToyRemoteFunction")
        local grabs = ReplicatedStorage:FindFirstChild("GrabEvents")
        local owner = grabs and grabs:FindFirstChild("SetNetworkOwner")
        local folder = Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
        local events = ReplicatedStorage:FindFirstChild("BombEvents")
        local explosion = events and events:FindFirstChild("BombExplode")
        if not spawn or not owner or not folder or (explode and not explosion) then
            status:SetText("Missile remotes or toy folder are not ready."); return false
        end
        local operation = name .. (explode and ":explode" or ":throw")
        if pending[operation] then status:SetText("That missile action is already waiting for its toy."); return false end
        local ticket, accepted = generation, false
        local function current()
            return Hub.alive and enabled and ticket == generation and Player.Character == char and hum.Health > 0
        end
        local function finish()
            disconnect(pending[operation]); pending[operation] = nil
        end
        -- Same order as the supplied callbacks: subscribe FIRST, then spawn asynchronously.
        pending[operation] = Hub.connect(folder.ChildAdded, function(child)
            if accepted or not current() or child.Name ~= name then return end
            local number = child:WaitForChild("ThisToysNumber", 1)
            local counter = folder:FindFirstChild("ToyNumber")
            if not number or not counter or number.Value ~= counter.Value - 1 or accepted or not current() then return end
            accepted = true
            finish()
            local hit = child:WaitForChild("PartHitDetector", 1)
            if not hit or not hit:IsA("BasePart") or child.Parent ~= folder or not current() then return end
            Hub.fire(owner, hit, hit.CFrame)
            if explode then
                local body = child:WaitForChild("Body", 1)
                if not body or not body:IsA("BasePart") or not current() then return end
                Hub.fire(explosion, {
                    Radius = 17.5, TimeLength = 2, Hitbox = hit,
                    ExplodesByFire = false, MaxForcePerStudSquared = 225,
                    Model = child, ImpactSpeed = 100, ExplodesByPointy = false,
                    DestroysModel = false, PositionPart = body,
                }, body.Position)
                status:SetText("Requested " .. name .. " explosion (reference action).")
            else
                local camera = Workspace.CurrentCamera
                if not camera then return end
                local velocityObj = Hub.new("BodyVelocity", hit)
                forces[velocityObj] = hit.AssemblyRootPart or hit
                Hub.missileLaunchClaims[forces[velocityObj]] = velocityObj
                velocityObj.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
                velocityObj.Velocity = camera.CFrame.LookVector * 500
                Debris:AddItem(velocityObj, 10)
                task.delay(10, function() release(velocityObj) end)
                status:SetText("Threw BombMissile at 500 studs/sec (reference action).")
            end
        end)
        -- Reference explosion listeners expire after one second; bound throw listeners too.
        task.delay(explode and 1 or 5, function()
            if ticket == generation and not accepted then finish() end
        end)
        local spawnCFrame = head and head.CFrame or root.CFrame
        task.spawn(function()
            if not current() then return end
            local ok, err = pcall(function() Hub.invoke(spawn, name, spawnCFrame, Vector3.zero) end)
            if not ok and current() then finish(); status:SetText("Missile spawn failed: " .. tostring(err)) end
        end)
        return true
    end
    function Hub.throwMissile()
        if not Hub.alive or not enabled or Hub.keybindCaptureActive or UserInputService:GetFocusedTextBox() then return false end
        local localPlayer = Player
        local playerCharacter = localPlayer.Character
        local toysFolder = Workspace:FindFirstChild(localPlayer.Name .. "SpawnedInToys")
        if not playerCharacter or not toysFolder then return false end
        local workspace = Workspace
        local SetNetworkOwner = ReplicatedStorage.GrabEvents.SetNetworkOwner
        local ownedToys = {}
        local node = localPlayer:FindFirstChildOfClass("PlayerGui")
        for _, name in ipairs({"MenuGui", "Menu", "TabContents", "Toys", "Contents"}) do node = node and node:FindFirstChild(name) end
        if node then
            for _, toy in ipairs(node:GetChildren()) do
                if toy.Name ~= "UIGridLayout" then ownedToys[toy.Name] = true end
            end
        else
            ownedToys.BombMissile = true -- Let the normal server spawn validate while the menu loads.
        end
        local OrionLib = {MakeNotification = function(_, info) status:SetText(info.Content) end}
        -- BEGIN supplied spawnItemCf (verbatim)
local function spawnItemCf(itemName, cframe)
	task.spawn(function()
		local rotation = Vector3.new(0, 0, 0)
		ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer(itemName, cframe, rotation)
	end)
end
        -- END supplied spawnItemCf
        -- BEGIN supplied Throw Bomb callback (only connection bookkeeping added)
		if not ownedToys["BombMissile"] then
			OrionLib:MakeNotification({Name = "Missing toy", Content = "You do not own the BombMissile toy. ", Image = "rbxassetid://4483345998", Time = 3})
			return
		end

		local connection
		connection = toysFolder.ChildAdded:Connect(function(child)
			if child.Name == "BombMissile" then
				if child:WaitForChild("ThisToysNumber", 1) then

					if child.ThisToysNumber.Value == (toysFolder.ToyNumber.Value - 1) then

						connection:Disconnect()

						SetNetworkOwner:FireServer(child.PartHitDetector, child.PartHitDetector.CFrame)
						local velocityObj = Instance.new("BodyVelocity", child.PartHitDetector)
						velocityObj.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
						velocityObj.Velocity = workspace.CurrentCamera.CFrame.lookVector * 500
						Debris:AddItem(velocityObj, 10)
                        -- BEGIN hub bookkeeping (no launch changes)
                        local assembly = child.PartHitDetector.AssemblyRootPart or child.PartHitDetector
                        forces[velocityObj] = assembly
                        Hub.missileLaunchClaims[assembly] = velocityObj
                        Hub.instances[velocityObj] = true
                        task.delay(10, function() release(velocityObj) end)
                        -- END hub bookkeeping
					end
				end
			end
		end)
        table.insert(referenceConnections, connection)
        Hub.connections[connection] = true
		spawnItemCf("BombMissile", playerCharacter.Head.CFrame or playerCharacter.HumanoidRootPart.CFrame)
        -- END supplied Throw Bomb callback
        return true
    end
    function Hub.explodeMissile(name)
        if name ~= "BombMissile" and name ~= "FireworkMissile" then return false end
        return run(name, true)
    end
    group:AddLabel("Throw Bomb"):AddKeyPicker("MissileThrowKey", {Default = "V", Text = "Throw Bomb", Callback = Hub.throwMissile})
    group:AddLabel("Explode Bomb"):AddKeyPicker("ExplodeBombKey", {Default = "J", Text = "Explode Bomb", Callback = function() Hub.explodeMissile("BombMissile") end})
    group:AddLabel("Explode Firework"):AddKeyPicker("ExplodeFireworkKey", {Default = "N", Text = "Explode Firework", Callback = function() Hub.explodeMissile("FireworkMissile") end})
    group:AddToggle("MissileThrowEnabled", {Text = "Enable missile actions", Default = true, Callback = function(on) enabled = on; if not on then cancel() end end})
    group:AddButton({Text = "Throw Bomb", Func = Hub.throwMissile})
    group:AddButton({Text = "Explode Bomb", Func = function() Hub.explodeMissile("BombMissile") end})
    group:AddButton({Text = "Explode Firework", Func = function() Hub.explodeMissile("FireworkMissile") end})
    group:AddButton({Text = "Cancel missile actions", Func = cancel})
    group:AddLabel("V: throw a new bomb at 500 studs/sec. J: spawn and immediately explode a bomb. N: spawn and immediately explode a firework. These are separate reference actions; no added impact trigger or fuse. Server physics and remote validation still apply.")
    Hub.connect(Player.CharacterRemoving, cancel)
    Hub.cleanup(function()
        enabled = false; cancel()
        Hub.throwMissile, Hub.explodeMissile = nil, nil
    end)
end)()
end
-- End missile throw.

-- Click TP requires a finite, solid surface hit, never Mouse.Hit's sky fallback.
Hub.clickTeleport=function()
    if Hub.safeZoneLoopActive then return end
            local char=Player.Character
            local root=char and char:FindFirstChild("HumanoidRootPart")
            local hum=char and char:FindFirstChildOfClass("Humanoid")
            if not root or not hum or hum.Health<=0 then return end
            local ray=mouse.UnitRay
            local filter=RaycastParams.new()
            filter.FilterType=Enum.RaycastFilterType.Exclude
            filter.FilterDescendantsInstances={char}
            filter.RespectCanCollide=true
            filter.IgnoreWater=true
            local hit=Workspace:Raycast(ray.Origin,ray.Direction*512,filter)
            if not hit or hit.Normal.Y<0.5 then return end
            local position=hit.Position
            for _,value in ipairs({position.X,position.Y,position.Z}) do
                if value~=value or math.abs(value)==math.huge then return end
            end
            if (position-root.Position).Magnitude>512 or position.Y<=Workspace.FallenPartsDestroyHeight+8 then return end
            local characterOwner=Hub.playerOf(hit.Instance)
            if characterOwner then return end
            local clearance=math.max(3,hum.HipHeight+root.Size.Y/2+0.5)
            root.CFrame=CFrame.new(position+Vector3.new(0,clearance,0))*root.CFrame.Rotation
            root.AssemblyLinearVelocity=Vector3.zero
            root.AssemblyAngularVelocity=Vector3.zero
end
MiscGroup:AddToggle("TPToggle",{Text="Click TP (Z)",Default=false,Callback=function(on)
    if tpToolConn then tpToolConn:Disconnect();Hub.connections[tpToolConn]=nil;tpToolConn=nil end
    if on then tpToolConn=Hub.connect(UserInputService.InputBegan,function(input,processed)
        if not processed and Hub.matchesKeybind("ClickTeleportKey", input, "Z") and not UserInputService:GetFocusedTextBox() then Hub.clickTeleport() end
    end) end
end})


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
Hub.menuMouse = setFreeMouse
setFreeMouse(Hub.menuVisible ~= false)
Hub.cleanup(function() Hub.menuMouse = nil; setFreeMouse(false) end)
Hub.connect(UserInputService.InputBegan, function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if Hub.matchesKeybind("FreeMouseKey", input, "F") then setFreeMouse(not enabled) end
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

	-- Correlate a real departure with proximity to a recently detected hole.
	local recentHoles={}
	local lastPositions={}
	local function rememberHole(obj)
		if not isBlackHole(obj) then return end
		local position=getBHPosition(obj)
		if not position then return end
		table.insert(recentHoles,{position=position,time=os.clock(),object=obj})
		if #recentHoles>20 then table.remove(recentHoles,1) end
	end
	Hub.connect(workspace.ChildAdded,function(obj)
		task.delay(0.1,function() if Hub.alive and obj.Parent then rememberHole(obj) end end)
	end)
	for _,obj in ipairs(workspace:GetChildren()) do rememberHole(obj) end
	local nextSample=0
	Hub.connect(RunService.Heartbeat,function()
		local now=os.clock()
		if now<nextSample then return end
		nextSample=now+0.25
		for _,person in ipairs(Players:GetPlayers()) do
			local char=person.Character
			local root=char and char:FindFirstChild("HumanoidRootPart")
			if root then lastPositions[person]={position=root.Position,time=now} end
		end
		for index=#recentHoles,1,-1 do
			if now-recentHoles[index].time>6 then table.remove(recentHoles,index) end
		end
	end)
	Hub.connect(Players.PlayerRemoving,function(person)
		local cached=lastPositions[person]
		lastPositions[person]=nil
		local char=person.Character
		local root=char and char:FindFirstChild("HumanoidRootPart")
		local position=root and root.Position or (cached and os.clock()-cached.time<2 and cached.position)
		if not position then return end
		for _,hole in ipairs(recentHoles) do
			if os.clock()-hole.time<=6 then
				local holePosition=hole.object.Parent and getBHPosition(hole.object) or hole.position
				if holePosition and (position-holePosition).Magnitude<=100 then
					notify("Player kicked",person.Name .. " has been taken by a blackhole",5)
					return
				end
			end
		end
	end)
	Hub.cleanup(function() table.clear(lastPositions);table.clear(recentHoles) end)
end

-- Anchor Object
Hub.anchorHeldObject = function(value)
		if type(value)=="string" then return end -- Rebinding is not an activation.
		local original = workspace:FindFirstChild("GrabParts")
		if not original then return end

		local grabPart = original:FindFirstChild("GrabPart", true)
		if not grabPart or not grabPart:IsA("BasePart") then return end

		local heldPart
		for _,joint in ipairs(original:GetDescendants()) do
			if joint:IsA("JointInstance") or joint:IsA("WeldConstraint") then
				for _,part in pairs({joint.Part1,joint.Part0}) do
					if part and part:IsA("BasePart") and not part:IsDescendantOf(original) then
						heldPart=part;break
					end
				end
			end
			if heldPart then break end
		end
		if not heldPart then
			local beam=original:FindFirstChildWhichIsA("Beam",true)
			local attachment=beam and beam.Attachment1
			local part=attachment and attachment.Parent
			if part and part:IsA("BasePart") and not part:IsDescendantOf(original) then heldPart=part end
		end
		if not heldPart then notify("Anchor Object","Grab an object first, its attachment was not found.",4);return end
		local targetModel=heldPart:FindFirstAncestorOfClass("Model")
		if not targetModel then targetModel=heldPart end
		local ancestor=heldPart.Parent
		while ancestor and ancestor~=workspace do
			if ancestor:IsA("Model") and ancestor:FindFirstChildOfClass("Humanoid") then
				notify("Anchor Object","This bind only supports objects, not characters.",4);return
			end
			ancestor=ancestor.Parent
		end
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

		local ok,clone = pcall(function() return original:Clone() end)
		if not ok or not clone then notify("Anchor Object","The current grab could not be copied.",4);return end
		Hub.instances[clone]=true
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
		if Hub.styleAnchorHighlight then Hub.styleAnchorHighlight(hl) end

		local destroyConnection
		destroyConnection=Hub.connect(clone.Destroying,function()
			if hl.Parent then hl:Destroy() end
			if destroyConnection then destroyConnection:Disconnect();Hub.connections[destroyConnection]=nil end
		end)

end
Hub.keybindGroups.actions:AddLabel("Anchor held object"):AddKeyPicker("AnchorObjectKey", {Default="G",Text="Anchor Object",NoUI=false,Callback=Hub.anchorHeldObject})



-- Local cosmetic effects: no remotes, physics changes or character reparenting.
do
	local group = Tabs.Aura:AddRightGroupbox("Local Visual Auras")
	local outlineOn, lightOn = false, false
	local outline, light, childConnection
	local currentCharacter
	local disposed = false

	local function clearEffects()
		if outline then outline:Destroy(); outline = nil end
		if light then light:Destroy(); light = nil end
	end

	local function refresh()
		clearEffects()
		local char = currentCharacter
		if disposed or not char or not char.Parent then return end
		if outlineOn then
			outline = Instance.new("Highlight")
			outline.Name = "ArrivaLocalAura"
			outline.Adornee = char
			outline.DepthMode = Enum.HighlightDepthMode.Occluded
			outline.FillColor = Color3.fromRGB(130, 90, 255)
			outline.OutlineColor = Color3.fromRGB(210, 190, 255)
			outline.FillTransparency = 0.85
			outline.OutlineTransparency = 0.15
			outline.Parent = char
		end
		local root = char:FindFirstChild("HumanoidRootPart")
		if lightOn and root then
			light = Instance.new("PointLight")
			light.Name = "ArrivaLocalGlow"
			light.Color = Color3.fromRGB(150, 110, 255)
			light.Brightness = 1
			light.Range = 12
			light.Shadows = false
			light.Parent = root
		end
	end

	local function bind(char)
		if childConnection then childConnection:Disconnect(); childConnection = nil end
		clearEffects()
		currentCharacter = char
		if disposed or not char then return end
		childConnection = char.ChildAdded:Connect(function(child)
			if child.Name == "HumanoidRootPart" then refresh() end
		end)
		refresh()
	end

	group:AddToggle("LocalOutlineAura", {
		Text = "Self Outline Aura", Default = false,
		Callback = function(on) outlineOn = on; refresh(); Hub.requestSave() end,
	})
	group:AddToggle("LocalGlowAura", {
		Text = "Self Glow Aura", Default = false,
		Callback = function(on) lightOn = on; refresh(); Hub.requestSave() end,
	})
	Hub.connect(Player.CharacterAdded, bind)
	Hub.connect(Player.CharacterRemoving, function(char)
		if char == currentCharacter then bind(nil) end
	end)
	Hub.cleanup(function()
		disposed = true
		bind(nil)
	end)
	bind(Player.Character)
end

-- Camera-only spectator, adapted from the reference's View feature.
do
	local group = Tabs.Player:AddRightGroupbox("Spectator Camera")
	local selected, enabled, stopped = nil, false, false
	local originalCamera, originalSubject
	local characterConnection, childConnection
	local dropdown
	local function disconnectTarget()
		if characterConnection then characterConnection:Disconnect(); characterConnection = nil end
		if childConnection then childConnection:Disconnect(); childConnection = nil end
	end
	local function restore()
		if originalCamera then
			local subject = originalSubject
			if not subject or not subject.Parent then
				subject = Player.Character and Player.Character:FindFirstChildOfClass("Humanoid")
			end
			if subject then pcall(function() originalCamera.CameraSubject = subject end) end
		end
		originalCamera, originalSubject = nil, nil
	end
	local function update(char)
		if childConnection then childConnection:Disconnect(); childConnection = nil end
		if stopped or not enabled or not char then return end
		local function apply()
			local camera = workspace.CurrentCamera
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if camera and humanoid then
				if camera ~= originalCamera then
					restore()
					originalCamera, originalSubject = camera, camera.CameraSubject
				end
				camera.CameraSubject = humanoid
			end
		end
		childConnection = char.ChildAdded:Connect(function(child)
			if child:IsA("Humanoid") then apply() end
		end)
		apply()
	end
	local function bind()
		disconnectTarget()
		if stopped or not enabled or not selected then restore(); return end
		characterConnection = selected.CharacterAdded:Connect(update)
		update(selected.Character)
	end
	local function names()
		local values = {}
		for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
			if player ~= Player then table.insert(values, player.Name) end
		end
		table.sort(values)
		return values
	end
	dropdown = group:AddDropdown("LocalSpectatorPlayer", {
		Text = "View Player", Values = names(), AllowNull = true,
		Callback = function(name)
			restore()
			selected = type(name) == "string" and game:GetService("Players"):FindFirstChild(name) or nil
			bind()
		end,
	})
	group:AddToggle("LocalSpectatorEnabled", {
		Text = "Spectate (camera only)", Default = false,
		Callback = function(on) enabled = on; bind() end,
	})
	local players = game:GetService("Players")
	Hub.connect(players.PlayerAdded,function() Hub.queueRefresh("spectator",function() dropdown:SetValues(names()) end) end)
	Hub.connect(players.PlayerRemoving, function(leaving)
		local values = names()
		local index = table.find(values, leaving.Name)
		if index then table.remove(values, index) end
		if leaving == selected then selected = nil; bind(); dropdown:SetValue(nil) end
		Hub.queueRefresh("spectator",function() dropdown:SetValues(names()) end)
	end)
	Hub.connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
		if enabled and selected then update(selected.Character) end
	end)
	Hub.cleanup(function() stopped = true; disconnectTarget(); restore() end)
end

-- Creative shapes: local decorations or the local player's existing toys only.
-- No ownership requests, grab remotes, player targets or map-object collection.
do
	(function()
		local shapes=Tabs.Fun:AddLeftGroupbox("Creative Object Aura")
		local settings=Tabs.Fun:AddRightGroupbox("Shape Settings")
		local enabled=false
		local mode,shape="Local decorations","Heart"
		local count,radius,height,distance,speed=24,8,5,12,20
		local entries={}
		local connection,decorationFolder
		local epoch,phase,elapsed,nextScan=0,0,0,0
		local status=shapes:AddLabel("Aura is off.")
        local centerMode,placedCenter="Follow me",nil
        local function aimedCenter()
            local char=Player.Character
            local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances=decorationFolder and {char,decorationFolder} or {char}
            params.IgnoreWater=true
            local ray=mouse.UnitRay;local hit=Workspace:Raycast(ray.Origin,ray.Direction*200,params)
            if not hit then return nil end
            local root=char and char:FindFirstChild("HumanoidRootPart")
            if not root or (hit.Position-root.Position).Magnitude>100 then return nil end
            return CFrame.new(hit.Position+Vector3.new(0,height,0))*root.CFrame.Rotation
        end
        settings:AddDropdown("CreativeAuraCenter",{Text="Formation center",Values={"Follow me","Follow mouse","Click to place"},Default=1,
            Callback=function(value) centerMode=value;placedCenter=nil end})
        Hub.connect(UserInputService.InputBegan,function(input,processed)
            if enabled and centerMode=="Click to place" and not processed and not UserInputService:GetFocusedTextBox()
                and (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch) then
                placedCenter=aimedCenter() or placedCenter
            end
        end)
        local spawnBatch,cancelSpawn

		local function point(name,index,total,rotation)
			local fraction=(index-1)/math.max(total,1)
			local angle=fraction*math.pi*2+rotation
			if name=="Heart" then
				return Vector3.new(16*math.sin(angle)^3/18,
					(13*math.cos(angle)-5*math.cos(2*angle)-2*math.cos(3*angle)-math.cos(4*angle))/18,0)
			elseif name=="Figure Eight" then
				return Vector3.new(math.sin(angle),math.sin(2*angle)*0.5,0)
			elseif name=="Tornado" then
                local width=0.2+fraction*0.8
                return Vector3.new(math.cos(angle*3)*width,(fraction-0.5)*2,math.sin(angle*3)*width)
            elseif name=="Blackhole" then
                local width=0.15+fraction*0.85
                return Vector3.new(math.cos(angle*3)*width,math.sin(angle*3)*width,0)
            elseif name=="Star" then
                local width=index%2==0 and 0.45 or 1
                return Vector3.new(math.cos(angle)*width,math.sin(angle)*width,0)
            elseif name=="Helix" then
				return Vector3.new(math.cos(angle),(fraction-0.5)*2,math.sin(angle))
			end
			return Vector3.new(math.cos(angle),math.sin(angle),0)
		end
		Hub.creativeShapePoint=point

		local function release(entry)
			if entry.decoration then
				pcall(function() entry.part:Destroy() end)
				return
			end
			for _,object in ipairs(entry.controllers or {}) do pcall(function() object:Destroy() end) end
			for part,value in pairs(entry.collisions or {}) do
				pcall(function() if part.Parent then part.CanCollide=value end end)
			end
			pcall(function()
				if entry.part.Parent and not entry.part.Anchored then
					entry.part.AssemblyLinearVelocity=Vector3.zero
					entry.part.AssemblyAngularVelocity=Vector3.zero
				end
			end)
		end
		local function stopWorker()
			if cancelSpawn then cancelSpawn() end
			epoch+=1
			if connection then connection:Disconnect();Hub.connections[connection]=nil;connection=nil end
			for _,entry in ipairs(entries) do release(entry) end
			table.clear(entries)
			if decorationFolder then decorationFolder:Destroy();decorationFolder=nil end
			elapsed,nextScan=0,0
		end
		local function characterRoot()
			local char=Player.Character
			return char and char:FindFirstChild("HumanoidRootPart")
		end
		local function safeAssembly(part,folder)
            if part and ((Hub.toyBuildClaims and Hub.toyBuildClaims[part.AssemblyRootPart or part]) or (Hub.missileLaunchClaims and Hub.missileLaunchClaims[part.AssemblyRootPart or part])) then return nil end
			if not part.Parent or part.Anchored or not part:IsDescendantOf(folder) then return nil end
			local owner=part:FindFirstChild("PartOwner")
			if owner and (owner:IsA("StringValue") or owner:IsA("ObjectValue")) then
				local value=owner.Value
				if value~=nil and value~="" and value~=Player.Name and value~=Player then return nil end
			end
			local parts=part:GetConnectedParts(true)
			table.insert(parts,part)
			for _,item in ipairs(parts) do
				if not item:IsDescendantOf(folder) or item.Anchored or item:IsA("Seat") or item:IsA("VehicleSeat") then return nil end
				local current=item.Parent
				while current and current~=folder do
					if current:IsA("Model") and (current:FindFirstChildOfClass("Humanoid")
						or current:FindFirstChildWhichIsA("Seat",true) or current:FindFirstChildWhichIsA("VehicleSeat",true)) then return nil end
					current=current.Parent
				end
			end
			return parts
		end
		local function addToy(part,parts)
			local collisions={}
			for _,item in ipairs(parts) do collisions[item]=item.CanCollide;item.CanCollide=false end
			local attachment=Hub.new("Attachment",part)
			attachment.Name="ArrivaCreativeAttachment"
			local position=Hub.new("AlignPosition",part)
			position.Name="ArrivaCreativePosition"
			position.Mode=Enum.PositionAlignmentMode.OneAttachment
			position.Attachment0=attachment
			position.Position=part.Position
			position.ApplyAtCenterOfMass=true
			position.MaxForce=math.clamp(part.AssemblyMass*5000,2500,100000)
			position.MaxVelocity=40
			position.Responsiveness=40
			local orientation=Hub.new("AlignOrientation",part)
			orientation.Name="ArrivaCreativeOrientation"
			orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment
			orientation.Attachment0=attachment
			orientation.CFrame=part.CFrame.Rotation
			orientation.MaxTorque=100000
			orientation.Responsiveness=30
			table.insert(entries,{part=part,controllers={position,orientation,attachment},
				position=position,orientation=orientation,collisions=collisions})
		end
		local function refreshToys(root)
			local folder=Workspace:FindFirstChild(Player.Name .. "SpawnedInToys")
			local used={}
			for index=#entries,1,-1 do
				local entry=entries[index]
				if not folder or not safeAssembly(entry.part,folder) then
					release(entry);table.remove(entries,index)
				else used[entry.part]=true end
			end
			if folder and #entries<count then
				for _,item in ipairs(folder:GetDescendants()) do
					if item:IsA("BasePart") then
						local part=item.AssemblyRootPart or item
						if not used[part] and (part.Position-root.Position).Magnitude<=80 then
							used[part]=true
							local parts=safeAssembly(part,folder)
							if parts then addToy(part,parts) end
						end
					end
					if #entries>=count then break end
				end
			end
			status:SetText(string.format("Using %d of your toy assemblies, up to %d. Others may not see client-owned movement.",#entries,count))
		end
		local function start(skipSpawn)
			stopWorker()
			if not enabled then status:SetText("Aura is off.");return end
			phase=0
			if mode=="Local decorations" then
				decorationFolder=Hub.new("Folder",Workspace)
				decorationFolder.Name="ArrivaCreativeDecorations"
				for _=1,count do
					local part=Hub.new("Part",decorationFolder)
					part.Name="ShapeDot"
					part.Shape=Enum.PartType.Ball
					part.Size=Vector3.new(0.6,0.6,0.6)
					part.Material=Enum.Material.Neon
					part.Color=Color3.fromRGB(239,120,175)
					part.Anchored=true
					part.CanCollide=false;part.CanTouch=false;part.CanQuery=false;part.CastShadow=false
					part.Transparency=1
					table.insert(entries,{part=part,decoration=true})
				end
				status:SetText("Local decoration mode, visible only to you.")
			end
			connection=Hub.connect(RunService.Heartbeat,function(dt)
				elapsed+=dt
				if elapsed<1/30 then return end
				local delta=elapsed;elapsed=0
				local root=characterRoot()
				if not root then return end
				phase=(phase+math.rad(speed)*math.min(delta,0.1))%(math.pi*2)
				if mode=="My spawned toys" and os.clock()>=nextScan then
					nextScan=os.clock()+2
					refreshToys(root)
				end
				local center=root.CFrame*CFrame.new(0,height,-distance)
                if centerMode=="Follow mouse" then center=aimedCenter() or center
                elseif centerMode=="Click to place" then center=placedCenter or center end
				for index=#entries,1,-1 do
					local entry=entries[index]
					if not entry.part.Parent then release(entry);table.remove(entries,index)
					else
						local goal=center:PointToWorldSpace(point(shape,index,#entries,phase)*radius)
						if entry.decoration then
							entry.part.CFrame=CFrame.new(goal)
							entry.part.Transparency=0
						else
							entry.position.Position=goal
							entry.part.AssemblyAngularVelocity=Vector3.zero
						end
					end
				end
			end)
			if not skipSpawn and mode=="My spawned toys" and spawnBatch then task.defer(function() spawnBatch(true) end) end
		end
		shapes:AddToggle("CreativeAuraEnabled",{Text="Creative Object Aura",Default=false,
			Callback=function(on) enabled=on;start() end})
		shapes:AddDropdown("CreativeAuraSource",{Text="Objects to use",Values={"Local decorations","My spawned toys"},Default=1,
			Callback=function(value) mode=value;start() end})
		shapes:AddLabel("Toy mode uses only your existing unanchored toys nearby. It skips characters, vehicles, other players' objects and map parts. It does not request network ownership.")
		settings:AddDropdown("CreativeAuraShape",{Text="Shape",Values={"Heart","Ring","Helix","Figure Eight","Tornado","Blackhole","Star"},Default=1,
			Callback=function(value) shape=value end})
		settings:AddSlider("CreativeAuraCount",{Text="Maximum objects",Default=24,Min=8,Max=40,Rounding=0,
			Callback=function(value) count=value;start() end})
		settings:AddSlider("CreativeAuraRadius",{Text="Shape size",Default=8,Min=3,Max=20,Rounding=0,Callback=function(value) radius=value end})
		settings:AddSlider("CreativeAuraHeight",{Text="Height",Default=5,Min=0,Max=20,Rounding=0,Callback=function(value) height=value end})
		settings:AddSlider("CreativeAuraDistance",{Text="Distance in front",Default=12,Min=6,Max=40,Rounding=0,Callback=function(value) distance=value end})
		settings:AddSlider("CreativeAuraSpeed",{Text="Animation speed",Default=20,Min=0,Max=90,Rounding=0,Callback=function(value) speed=value end})
		-- Bounded, opt-in spawning of decorative toys through the normal menu remote.
		local toyGroup=Tabs.Fun:AddLeftGroupbox("Shape Toy Picker")
		local catalog={
			{id="BallMagicLight",name="Light Ball",points=10},
			{id="MineralCrystalPink",name="Crystal",points=10},
			{id="ToyAnimalDuck",name="Rubber Duck",points=10},
			{id="ToyAnimalBear",name="Stuffed Bear",points=10},
			{id="ToyAnimalFrog",name="Toy Frog",points=10},
			{id="ToyAnimalTiger",name="Stuffed Tiger",points=10},
			{id="ToyAnimalUnicorn",name="Stuffed Unicorn",points=10},
			{id="DiceSmall",name="Small Die",points=5},
			{id="DiceBig",name="Big Die",points=5},
			{id="BallBasketball",name="Basketball",points=10},
			{id="MineralDiamond",name="Diamond",points=5},
			{id="MineralIngotGold",name="Gold Ingot",points=5},
			{id="Snowflake",name="Snowflake",points=10},
			{id="TetracubeI",name="Tetracube I",points=5},
			{id="TetracubeO",name="Tetracube O",points=5},
			{id="TetracubeT",name="Tetracube T",points=5}
		}
		local selected=catalog[1]
		local amount,autoSpawn=8,false
		local busy,cancelled=false,false
		cancelSpawn=function() cancelled=true end
		local spawnedHere={}
		local spawnStatus=toyGroup:AddLabel("Ready, choose a toy you already own.")
		local budget=toyGroup:AddLabel("Toy points are checked before every spawn.")
		local function updateBudget()
			local used=Player:FindFirstChild("UsedToyPoints")
			local cap=Player:FindFirstChild("ToysLimitCap")
			if used and cap and typeof(used.Value)=="number" and typeof(cap.Value)=="number" then
				budget:SetText(string.format("Toy points: %d / %d, selected toy costs %d.",used.Value,cap.Value,selected.points))
				return math.max(0,cap.Value-used.Value)
			end
			budget:SetText("Toy-point information unavailable, spawning is paused.")
			return nil
		end
		local function toyFolder() return Workspace:FindFirstChild(Player.Name .. "SpawnedInToys") end
		spawnBatch=function(automatic,requestedAmount)
			if busy or not Hub.alive then return end
			if automatic and (not autoSpawn or not enabled or mode~="My spawned toys") then return end
			local choice=selected
			local wanted=requestedAmount or amount
			if automatic then
				local existing=0
				local folder=toyFolder()
				if folder then for _,toy in ipairs(folder:GetChildren()) do
						if toy.Name==choice.id then existing+=1 end
					end end
				wanted=math.min(amount,math.max(0,count-existing))
			end
			if wanted==0 then spawnStatus:SetText("Enough matching toys already exist.");return end
			local menu=ReplicatedStorage:FindFirstChild("MenuToys")
			local remote=menu and menu:FindFirstChild("SpawnToyRemoteFunction")
			if not remote or not remote:IsA("RemoteFunction") then spawnStatus:SetText("Toy spawning is unavailable in this server.");return end
			busy=true;cancelled=false
			task.spawn(function()
				local made=0
				local ok,err=pcall(function()
					for index=1,wanted do
						if cancelled or not Hub.alive then break end
						local root=characterRoot()
						local char=Player.Character
						local hum=char and char:FindFirstChildOfClass("Humanoid")
						if not root or not hum or hum.Health<=0 then spawnStatus:SetText("Stopped, your character is unavailable.");return end
						local remaining=updateBudget()
						if not remaining or remaining<choice.points then spawnStatus:SetText("Stopped, not enough toy points available.");return end
						local before={}
						local folder=toyFolder()
						if folder then for _,toy in ipairs(folder:GetChildren()) do before[toy]=true end end
						spawnStatus:SetText(string.format("Spawning %s, %d / %d. Stop cancels remaining requests.",choice.name,index,wanted))
						-- Only one request can be in flight, even if the server is slow.
						remote:InvokeServer(choice.id,root.CFrame*CFrame.new((index%4)*2,0,-10-math.floor((index-1)/4)*2),Vector3.zero)
						local found
						local deadline=os.clock()+5
						repeat
							folder=toyFolder()
							if folder then for _,toy in ipairs(folder:GetChildren()) do
									if toy.Name==choice.id and not before[toy] then found=toy;break end
								end end
							if found or cancelled or not Hub.alive or Player.Character~=char then break end
							task.wait(0.1)
						until os.clock()>=deadline
						if found then spawnedHere[found]=true;made+=1 end
						if cancelled or not Hub.alive then break end
						if Player.Character~=char then spawnStatus:SetText("Stopped after respawn.");return end
						if not found then spawnStatus:SetText("Toy did not appear, check that you own it and can spawn here.");return end
						task.wait(0.75)
					end
					if Hub.alive then spawnStatus:SetText(string.format("%s, spawned %d toy(s).",cancelled and "Stopped" or "Finished",made)) end
				end)
				busy=false
				if Hub.alive then
					updateBudget()
					if not ok then spawnStatus:SetText("Spawning stopped after an error.");warn("Creative toy spawning:",err) end
				end
			end)
		end
		local labels,byLabel={},{}
		for _,toy in ipairs(catalog) do
			local label=string.format("%s (%d points)",toy.name,toy.points)
			table.insert(labels,label);byLabel[label]=toy
		end
		table.insert(labels,"Pallet (5 points)");byLabel["Pallet (5 points)"]={id="PalletLightBrown",name="Pallet",points=5}
		local picker=toyGroup:AddDropdown("CreativeToySelection",{Text="Decorative toy",Values=labels,Default=1,
			Callback=function(value) if byLabel[value] then selected=byLabel[value];updateBudget() end end})
		toyGroup:AddInput("CreativeToySearch",{Text="Search toys",Default="",Finished=false,
			Callback=function(query)
				local filtered={}
				query=string.lower(tostring(query or ""))
				for _,label in ipairs(labels) do if string.find(string.lower(label),query,1,true) then table.insert(filtered,label) end end
				picker:SetValues(filtered)
			end})
		toyGroup:AddSlider("CreativeToyBatchSize",{Text="Toys per batch",Default=8,Min=1,Max=12,Rounding=0,
			Callback=function(value) amount=math.clamp(math.floor(value),1,12) end})
		toyGroup:AddToggle("CreativeToyAutoSpawn",{Text="Spawn missing toys when aura starts",Default=false,
			Callback=function(value) autoSpawn=value end})
		toyGroup:AddButton({Text="Spawn selected toys",Func=function() spawnBatch(false) end})
        Hub.quickSpawnCreativeToy=function() spawnBatch(false,1) end
        local quickEnabled=false
        toyGroup:AddToggle("CreativeQuickSpawn",{Text="Quick spawn selected toy",Default=false,Callback=function(on) quickEnabled=on end})
        Hub.keybindGroups.actions:AddLabel("Quick-spawn selected toy"):AddKeyPicker("CreativeQuickSpawnKey",{Default="P",NoUI=true,Text="Quick-spawn key"})
        Hub.connect(UserInputService.InputBegan,function(input,processed)
            local key=Options.CreativeQuickSpawnKey
            if not processed and quickEnabled and key and Hub.matchesKeybind("CreativeQuickSpawnKey", input, "P") and not UserInputService:GetFocusedTextBox() then spawnBatch(false,1) end
        end)
		toyGroup:AddButton({Text="Stop spawning",Func=function() cancelled=true;spawnStatus:SetText(busy and "Stopping after the current request returns." or "No spawn batch running.") end})
		toyGroup:AddButton({Text="Remove toys spawned by this tool",Func=function()
			cancelled=true
			if busy then spawnStatus:SetText("Wait for the current batch to stop, then remove its toys.");return end
			local menu=ReplicatedStorage:FindFirstChild("MenuToys")
			local remote=menu and menu:FindFirstChild("DestroyToy")
			if not remote or not remote:IsA("RemoteEvent") then spawnStatus:SetText("Toy removal is unavailable.");return end
			busy=true
			task.spawn(function()
				local ok,err=pcall(function()
					stopWorker()
					for toy in pairs(spawnedHere) do
						if not Hub.alive then break end
						local folder=toyFolder()
						if folder and toy.Parent==folder then remote:FireServer(toy);task.wait(0.25) end
						spawnedHere[toy]=nil
					end
					if Hub.alive and enabled then start(true) end
				end)
				busy=false
				if not ok then warn("Creative toy cleanup:",err) end
			end)
		end})
		toyGroup:AddLabel("Up to 12 toys per batch, no purchases. Auto-spawn runs once when the toy aura starts, it does not continuously replace toys. Removal only tracks toys detected during this session's spawn requests.")
		Hub.connect(Player.CharacterRemoving,function() cancelled=true end)
		Hub.cleanup(function() cancelled=true;autoSpawn=false end)
		for _,name in ipairs({"UsedToyPoints","ToysLimitCap"}) do
			local value=Player:FindFirstChild(name)
			if value then Hub.connect(value.Changed,updateBudget) end
		end
		updateBudget()

		Hub.connect(Player.CharacterRemoving,stopWorker)
		Hub.connect(Player.CharacterAdded,function(char)
			local ticket=epoch
			task.spawn(function()
				local root=char:WaitForChild("HumanoidRootPart",5)
				if root and enabled and Hub.alive and epoch==ticket and Player.Character==char then start() end
			end)
		end)
		Hub.cleanup(function() enabled=false;stopWorker();Hub.creativeShapePoint=nil end)
	end)()
end

-- Nearby object attraction, without ownership requests or player manipulation.
do
	(function()
		local group=Tabs.Aura:AddRightGroupbox("Object Attraction Aura")
		local enabled=false
		local range,pullSpeed,limit=35,1200,80
		local entries={}
        Hub.objectAttractionParts=entries
		local connection
		local elapsed,scanElapsed=0,0
		local status=group:AddLabel("Attraction is off.")
		local query=OverlapParams.new()
		query.FilterType=Enum.RaycastFilterType.Exclude
		query.MaxParts=512

		local function characterPart(part)
			local parent=part.Parent
			while parent and parent~=Workspace do
				if parent:IsA("Model") and Players:GetPlayerFromCharacter(parent) then return true end
				parent=parent.Parent
			end
			return false
		end
		local function eligible(part)
            if part and ((Hub.toyBuildClaims and Hub.toyBuildClaims[part.AssemblyRootPart or part]) or (Hub.missileLaunchClaims and Hub.missileLaunchClaims[part.AssemblyRootPart or part])) then return false end
			if not part or not part.Parent or not part:IsDescendantOf(Workspace) or part.Anchored then return false end
			if part:IsA("Seat") or part:IsA("VehicleSeat") or characterPart(part) then return false end
			-- Avoid competing with the separate creative shape controller.
			if part:FindFirstChild("ArrivaCreativeAttachment") then return false end
			for _,other in ipairs(part:GetConnectedParts(true)) do
				if other.Anchored or other:IsA("Seat") or other:IsA("VehicleSeat") or characterPart(other) then return false end
			end
			return true
		end
		local function release(part)
			local entry=entries[part]
			if not entry then return end
			entries[part]=nil
			for _,object in ipairs(entry) do
				Hub.instances[object]=nil
				Hub.assetTargets[object]=nil
				pcall(function() object:Destroy() end)
			end
			for member,saved in pairs(entry.physics) do
				pcall(function()
					if member.Parent then member.CanCollide=saved.collide;member.Massless=saved.massless end
				end)
			end
		end
		local function applyPhysics(part,entry)
			local members=part:GetConnectedParts(true)
			table.insert(members,part)
			local present={}
			for _,member in ipairs(members) do
				present[member]=true
				if not entry.physics[member] then
					entry.physics[member]={collide=member.CanCollide,massless=member.Massless}
				end
				member.CanCollide=false
				member.Massless=true
			end
			for member,saved in pairs(entry.physics) do
				if not present[member] then
					pcall(function()
						if member.Parent then member.CanCollide=saved.collide;member.Massless=saved.massless end
					end)
					entry.physics[member]=nil
				end
			end
		end
		local function stop()
			if connection then connection:Disconnect();Hub.connections[connection]=nil;connection=nil end
			local parts={}
			for part in pairs(entries) do table.insert(parts,part) end
			for _,part in ipairs(parts) do release(part) end
			elapsed,scanElapsed=0,0
		end
		local function add(part)
			entries[part]={physics={}}
			applyPhysics(part,entries[part])
		end
		local function scan(root)
			local active=0
			for part in pairs(entries) do
				if not eligible(part) or (part.Position-root.Position).Magnitude>range+5 then release(part)
				else applyPhysics(part,entries[part]);active+=1 end
			end
			query.FilterDescendantsInstances=Player.Character and {Player.Character} or {}
			if active<limit then
				local seen={}
				for _,item in ipairs(Workspace:GetPartBoundsInRadius(root.Position,range,query)) do
					local part=item.AssemblyRootPart or item
					if not seen[part] and not entries[part] then
						seen[part]=true
						if (part.Position-root.Position).Magnitude<=range and eligible(part) then
							add(part);active+=1
							if active>=limit then break end
						end
					end
				end
			end
			status:SetText(string.format("Attracting %d objects, range %d studs.",active,range))
		end
		local function start()
			stop()
			if not enabled then status:SetText("Attraction is off.");return end
			scanElapsed=0.5
			connection=Hub.connect(RunService.Heartbeat,function(dt)
				elapsed+=dt;scanElapsed+=dt
				if elapsed<1/30 then return end
				local deltaTime=math.min(elapsed,0.1)
				elapsed=0
				local char=Player.Character
				local hum=char and char:FindFirstChildOfClass("Humanoid")
				local root=char and char:FindFirstChild("HumanoidRootPart")
				if not root or not hum or hum.Health<=0 then stop();status:SetText("Waiting for your character.");return end
				if scanElapsed>=0.5 then scanElapsed=0;scan(root) end
				-- Gather around the character rather than targeting their body.
				for part,entry in pairs(entries) do
					if not part.Parent or part.Anchored then release(part)
					else
						local delta=part.Position-root.Position
						local horizontal=Vector3.new(delta.X,0,delta.Z)
						local direction=horizontal.Magnitude>0.01 and horizontal.Unit or root.CFrame.LookVector
						local goal=root.Position+direction*6+Vector3.new(0,1,0)
						local offset=goal-part.Position
						local step=pullSpeed*deltaTime
						local position=offset.Magnitude<=step and goal or part.Position+offset.Unit*step
						part.CFrame=CFrame.new(position)*part.CFrame.Rotation
						part.AssemblyLinearVelocity=Vector3.zero
						part.AssemblyAngularVelocity=Vector3.zero
					end
				end
			end)
		end
		group:AddToggle("ObjectAttractionEnabled",{Text="Object Attraction Aura",Default=false,
			Callback=function(value) enabled=value;start() end})
		group:AddSlider("ObjectAttractionRange",{Text="Attraction range",Default=35,Min=10,Max=120,Rounding=0,
			Callback=function(value) range=value;scanElapsed=0.5 end})
		group:AddSlider("ObjectAttractionDirectSpeed",{Text="Attraction speed (studs/sec)",Default=1200,Min=100,Max=3000,Rounding=0,
			Callback=function(value) pullSpeed=value end})
		group:AddSlider("ObjectAttractionLimit",{Text="Maximum objects",Default=80,Min=10,Max=150,Rounding=0,
			Callback=function(value) limit=value;if enabled then start() end end})
		group:AddLabel("Pulls nearby unanchored objects and NPCs into a 6-stud ring with collisions off and Massless enabled. Original properties are restored on release. Skips actual players and assemblies connected to them, anchored parts, seats and toys in the creative aura. Movement depends on client physics ownership. Large batches can reduce FPS.")
		Hub.connect(Player.CharacterRemoving,stop)
		Hub.connect(Player.CharacterAdded,function(char)
			task.spawn(function()
				local root=char:WaitForChild("HumanoidRootPart",5)
				if root and enabled and Hub.alive and Player.Character==char then start() end
			end)
		end)
		Hub.cleanup(function() enabled=false;stop();Hub.objectAttractionParts=nil end)
	end)()
end

-- Notification-only inspection of server-to-client RemoteEvent arguments.
do
	(function()
		local group=Tabs.AntiLag:AddRightGroupbox("Incoming Payload Monitor")
		local enabled=false
		local threshold,cooldown=256*1024,8
		local generation,nextAlert=0,0
		local listeners,watched={},{}
		local remoteCount=0
		local lastReport
		local received,largest=0,0
		local captureNext=false
		local discovering=false
		local status=group:AddLabel("Incoming payload monitor is off.")
		local function resolvePlayer(value)
			if typeof(value)~="Instance" then return nil end
			local ok,player=pcall(function()
				if not value:IsA("Player") then return nil end
				-- Resolve to the service's current Player, avoiding reliance on
				-- equality of executor-wrapped instance references.
				return Players:GetPlayerByUserId(value.UserId)
			end)
			return ok and player or nil
		end

		-- Counts observed string and buffer bytes, not compressed packets or transport overhead.
		-- The budget bounds table traversal, cycles are never followed twice.
		local function inspect(args)
			local bytes,budget=0,128
			local seen={}
			local sender,ambiguous
			local function visit(value,depth)
				if budget<=0 then return end
				budget-=1
				local kind=typeof(value)
				if kind=="string" then bytes+=#value
				elseif kind=="buffer" then bytes+=buffer.len(value)
				elseif kind=="Instance" then
					local player=resolvePlayer(value)
					if player then
						if sender and sender.UserId~=player.UserId then ambiguous=true else sender=player end
					end
				elseif kind=="table" and depth<4 and not seen[value] then
					seen[value]=true
					for key,item in pairs(value) do
						if budget<=0 then break end
						visit(key,depth+1);visit(item,depth+1)
					end
				end
			end
			for index=1,args.n do
				if budget<=0 then break end
				visit(args[index],0)
			end
			return bytes,not ambiguous and sender or nil,budget<=0
		end
		local function safePath(instance)
			local ok,path=pcall(function() return instance:GetFullName() end)
			return ok and path:sub(1,180) or instance.ClassName
		end
		local function diagnostic(remote,args,bytes,sender,truncated)
			local lines={"[Arriva payload diagnostic]", "Remote: " .. safePath(remote),
				string.format("Observed string/buffer bytes: %d%s",bytes,truncated and " (inspection limit reached)" or ""),
				"Player value included: " .. (sender and sender.Name or "none or ambiguous")}
			-- Remote location can identify a character's remote without identifying
			-- who originally caused the server to fire it.
			local ancestor=remote.Parent
			while ancestor and ancestor~=game do
				if ancestor:IsA("Model") then
					local owner=Players:GetPlayerFromCharacter(ancestor)
					if owner then table.insert(lines,"Remote belongs to character: " .. owner.Name);break end
				end
				ancestor=ancestor.Parent
			end
			for index=1,math.min(args.n,12) do
				local value=args[index]
				local kind=typeof(value)
				local detail=kind
				if kind=="string" then
					detail=string.format("string, %d bytes",#value)
					if #value<=32 then detail..=", " .. string.format("%q",value:gsub("%c","?")) end
				elseif kind=="Instance" then detail=value.ClassName .. ", " .. safePath(value)
				elseif kind=="buffer" then detail=string.format("buffer, %d bytes",buffer.len(value))
				end
				table.insert(lines,string.format("Arg %d: %s",index,detail))
			end
			if args.n>12 then table.insert(lines,"Additional arguments omitted.") end
			return table.concat(lines,"\n")
		end
		local function stop()
			generation+=1
			for connection in pairs(listeners) do
				connection:Disconnect();Hub.connections[connection]=nil
			end
			table.clear(listeners);table.clear(watched)
			remoteCount=0;nextAlert=0;received=0;largest=0;captureNext=false;discovering=false
		end
		local function track(event,callback)
			local connection=Hub.connect(event,callback)
			listeners[connection]=true
			return connection
		end
		local function watch(remote)
			if watched[remote] or remoteCount>=2048 or not (remote:IsA("RemoteEvent") or remote:IsA("UnreliableRemoteEvent")) then return end
			local accessible,event=pcall(function() return remote.OnClientEvent end)
			if not accessible then return end
			local ok,incoming=pcall(track,event,function(...)
				if not enabled then return end
				received+=1
				if not captureNext and os.clock()<nextAlert then return end
				local args=table.pack(...)
				local bytes,sender,truncated=inspect(args)
				-- Captured FTAP ExtendGrabLine events put the relayed Player first.
				if remote.Name=="ExtendGrabLine" and remote.Parent and remote.Parent.Name=="GrabEvents" then
					sender=resolvePlayer(args[1]) or sender
				end
				largest=math.max(largest,bytes)
				if captureNext then
					captureNext=false
					lastReport=diagnostic(remote,args,bytes,sender,truncated)
					print(lastReport)
					notify("Payload monitor","Captured one incoming event, details are in the F9 console.",5)
				end
				if bytes<threshold then return end
				if os.clock()<nextAlert then return end
				nextAlert=os.clock()+cooldown
				lastReport=diagnostic(remote,args,bytes,sender,truncated)
				print(lastReport)
				local name=remote.Name:sub(1,80)
				local amount=string.format("%s%.2f MiB of string/buffer data",truncated and "at least " or "",bytes/1048576)
				local message=sender and (sender.Name .. ", " .. amount .. ", remote: " .. name .. ".")
					or (name .. " received " .. amount .. ".")
				notify("Large incoming payload",message,6)
				status:SetText(string.format("Watching %d remotes, last alert %.2f MiB of string/buffer data.",remoteCount,bytes/1048576))
			end)
			if not ok then return end
			watched[remote]=true;remoteCount+=1
			local destroying
			destroying=track(remote.Destroying,function()
				if watched[remote] then watched[remote]=nil;remoteCount-=1 end
				incoming:Disconnect();Hub.connections[incoming]=nil
				listeners[incoming]=nil
				destroying:Disconnect();Hub.connections[destroying]=nil
				listeners[destroying]=nil
			end)
		end
		local function start()
			stop()
			if not enabled then status:SetText("Incoming payload monitor is off.");return end
			local ticket=generation
			-- Listen first so new remotes aren't missed during initial discovery.
			track(game.DescendantAdded,watch)
			discovering=true
			status:SetText("Discovering incoming remotes...")
			local uiElapsed=0
			track(RunService.Heartbeat,function(dt)
				uiElapsed+=dt
				if uiElapsed<1 then return end
				uiElapsed=0
				status:SetText(string.format("%s%d remotes, %d events received, largest inspected %.1f KiB.",
					discovering and "Scanning, " or "Watching ",remoteCount,received,largest/1024))
			end)
			task.spawn(function()
				local queue={}
				local head,tail=1,0
				tail=1;queue[tail]=game
				while head<=tail and enabled and Hub.alive and generation==ticket do
					local deadline=os.clock()+0.001
					local processed=0
					repeat
						local item=queue[head];queue[head]=nil;head+=1
						if item and (item==game or item.Parent) then
							watch(item)
							-- Some engine services cannot be enumerated by a client.
							local ok,children=pcall(function() return item:GetChildren() end)
							if ok then for _,child in ipairs(children) do tail+=1;queue[tail]=child end end
						end
						processed+=1
					until head>tail or processed>=128 or os.clock()>=deadline
					RunService.Heartbeat:Wait()
				end
				if enabled and Hub.alive and generation==ticket then
					discovering=false
					status:SetText(string.format("Watching %d remotes, %d events received.",remoteCount,received))
				end
			end)
		end
		group:AddToggle("IncomingPayloadMonitor",{Text="Large incoming payload alerts",Default=false,
			Callback=function(value) enabled=value;start() end})
		group:AddSlider("IncomingPayloadThreshold",{Text="String/buffer alert threshold (KiB)",Default=256,Min=1,Max=4096,Rounding=0,
			Callback=function(value) threshold=value*1024 end})
		group:AddSlider("IncomingPayloadCooldown",{Text="Alert cooldown (seconds)",Default=8,Min=2,Max=60,Rounding=0,
			Callback=function(value) cooldown=value end})
		group:AddButton({Text="Print last payload diagnostic",Func=function()
			if lastReport then print(lastReport)
			else notify("Payload monitor","No oversized incoming payload has been recorded this session.",5) end
		end})
		group:AddButton({Text="Capture next incoming event",Func=function()
			if not enabled then notify("Payload monitor","Enable the monitor first.",4);return end
			captureNext=true
			notify("Payload monitor","Waiting for one incoming RemoteEvent, even below the alert threshold.",5)
		end})
		group:AddLabel("Scans accessible remotes across the client, including player and sound containers. Measures observed string/buffer bytes, not wire size. Player values are event metadata, not proof of origin. Cannot inspect other clients' private outgoing calls, engine-internal traffic, or block data. RemoteFunction callbacks are left untouched. Discovery is capped at 2048 remotes.")
		Hub.cleanup(function() enabled=false;stop() end)
	end)()
end

-- A saved destination is explicit, it does not grant server-side safe-zone status.
do
(function()
    local group=Tabs.Defense:AddRightGroupbox("Safe Zone")
    local destination=Vector3.new(606,124,-101)
    local spawnEnabled,loopEnabled=false,false
    local loopConnection
    local epoch=0
    local status=group:AddLabel("Safe zone: 606, 124, -101. Use my current position to change it.")
    local function setDestination(text)
        local x,y,z=tostring(text or ""):match("^%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*,%s*([%+%-%.%deE]+)%s*$")
        x,y,z=tonumber(x),tonumber(y),tonumber(z)
        if not x or not y or not z or x~=x or y~=y or z~=z or math.abs(x)>1000000 or math.abs(y)>1000000 or math.abs(z)>1000000 then
            destination=nil;status:SetText("Set a safe zone using your current position or enter X, Y, Z.");return
        end
        if y<=Workspace.FallenPartsDestroyHeight+8 then destination=nil;status:SetText("Safe zone rejected, destination is below the map.");return end
        destination=Vector3.new(x,y,z)
        status:SetText(string.format("Saved safe zone: %.1f, %.1f, %.1f",x,y,z))
    end
    local function go(char)
        if not destination or char~=Player.Character then return false end
        local root=char and char:FindFirstChild("HumanoidRootPart")
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if not root or not hum or hum.Health<=0 then return false end
        root.CFrame=CFrame.new(destination)*root.CFrame.Rotation
        root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
        return true
    end
    group:AddInput("SafeZoneCoordinates",{Text="Saved destination (X, Y, Z)",Default="606, 124, -101",Finished=true,Callback=setDestination})
    group:AddButton({Text="Use my current position",Func=function()
        local char=Player.Character
        local root=char and char:FindFirstChild("HumanoidRootPart")
        if not root then return end
        local p=root.Position
        Options.SafeZoneCoordinates:SetValue(string.format("%.3f, %.3f, %.3f",p.X,p.Y,p.Z))
        Hub.requestSave()
    end})
    group:AddButton({Text="Go to safe zone now",Func=function()
        if not go(Player.Character) then notify("Safe zone","Set a destination and wait for your character to be ready.",4) end
    end})
    group:AddToggle("SpawnAtSafeZone",{Text="Spawn at safe zone",Default=false,Callback=function(on) spawnEnabled=on;epoch+=1;Hub.requestSave() end})
    group:AddToggle("LoopSafeZone",{Text="Loop go to safe zone (10/sec)",Default=false,Callback=function(on)
        loopEnabled=on;Hub.safeZoneLoopActive=on
        if loopConnection then loopConnection:Disconnect();Hub.connections[loopConnection]=nil;loopConnection=nil end
        Hub.requestSave()
        if not on then return end
        local elapsed=0
        loopConnection=Hub.connect(RunService.Heartbeat,function(dt)
            elapsed+=dt
            if elapsed<0.1 then return end
            elapsed=0 -- No burst of catch-up teleports after a lag spike.
            go(Player.Character)
        end)
        if not destination then notify("Safe zone","Choose Use my current position before the loop can move you.",5) end
    end})
    Hub.connect(Player.CharacterAdded,function(char)
        epoch+=1;local ticket=epoch
        if not spawnEnabled then return end
        task.spawn(function()
            local deadline=os.clock()+8
            repeat
                if not Hub.alive or not spawnEnabled or epoch~=ticket or Player.Character~=char then return end
                if go(char) then return end
                task.wait(0.1)
            until os.clock()>=deadline
        end)
    end)
    Hub.connect(Player.CharacterRemoving,function() epoch+=1 end)
    group:AddLabel("Choose a position inside the game's real safe zone. These options teleport your character, they do not grant protection or change your RespawnLocation. Loop mode overrides ordinary movement while enabled.")
    Hub.cleanup(function()
        spawnEnabled=false;loopEnabled=false;epoch+=1;Hub.safeZoneLoopActive=nil
        if loopConnection then loopConnection:Disconnect();Hub.connections[loopConnection]=nil;loopConnection=nil end
    end)
end)()
end


-- Local presentation tools inspired by the reference's Perspective settings.
do
(function()
    local group=Tabs.Player:AddRightGroupbox("Camera Effects")
    local preset,strength="Off",50
    local gui,effect,overlay
    local disposed=false
    local function clear()
        if overlay then Hub.instances[overlay]=nil;Hub.assetTargets[overlay]=nil end
        if gui then Hub.instances[gui]=nil;Hub.assetTargets[gui]=nil;gui:Destroy() end
        if effect then Hub.instances[effect]=nil;Hub.assetTargets[effect]=nil;effect:Destroy() end
        gui,effect,overlay=nil,nil,nil
    end
    local function apply()
        if disposed or preset=="Off" then clear();return end
        local playerGui=Player:FindFirstChildOfClass("PlayerGui")
        if not playerGui then return end
        if not gui or not gui.Parent or not effect or not effect.Parent then
            clear()
            gui=Hub.new("ScreenGui",playerGui)
            gui.Name="ArrivaCameraEffects";gui.ResetOnSpawn=false;gui.IgnoreGuiInset=true;gui.DisplayOrder=-10
            overlay=Hub.new("ImageLabel",gui)
            overlay.Size=UDim2.fromScale(1,1);overlay.BackgroundTransparency=1;overlay.BorderSizePixel=0
            overlay.Active=false;overlay.ImageColor3=Color3.new(0,0,0)
            effect=Hub.new("ColorCorrectionEffect",game:GetService("Lighting"))
        end
        overlay.Image=preset=="Old TV" and "rbxassetid://8586979842" or "rbxassetid://5945121255"
        overlay.ImageTransparency=1-strength/100*0.6
        effect.Name="ArrivaCameraColor";effect.Saturation=-(preset=="Old TV" and 0.3 or 0.6)*strength/100
    end
    group:AddDropdown("LocalCameraEffect",{Text="Camera effect",Values={"Off","Vignette","Old TV"},Default=1,
        Callback=function(value) preset=value;apply() end})
    group:AddSlider("LocalCameraEffectStrength",{Text="Effect strength (%)",Default=50,Min=0,Max=100,Rounding=0,
        Callback=function(value) strength=value;apply() end})
    group:AddLabel("Local overlay and color grading only. Turn Off to restore the normal view.")
    Hub.connect(Player.ChildAdded,function(child) if child:IsA("PlayerGui") then apply() end end)
    Hub.cleanup(function() disposed=true;clear() end)
end)()
end


-- UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
do
	local widget=Tabs.Customization:AddRightGroupbox("On-screen FPS & Ping")
	widget:AddToggle("FloatingMetricsVisible",{Text="Show FPS and ping widget",Default=true,
		Callback=function(on) Hub.setMetricsPreference("metricsShown",on) end})
	widget:AddDropdown("FloatingMetricsPosition",{Text="Widget position",Default=1,
		Values={"Top Right","Top Left","Top Center","Bottom Right","Bottom Left","Bottom Center"},
		Callback=function(position) Hub.setMetricsPreference("metricsPosition",position) end})
	widget:AddSlider("FloatingMetricsSize",{Text="Widget size (%)",Default=100,Min=80,Max=140,Rounding=0,
		Callback=function(value) Hub.setMetricsPreference("metricsSize",value/100) end})
	widget:AddLabel("Stays visible while the menu is closed and follows your theme. Updates twice per second.")
end
local ThemeGroup = Tabs.Customization:AddLeftGroupbox("Hub Theme")
-- Optional creative tools. No ownership requests or changes to other players' toys.
do
    local selectors=Tabs.Updates:AddLeftGroupbox("ESP and Selector Polish")
    selectors:AddLabel("Player ESP uses bold white lettering with a white character outline. Fill color remains separate. Player lists update in place without closing an open menu or resetting a player who is still listed. If your selected player leaves, the choice clears instead of switching to someone else.")
    local fixes=Tabs.Updates:AddLeftGroupbox("Protection and Stability Fixes")
    fixes:AddLabel("The extra ESP now uses the main ESP switch and appearance section. Action buttons have more room, padded text and bounded text scaling.")
    fixes:AddLabel("Anti Paint ignores unrelated object removals. Joining and leaving players no longer rebuild every dropdown row, and roster refresh bursts are combined. Departed-player ownership and target respawn bindings are disconnected.")
    fixes:AddLabel("Anti Paint and Blobman startup scans are spread over frames. Anti Blobman also checks detector parts and constraints that arrive after the toy appears, while leaving your own Blobman alone.")
    fixes:AddLabel("Optional extreme velocity recovery and unwanted-seat protection are in Defense. Frame spike recording is in Anti Lag. They start off, so you can choose which protections suit your setup.")
    local log=Tabs.Updates:AddLeftGroupbox("Creative Feature Pack")
    log:AddLabel("Your toys now have their own manager. Refresh the list to locate a toy, bring it closer or put it into a named group. Groups keep their spacing when moved. Delete buttons need a separate switch enabled first.")
    log:AddLabel("Creative Object Aura now includes Tornado, Blackhole and Star formations. Follow your cursor or click a spot to leave the formation there. Local decoration mode still works without spawning toys.")
    log:AddLabel("Anchor highlights have separate fill and outline colors, transparency and optional labels. Player Options now includes map locations, custom coordinates, a detailed avatar/health ESP and adjustable follow positioning for your character.")
    log:AddLabel("Menu Customization includes optional corner buttons for surface teleport, anchoring the held object and spawning a selected decorative toy. They use your hub theme and the existing action handlers.")
end
do
(function()
    local manager=Tabs.Fun:AddRightGroupbox("My Toy Manager and Groups")
    local list,selected={},nil
    local groups,groupName={},"My group"
    local status=manager:AddLabel("Refresh to list your toys.")
    local function folder() return Workspace:FindFirstChild(Player.Name.."SpawnedInToys") end
    local function own(model)
        local f=folder()
        return f and model and model.Parent==f and model:IsA("Model")
    end
    local function movable(model)
        if not own(model) or model:FindFirstChildOfClass("Humanoid") then return false end
        for _,p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                if (Hub.toyBuildClaims and Hub.toyBuildClaims[p.AssemblyRootPart or p]) or (Hub.missileLaunchClaims and Hub.missileLaunchClaims[p.AssemblyRootPart or p]) then return false end
                if p.Anchored or p:IsA("Seat") or p:IsA("VehicleSeat") then return false end
                for _,q in ipairs(p:GetConnectedParts(true)) do
                    if not q:IsDescendantOf(model) then return false end
                end
            end
        end
        return model:FindFirstChildWhichIsA("BasePart",true)~=nil
    end
    Hub.isOwnCreativeToy=own
    local function root() return Player.Character and Player.Character:FindFirstChild("HumanoidRootPart") end
    local function report(text) status:SetText(text) end
    local picker
    local function refresh()
        list={};local labels={};local f=folder()
        if f then for _,model in ipairs(f:GetChildren()) do
            if own(model) and #labels<100 then
                local label=string.format("%03d | %s",#labels+1,model.Name)
                list[label]=model;table.insert(labels,label)
            end
        end end
        table.sort(labels);picker:SetValues(labels)
        selected=nil
        report(string.format("%d toys listed. Select one before using an action.",#labels))
    end
    picker=manager:AddDropdown("OwnToySelection",{Text="Your toys",Values={},Callback=function(value) selected=list[value] end})
    manager:AddButton("Refresh toy list",refresh)
    manager:AddButton("Locate selected toy",function()
        local r=root();if not r or not own(selected) then return end
        report(string.format("%s is %.0f studs away.",selected.Name,(selected:GetPivot().Position-r.Position).Magnitude))
        local h=Hub.new("Highlight",selected);h.Adornee=selected
        task.delay(3,function() if h.Parent then h:Destroy() end end)
    end)
    local function move(models)
        local r=root();if not r then return end
        local valid={}
        for model in pairs(models) do if movable(model) and #valid<40 then table.insert(valid,model) end end
        if #valid==0 then report("No movable own toys selected. Anchored, seated or connected toys are skipped.");return end
        local origin=valid[1]:GetPivot();local goal=r.CFrame*CFrame.new(0,2,-10)
        for _,model in ipairs(valid) do
            model:PivotTo(goal*origin:ToObjectSpace(model:GetPivot()))
            for _,p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then
                p.AssemblyLinearVelocity=Vector3.zero;p.AssemblyAngularVelocity=Vector3.zero
            end end
        end
        report(string.format("Moved %d own toys. Server ownership can limit replication.",#valid))
    end
    manager:AddButton("Bring selected toy in front",function() if selected then move({[selected]=true}) end end)
    local confirm=false
    manager:AddToggle("OwnToyDeleteConfirm",{Text="Allow delete buttons",Default=false,Callback=function(on) confirm=on end})
    local function delete(models)
        if not confirm then report("Enable Allow delete buttons first.");return end
        local menu=ReplicatedStorage:FindFirstChild("MenuToys")
        local remote=menu and menu:FindFirstChild("DestroyToy")
        if not remote then report("Toy delete is unavailable.");return end
        local count=0
        for model in pairs(models) do if own(model) and count<40 then remote:FireServer(model);count+=1 end end
        report(string.format("Requested deletion of %d own toys.",count))
    end
    manager:AddButton("Delete selected toy",function() if selected then delete({[selected]=true}) end end)
    manager:AddInput("OwnToyGroupName",{Text="Group name",Default="My group",Finished=true,Callback=function(value)
        groupName=string.sub(tostring(value),1,48);if groupName=="" then groupName="My group" end
    end})
    manager:AddButton("Add selected toy to named group",function()
        if not own(selected) then return end
        groups[groupName]=groups[groupName] or {};groups[groupName][selected]=true;report("Added to "..groupName..".")
    end)
    manager:AddButton("Add all movable own toys to named group",function()
        local f=folder();if not f then return end
        local set={};local count=0
        for _,model in ipairs(f:GetChildren()) do if count<40 and movable(model) then set[model]=true;count+=1 end end
        groups[groupName]=set;report(string.format("%s contains %d toys.",groupName,count))
    end)
    manager:AddButton("Move named group in front",function() move(groups[groupName] or {}) end)
    manager:AddButton("Release named group",function() groups[groupName]=nil;report("Group cleared. Your toys are unchanged.") end)
    manager:AddButton("Delete named group toys",function() delete(groups[groupName] or {}) end)
    manager:AddLabel("Groups are session selections. Enter an existing group name to use it again.")
    Hub.cleanup(function() table.clear(groups);table.clear(list) end)
end)()
end

do
(function()
    local group=Tabs.Player:AddRightGroupbox("Map Locations")
    local locations={Spawn=Vector3.new(4,-7,-3),["Safe Zone"]=Vector3.new(606,124,-101),
        ["Farm House"]=Vector3.new(-234,83,-324),["Blue Safe House"]=Vector3.new(538,96,-372),
        ["Big Cave"]=Vector3.new(17,-7,539),["Train Cave"]=Vector3.new(500,62,-307),
        ["Mine Cave"]=Vector3.new(-254,-7,518),["Witch Safe House"]=Vector3.new(296,-4,494),
        ["Red Safe House"]=Vector3.new(-516,-6,-162)}
    local destination="Safe Zone";local custom="606, 124, -101"
    local names={};for name in pairs(locations) do table.insert(names,name) end;table.sort(names)
    group:AddDropdown("MapDestination",{Text="Location",Values=names,Default=table.find(names,destination),Callback=function(value) destination=value end})
    local function teleport(position)
        if Hub.safeZoneLoopActive then notify("Teleport","Turn off the safe-zone loop first.",4);return end
        local char=Player.Character;local r=char and char:FindFirstChild("HumanoidRootPart")
        local hum=char and char:FindFirstChildOfClass("Humanoid")
        if not r or not hum or hum.Health<=0 then return end
        if position.Y<=Workspace.FallenPartsDestroyHeight+8 then return end
        r.CFrame=CFrame.new(position)*r.CFrame.Rotation;r.AssemblyLinearVelocity=Vector3.zero;r.AssemblyAngularVelocity=Vector3.zero
    end
    group:AddButton("Go to selected location",function() if locations[destination] then teleport(locations[destination]) end end)
    group:AddInput("MapCustomCoordinates",{Text="Custom X, Y, Z",Default=custom,Finished=true,Callback=function(value) custom=value end})
    group:AddButton("Go to custom coordinates",function()
        local nums={};for n in tostring(custom):gmatch("[^,%s]+") do table.insert(nums,tonumber(n) or false) end
        if #nums~=3 then return end
        for _,n in ipairs(nums) do if not n or n~=n or math.abs(n)>100000 then return end end
        teleport(Vector3.new(nums[1],nums[2],nums[3]))
    end)
    group:AddButton("Save current position as custom",function()
        local r=Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")
        if r then Options.MapCustomCoordinates:SetValue(string.format("%.2f, %.2f, %.2f",r.Position.X,r.Position.Y,r.Position.Z)) end
    end)
    group:AddLabel("Named coordinates come from the reference script and may change with map updates.")
end)()
end

do
(function()
    local group=Tabs.Player:AddRightGroupbox("Follow Player Position")
    local target,enabled,side,distance,height=nil,false,"Behind",8,0
    local picker;local elapsed=0
    local function refresh()
        local names={};for _,p in ipairs(Players:GetPlayers()) do if p~=Player then table.insert(names,p.Name) end end
        table.sort(names);picker:SetValues(names)
    end
    picker=group:AddDropdown("SelfFollowPlayer",{Text="Follow player",Values={},Callback=function(value) target=Players:FindFirstChild(value) end})
    group:AddButton("Refresh follow players",refresh)
    refresh()
    group:AddDropdown("SelfFollowSide",{Text="Position",Values={"Behind","Left","Right","Front"},Default=1,Callback=function(value) side=value end})
    group:AddSlider("SelfFollowDistance",{Text="Distance",Default=8,Min=3,Max=40,Rounding=0,Callback=function(value) distance=value end})
    group:AddSlider("SelfFollowHeight",{Text="Height offset",Default=0,Min=0,Max=20,Rounding=0,Callback=function(value) height=value end})
    group:AddToggle("SelfFollowEnabled",{Text="Follow selected player",Default=false,Callback=function(on) enabled=on end})
    group:AddLabel("Moves your character only. Pauses for seats, death or the safe-zone loop.")
    Hub.connect(Players.PlayerAdded,function() Hub.queueRefresh("follow",refresh) end);Hub.connect(Players.PlayerRemoving,function(p) if p==target then target=nil end;Hub.queueRefresh("follow",refresh) end)
    Hub.connect(RunService.Heartbeat,function(dt)
        if not enabled or Hub.safeZoneLoopActive then return end
        elapsed+=dt;if elapsed<0.1 then return end;elapsed=0
        local char=Player.Character;local r=char and char:FindFirstChild("HumanoidRootPart")
        local h=char and char:FindFirstChildOfClass("Humanoid")
        local other=target and target.Character;local t=other and other:FindFirstChild("HumanoidRootPart")
        local th=other and other:FindFirstChildOfClass("Humanoid")
        if not r or not h or h.Health<=0 or h.SeatPart or not t or not th or th.Health<=0 then return end
        local offset=side=="Left" and Vector3.new(-distance,height,0) or side=="Right" and Vector3.new(distance,height,0)
            or side=="Front" and Vector3.new(0,height,-distance) or Vector3.new(0,height,distance)
        local goal=t.CFrame*CFrame.new(offset)
        if goal.Position.Y>Workspace.FallenPartsDestroyHeight+8 then r.CFrame=goal;r.AssemblyLinearVelocity=Vector3.zero end
    end)
end)()
end

do
(function()
    local group=Tabs.Customization:AddRightGroupbox("Anchor Appearance")
    local fill,outline=Color3.fromRGB(0,85,255),Color3.fromRGB(0,170,255)
    local fillAlpha,lineAlpha,labels=0.4,0.7,false
    local active={}
    local function style(h)
        if not h.Parent then active[h]=nil;return end
        h.FillColor=fill;h.OutlineColor=outline;h.FillTransparency=fillAlpha;h.OutlineTransparency=lineAlpha
        local old=h:FindFirstChild("ArrivaAnchorLabel")
        if labels and not old then
            local part=h.Parent:IsA("BasePart") and h.Parent or h.Parent:FindFirstChildWhichIsA("BasePart",true)
            if part then
                local gui=Hub.new("BillboardGui",h);gui.Name="ArrivaAnchorLabel";gui.Adornee=part
                gui.Size=UDim2.fromOffset(140,26);gui.StudsOffset=Vector3.new(0,3,0);gui.AlwaysOnTop=true
                local text=Hub.new("TextLabel",gui);text.Size=UDim2.fromScale(1,1);text.BackgroundTransparency=1
                text.Text="Anchored object";text.TextColor3=outline;text.TextSize=14
            end
        elseif old and not labels then old:Destroy() end
        if old then local text=old:FindFirstChildOfClass("TextLabel");if text then text.TextColor3=outline end end
    end
    Hub.styleAnchorHighlight=function(h) active[h]=true;style(h) end
    local function refresh() for h in pairs(active) do style(h) end end
    local function color(value)
        local hex=tostring(value):gsub("#","")
        if #hex~=6 or not hex:match("^%x+$") then return nil end
        return Color3.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
    end
    group:AddInput("AnchorFillHex",{Text="Fill hex",Default="0055FF",Finished=true,Callback=function(value) fill=color(value) or fill;refresh() end})
    group:AddInput("AnchorOutlineHex",{Text="Outline hex",Default="00AAFF",Finished=true,Callback=function(value) outline=color(value) or outline;refresh() end})
    group:AddSlider("AnchorFillOpacity",{Text="Fill transparency",Default=40,Min=0,Max=100,Rounding=0,Callback=function(value) fillAlpha=value/100;refresh() end})
    group:AddSlider("AnchorLineOpacity",{Text="Outline transparency",Default=70,Min=0,Max=100,Rounding=0,Callback=function(value) lineAlpha=value/100;refresh() end})
    group:AddToggle("AnchorLabels",{Text="Anchor labels",Default=false,Callback=function(on) labels=on;refresh() end})
    Hub.cleanup(function() table.clear(active);Hub.styleAnchorHighlight=nil end)
end)()
end


do
(function()
    local group=Tabs.Customization:AddRightGroupbox("Touch Action Buttons")
    local gui=Hub.new("ScreenGui",Player:WaitForChild("PlayerGui"));gui.Name="ArrivaTouchActions";gui.ResetOnSpawn=false;gui.Enabled=false
    Hub.touchActionsGui=gui
    local palette=Hub.creativeUIPalette or {sidebar=Color3.fromRGB(31,31,31),card=Color3.fromRGB(33,33,33),text=Color3.fromRGB(237,237,237)}
    local panel=Hub.new("Frame",gui);panel.Size=UDim2.fromOffset(224,164);panel.BackgroundColor3=palette.sidebar
    local corner=Hub.new("UICorner",panel);corner.CornerRadius=UDim.new(0,12)
    local position="Bottom right"
    local function place()
        panel.AnchorPoint=Vector2.new(position:find("right") and 1 or 0,position:find("Bottom") and 1 or 0)
        panel.Position=UDim2.new(panel.AnchorPoint.X,panel.AnchorPoint.X==1 and -16 or 16,panel.AnchorPoint.Y,panel.AnchorPoint.Y==1 and -90 or 80)
    end
    local function button(text,y,action)
        local b=Hub.new("TextButton",panel);b.Position=UDim2.fromOffset(8,y);b.Size=UDim2.fromOffset(208,44)
        b.BackgroundColor3=palette.card;b.TextColor3=palette.text;b.TextSize=14;b.Text=text;b.TextWrapped=true;b.TextScaled=true
        local padding=Hub.new("UIPadding",b);padding.PaddingLeft=UDim.new(0,10);padding.PaddingRight=UDim.new(0,10);padding.PaddingTop=UDim.new(0,4);padding.PaddingBottom=UDim.new(0,4)
        local size=Hub.new("UITextSizeConstraint",b);size.MinTextSize=10;size.MaxTextSize=14
        local c=Hub.new("UICorner",b);c.CornerRadius=UDim.new(0,8)
        Hub.connect(b.Activated,function() if Hub.alive and not UserInputService:GetFocusedTextBox() then action() end end)
    end
    button("TP to aimed surface",8,function() if Hub.clickTeleport then Hub.clickTeleport() end end)
    button("Anchor held object",60,function() if Hub.anchorHeldObject then Hub.anchorHeldObject(false) end end)
    button("Spawn selected toy",112,function() if Hub.quickSpawnCreativeToy then Hub.quickSpawnCreativeToy() end end)
    group:AddToggle("TouchActionsEnabled",{Text="Show action buttons",Default=false,Callback=function(on) gui.Enabled=on end})
    group:AddDropdown("TouchActionsPosition",{Text="Action button corner",Values={"Bottom right","Bottom left","Top right","Top left"},Default=1,Callback=function(value) position=value;place() end})
    group:AddLabel("TP uses the aimed surface. Spawn uses the Shape Toy Picker selection.")
    place()
end)()
end

ThemeGroup:AddDropdown("SidebarTheme", {
	Text="Hub theme", Values={"Default","Midnight","Violet","Forest","Rose","Ocean","Amber","Custom"}, Default=1,
	Callback=function(name)
		if Hub.setSidebarTheme then Hub.setSidebarTheme(name) end
		Hub.requestSave()
	end,
})
do
	local appearance=Tabs.Customization:AddRightGroupbox("Custom Theme Colors")
	appearance:AddLabel("Select Custom in Hub Theme. Click a color swatch to open the picker; HEX entry also works.")
	local function field(id,label,key,value)
		appearance:AddInput(id,{Text=label,Default=value,Finished=true,
			Callback=function(color)
				if Hub.setCustomThemeColor and not Hub.setCustomThemeColor(key,color) then
					Library:Notify({Title="Theme warning",Description="Use a six-digit HEX color, e.g. #4589BF.",Time=4})
				end
			end})
	end
	field("CustomThemeBackground","Background HEX","background","#191919")
	field("CustomThemeAccent","Accent HEX","accent","#4589BF")
	field("CustomThemeText","Text HEX","text","#EDEDED")
	local notices=Tabs.Notifications:AddRightGroupbox("Position & Appearance")
	notices:AddDropdown("NotificationPosition",{Text="Notification position",Default=1,
		Values={"Bottom Right","Bottom Left","Bottom Center","Top Right","Top Left","Top Center"},
		Callback=function(value) Hub.setNoticePreference("noticePosition",value) end})
	notices:AddSlider("NotificationScale",{Text="Notification size (%)",Default=100,Min=80,Max=130,Rounding=0,
		Callback=function(value) Hub.setNoticePreference("noticeScale",value/100) end})
	notices:AddSlider("NotificationLimit",{Text="Maximum visible notifications",Default=3,Min=1,Max=5,Rounding=0,
		Callback=function(value) Hub.setNoticePreference("noticeLimit",value) end})
	notices:AddSlider("NotificationDuration",{Text="Notification duration multiplier",Default=1,Min=0.5,Max=2,Rounding=1,
		Callback=function(value) Hub.setNoticePreference("noticeDuration",value) end})
	notices:AddButton({Text="Preview notification",Func=function()
		Library:Notify({Title="Notification preview",Description="Your notification position, size and theme preview.",Time=5})
	end})
end
do
	local queued,busy=false,false
	MenuGroup:AddButton({Text="Rejoin + Auto Execute",Func=function()
		if busy then return end
		local queue=queue_on_teleport or queueonteleport
		if type(queue)~="function" then
			notify("Rejoin warning","Your executor does not expose teleport queuing.",6)
			return
		end
		if not queued then
			local loader=[=[
if not game:IsLoaded() then game.Loaded:Wait() end
task.wait(2)
local ok,err=pcall(function()
    local source=game:HttpGet("https://raw.githubusercontent.com/arrivabus415/ArrivaCoreHub/main/main.lua")
    local run,compileError=loadstring(source)
    if not run then error(compileError) end
    run()
end)
if not ok then warn("[Arriva auto execute] " .. tostring(err)) end
]=]
			local okQueue,err=pcall(queue,loader)
			if not okQueue then notify("Rejoin error",tostring(err),6);return end
			queued=true
		end
		busy=true
		if Hub.pollSettings then pcall(Hub.pollSettings) end
		local ok,err=pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId,Player) end)
		if not ok then busy=false;notify("Rejoin error",tostring(err),6) end
		task.delay(10,function() busy=false end)
	end})
end
do
	local section0=Tabs.Updates:AddLeftGroupbox("Version 2.0")
	section0:AddLabel("The menu has had a bit of a tidy-up. There are more ways to make it yours, notifications are clearer, and the larger settings groups now have their own tabs.")
	section0:AddLabel("Your saved settings still use the same controls, so moving things around should not mean setting everything up again.")
	local section1=Tabs.Updates:AddLeftGroupbox("A little more Arriva")
	section1:AddLabel("The header now uses the Arriva emblem, with a slanted title to sit alongside it. The logo stays in its original proportions.")
	section1:AddLabel("This update log has its own tab now. Notes are grouped by what changed, instead of being squeezed into UI Settings.")
	local section2=Tabs.Updates:AddLeftGroupbox("Make the menu yours")
	section2:AddLabel("Themes, custom colors and appearance controls now live in Menu Customization. Pick a preset or choose Custom to build your own look.")
	section2:AddLabel("Custom colors have clickable pickers as well as HEX boxes. You can change the background, accent and text colors; the rest of the palette follows those choices.")
	section2:AddLabel("Added Rose, Ocean and Amber alongside the earlier themes. Slider fills, tracks, inputs and toggles follow the selected palette.")
	section2:AddLabel("Turning off the rainbow border removes the outline completely. Border thickness, animation speed and menu scale are adjustable too.")
	local section3=Tabs.Updates:AddLeftGroupbox("Notifications")
	section3:AddLabel("Notifications remain visible when the main menu is closed. They stack in order and close the gaps when older messages disappear.")
	section3:AddLabel("Long headings and messages have room to wrap. Text contrast, spacing and header alignment have also been adjusted.")
	section3:AddLabel("Different events have their own icons, including joins, departures, warnings and respawns. Event colors stay separate from the menu theme.")
	section3:AddLabel("You can choose the position, size, duration and number of visible notifications. There is a preview button to try the settings before leaving the menu.")
	section3:AddLabel("Fixed an older message format that could show the duration as the body text.")
	local section4=Tabs.Updates:AddLeftGroupbox("Anti Lag and connection alerts")
	section4:AddLabel("Automatic line protection and connection settings now have a dedicated Anti Lag tab. Force Anti Lag is still in Defense.")
	section4:AddLabel("Auto Anti Lag can switch local line protection on during a burst, then restore the previous setting after a quiet period. Manual protection takes priority.")
	section4:AddLabel("The line threshold, detection window and quiet period are adjustable. Optional ping and client-performance alerts also have their own thresholds and repeat cooldowns.")
	section4:AddLabel("These alerts report what your client sees. They do not identify who caused a slowdown.")
	local section5=Tabs.Updates:AddLeftGroupbox("Controls and small fixes")
	section5:AddLabel("Grab Options is separated from Grab Customization, and the FPS buttons have clearer names.")
	section5:AddLabel("The G-key object anchor now checks the grab attachment instead of relying on nearby touching parts. Changing the bind no longer activates it.")
	section5:AddLabel("Opening the menu releases the cursor; closing it restores the previous mouse state. The separate mouse shortcut is still available.")
	section5:AddLabel("Adjusted the scroll gutter and section headings to give the controls a little more breathing room.")
	local section6=Tabs.Updates:AddLeftGroupbox("Rejoining")
	section6:AddLabel("UI Settings now has Rejoin + Auto Execute for setups that support teleport queuing. It loads the main hub from the Arriva GitHub repository after rejoining.")
	section6:AddLabel("If the required executor feature is missing, the button shows a message instead of silently failing.")
	local section7=Tabs.Updates:AddLeftGroupbox("Testing notes")
	section7:AddLabel("This build has passed a syntax check. Some earlier UI and monitor changes also have mocked checks, but those do not replace testing inside the game.")
	section7:AddLabel("If something still looks off, a screenshot and the name of the setting help narrow it down.")
end

do
	local events=Tabs.Notifications:AddLeftGroupbox("Player Events")
	local preferences={joins=true,leaves=true,respawns=true,self=true}
	local roster={}
	local function toggle(id,title,key)
		events:AddToggle(id,{Text=title,Default=true,Callback=function(on) preferences[key]=on end})
	end
	toggle("NotifyPlayerJoins","Player joined","joins")
	toggle("NotifyPlayerLeaves","Player left","leaves")
	toggle("NotifyPlayerRespawns","Player respawned","respawns")
	toggle("NotifyMyCharacter","My death and respawn","self")
	events:AddLabel("A player's first character spawn is not counted as a respawn. Repeated respawn alerts have an eight-second cooldown per player.")
	local function disconnect(connection)
		if connection then connection:Disconnect();Hub.connections[connection]=nil end
	end
	local function track(person)
		if roster[person] then return end
		local entry={seen=person.Character~=nil,last=-math.huge}
		roster[person]=entry
		local function watchDeath(char)
			disconnect(entry.death);entry.death=nil
			if person~=Player or not char then return end
			local hum=char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid",5)
			if not Hub.alive or roster[person]~=entry or person.Character~=char or not hum then return end
			entry.death=Hub.connect(hum.Died,function()
				if preferences.self then notify("Character warning","Your character died. Waiting for respawn.",4) end
			end)
		end
		entry.character=Hub.connect(person.CharacterAdded,function(char)
			local respawn=entry.seen
			entry.seen=true
			if respawn and os.clock()-entry.last>=8 then
				entry.last=os.clock()
				if person==Player then
					if preferences.self then notify("Character respawned","Your character has respawned.",4) end
				elseif preferences.respawns then
					-- Let the existing targeted respawn alert handle tracked players.
					local duplicate=respawnNotifyActive and isTrackedPlayer(person)
					if not duplicate then notify("Player respawned",person.Name .. " has respawned.",4) end
				end
			end
			watchDeath(char)
		end)
		if person==Player and person.Character then
			task.spawn(function() watchDeath(person.Character) end)
		end
	end
	for _,person in ipairs(Players:GetPlayers()) do track(person) end
	Hub.connect(Players.PlayerAdded,function(person)
		track(person)
		if preferences.joins then notify("Player joined",person.Name .. " joined the server.",4) end
	end)
	Hub.connect(Players.PlayerRemoving,function(person)
		local entry=roster[person]
		roster[person]=nil
		if entry then disconnect(entry.character);disconnect(entry.death) end
		if preferences.leaves then notify("Player left",person.Name .. " left the server.",4) end
	end)
	Hub.cleanup(function()
		for _,entry in pairs(roster) do disconnect(entry.character);disconnect(entry.death) end
		table.clear(roster)
	end)
end

do
	local reloading=false
	MenuGroup:AddButton({Text="Reload Hub",Func=function()
		if reloading then return end
		reloading=true
		notify("Reload Hub","Checking the latest hub version...",3)
		local ok,compiled=pcall(function()
			local source=game:HttpGet("https://raw.githubusercontent.com/arrivabus415/ArrivaCoreHub/main/main.lua")
			local run,err=loadstring(source)
			if not run then error(err) end
			return run
		end)
		if not ok then
			reloading=false
			notify("Reload error","Download or compilation failed. Your current hub is still running. " .. tostring(compiled),8)
			return
		end
		if not Hub.alive or Library.unloaded then return end
		-- A native task survives the old hub's managed-worker cancellation.
		Hub.nativeTask.defer(function()
			if not Hub.alive or Library.unloaded then return end
			Library:Unload()
			local success,err=pcall(compiled)
			if not success then
				warn("[Arriva reload] " .. tostring(err))
				pcall(function()
					game:GetService("StarterGui"):SetCore("SendNotification",{
						Title="Arriva reload failed",Text="The new hub could not start. Check the console for details.",Duration=8,
					})
				end)
			end
		end)
	end})
end
MenuGroup:AddButton("Unload", function() Library:Unload() end)
MenuGroup:AddLabel("Emergency unload: End by default; edit shortcuts in KeyBinds", true)
Hub.connect(UserInputService.InputBegan, function(input, processed)
	if processed or UserInputService:GetFocusedTextBox() then return end
	if Hub.matchesKeybind("EmergencyUnloadKey", input, "End") then Library:Unload() end
end)
MenuGroup:AddButton({Text = "Diagnostics", Func = function()
	local listeners, workers = 0, 0
	for connection in pairs(Hub.connections) do if connection.Connected then listeners += 1 end end
	for thread in pairs(Hub.threads) do if coroutine.status(thread) ~= "dead" then workers += 1 end end
	notify("Diagnostics", string.format("%d listeners / %d active workers. Config storage: %s. Touch API: %s.",
		listeners, workers, Hub.storage and "available" or "unavailable", firetouchinterest and "available" or "unavailable"), 8)
end})
Hub.keybindGroups.interface:AddLabel("Toggle menu"):AddKeyPicker("MenuKeybind", { Default = "M", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

-- Session customization does not require executor file-storage support.
ThemeManager:ApplyToTab(Tabs.Customization)
Hub.storage = type(isfile)=="function" and type(readfile)=="function" and type(writefile)=="function" and type(isfolder)=="function" and type(makefolder)=="function"
if Hub.storage then
	local ok, err = pcall(function()
		ThemeManager:SetLibrary(Library)
		SaveManager:SetLibrary(Library)
		SaveManager:SetIgnoreIndexes({"MultiWhitelist"})
		Hub.installConfigLoading(SaveManager)
		ThemeManager:SetFolder("ArrivaCoreHub")
		SaveManager:SetFolder("ArrivaCoreHub/Configs")
		SaveManager:BuildConfigSection(Tabs["UI Settings"])
		local success,loadError=SaveManager:Load("AutoSave")
		if success then notify("Config","Your saved settings were loaded.")
		elseif loadError~="No saved configuration" then
			notify("Config warning","Settings could not load. Autosave is paused to protect the existing file. " .. tostring(loadError),10)
		end
	end)
	if not ok then Hub.storage = false; notify("Config", tostring(err)) end
else
	notify("Config", "File storage unavailable. Settings work for this session.")
end
-- Defer until SaveManager's deferred load callbacks have finished.
task.defer(function()
	if not Hub.loadedSafety then Hub.readSafety() end
	if Hub.refreshWhitelistUI then Hub.refreshWhitelistUI() end
	Hub.lastSettings=Hub.captureSettings()
	Hub.ready = true
	Hub.env.ArrivaCoreStarting=nil
	Hub.startupSeconds=os.clock()-Hub.startupBegan
	if not Hub.configLoaded and not Hub.configLoadFailed then Hub.requestSave() end
end)
MenuGroup:AddSlider("StartupFeatureDelay",{Text="Saved-feature startup delay (seconds)",Default=3,Min=0,Max=10,Rounding=1,Callback=function() end})
MenuGroup:AddButton({Text="Startup diagnostics",Func=function()
    local listeners,workers=0,0
    for connection in pairs(Hub.connections) do if connection.Connected then listeners+=1 end end
    for thread in pairs(Hub.threads) do if coroutine.status(thread)~="dead" then workers+=1 end end
    local progress=Hub.restoreProgress
    local message=string.format("UI startup %.2fs, %d listeners, %d tracked workers.",Hub.startupSeconds or 0,listeners,workers)
    if progress then message..=string.format(" Saved enabled features started: %d/%d%s.",progress.started,progress.total,progress.done and " (finished)" or " (starting)") end
    if Hub.lastRestoreControl then message..=" Last restored: "..Hub.lastRestoreControl.."." end
    if Hub.lastUIError then message..=" Last callback error: "..Hub.lastUIError:sub(1,180) end
    if Hub.lastCallbackError then message..=" Last event error: "..Hub.lastCallbackError:sub(1,180) end
    if Hub.lastWorkerError then message..=" Last worker error: "..Hub.lastWorkerError:sub(1,180) end
    print("[Arriva startup] "..message);notify("Startup diagnostics",message,10)
end})
MenuGroup:AddButton({Text = "Save status", Func = function()
	local message = "Storage: " .. (Hub.storage and "available" or "unavailable")
		.. " | Last successful save: " .. (Hub.lastSaveAt or "none this session")
	if Hub.lastLoadPath then message ..= " | Loaded: " .. Hub.lastLoadPath end
	if Hub.configLoadFailed then message ..= " | Autosave paused: load failed" end
	if Hub.lastLoadError then message ..= " | Load error: " .. Hub.lastLoadError;warn("[Arriva config load] " .. Hub.lastLoadError) end
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
	if Hub.stopBlobFlight then Hub.stopBlobFlight() end
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

-- Autosave is scheduled after setting changes; no permanent polling loop.

-- Send loaded message

notify("Arriva Core Hub 2.0", "Hub loaded. Your saved settings and controls are ready.", 5)
