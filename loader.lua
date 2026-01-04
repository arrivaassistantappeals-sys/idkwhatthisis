--=====================================================
-- ARRIVA CORE HUB – OWNER COMMAND CORE (ALWAYS FIRST)
--=====================================================

--// Services
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local StarterGui = game:GetService("StarterGui")

--// Player
local LocalPlayer = Players.LocalPlayer
local character = LocalPlayer.Character
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
}

--// Whitelist check
if WHITELIST[LocalPlayer.UserId] ~= LocalPlayer.Name then
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
		local TextChatService = game:GetService("TextChatService")
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

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = Color3.fromRGB(255, 170, 0);
			Font = Enum.Font.SourceSansBold;
			FontSize = Enum.FontSize.Size18;
		})
	end)
end

--// Get all whitelisted players currently in-game
local function getWhitelistedPlayers()
	local whitelisted = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if WHITELIST[plr.UserId] then
			table.insert(whitelisted, plr)
		end
	end
	return whitelisted
end

--// Enhanced player finder
local function findTarget(targetStr)
	if not targetStr then return nil end

	targetStr = targetStr:lower()

	-- "me" = LocalPlayer
	if targetStr == "me" then
		return {LocalPlayer}
	end

	-- "all" = all whitelisted players
	if targetStr == "all" then
		return getWhitelistedPlayers()
	end

	-- Partial match (username or display name)
	local matches = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if WHITELIST[plr.UserId] then -- Only match whitelisted players
			if plr.Name:lower():find(targetStr) or plr.DisplayName:lower():find(targetStr) then
				table.insert(matches, plr)
			end
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

--// CHAT LISTENER (ROBUST – ALL CHANNELS)
if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
	TextChatService.OnIncomingMessage = function(message)
		if not message.TextSource then return end
		local speaker = Players:GetPlayerByUserId(message.TextSource.UserId)
		if speaker then
			processCommand(speaker, message.Text)
		end
	end
else
	-- Old chat fallback
	local function hookPlayer(plr)
		plr.Chatted:Connect(function(msg)
			processCommand(plr, msg)
		end)
	end

	for _, p in ipairs(Players:GetPlayers()) do
		hookPlayer(p)
	end
	Players.PlayerAdded:Connect(hookPlayer)
end

print("Arriva Core Hub owner command core loaded")
--=====================================================

-- Main script continues
loadstring(game:HttpGet('https://raw.githubusercontent.com/EdgeIY/infiniteyield/master/source'))()

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles
Library.ForceCheckbox = false

local Window = Library:CreateWindow({
	Title = "Arriva Core Hub V1.4",
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
	Info = Window:AddTab("Information", "clipboard-pen-line")
}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local PS = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local R = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Debris = game:GetService("Debris")
local Workspace = workspace
local Player = PS.LocalPlayer
local Camera = Workspace.CurrentCamera
local CE = RS:WaitForChild("CharacterEvents", 10)
local BeingHeld = Player:WaitForChild("IsHeld", 10)
local StruggleEvent = CE and CE:WaitForChild("Struggle")
local characterEventsFolder = RS:WaitForChild("CharacterEvents")
local createGrabLineEvent = RS:WaitForChild("GrabEvents"):WaitForChild("CreateGrabLine")
local destroyGrabLineEvent = RS:WaitForChild("GrabEvents"):WaitForChild("DestroyGrabLine")
local setNetworkOwnerEvent = RS:WaitForChild("GrabEvents"):WaitForChild("SetNetworkOwner")
local extendGrabLineRemoteEvent = RS:WaitForChild("GrabEvents"):WaitForChild("ExtendGrabLine")
local ragdollRemoteEvent = characterEventsFolder:WaitForChild("RagdollRemote")
local playerScriptsFolder = LocalPlayer:WaitForChild("PlayerScripts")
anticreatelinelocalscript = playerScriptsFolder:WaitForChild("CharacterAndBeamMove")
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
local function deleteAllPaintParts()
	for _, obj in ipairs(Workspace:GetDescendants()) do
		if obj:IsA("BasePart") and obj.Name == "PaintPlayerPart" then
			local clone = obj:Clone()
			clone.Archivable = true
			paintPartsBackup[obj:GetDebugId()] = { clone = clone, parent = obj.Parent }
			obj:Destroy()
		end
	end
end

local function restorePaintParts()
	for _, data in pairs(paintPartsBackup) do
		if data.clone and data.parent then data.clone.Parent = data.parent end
	end
	paintPartsBackup = {}
end

local function watchNewPaintParts()
	table.insert(paintConnections, Workspace.DescendantAdded:Connect(function(obj)
		if obj:IsA("BasePart") and obj.Name == "PaintPlayerPart" then
			task.defer(function()
				if obj and obj.Parent then
					local clone = obj:Clone()
					clone.Archivable = true
					paintPartsBackup[obj:GetDebugId()] = { clone = clone, parent = obj.Parent }
					obj:Destroy()
				end
			end)
		end
	end))
end

local function disconnectWatchers()
	for _, conn in ipairs(paintConnections) do if conn.Connected then conn:Disconnect() end end
	paintConnections = {}
end

local function setTouchQuery(state)
	local char = Workspace:FindFirstChild(Player.Name)
	if not char then return end
	for _, v in ipairs(char:GetChildren()) do
		if v:IsA("Part") or v:IsA("BasePart") then v.CanTouch = state v.CanQuery = state end
	end
end



-- Anti-Gucci Systems
local antiGucciConnection
local safePosition
local restoreFrames = 0

local function spawnBlobman()
	local args = {[1] = "CreatureBlobman", [2] = CFrame.new(0, 5000000, 0), [3] = Vector3.new(0, 60, 0)}
	pcall(function() ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer(unpack(args)) end)
	local folder = Workspace:WaitForChild(Player.Name.."SpawnedInToys", 5)
	if folder and folder:FindFirstChild("CreatureBlobman") then
		local blob = folder.CreatureBlobman
		if blob:FindFirstChild("Head") then blob.Head.CFrame = CFrame.new(0, 50000, 0) blob.Head.Anchored = true end
		notify("Success", "Blobman Spawned!", 3)
	end
end

local function startAntiGucci()
	local character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
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

	if seat and seat:IsA("VehicleSeat") then 
		rootPart.CFrame = seat.CFrame + Vector3.new(0, 2, 0) 
		seat:Sit(humanoid) 
	end

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function() 
		if humanoid.Jump and humanoid.Sit then 
			restoreFrames = 15 
			safePosition = rootPart.Position 
		end 
	end)

	if antiGucciConnection then antiGucciConnection:Disconnect() end
	antiGucciConnection = R.Heartbeat:Connect(function()
		if not rootPart or not humanoid then return end
		ReplicatedStorage.CharacterEvents.RagdollRemote:FireServer(rootPart, 0)
		if restoreFrames > 0 then 
			rootPart.CFrame = CFrame.new(safePosition) 
			restoreFrames = restoreFrames - 1 
		end
	end)

	task.spawn(function() 
		while humanoid.Sit do 
			task.wait(1) 
		end 
		task.wait(0.5) 
		rootPart.CFrame = CFrame.new(safePosition) 
	end)
end

local function stopAntiGucci()
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
	local character = Player.Character or Player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid")
	local rootPart = character:WaitForChild("HumanoidRootPart")
	safePositionTrain = rootPart.Position
	local folder = workspace.Map.AlwaysHereTweenedObjects
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

	humanoid:GetPropertyChangedSignal("Jump"):Connect(function() 
		if humanoid.Jump and humanoid.Sit then 
			restoreFramesTrain = 15 
			safePositionTrain = rootPart.Position 
		end 
	end)

	if antiGucciConnectionTrain then antiGucciConnectionTrain:Disconnect() end
	antiGucciConnectionTrain = R.Heartbeat:Connect(function()
		if not rootPart or not humanoid then return end
		ReplicatedStorage.CharacterEvents.RagdollRemote:FireServer(rootPart, 0)
		if restoreFramesTrain > 0 then 
			rootPart.CFrame = CFrame.new(safePositionTrain) 
			restoreFramesTrain = restoreFramesTrain - 1 
		end
	end)

	task.spawn(function() 
		while humanoid.Sit do 
			task.wait(1) 
		end 
		task.wait(0.5) 
		rootPart.CFrame = CFrame.new(safePositionTrain) 
	end)
end

local function stopAntiGucciTrain()
	if antiGucciConnectionTrain then 
		antiGucciConnectionTrain:Disconnect() 
		antiGucciConnectionTrain = nil 
	end
end

-- Defense Tab
local DefenseGroup = Tabs.Defense:AddLeftGroupbox("Defense Main")
local DefenseExtra = Tabs.Defense:AddRightGroupbox("Extra Defense")

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer

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
			p.Anchored = state
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
	freezeConn = RunService.Heartbeat:Connect(function()
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

local function onGrabDetected()
	if not antiGrabEnabled then return end

	local char = Player.Character
	if not char then return end

	-- server-side struggle ASAP
	pcall(function()
		if Struggle then Struggle:FireServer(Player) end
		if StopVelocity then StopVelocity:FireServer() end
	end)

	-- instant hard stop
	anchorAll(char, true)
	freezeChar(char)

	-- wait ONLY while held
	local isHeld = Player:FindFirstChild("IsHeld")
	if isHeld then
		local conn
		conn = isHeld.Changed:Connect(function(v)
			if v == false then
				unfreezeChar(char)
				if conn then conn:Disconnect() end
			end
		end)
		table.insert(connections, conn)
	else
		task.delay(0.15, function()
			unfreezeChar(char)
		end)
	end
end

--------------------------------------------------
-- Character hook
--------------------------------------------------

local function hookCharacter(char)
	local head = char:WaitForChild("Head", 5)
	local hum = char:WaitForChild("Humanoid", 5)
	if not (head and hum) then return end

	-- detect grab instantly
	table.insert(connections,
		head.ChildAdded:Connect(function(child)
			if antiGrabEnabled and child.Name == "PartOwner" then
				onGrabDetected()
			end
		end)
	)

	-- prevent non-blob seating
	table.insert(connections,
		hum.Changed:Connect(function(prop)
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
		SaveManager:Save("AutoSave")
		SaveManager:Save("AutoSave")
		antiGrabEnabled = on
		disconnectAll()

		if on then
			if Player.Character then
				hookCharacter(Player.Character)
			end

			table.insert(connections,
				Player.CharacterAdded:Connect(function(char)
					task.wait(0.1)
					hookCharacter(char)
				end)
			)
		else
			unfreezeChar(Player.Character)
		end
	end
})


local function anti(Descendant)
	if Descendant:FindFirstChild("LeftDetector") and Descendant:FindFirstChild("RightDetector") then
		Descendant:WaitForChild("LeftDetector"):WaitForChild("LeftAlignOrientation").Enabled = false
		Descendant:WaitForChild("LeftDetector"):WaitForChild("LeftWeld").Enabled = false
		Descendant:WaitForChild("RightDetector"):WaitForChild("RightAlignOrientation").Enabled = false
		Descendant:WaitForChild("RightDetector"):WaitForChild("RightWeld").Enabled = false
		Descendant:WaitForChild("LeftDetector"):Destroy()
		Descendant:WaitForChild("RightDetector"):Destroy()
	end
end

local antiBlob1T=false
local function antiBlob1F()
	antiBlob1T=true

	if antiBlob1F then
		for _, Descendant in pairs(workspace:GetDescendants()) do
			if Descendant.Name == "CreatureBlobman" then
				anti(Descendant)
			end
		end

		workspace.DescendantAdded:Connect(function(Descendant)
			if Descendant.Name == "CreatureBlobman" then
				wait(0.1)
				anti(Descendant)
			end
		end)
	end
end

DefenseGroup:AddToggle("AntiBlobmanToggle", {
	Text="Anti Blobman", 
	Default=false,
	Callback=function(on)
		SaveManager:Save("AutoSave")
		if on then antiBlob1F() else antiBlob1T=false end
	end
})

local antiExplodeT=false
local function antiExplodeF()
	antiExplodeT=true
	local char=Player.Character
	if not char then return end
	local hrp=char:WaitForChild("HumanoidRootPart")
	workspace.ChildAdded:Connect(function(model)
		if model.Name=="Part" and antiExplodeT then
			local mag=(model.Position-hrp.Position).Magnitude
			if mag<=20 then
				hrp.Anchored=true
				wait(0.01)
				while char["Right Arm"].RagdollLimbPart.CanCollide do wait(0.001) end
				hrp.Anchored=false
			end
		end
	end)
end

DefenseGroup:AddToggle("AntiExplosionToggle", {
	Text="Anti Explosion", 
	Default=false,
	Callback=function(on)
		SaveManager:Save("AutoSave")
		if on then antiExplodeF() else antiExplodeT=false end
	end
})

-- Anti-Burn System (FINAL / PERSISTENT)


local extinguisher = workspace.Map.Hole.PoisonBigHole.ExtinguishPart
extinguisher.Size = Vector3.new(0.5, 0.5, 0.5)
extinguisher.Transparency = 1
if extinguisher:FindFirstChild("Tex") then
	extinguisher.Tex.Transparency = 1
end

local antiBurnEnabled = false
local burnThreadToken = 0

local function hookBurn(char)
	burnThreadToken += 1
	local token = burnThreadToken

	local hum = char:WaitForChild("Humanoid")
	local hrp = char:WaitForChild("HumanoidRootPart")
	local firePart = hrp:WaitForChild("FirePlayerPart")

	-- FireDebounce can live in two places
	local function getFireDebounce()
		return hum:FindFirstChild("FireDebounce")
			or firePart:FindFirstChild("FireDebounce")
	end

	task.spawn(function()
		while antiBurnEnabled and hum.Parent and burnThreadToken == token do
			local fireDebounce = getFireDebounce()

			if fireDebounce and fireDebounce.Value == true then
				-- extinguish
				extinguisher.CFrame =
					firePart.CFrame
					* CFrame.new(
						math.random(-1, 1),
						math.random(-1, 1),
						math.random(-1, 1)
					)

				if firetouchinterest then
					firetouchinterest(firePart, extinguisher, 0)
					task.wait(0.05)
					firetouchinterest(firePart, extinguisher, 1)
				else
					warn("Executor does not support firetouchinterest!")
				end

				-- kill visuals + sounds
				for _, obj in ipairs(firePart:GetDescendants()) do
					if obj:IsA("Sound") then
						obj:Stop()
					elseif obj:IsA("ParticleEmitter") or obj:IsA("Light") then
						obj.Enabled = false
					end
				end

				-- wait for server to reset naturally
				repeat
					task.wait(0.05)
				until not fireDebounce.Value or not antiBurnEnabled
			end

			task.wait(0.1)
		end
	end)
end

-- Respawn support
LocalPlayer.CharacterAdded:Connect(function(char)
	if antiBurnEnabled then
		task.wait(0.1)
		hookBurn(char)
	end
end)

-- UI toggle
DefenseGroup:AddToggle("AntiBurnToggle", {
	Text = "Anti Burn",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		SaveManager:Save("AutoSave")
		antiBurnEnabled = on
		if on then
			if LocalPlayer.Character then
				hookBurn(LocalPlayer.Character)
			end
		else
			-- invalidate running threads
			burnThreadToken += 1
		end
	end
})

-- Anti-Void
local antiVoidConn
local VOID_THRESHOLD = -50
local SAFE_HEIGHT = 100

DefenseGroup:AddToggle("AntiVoidToggle", {
	Text = "Anti Void",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		if on then
			if antiVoidConn then antiVoidConn:Disconnect() end
			antiVoidConn = R.Heartbeat:Connect(function()
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

-- Anti-Sticky
local antiStickyT = false
DefenseGroup:AddToggle("AntiStickyToggle", {
	Text = "Anti Sticky",
	Default = false,
	Callback = function(Value)
		antiStickyT = Value
		if Player.PlayerScripts:FindFirstChild("StickyPartsTouchDetection") then
			Player.PlayerScripts.StickyPartsTouchDetection.Disabled = Value
		end
	end,
})


local function isFromLocalPlayer(inst)
	return LocalPlayer.Character and inst:IsDescendantOf(LocalPlayer.Character)
end

local function removeExistingLines()
	for _, v in ipairs(workspace:GetDescendants()) do
		if v:IsA("Beam") or v.Name:lower():find("line") then
			if not isFromLocalPlayer(v) then
				pcall(function()
					v:Destroy()
				end)
			end
		end
	end
end

DefenseGroup:AddToggle("AntiLagToggle", {
	Text = "Anti Lag",
	Default = false,
	Callback = function(Value)
		anticreatelinelocalscript.Disabled = Value

		if Value then
			removeExistingLines()
		end
	end,
})



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
				local plr = game.Players.LocalPlayer
				local char = plr.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				if not hrp then return end

				local ToyName = "FoodHamburger"
				local RS = game:GetService("ReplicatedStorage")
				local Workspace = game:GetService("Workspace")
				local SpawnRemote = RS.MenuToys.SpawnToyRemoteFunction

				while _G.AntiInputLag do
					local toysFolder = Workspace:FindFirstChild(plr.Name.."SpawnedInToys")
					local burger = toysFolder and toysFolder:FindFirstChild(ToyName)

					if not burger then
						task.spawn(function()
							pcall(function()
								local spawnCF = hrp.CFrame * CFrame.new(0, 5, 0)
								SpawnRemote:InvokeServer(ToyName, spawnCF, Vector3.new(0,0,0))
							end)
						end)

						local startWait = tick()
						repeat 
							R.Heartbeat:Wait()
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
									holdPart.DropItemRemoteFunction:InvokeServer(burger, hrp.CFrame * CFrame.new(0, 2000, 0), Vector3.new(0,0,0))
								end)
								burger:Destroy()
							else
								pcall(function()
									holdPart.HoldItemRemoteFunction:InvokeServer(burger, char)
								end)
								task.wait()

								pcall(function()
									holdPart.DropItemRemoteFunction:InvokeServer(burger, hrp.CFrame * CFrame.new(0, 2000, 0), Vector3.new(0,0,0))
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
			local plr = game.Players.LocalPlayer
			local inv = workspace:FindFirstChild(plr.Name.."SpawnedInToys")
			local destroyrem = game.ReplicatedStorage:FindFirstChild("MenuToys") and game.ReplicatedStorage.MenuToys:FindFirstChild("DestroyToy")

			if inv and destroyrem then
				for _, v in pairs(inv:GetChildren()) do
					if v.Name == "AntiKick" or v.Name == "NinjaShuriken" then
						pcall(function() destroyrem:FireServer(v) end)
					end
				end
			end
		end

		if Value then
			task.spawn(function()
				local plr = game.Players.LocalPlayer
				local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
							setOwner:FireServer(kunai.SoundPart, kunai.SoundPart.CFrame)
						end
					end

					local firePart = currentHRP:FindFirstChild("FirePlayerPart") or currentHRP:WaitForChild("FirePlayerPart", 5)
					if firePart then
						stickyEvent:FireServer(kunai.StickyPart, firePart, CFrame.new(0,0,0) * CFrame.Angles(0,math.rad(90),math.rad(90)))
					end

					for _, obj in pairs(kunai:GetChildren()) do
						if obj.Name == "Pyramid" then
							obj.CanTouch = false; obj.CanCollide = false; obj.CanQuery = false; obj.Transparency = 0
							if not obj:FindFirstChild("Highlight") then
								local high = Instance.new("Highlight", obj)
								high.FillColor = Color3.fromRGB(0, 0, 0)
							end
						elseif obj.Name == "Main" then
							obj.CanTouch = false; obj.CanCollide = false; obj.CanQuery = false; obj.Transparency = 0
							if not obj:FindFirstChild("Highlight") then
								local high = Instance.new("Highlight", obj)
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
								spawnRemote:InvokeServer(name, currentHRP.CFrame * CFrame.new(0, 12, 20), Vector3.new(0,0,0))
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

-- Loop TP
local tpActive = false
DefenseExtra:AddToggle("LoopTP", {
	Text = "Loop TP",
	Default = false,
	Callback = function(Value)
		tpActive = Value
		local char = Player.Character or Player.CharacterAdded:Wait()
		local hrp = char:WaitForChild("HumanoidRootPart")
		local hum = char:FindFirstChildOfClass("Humanoid")
		if Value then
			if hum then hum.PlatformStand = true end
			task.spawn(function()
				while tpActive and hrp do
					local x = math.random(-500, 500)
					local y = math.random(30, 480)
					local z = math.random(-500, 500)
					hrp.CFrame = CFrame.new(x, y, z)
					task.wait(0.03)
				end
			end)
		else
			if hum then hum.PlatformStand = false end
		end
	end,
})




-- Auto Attacker
local AutoAttacker = false
local headConnection
DefenseExtra:AddToggle("AutoAttacker", {
	Text = "Auto Attacker",
	Default = false,
	Callback = function(Value)
		AutoAttacker = Value
	end
})

function CheckNetworkOwnerShipOnPlayer(potentialPlayer, condition)
	if typeof(potentialPlayer) == "Instance" and (potentialPlayer:IsA("Player") and potentialPlayer.Character) and (potentialPlayer.Character:FindFirstChild("Head") and (potentialPlayer.Character.Head:FindFirstChild("PartOwner") and potentialPlayer.Character.Head.PartOwner.Value == LocalPlayer.Name)) then
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
	if LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and (typeof(otherPlayer) == "Instance" and (otherPlayer:IsA("Player") and otherPlayer.Character)) and (otherPlayer.Character:FindFirstChild("HumanoidRootPart") and otherPlayer.Character.HumanoidRootPart:FindFirstChild("FirePlayerPart"))) then
		local firePlayerPart = otherPlayer.Character.HumanoidRootPart.FirePlayerPart
		local distanceFromFirePlayerPart = LocalPlayer:DistanceFromCharacter(firePlayerPart.Position)
		if type(callbackFunction) == "function" then
			callbackFunction()
		end
		if distanceFromFirePlayerPart <= 30 then
			setNetworkOwnerEvent:FireServer(firePlayerPart, lookAt(LocalPlayer.Character.HumanoidRootPart.Position, firePlayerPart.Position))
			return true
		end
	end
end
function SNOWshipPlayer(otherPlayer, callbackFunction)
	if LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and (typeof(otherPlayer) == "Instance" and (otherPlayer:IsA("Player") and otherPlayer.Character)) and otherPlayer.Character:FindFirstChild("HumanoidRootPart")) then
		local otherPlayerHumanoidRootPart = otherPlayer.Character.HumanoidRootPart
		local distanceFromOtherPlayer = LocalPlayer:DistanceFromCharacter(otherPlayerHumanoidRootPart.Position)
		if CheckNetworkOwnerShipOnPlayer(otherPlayer) then
			if type(callbackFunction) == "function" then
				callbackFunction()
			end
			return true
		end
		if distanceFromOtherPlayer <= 30 then
			setNetworkOwnerEvent:FireServer(otherPlayerHumanoidRootPart, lookAt(LocalPlayer.Character.HumanoidRootPart.Position, otherPlayerHumanoidRootPart.Position))
		end
	end
end
function SNOWship(targetPart)
	if targetPart and typeof(targetPart) == "Instance" then
		local distanceFromCharacter = LocalPlayer:DistanceFromCharacter(targetPart.Position)
		if LocalPlayer.Character and (LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and distanceFromCharacter <= 30) then
			setNetworkOwnerEvent:FireServer(targetPart, lookAt(LocalPlayer.Character.HumanoidRootPart.Position, targetPart.Position))
		end
	end
end
function CreateSkyVelocity(skyObject)
	if not skyObject:FindFirstChild("SkyVelocity") then
		local skyVelocityBodyVelocity = Instance.new("BodyVelocity", skyObject)
		skyVelocityBodyVelocity.Name = "SkyVelocity"
		skyVelocityBodyVelocity.Velocity = Vector3.new(0, 100000000000000, 0)
		skyVelocityBodyVelocity.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
	end
end


local heldObjectName = nil
character.DescendantAdded:Connect(function(hitPart)
	if hitPart.Name == "PartOwner" then
		heldObjectName = tostring(hitPart.Value)
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
			if otherPlayer and otherPlayer ~= LocalPlayer then
				-- Death mode counter action
				local counterAction = function()
					local humanoidInstance = otherHumanoid
					if humanoidInstance then
						CreateSkyVelocity(otherHumanoidRootPart)
						for _ = 0, 20 do
							humanoidInstance.BreakJointsOnDeath = false
							humanoidInstance:ChangeState(Enum.HumanoidStateType.Dead)
							humanoidInstance.Jump = true
							humanoidInstance.Sit = true
						end
						task.wait()
						RS.GrabEvents.DestroyGrabLine:FireServer(otherHumanoidRootPart)
					end
				end

				-- Execute SNOWship loop
				for _ = 1, 50 do
					if SNOWshipPlayer(otherPlayer, counterAction) then
						break
					end
					task.wait()
				end
			end
		end 
	end
end)

-- Player Tab
local PlayerView = Tabs.Player:AddLeftGroupbox("View & Movement")
local PlayerESP = Tabs.Player:AddRightGroupbox("ESP")
local PlayerPerf = Tabs.Player:AddRightGroupbox("Performance")

-- Third Person View
local function enableThirdPerson()
	Player.CameraMode = Enum.CameraMode.Classic
	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = Player.Character:WaitForChild("Humanoid")
	Player.CameraMaxZoomDistance = 16456456546
	Player.CameraMinZoomDistance = 0.5
end

local function disableThirdPerson()
	Player.CameraMode = Enum.CameraMode.LockFirstPerson
	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = Player.Character:WaitForChild("Humanoid")
	Player.CameraMaxZoomDistance = 0
	Player.CameraMinZoomDistance = 0
end

PlayerView:AddToggle("ThirdPersonToggle", {
	Text = "3rd Person View",
	Default = false,
	Callback = function(Value)
		if Value then enableThirdPerson() else disableThirdPerson() end
	end
})

-- Spin Character
local spinningConnection
local spinSpeed = 5
PlayerView:AddToggle("SpinToggle", {
	Text = "Spin Character",
	Default = false,
	Callback = function(Value)
		if Value then
			spinningConnection = R.Heartbeat:Connect(function()
				local character = Player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if root then root.CFrame = root.CFrame * CFrame.Angles(0, math.rad(spinSpeed), 0) end
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
			SpeedModConnection = R.Heartbeat:Connect(function()
				local character = Player.Character
				if character then
					local root = character:FindFirstChild("HumanoidRootPart")
					local hum = character:FindFirstChildOfClass("Humanoid")
					if root and hum then
						root.CFrame = root.CFrame + hum.MoveDirection * speedMultiplier
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
					hum.JumpPower = JumpPower
				else
					hum.JumpPower = 50
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
					hum.JumpPower = Value
				end
			end
		end
	end
})

Player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid")
	task.wait(0.1)
	if jumpModifierEnabled then
		hum.JumpPower = JumpPower
	end
	if speedModifierEnabled and SpeedModConnection then
		SpeedModConnection:Disconnect()
		SpeedModConnection = R.Heartbeat:Connect(function()
			local root = char:FindFirstChild("HumanoidRootPart")
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if root and humanoid then
				root.CFrame = root.CFrame + humanoid.MoveDirection * speedMultiplier
			end
		end)
	end
end)

UserInputService.JumpRequest:Connect(function()
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
	local box = Instance.new("BoxHandleAdornment")
	box.Adornee = obj
	box.AlwaysOnTop = true
	box.ZIndex = 5
	box.Color3 = Color3.fromRGB(255, 255, 255)
	box.Transparency = 0.5
	box.Size = obj.Size
	box.Parent = game.CoreGui
	espBoxes[obj] = box
	obj.AncestryChanged:Connect(function(_, parent)
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

workspace.DescendantAdded:Connect(function(obj) if espEnabled and IsTarget(obj) then AddBoxESP(obj) end end)

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
		local function createESP(plr)
			if plr == Player then return end
			if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
				local hrp = plr.Character.HumanoidRootPart
				if hrp:FindFirstChild("NameESP") then return end

				local billboard = Instance.new("BillboardGui")
				billboard.Name = "NameESP"
				billboard.Adornee = hrp
				billboard.Size = UDim2.new(0, 120, 0, 70)
				billboard.StudsOffset = Vector3.new(0, 3.5, 0)
				billboard.AlwaysOnTop = true
				billboard.Parent = hrp

				local container = Instance.new("Frame")
				container.Size = UDim2.new(1, 0, 1, 0)
				container.BackgroundTransparency = 1
				container.Parent = billboard

				local pfpFrame = Instance.new("Frame")
				pfpFrame.Size = UDim2.new(0, 40, 0, 40)
				pfpFrame.Position = UDim2.new(0.5, 0, 0, 0)
				pfpFrame.AnchorPoint = Vector2.new(0.5, 0)
				pfpFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 35)
				pfpFrame.BorderSizePixel = 0
				pfpFrame.Parent = container

				local pfpCorner = Instance.new("UICorner")
				pfpCorner.CornerRadius = UDim.new(1, 0)
				pfpCorner.Parent = pfpFrame

				local pfpImage = Instance.new("ImageLabel")
				pfpImage.Size = UDim2.new(1, 0, 1, 0)
				pfpImage.BackgroundTransparency = 1
				pfpImage.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. plr.UserId .. "&width=150&height=150&format=png"
				pfpImage.Parent = pfpFrame

				local pfpImageCorner = Instance.new("UICorner")
				pfpImageCorner.CornerRadius = UDim.new(1, 0)
				pfpImageCorner.Parent = pfpImage

				local textLabel = Instance.new("TextLabel")
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
			for _, plr in pairs(PS:GetPlayers()) do 
				createESP(plr) 
				plr.CharacterAdded:Connect(function() 
					task.wait(0.1)
					createESP(plr) 
				end) 
			end
			PS.PlayerAdded:Connect(function(plr) 
				plr.CharacterAdded:Connect(function() 
					task.wait(0.1)
					createESP(plr) 
				end) 
			end)
		else
			for _, plr in pairs(PS:GetPlayers()) do
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
		for _, plr in pairs(PS:GetPlayers()) do
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

	noclipConn = R.Stepped:Connect(function()
		if not noclipEnabled then return end
		local char = Player.Character
		if char then
			applyNoclip(char)
		end
	end)

	charConn = Player.CharacterAdded:Connect(function()
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
		SaveManager:Save("AutoSave")
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
	for _, plr in ipairs(PS:GetPlayers()) do
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
		return PS:FindFirstChild(username)
	end
	return nil
end

TargetGroup:AddDropdown("KickPlayerDropdown", {
	Values = getPlayerList(),
	Default = 1,
	Multi = false,
	Text = "select player to loop",
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

-- Loop Kick Toggle (Spam Grab)
TargetGroup:AddToggle("LoopKickSpamToggle", {
	Text = "Kick (spam grab)",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
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
			local RS = game:GetService("ReplicatedStorage")    
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

				local tChar = target.Character    
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")    
				local tHum = tChar and tChar:FindFirstChild("Humanoid")    

				myChar = Player.Character    
				myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")    

				if tRoot and tHum and tHum.Health > 0 and myRoot then    
					tRoot.AssemblyLinearVelocity = Vector3.zero    
					tRoot.AssemblyAngularVelocity = Vector3.zero    
					tRoot.Velocity = Vector3.zero    

					if not dragging then    
						myRoot.CFrame = tRoot.CFrame    
						myRoot.Velocity = Vector3.zero    

						pcall(function()    
							tHum.PlatformStand = true    
							tHum.Sit = true    
							GE.SetNetworkOwner:FireServer(tRoot, myRoot.CFrame)   
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

						tRoot.CFrame = lockPos    
						tRoot.Velocity = Vector3.zero    
						tRoot.RotVelocity = Vector3.zero    

						tHum.PlatformStand = true    
						tHum.Sit = false    

						pcall(function()    
							GE.SetNetworkOwner:FireServer(tRoot, lockPos)    
							GE.DestroyGrabLine:FireServer(tRoot)    
							GE.SetNetworkOwner:FireServer(tRoot, lockPos)    
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
		SaveManager:Save("AutoSave")
		loopKillEnabled = on
		if on then
			local target = SelectedPlayer
			if not target then 
				notify("System", "Select target first", 3)
				Toggles.LoopKillToggle:SetValue(false)
				return 
			end

			task.spawn(function()
				local RS = game:GetService("ReplicatedStorage")
				local GE = RS:WaitForChild("GrabEvents")

				while loopKillEnabled do
					if not target or not target.Parent or not target.Character then
						loopKillEnabled = false
						Toggles.LoopKillToggle:SetValue(false)
						break
					end

					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
					local tChar = target.Character
					local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
					local tHum = tChar and tChar:FindFirstChild("Humanoid")
					local tHead = tChar and tChar:FindFirstChild("Head")

					if tRoot and tHum and tHead and myRoot then
						local currentPos = myRoot.CFrame

						for _ = 0, 50 do
							if not loopKillEnabled or not tRoot.Parent then break end

							applyNoclip(myChar)
							SNOWship(tRoot)

							-- Check if SNOWship was successful
							if not loopKillEnabled or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
								GE.DestroyGrabLine:FireServer(tRoot)
								CreateSkyVelocity(tRoot)
								break
							end

							task.wait()

							-- Teleport to target
							if tRoot.Position.Y <= -12 then
								myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 5, -15))
							else
								myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, -10, -10))
							end
							myRoot.Velocity = Vector3.zero

							-- Apply death state
							tHum.BreakJointsOnDeath = false
							tHum:ChangeState(Enum.HumanoidStateType.Dead)
							tHum.Jump = true
							tHum.Sit = false
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
		SaveManager:Save("AutoSave")
		loopKillEnabledAll = on
		if on then
			task.spawn(function()
				local RS = game:GetService("ReplicatedStorage")
				local PS = game:GetService("Players")
				local GE = RS:WaitForChild("GrabEvents")

				while loopKillEnabledAll do
					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

					if myRoot then
						local currentPos = myRoot.CFrame

						for _, target in pairs(PS:GetPlayers()) do
							if not loopKillEnabledAll then break end
							if target == Player then continue end

							if not target or not target.Parent or not target.Character then
								continue
							end

							local tChar = target.Character
							local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
							local tHum = tChar and tChar:FindFirstChild("Humanoid")
							local tHead = tChar and tChar:FindFirstChild("Head")

							-- Check if player is not in their plot
							local inPlotValue = target:FindFirstChild("InPlot")
							local isInPlot = inPlotValue and inPlotValue.Value

							if tRoot and tHum and tHead and tHum.Health > 0 and not isInPlot then
								for _ = 0, 50 do
									if not loopKillEnabledAll or not tRoot.Parent then break end

									applyNoclip(myChar)
									SNOWship(tRoot)

									-- Check if SNOWship was successful
									if not loopKillEnabledAll or (CheckNetworkOwnerShipOnPlayer and CheckNetworkOwnerShipOnPlayer(target)) or tRoot.AssemblyLinearVelocity.Magnitude > 500 then
										GE.DestroyGrabLine:FireServer(tRoot)
										CreateSkyVelocity(tRoot)
										break
									end

									task.wait()

									-- Teleport to target
									if tRoot.Position.Y <= -12 then
										myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, 5, -15))
									else
										myRoot.CFrame = CFrame.new(tRoot.Position + Vector3.new(0, -10, -10))
									end
									myRoot.Velocity = Vector3.zero

									-- Apply death state
									tHum.BreakJointsOnDeath = false
									tHum:ChangeState(Enum.HumanoidStateType.Dead)
									tHum.Jump = true
									tHum.Sit = false
								end

								task.wait(0.1)
							end
						end

						if myRoot then
							restoreCollision()
							myRoot.CFrame = currentPos
							myRoot.Velocity = Vector3.zero
						end
					end

					task.wait(0.2)
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
-- Loop Void
local loopVoidEnabled = false
TargetGroup:AddToggle("LoopVoidToggle", {
	Text = "Loop Void",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		loopVoidEnabled = on
		if not on then return end

		task.spawn(function()
			local RS = game:GetService("ReplicatedStorage")
			local RunService = game:GetService("RunService")
			local GE = RS:WaitForChild("GrabEvents")

			while loopVoidEnabled do
				local target = SelectedPlayer

				if not target or not target.Character then
					task.wait(0.5)
					continue
				end

				local tRoot = target.Character:FindFirstChild("HumanoidRootPart")
				if not tRoot then
					task.wait(0.5)
					continue
				end

				pcall(function()
					GE.SetNetworkOwner:FireServer(tRoot)
					tRoot.CFrame = CFrame.new(0, -10000, 0)
					GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
					GE.DestroyGrabLine:FireServer(tRoot)
				end)

				task.wait(1)
			end
		end)
	end
})

-- Loop Kick with Blob
TargetGroup:AddToggle("LoopKickBlobToggle", {
	Text = "Loop Kick (grab + blob)",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		kickLoopEnabled = on

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

		task.spawn(function()
			local RS = game:GetService("ReplicatedStorage")
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
			local tChar = target.Character
			local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")

			if tRoot and blobRoot then
				local bringStart = tick()
				while tick() - bringStart < 0.35 do
					if not kickLoopEnabled then break end

					blobRoot.CFrame = tRoot.CFrame
					blobRoot.Velocity = Vector3.zero

					pcall(function()
						if CG and R_Det then CG:FireServer(R_Det, tRoot, R_Weld) end
						GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
						GE.SetNetworkOwner:FireServer(tRoot, blobRoot.CFrame)
					end)
					R.Heartbeat:Wait()
				end

				blobRoot.CFrame = SavedPos
				blobRoot.Velocity = Vector3.zero
				task.wait(0.05)
			end

			local packetTimer = 0

			while kickLoopEnabled do
				if not target or not target.Parent or not target.Character then
					break
				end

				local tChar = target.Character
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
				local tHum = tChar and tChar:FindFirstChild("Humanoid")

				if tRoot and tHum and tHum.Health > 0 and blobRoot then
					blobRoot.CFrame = SavedPos
					blobRoot.Velocity = Vector3.zero

					local lockPos = SavedPos * CFrame.new(0, 23, 0)

					tRoot.CFrame = lockPos
					tRoot.Velocity = Vector3.zero
					tRoot.RotVelocity = Vector3.zero

					if tick() - packetTimer > 0.05 then
						packetTimer = tick()
						pcall(function()
							tHum.PlatformStand = true
							tHum.Sit = true
							GE.SetNetworkOwner:FireServer(tRoot, lockPos)

							if R_Det then
								local weld = R_Det:FindFirstChild("RightWeld") or R_Det:FindFirstChildWhichIsA("Weld")
								if weld then CD:FireServer(weld) end
							end
							GE.DestroyGrabLine:FireServer(tRoot)

							if R_Det then CG:FireServer(R_Det, tRoot, R_Weld) end
							GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
						end)
					end
				else
					blobRoot.CFrame = SavedPos
					blobRoot.Velocity = Vector3.zero
				end

				if not kickLoopEnabled then break end
				R.Heartbeat:Wait()
			end

			kickLoopEnabled = false
			if Toggles.LoopKickBlobToggle then Toggles.LoopKickBlobToggle:SetValue(false) end

			if blobRoot then
				blobRoot.CFrame = SavedPos
				blobRoot.Velocity = Vector3.zero
			end
		end)
	end
})

-- Dual Hand Loop Kick
local loopKickDualActive = false
TargetGroup:AddToggle("DualHandLoopKick", {
	Text = "Loop Kick (blob)",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		loopKickDualActive = on
		if on then
			if not SelectedPlayer then 
				notify("Error", "Select target first", 3)
				Toggles.DualHandLoopKick:SetValue(false)
				return 
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

					local targetChar = target.Character
					local targetHRP = targetChar and targetChar:FindFirstChild("HumanoidRootPart")
					local targetHum = targetChar and targetChar:FindFirstChild("Humanoid")

					if targetHRP and targetHum and targetHum.Health > 0 then
						if targetChar ~= lastTargetCharDual then
							lastTargetCharDual = targetChar
							if bp then bp:Destroy() bp = nil end
							if hrp then hrp.CFrame = targetHRP.CFrame * CFrame.new(0, 25, 0) end
							task.wait(0.2)
							grab:FireServer(leftDet, targetHRP, leftWeld)
							task.wait(0.3)
							drop:FireServer(leftWeld, targetHRP)
							task.wait(0.1)
							bp = Instance.new("BodyPosition")
							bp.Position = Vector3.new(0, 999999, 0)
							bp.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
							bp.Parent = targetHRP
							grab:FireServer(leftDet, targetHRP, leftWeld)
							task.wait(0.2)
							drop:FireServer(leftWeld, targetHRP)
						end

						grab:FireServer(leftDet, targetHRP, leftWeld)
						task.wait()
						drop:FireServer(leftWeld, targetHRP)
						task.wait()
						grab:FireServer(rightDet, targetHRP, rightWeld)
						task.wait()
						drop:FireServer(rightWeld, targetHRP)
						task.wait()
						grab:FireServer(leftDet, targetHRP, leftWeld)
						grab:FireServer(rightDet, targetHRP, rightWeld)
						task.wait()
						drop:FireServer(leftWeld, targetHRP)
						drop:FireServer(rightWeld, targetHRP)
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
		SaveManager:Save("AutoSave")
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
						local tChar = target.Character
						local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
						local tHum = tChar and tChar:FindFirstChild("Humanoid")

						if tRoot and tHum and tHum.Health > 0 then
							if not flingBAV or flingBAV.Parent ~= hrp then
								if flingBAV then flingBAV:Destroy() end
								flingBAV = Instance.new("BodyAngularVelocity")
								flingBAV.Name = "MaestroSpin"
								flingBAV.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
								flingBAV.AngularVelocity = Vector3.new(0, 10000, 0)
								flingBAV.P = 10000
								flingBAV.Parent = hrp
							end

							for _, part in pairs(char:GetDescendants()) do
								if part:IsA("BasePart") then
									part.CanCollide = false
								end
							end

							local loop = RunService.Heartbeat:Connect(function()
								if not playerFlingActive or not tRoot or not tRoot.Parent then return end
								hrp.CFrame = tRoot.CFrame
								hrp.Velocity = Vector3.zero 
							end)

							local startTime = tick()
							while tick() - startTime < 1.5 do
								if not playerFlingActive or not tRoot.Parent then break end
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
							part.CanCollide = true
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

game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.B and _G.AutoSitBlobZ then
		local plr = game.Players.LocalPlayer
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
					game.ReplicatedStorage.MenuToys.SpawnToyRemoteFunction:InvokeServer("CreatureBlobman", hrp.CFrame, Vector3.zero)
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
					R.Heartbeat:Wait()
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

UserInputService.InputBegan:Connect(function(input, gameProcessed)
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

R.Heartbeat:Connect(function()
	if not blobFlyActive or not blobMasterSwitch then 
		if bvInstance then bvInstance:Destroy() bvInstance = nil end
		if bgInstance then bgInstance:Destroy() bgInstance = nil end
		return 
	end

	local root = GetBlobRoot()
	if root then
		if not root:FindFirstChild("BlobFlyVelocity") then
			bvInstance = Instance.new("BodyVelocity")
			bvInstance.Name = "BlobFlyVelocity"
			bvInstance.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bvInstance.P = 10000
			bvInstance.Parent = root
		else
			bvInstance = root.BlobFlyVelocity
		end

		if not root:FindFirstChild("BlobFlyGyro") then
			bgInstance = Instance.new("BodyGyro")
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
					if not SelectedPlayer or not SelectedPlayer.Parent then
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
							if not DestroyTargetGucciActive then break end

							if obj.Name == "CreatureBlobman" then
								foundBlob = true
								local seat = obj:FindFirstChild("VehicleSeat") or obj:FindFirstChildWhichIsA("VehicleSeat", true)

								if seat then
									local myChar = Player.Character
									local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
									local myHum = myChar and myChar:FindFirstChild("Humanoid")

									if myRoot and myHum then
										if myHum.SeatPart ~= seat then
											notify("Target", "Reset", 1)

											local magnetConnection
											magnetConnection = RunService.Stepped:Connect(function()
												if myRoot and seat then
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
												if not DestroyTargetGucciActive then break end
												if myHum.SeatPart == seat then break end

												seat:Sit(myHum)
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
		if not SelectedPlayer then return end

		local char = Player.Character
		local hum = char and char:FindFirstChild("Humanoid")
		local seat = hum and hum.SeatPart
		if not seat or seat.Parent.Name ~= "CreatureBlobman" then return end

		local blob = seat.Parent
		local blobRoot = blob:FindFirstChild("HumanoidRootPart")
		local scriptObj = blob:FindFirstChild("BlobmanSeatAndOwnerScript")
		if not blobRoot or not scriptObj then return end

		local CG = scriptObj:FindFirstChild("CreatureGrab")
		local CD = scriptObj:FindFirstChild("CreatureDrop")
		local R_Det = blob:FindFirstChild("RightDetector")
		local R_Weld = R_Det and R_Det:FindFirstChild("RightWeld")

		local tChar = SelectedPlayer.Character
		local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if not tRoot then return end

		local home = blobRoot.CFrame
		blobRoot.CFrame = tRoot.CFrame
		blobRoot.Velocity = Vector3.new()
		blobRoot.RotVelocity = Vector3.new()
		task.wait(0.3)

		pcall(function()
			CG:FireServer(R_Det, tRoot, R_Weld)
		end)

		task.wait(0.5)
		blobRoot.CFrame = home
		blobRoot.Velocity = Vector3.new()
		blobRoot.RotVelocity = Vector3.new()
		task.wait(0.05)

		for i = 1, 12 do
			tRoot.CFrame = home * CFrame.new(0,3,0)
			tRoot.Velocity = Vector3.new()
			tRoot.RotVelocity = Vector3.new()
			task.wait(0.03)
		end

		for i = 1, 8 do
			local weld = R_Det:FindFirstChild("RightWeld")
			if weld then
				pcall(function()
					CD:FireServer(weld)
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
			local RS = game:GetService("ReplicatedStorage")
			local RunService = game:GetService("RunService")
			local Players = game:GetService("Players")
			local GE = RS:WaitForChild("GrabEvents")

			local myChar = Player.Character
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myRoot then return end

			local savedPos = myRoot.CFrame

			for _, target in ipairs(Players:GetPlayers()) do
				if target == Player then continue end

				local inPlot = target:FindFirstChild("InPlot")
				if inPlot and inPlot.Value == true then
					continue
				end

				local tChar = target.Character
				local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
				local tHum = tChar and tChar:FindFirstChild("Humanoid")

				if not (tRoot and tHum and tHum.Health > 0) then
					continue
				end

				local dragging = false
				local grabStartTime = 0

				local start = tick()
				while tRoot.Parent and tHum.Health > 0 and tick() - start < 0.9 do
					tRoot.AssemblyLinearVelocity = Vector3.zero
					tRoot.AssemblyAngularVelocity = Vector3.zero
					tRoot.Velocity = Vector3.zero

					if not dragging then
						myRoot.CFrame = tRoot.CFrame
						myRoot.Velocity = Vector3.zero

						pcall(function()
							tHum.PlatformStand = true
							tHum.Sit = true
							GE.SetNetworkOwner:FireServer(tRoot, CFrame.new(myRoot.Position, tRoot.Position))
							GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
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

						tRoot.CFrame = lockPos
						tRoot.Velocity = Vector3.zero
						tRoot.RotVelocity = Vector3.zero

						tHum.PlatformStand = true
						tHum.Sit = false

						pcall(function()
							GE.SetNetworkOwner:FireServer(tRoot, lockPos)
							GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
						end)
					end

					RunService.Heartbeat:Wait()
				end

				pcall(function()
					tHum.PlatformStand = false
					tHum.Sit = false
					GE.DestroyGrabLine:FireServer(tRoot)
				end)

				task.wait(0.15)
			end

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

			local RS = game:GetService("ReplicatedStorage")
			local RunService = game:GetService("RunService")
			local GE = RS:WaitForChild("GrabEvents")

			local myChar = Player.Character
			local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
			if not myRoot then return end

			local tChar = target.Character
			local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
			local tHum = tChar and tChar:FindFirstChild("Humanoid")
			if not (tRoot and tHum and tHum.Health > 0) then return end

			local savedPos = myRoot.CFrame
			local dragging = false
			local grabStartTime = 0

			local start = tick()
			while tRoot.Parent and tHum.Health > 0 and tick() - start < 0.9 do
				tRoot.AssemblyLinearVelocity = Vector3.zero
				tRoot.AssemblyAngularVelocity = Vector3.zero
				tRoot.Velocity = Vector3.zero

				if not dragging then
					myRoot.CFrame = tRoot.CFrame
					myRoot.Velocity = Vector3.zero

					pcall(function()
						tHum.PlatformStand = true
						tHum.Sit = true
						GE.SetNetworkOwner:FireServer(tRoot, CFrame.new(myRoot.Position, tRoot.Position))
						GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
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

					tRoot.CFrame = lockPos
					tRoot.Velocity = Vector3.zero
					tRoot.RotVelocity = Vector3.zero

					tHum.PlatformStand = true
					tHum.Sit = false

					pcall(function()
						GE.SetNetworkOwner:FireServer(tRoot, lockPos)
						GE.CreateGrabLine:FireServer(tRoot, Vector3.zero, tRoot.Position, false)
					end)
				end

				RunService.Heartbeat:Wait()
			end

			pcall(function()
				tHum.PlatformStand = false
				tHum.Sit = false
				GE.DestroyGrabLine:FireServer(tRoot)
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
				local SetNetOwner = game:GetService("ReplicatedStorage").GrabEvents.SetNetworkOwner
				local LocalPlayer = game.Players.LocalPlayer

				local function invis_touch(part, cf)
					SetNetOwner:FireServer(part, cf)
				end

				local function CheckAndYeet(toy)
					local part = toy:FindFirstChild("SoundPart")
					if part then
						invis_touch(part, part.CFrame)
						if part:FindFirstChild("PartOwner") and part.PartOwner.Value == LocalPlayer.Name then
							part.CFrame = CFrame.new(0, 1000, 0)
						end
					end
				end

				while antiAntiKickActive do
					local target = SelectedPlayer
					if target then
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
		SaveManager:Save("AutoSave")
		antiAntiLagEnabled = on

		if not on then
			antiAntiLagEnabled = false
			return
		end

		task.spawn(function()
			local plr = game.Players.LocalPlayer
			local char = plr.Character
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if not hrp then return end

			local burgers = {}

			for _, v in ipairs(workspace:GetDescendants()) do
				if v.Name == "FoodHamburger" and v:IsA("Model") and v:FindFirstChild("HoldPart") then
					burgers[#burgers+1] = v
				end
			end

			workspace.DescendantAdded:Connect(function(obj)
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
						local hp = b.HoldPart

						pcall(function()
							hp.HoldItemRemoteFunction:InvokeServer(b, char)
						end)

						task.wait()

						pcall(function()
							hp.DropItemRemoteFunction:InvokeServer(b, CFrame.new(hrp.Position + Vector3.new(0,-2000,0)), Vector3.new(0,0,0))
						end)
					end
				end

				task.wait()
			end
		end)
	end
})

-- Whitelist System
WhitelistGroup:AddDropdown("MultiWhitelist", {
	Values = getPlayerList(),
	Default = {},
	Multi = true,
	Text = "whitelist people",
})

WhitelistGroup:AddButton({
	Text = "refresh list",
	Func = function()
		Options.MultiWhitelist:SetValues(getPlayerList())
	end
})

-- Joined Notify
local notifyActive = false
local notifyConnection = nil
WhitelistGroup:AddToggle("JoinedNotifyBtn", {
	Text = "Target Joined Notify",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		notifyActive = on

		if on then
			notify("Radar", "Tracking targets. Waiting for targets that have returned / re-entered…", 3)

			if notifyConnection then notifyConnection:Disconnect() end

			notifyConnection = PS.PlayerAdded:Connect(function(newPlayer)
				if not notifyActive then return end

				local detected = false
				local reason = ""

				local whitelistTable = Options.MultiWhitelist.Value
				for nameString, isSelected in pairs(whitelistTable) do
					if isSelected then
						local actualName = nameString:match("%((.-)%)")
						if actualName == newPlayer.Name then
							detected = true
							reason = "[Whitelist]"
							break
						end
					end
				end

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
					SelectedPlayer = newPlayer
					local sound = Instance.new("Sound", workspace)
					sound.SoundId = "rbxassetid://4590662766"
					sound.Volume = 2
					sound:Play()
					game:GetService("Debris"):AddItem(sound, 3)
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
	local whitelistTable = Options.MultiWhitelist.Value

	-- Whitelist check
	for nameString, isSelected in pairs(whitelistTable) do
		if isSelected then
			local actualName = nameString:match("%((.-)%)")
			if actualName == player.Name then
				return true, "[Whitelist]"
			end
		end
	end

	-- Main target check
	if Options.KickPlayerDropdown and Options.KickPlayerDropdown.Value then
		local selectedName = Options.KickPlayerDropdown.Value:match("%((.-)%)")
		if selectedName == player.Name then
			return true, "[Main Target]"
		end
	end

	return false, nil
end

local function trackRespawn(player)
	if respawnConnections[player] then return end

	respawnConnections[player] = player.CharacterAdded:Connect(function()
		if not respawnNotifyActive then return end

		local tracked, reason = isTrackedPlayer(player)
		if not tracked then return end

		notify("Target Respawned! " .. reason .. " | Player: " .. player.Name, 8)
		SelectedPlayer = player

		local sound = Instance.new("Sound")
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
		SaveManager:Save("AutoSave")
		respawnNotifyActive = on

		if on then
			notify("Radar", "Tracking target respawns…", 3)

			-- Hook all current players
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= LocalPlayer then
					trackRespawn(plr)
				end
			end

			-- Hook new players too
			respawnConnections["_PlayerAdded"] = Players.PlayerAdded:Connect(function(plr)
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
		SaveManager:Save("AutoSave")
		deathAuraEnabled = on
		if on then
			task.spawn(function()
				local RS = game:GetService("ReplicatedStorage")
				local PS = game:GetService("Players")
				local GE = RS:WaitForChild("GrabEvents")

				while deathAuraEnabled do
					local myChar = Player.Character
					local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")

					if myRoot then
						-- Find all players within 50 studs
						for _, target in pairs(PS:GetPlayers()) do
							if not deathAuraEnabled then break end
							if target == Player then continue end

							if not target or not target.Parent or not target.Character then
								continue
							end

							local tChar = target.Character
							local tRoot = tChar and tChar:FindFirstChild("HumanoidRootPart")
							local tHum = tChar and tChar:FindFirstChild("Humanoid")

							-- Check if player is within 50 studs and alive
							if tRoot and tHum and tHum.Health > 0 then
								local distance = (myRoot.Position - tRoot.Position).Magnitude

								if distance <= 50 then
									-- Death counter action
									local counterAction = function()
										if tHum then
											CreateSkyVelocity(tRoot)
											for _ = 0, 20 do
												tHum.BreakJointsOnDeath = false
												tHum:ChangeState(Enum.HumanoidStateType.Dead)
												tHum.Jump = true
												tHum.Sit = true
											end
											task.wait()
											GE.DestroyGrabLine:FireServer(tRoot)
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
			strengthConnection = workspace.ChildAdded:Connect(function(model)
				if model.Name == "GrabParts" then
					local partToImpulse = model.GrabPart.WeldConstraint.Part1
					if partToImpulse then
						local velocityObj = Instance.new("BodyVelocity", partToImpulse)
						model:GetPropertyChangedSignal("Parent"):Connect(function()
							if not model.Parent then
								if UserInputService:GetLastInputType() == Enum.UserInputType.MouseButton2 then
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

	noclipConnection = workspace.ChildAdded:Connect(function(v)
		if not noclipGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local grabPart = v:FindFirstChild("GrabPart")
			local weld = grabPart and grabPart:FindFirstChild("WeldConstraint")
			local targetChar = weld and weld.Part1 and weld.Part1.Parent

			if not (grabPart and targetChar and targetChar:IsA("Model")) then
				return
			end

			local parts = {}
			local originalCollision = {}

			for _, d in ipairs(targetChar:GetDescendants()) do
				if d:IsA("BasePart") and not d.Anchored then
					table.insert(parts, d)
					originalCollision[d] = d.CanCollide
				end
			end

			while noclipGrabEnabled and grabPart.Parent do
				for _, part in ipairs(parts) do
					if part and part.Parent and not part.Anchored then
						part.CanCollide = false
					end
				end
				task.wait(0.2)
			end

			for part, state in pairs(originalCollision) do
				if part and part.Parent then
					part.CanCollide = state
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
		SaveManager:Save("AutoSave")
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

	masslessConnection = workspace.ChildAdded:Connect(function(v)
		if not masslessGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local dragPart = v:FindFirstChild("DragPart")
			if not dragPart then return end

			local alignOri = dragPart:FindFirstChild("AlignOrientation")
			local alignPos = dragPart:FindFirstChild("AlignPosition")
			if not (alignOri and alignPos) then return end

			local oriTorque = alignOri.MaxTorque
			local oriOriResp = alignOri.Responsiveness
			local oriForce = alignPos.MaxForce
			local oriPosResp = alignPos.Responsiveness

			while masslessGrabEnabled and v.Parent do
				alignOri.MaxTorque = 1e46
				alignOri.Responsiveness = 20099
				alignPos.MaxForce = 1e51
				alignPos.Responsiveness = 20099
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
		SaveManager:Save("AutoSave")
		masslessGrabEnabled = on
		if on then
			startMasslessGrab()
		else
			stopMasslessGrab()
		end
	end
})

-- Kill Grab
local killGrabEnabled = false
local grabConnection

local function startKillGrab()
	if grabConnection then return end

	grabConnection = workspace.ChildAdded:Connect(function(v)
		if not killGrabEnabled then return end
		if not (v:IsA("Model") and v.Name == "GrabParts") then return end

		task.spawn(function()
			task.wait(0.05)

			local grabPart = v:FindFirstChild("GrabPart")
			local weld = grabPart and grabPart:FindFirstChild("WeldConstraint")
			local targetChar = weld and weld.Part1 and weld.Part1.Parent

			if not (grabPart and targetChar and targetChar ~= Player.Character) then
				return
			end

			local hum = targetChar:FindFirstChildOfClass("Humanoid")
			local root = targetChar:FindFirstChild("HumanoidRootPart")
			local myRoot = Player.Character and Player.Character:FindFirstChild("HumanoidRootPart")

			if not (hum and root and myRoot) then return end

			while killGrabEnabled and grabPart.Parent and hum.Health > 0 do
				pcall(function()
					RS.GrabEvents.SetNetworkOwner:FireServer(root, myRoot.CFrame)
					hum.BreakJointsOnDeath = false
					hum:ChangeState(Enum.HumanoidStateType.Dead)
					hum.Health = 0
					targetChar:BreakJoints()
				end)
				R.Heartbeat:Wait()
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
		SaveManager:Save("AutoSave")
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
local mouse = Player:GetMouse()
local tpToolConn

-- Click TP
MiscGroup:AddToggle("TPToggle", {
	Text = "Click TP (Z)",
	Default = false,
	Callback = function(Value)
		if Value then
			if tpToolConn then tpToolConn:Disconnect() end
			tpToolConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
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

-- Water Walk
local waterParts = {}
task.spawn(function()
	if workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("AlwaysHereTweenedObjects") then
		local oceanModel = workspace.Map.AlwaysHereTweenedObjects.Ocean.Object.ObjectModel
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
		SaveManager:Save("AutoSave")
		for _, item in pairs(waterParts) do
			if item.part then item.part.CanCollide = on end
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
	local success, result = pcall(function() return RS.GamepassEvents.CheckForGamepass:InvokeServer(20837132) end)
	if success and result then Triggerbot.maxDistance = 29.3 end
end)

if RS:FindFirstChild("GamepassEvents") and RS.GamepassEvents:FindFirstChild("FurtherReachBoughtNotifier") then
	RS.GamepassEvents.FurtherReachBoughtNotifier.OnClientEvent:Connect(function() Triggerbot.maxDistance = 29.3 end)
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
	if not model or not model:FindFirstChildOfClass("Humanoid") or model == c then return end

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

	if self.lastTarget then
		self.canGrab = false
		task.spawn(function()
			task.wait(self.preGrabDelay)
			pcall(mouse1press)
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

-- Packet Lag
local PacketSpamAmount = 100
MiscGroup:AddSlider("PacketAmountSlider", {
	Text = "Packet Lag",
	Default = 100,
	Min = 10,
	Max = 100000,
	Rounding = 0,
	Callback = function(Value)
		PacketSpamAmount = Value
	end
})

MiscGroup:AddToggle("PacketLagToggle", {
	Text = "Packet Lag",
	Default = false,
	Callback = function(Value)
		_G.PacketLagActive = Value

		if Value then
			task.spawn(function()
				local localName = game.Players.LocalPlayer.Name
				local RS = game:GetService("ReplicatedStorage")
				local GrabEvent = RS:WaitForChild("GrabEvents"):WaitForChild("ExtendGrabLine")

				while _G.PacketLagActive do
					pcall(function()
						GrabEvent:FireServer(string.rep("Huh what? why? no fuck off what nah blah meh buh whuhhhhh huh what why nah nah what huh meh blah blah buh whuhhhhhhh huh huh what why nah blah meh buh whuhhhhhhh WHAT huh nah why meh blah buh whuhhhhhhh huh huh huh why why nah nah blah blah meh buh whuhhhhhhh buh buh buh whuhhhhhhh huh what nah why meh blah buh whuhhhhhhh huh nah huh nah WHAT meh blah buh whuhhhhhhh huh what huh what nah nah blah meh buh whuhhhhhhh huh huh huh huh nah blah blah meh buh whuhhhhhhh huh what why nah huh meh blah buh whuhhhhhhh huh huh nah what why blah meh buh whuhhhhhhh huh WHAT nah meh blah buh whuhhhhhhh huh huh huh nah nah nah blah meh buh whuhhhhhhh", PacketSpamAmount))
					end)
					task.wait()
				end
			end)
		else
			_G.PacketLagActive = false
		end
	end
})

-- Line Lag
local LineSpam = false
local LineSpamAmount = 100

MiscGroup:AddSlider("LineLagAmount", {
	Text = "Lines / Frame",
	Default = 100,
	Min = 1,
	Max = 10000,
	Rounding = 0,
	Callback = function(val)
		LineSpamAmount = val
	end
})

MiscGroup:AddToggle("LineLag", {
	Text = "Line Lag",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		LineSpam = on
		if not on then return end

		task.spawn(function()
			local RS = game:GetService("ReplicatedStorage")
			local RunService = game:GetService("RunService")
			local Players = game:GetService("Players")
			local GE = RS:WaitForChild("GrabEvents")
			local CreateLine = GE:WaitForChild("CreateGrabLine")

			while LineSpam do
				for _, target in ipairs(Players:GetPlayers()) do
					if not LineSpam then break end
					if target == Player then continue end

					local char = target.Character
					local root = char and char:FindFirstChild("HumanoidRootPart")
					if root then
						for i = 1, LineSpamAmount do
							if not LineSpam then break end
							pcall(function()
								CreateLine:FireServer(root, Vector3.zero, root.Position, false)
							end)
						end
					end
				end

				R.Heartbeat:Wait()
			end
		end)
	end
})

-- Auto Reset
local autoResetEnabled = false
MiscGroup:AddToggle("AutoResetToggle", {
	Text = "Auto Reset",
	Default = false,
		Callback = function(on)
		SaveManager:Save("AutoSave")
		autoResetEnabled = on

		if not on then
			autoResetEnabled = false
			return
		end

		task.spawn(function()
			local plr = game.Players.LocalPlayer
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
		SaveManager:Save("AutoSave")
		Triggerbot.Enabled = value
		if Triggerbot.Enabled and not Triggerbot.Connection then
			Triggerbot.Connection = R.Heartbeat:Connect(function() Triggerbot:OnHeartbeat() end)
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
	Callback = function(value) game.Workspace.CurrentCamera.FieldOfView = value end
})

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
		if name:find(v:lower()) then
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
		if plr ~= LocalPlayer then
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

workspace.ChildAdded:Connect(function(obj)
	task.wait(0.1)
	if isBlackHole(obj) then
		local pos = getBHPosition(obj)
		if not pos then 
			notify("Error", "Black hole position not found!", 3) 
			return 
		end
		local closest = getClosestPlayer(pos)
		notify("Black Hole Alert", closest .. " has been kicked!", 5)
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

		if not targetModel then return end

		if not targetModel.Parent then
			local found = false
			local connection
			connection = targetModel.AncestryChanged:Connect(function(_, parent)
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

		local hl = Instance.new("Highlight")
		hl.Name = "AnchorHighlight"
		hl.FillColor = Color3.fromRGB(0, 85, 255)
		hl.FillTransparency = 0.4
		hl.OutlineColor = Color3.fromRGB(0, 170, 255)
		hl.OutlineTransparency = 0.7
		hl.Adornee = targetModel
		hl.Parent = targetModel

		local connection
		connection = R.Heartbeat:Connect(function()
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

local CreditsGroup = Tabs.Info:AddRightGroupbox("Credits")
local changeLogGroup = Tabs.Info:AddLeftGroupbox("Change Log")

changeLogGroup:AddLabel("Changelog", {
	Text = [[
• New Loop Kill system
• Fixed defenses not working correctly
• Fixed grab not working after respawn when Anti-Lag is enabled
• Added Auras tab + Death Aura
• Fixed inconsistent player WalkSpeed & JumpPower
• Fixed Block Loop Kick
• Plus multiple minor fixes & stability improvements
]],
	DoesWrap = true,
})

CreditsGroup:AddLabel("Credits", {
	Text = [[
• arrivabus415 - Programming
• j_91auratuffboi13 - Programming
• EZTCU4 - Contributing
• 00FSwedish - QA Testing
]],
	DoesWrap = true,
})


-- UI Settings
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu")
MenuGroup:AddButton("Unload", function() Library:Unload() end)
MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", { Default = "M", NoUI = true, Text = "Menu keybind" })
Library.ToggleKeybind = Options.MenuKeybind

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
ThemeManager:SetFolder("ArrivaCoreHub")
SaveManager:SetFolder("ArrivaCoreHub/Configs")
SaveManager:BuildConfigSection(Tabs["UI Settings"])
SaveManager:Load("AutoSave")
ThemeManager:ApplyToTab(Tabs["UI Settings"])
notify("Config file loaded!","Your settings were loaded from the last autosave!"	)



-- Player Events
PS.PlayerRemoving:Connect(function(player)
	notify("Leave Notification", (player and player.Name or "Unknown") .. " Left", 5)
	if plr:IsFriendsWith(Player.UserId) then
		notify("Friend Notification", player.Name .. " left", 5)
	else
		notify("Leave Notification", (player and player.Name or "Unknown") .. " Left", 5)
	end
end)

PS.PlayerAdded:Connect(function(plr)
	if plr:IsFriendsWith(Player.UserId) then
		notify("Friend Notification", plr.Name .. " joined", 5)
	end
end)


task.spawn(function()
	while true do
		task.wait(10)
		pcall(function()
			SaveManager:Save("AutoSave")
		end)
	end
end)



-- Send loaded message
--sendHubLoadedMessage()
