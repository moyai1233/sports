local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local RS = game:GetService("ReplicatedStorage")
local Spawner = {}

function Spawner.createNPCFactory(context)
	local Assets = context.assets
	local C = context.config
	local ClassicHead = context.classicHead
	local setGroup = context.setGroup
	local pick = context.pick

	----------------------------------------------------------------- NPC appearance
	local function richDecorate(model, super)
		model:SetAttribute("Rich", true)
		if super then model:SetAttribute("SuperRich", true) end
		local head = model:FindFirstChild("Head")
		if head then
			local g = Instance.new("BillboardGui"); g.Name = "RichTag"; g.Size = super and UDim2.fromOffset(210, 40) or UDim2.fromOffset(150, 34); g.StudsOffset = Vector3.new(0, super and 4.6 or 3.6, 0)
			g.LightInfluence = 0; g.MaxDistance = 90; g.AlwaysOnTop = false; g.Parent = head
			local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1); l.BackgroundColor3 = Color3.fromRGB(255, 214, 70)
			l.Font = Enum.Font.FredokaOne; l.TextScaled = true; l.Text = super and "👑 SUPER RICH MAN" or "💰 RICH MAN"; l.TextColor3 = Color3.fromRGB(90, 50, 10); l.Parent = g
			if super then
				-- 금발 글자가 흐르는 태그
				l.TextColor3 = Color3.new(1, 1, 1)
				local tg = Instance.new("UIGradient"); tg.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 60)), ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 60)) }); tg.Parent = l
				task.spawn(function() while tg.Parent do tg.Offset = Vector2.new(math.sin(os.clock() * 2.5) * 0.6, 0); task.wait(0.05) end end)
				local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(120, 70, 10); ts.Thickness = 2.2; ts.Parent = l
			end
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = l
			local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(120, 70, 10); st.Thickness = 2.5; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = l
			local gr = Instance.new("UIGradient"); gr.Rotation = 90; gr.Color = ColorSequence.new(Color3.fromRGB(255, 245, 170), Color3.fromRGB(255, 190, 40)); gr.Parent = l
			local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8); p.PaddingTop = UDim.new(0, 3); p.PaddingBottom = UDim.new(0, 3); p.Parent = l
		end
		-- golden sparkles + a warm glow follow him around
		local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
		if torso then
			local sp = Instance.new("ParticleEmitter"); sp.Name = "RichSparkle"
			sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"; sp.Color = ColorSequence.new(Color3.fromRGB(255, 220, 90))
			sp.Size = NumberSequence.new(0.35, 0); sp.Lifetime = NumberRange.new(0.6, 1.1); sp.Rate = 14; sp.Speed = NumberRange.new(0.5, 1.5)
			sp.SpreadAngle = Vector2.new(180, 180); sp.LightEmission = 1; sp.Parent = torso
			local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255, 210, 110); light.Range = 8; light.Brightness = 1.2; light.Parent = torso
			if super then
				sp.Rate = 8; sp.Size = NumberSequence.new(0.35, 0); sp.LightEmission = 0.4; sp.Color = ColorSequence.new(Color3.fromRGB(255, 235, 120), Color3.fromRGB(255, 170, 40))
				light.Range = 6; light.Brightness = 0.5
				-- 금빛 잔상 (걷을 때 뒤로 흐름)
				local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(-0.9, 0.2, 0); a0.Parent = torso
				local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(0.9, 0.2, 0); a1.Parent = torso
				local tr = Instance.new("Trail"); tr.Attachment0 = a0; tr.Attachment1 = a1; tr.Lifetime = 0.7; tr.MinLength = 0.1; tr.LightEmission = 1
				tr.Color = ColorSequence.new(Color3.fromRGB(255, 225, 110), Color3.fromRGB(255, 160, 30)); tr.Transparency = NumberSequence.new(0.8, 1); tr.WidthScale = NumberSequence.new(0.6, 0.1); tr.LightEmission = 0.3; tr.Parent = torso
			end
		end
		if super and head then
			local S = 1.25   -- 격이 다른 체격 (Humanoid 배율로 키움; 액세서리도 같이 커짐)
			local hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				for _, n in ipairs({ "BodyHeightScale", "BodyWidthScale", "BodyDepthScale", "HeadScale" }) do
					local v = hum:FindFirstChild(n); if v then v.Value = v.Value * S end
				end
				hum.WalkSpeed = 8
			end
		end
	end

	local function makeRichNPC(super)
		local src = (super and Assets:FindFirstChild("SuperRichMan")) or Assets:FindFirstChild("RichMan")
		local hd = src and src:FindFirstChildOfClass("HumanoidDescription")
		if not hd then return nil end
		local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(hd:Clone(), Enum.HumanoidRigType.R15) end)
		if ok and model and src.Name == "SuperRichMan" then
			-- 개발자가 넣어둔 슈퍼 리치맨 디자인: 얼굴 + 도미누스 + 황금 지팡이 (모델에서 추출한 액세서리)
			local h = model:FindFirstChildOfClass("Humanoid")
			local faceV = src:FindFirstChild("Face")
			local head = model:FindFirstChild("Head")
			if faceV and head then
				local fd = head:FindFirstChildOfClass("Decal") or Instance.new("Decal")
				fd.Name = "face"; fd.Face = Enum.NormalId.Front; fd.Texture = faceV.Value; fd.Parent = head
			end
			for _, c in ipairs(model:GetChildren()) do
				if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c:Destroy() end
			end
			for _, c in ipairs(src:GetChildren()) do
				if c:IsA("Accessory") then pcall(function() h:AddAccessory(c:Clone()) end)
				elseif c:IsA("Shirt") or c:IsA("Pants") then c:Clone().Parent = model end
			end
			return model
		end
		if not ok or not model then
			-- catalog items didn't load: build from the saved clothes/accessories instead
			ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(Instance.new("HumanoidDescription"), Enum.HumanoidRigType.R15) end)
			if not ok then return nil end
			local h = model:FindFirstChildOfClass("Humanoid")
			for _, c in ipairs(src:GetChildren()) do
				if c:IsA("Accessory") then pcall(function() h:AddAccessory(c:Clone()) end)
				elseif not c:IsA("HumanoidDescription") then c:Clone().Parent = model end
			end
		end
		return model
	end

	local function makeHeadlessNPC()
		local d = Instance.new("HumanoidDescription")
		d.Head = 134082579; d.Torso = 134082557; d.LeftArm = 134082453; d.RightArm = 134082473; d.LeftLeg = 134082507; d.RightLeg = 134082533
		d.HeadColor = Color3.new(0.96, 0.8, 0.19); d.TorsoColor = Color3.new(0.77, 0.16, 0.11)
		d.LeftArmColor = Color3.new(0.64, 0.64, 0.65); d.RightArmColor = Color3.new(0.64, 0.64, 0.65)
		d.LeftLegColor = Color3.new(0.84, 0.77, 0.6); d.RightLegColor = Color3.new(0.84, 0.77, 0.6)
		d.Face = 0
		local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15) end)
		if not ok or not model then return nil end
		local head = model:FindFirstChild("Head")
		if head then head.Transparency = 1; for _, x in ipairs(head:GetChildren()) do if x:IsA("Decal") then x:Destroy() end end end
		-- 손에 불타는 호박
		local hand = model:FindFirstChild("RightHand")
		local src = RS:FindFirstChild("ItemModels") and RS.ItemModels:FindFirstChild("headless") and RS.ItemModels.headless:FindFirstChild("Pumpkin")
		if hand and src then
			local pk = src:Clone(); pk.Name = "HeldPumpkin"
			pk.Size = pk.Size * (1.5 / math.max(pk.Size.X, pk.Size.Y, pk.Size.Z))
			pk.Anchored = false; pk.CanCollide = false; pk.CanTouch = false; pk.CanQuery = false; pk.Massless = true
			pk.CFrame = hand.CFrame * CFrame.new(0, -0.55, -0.35)
			local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = pk; w.Parent = pk
			pk.Parent = model
		end
		model:SetAttribute("Headless", true)
		-- 이름표 + 주황 불꽃
		local tagAt = model:FindFirstChild("UpperTorso") or head
		if tagAt then
			local g = Instance.new("BillboardGui"); g.Name = "RichTag"; g.Size = UDim2.fromOffset(160, 34); g.StudsOffset = Vector3.new(0, 4, 0)
			g.LightInfluence = 0; g.MaxDistance = 90; g.Parent = tagAt
			local l = Instance.new("TextLabel"); l.Size = UDim2.fromScale(1, 1); l.BackgroundColor3 = Color3.fromRGB(255, 140, 40)
			l.Font = Enum.Font.FredokaOne; l.TextScaled = true; l.Text = "🎃 HEADLESS"; l.TextColor3 = Color3.new(1, 1, 1); l.Parent = g
			local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.5, 0); c.Parent = l
			local st = Instance.new("UIStroke"); st.Color = Color3.fromRGB(70, 20, 60); st.Thickness = 2.5; st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border; st.Parent = l
			local ts = Instance.new("UIStroke"); ts.Color = Color3.fromRGB(70, 20, 60); ts.Thickness = 2; ts.Parent = l
			local gr = Instance.new("UIGradient"); gr.Rotation = 90; gr.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(230, 90, 20)); gr.Parent = l
			local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0, 8); p.PaddingRight = UDim.new(0, 8); p.PaddingTop = UDim.new(0, 3); p.PaddingBottom = UDim.new(0, 3); p.Parent = l
			local sp = Instance.new("ParticleEmitter"); sp.Name = "RichSparkle"
			sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"; sp.Color = ColorSequence.new(Color3.fromRGB(255, 140, 40), Color3.fromRGB(160, 80, 230))
			sp.Size = NumberSequence.new(0.35, 0); sp.Lifetime = NumberRange.new(0.6, 1.1); sp.Rate = 12; sp.Speed = NumberRange.new(0.5, 1.5)
			sp.SpreadAngle = Vector2.new(180, 180); sp.LightEmission = 1; sp.Parent = tagAt
			local light = Instance.new("PointLight"); light.Color = Color3.fromRGB(255, 140, 50); light.Range = 9; light.Brightness = 1.3; light.Parent = tagAt
		end
		return model
	end

	local function makeNPC(rich, headless)
		if headless then
			local model = makeHeadlessNPC()
			if model then
				local anim = model:FindFirstChild("Animate"); if anim then anim:Destroy() end
				Assets.NPCAnimate:Clone().Parent = model
				model.Name = "Customer"
				local hum = model:FindFirstChildOfClass("Humanoid")
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.BreakJointsOnDeath = false
				hum.MaxHealth = math.huge; hum.Health = math.huge
				hum.RequiresNeck = false
				hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
				hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
				setGroup(model, "Customers")
				return model, hum
			end
		end
		if rich then
			local model = makeRichNPC(rich == "super")
			if model then
				local anim = model:FindFirstChild("Animate"); if anim then anim:Destroy() end
				Assets.NPCAnimate:Clone().Parent = model
				model.Name = "Customer"
				for _, acc in ipairs(model:GetChildren()) do
					if acc:IsA("Accessory") then
						for _, p in ipairs(acc:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.Massless = true end end
					end
				end
				local hum = model:FindFirstChildOfClass("Humanoid")
				hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				hum.WalkSpeed = 9                                     -- strolls in like he owns the place
				hum.BreakJointsOnDeath = false
				hum.MaxHealth = math.huge; hum.Health = math.huge
				hum.RequiresNeck = false
				hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
				hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
				richDecorate(model, rich == "super")
				ClassicHead.apply(model)   -- (11/19) 새 기본 머리에 얼굴 스티커가 늘어나 찍히는 문제
				setGroup(model, "Customers")
				return model, hum
			end
		end
		local d = Instance.new("HumanoidDescription")
		local outfit = (#C.Outfits > 0 and math.random() < 0.7) and pick(C.Outfits) or nil
		local skin, shirt, pants = pick(C.SkinTones), pick(C.ShirtColors), pick(C.PantsColors)
		d.HeadColor = skin; d.LeftArmColor = shirt; d.RightArmColor = shirt; d.TorsoColor = shirt
		d.LeftLegColor = pants; d.RightLegColor = pants
		if outfit then
			d.Shirt = outfit.Shirt or 0; d.Pants = outfit.Pants or 0; d.HairAccessory = outfit.Hair or ""; d.Face = outfit.Face or 0
			d.LeftArmColor = skin; d.RightArmColor = skin
		end
		-- 대부분의 손님은 npc 팩(ServerStorage.CustomerAssets.Looks)의 옷차림을 입는다
		local looks = Assets:FindFirstChild("Looks")
		local look = looks and #looks:GetChildren() > 0 and pick(looks:GetChildren()) or nil
		if look then
			d.Shirt = 0; d.Pants = 0; d.HairAccessory = ""; d.Face = 0
			d.HeadColor = look:GetAttribute("Head") or skin; d.TorsoColor = look:GetAttribute("Torso") or shirt
			d.LeftArmColor = look:GetAttribute("LeftArm") or skin; d.RightArmColor = look:GetAttribute("RightArm") or skin
			d.LeftLegColor = look:GetAttribute("LeftLeg") or pants; d.RightLegColor = look:GetAttribute("RightLeg") or pants
		end
		local ok, model = pcall(function() return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15) end)
		if not ok then return nil end
		if look then
			local h = model:FindFirstChildOfClass("Humanoid")
			for _, c in ipairs(look:GetChildren()) do
				if c:IsA("Accessory") then
					local acc = c:Clone()
					local okA = pcall(function() h:AddAccessory(acc) end)
					if not okA then acc:Destroy() end
				else
					c:Clone().Parent = model
				end
			end
			for _, acc in ipairs(model:GetChildren()) do
				if acc:IsA("Accessory") then
					for _, p in ipairs(acc:GetDescendants()) do
						if p:IsA("BasePart") then p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.Massless = true; p.Anchored = false end
					end
				end
			end
			local face = look:GetAttribute("Face")
			local head = model:FindFirstChild("Head")
			if face and head then
				local dec = head:FindFirstChild("face") or head:FindFirstChildOfClass("Decal") or Instance.new("Decal")
				dec.Name = "face"; dec.Face = Enum.NormalId.Front; dec.Texture = face; dec.Parent = head
				if head:IsA("MeshPart") then head.TextureID = "" end   -- (11/19) 새 기본 머리에 그려진 얼굴과 겹치지 않게
			end
		end
		local anim = model:FindFirstChild("Animate"); if anim then anim:Destroy() end
		Assets.NPCAnimate:Clone().Parent = model
		model.Name = "Customer"
		local hum = model:FindFirstChildOfClass("Humanoid")
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.WalkSpeed = 10 + math.random() * 3
		hum.BreakJointsOnDeath = false
		hum.MaxHealth = math.huge; hum.Health = math.huge
		hum.RequiresNeck = false
		hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
		hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
		ClassicHead.apply(model)   -- (11/19) 새 기본 머리에 얼굴 스티커가 늘어나 찍히는 문제 → 클래식 머리로 얼굴 표시
		setGroup(model, "Customers")
		return model, hum
	end

	-- 다른 서버 스크립트(탕후루 부스)가 같은 손님 외형을 쓰도록: ServerStorage.MakeNPC:Invoke() -> Model
	do
		local bf = SS:FindFirstChild("MakeNPC") or Instance.new("BindableFunction"); bf.Name = "MakeNPC"; bf.Parent = SS
		bf.OnInvoke = function(rich) local m = makeNPC(rich == true, false); return m end   -- rich = 탕후루 부스 RICH MAN (미슐랭 탕후루)
	end
	return makeNPC
end

function Spawner.start(context)
	local npc = context.customers
	local makeNPC = context.makeNPC
	local C = context.config
	local RushCfg = context.rushConfig
	local REGISTERS = context.registers
	local SPAWNS = context.spawnPoints
	local Y = context.groundY
	local DOOR_IN = context.doorIn
	local DOOR_OUT = context.doorOut
	local Assets = context.assets
	local folder = context.folder
	local dirtyFolder = context.dirtyFolder
	local fxFolder = context.fxFolder
	local announceRE = context.announce
	local workRE = context.workEvent
	local tickets = context.tickets
	local stations = context.kitchen
	local serving = context.serving
	local Money = context.money
	local Rank = context.rank
	local bubble = context.bubble
	local pick = context.pick
	local weighted = context.weighted
	local rushOn = context.rushOn
	local spawnFloorSpill = context.spawnFloorSpill
	local refreshBoard = context.refreshBoard
	local near = context.near
	local notify = context.notify
	local sfx = context.sfx
	local placeOnTable = context.placeOnTable

	----------------------------------------------------------------- spawner
	local function richInside()
		for c in pairs(npc.active) do if c.rich and c.alive then return true end end
		return false
	end
	local function superInside()   -- 👑 SUPER RICH MAN은 한 번에 1명
		for c in pairs(npc.active) do if c.superRich and c.alive then return true end end
		return false
	end
	----------------------------------------------------------------- Rich Man arrives by car (out of the tunnel, drops him at the shop front)
	local richCarBusy = false     -- true while any Rich Man car is queued or driving
	local richCars = 0
	local arriveByCar
	do
		-- the car's motion follows ReplicatedStorage.RichCarPath; every client draws it locally (RichCarClient) so it stays smooth
		-- with lag. The server only keeps the clock: it drops the Rich Man at DROP_T and removes the car at END_T.
		local Path = require(RS:WaitForChild("RichCarPath"))
		local queue, driving = {}, false
		local startNext
		local function runCar(onDrop)
			local tpl = Assets:FindFirstChild("RichCar")
			if not tpl then onDrop(nil); startNext(); return end
			local released = false
			local function release() if not released then released = true; startNext() end end
			local ok, err = pcall(function()
				local car = tpl:Clone()
				local t0 = workspace:GetServerTimeNow()
				car:SetAttribute("T0", t0)
				car:PivotTo(Path.cframe(0))
				-- StreamingEnabled: 서버에선 차가 터널 입구(멀리)에 서 있고 클라이언트가 직접 움직여서,
				--   기본 설정이면 가까운 부품만 내려받아 차가 깨져 보임 → 차 전체를 항상 한 번에 보냄
				pcall(function() car.ModelStreamingMode = Enum.ModelStreamingMode.Persistent end)
				car.Parent = fxFolder
				local function waitUntil(t) local d = t0 + t - workspace:GetServerTimeNow(); if d > 0 then task.wait(d) end end
				waitUntil(Path.DOOR_OPEN)
				local snd = car.Misc.RDoor:FindFirstChild("DoorOpen", true); if snd then snd:Play() end
				waitUntil(Path.DROP_T)
				local drop = (Path.cframe(Path.DROP_T) * Path.DROP_OFFSET).Position
				onDrop(Vector3.new(drop.X, Y, drop.Z))
				release()                                   -- the next car can leave the tunnel now
				waitUntil(Path.DOOR_CLOSE)
				local snd2 = car.Misc.RDoor:FindFirstChild("DoorClose", true); if snd2 then snd2:Play() end
				waitUntil(Path.END_T)
				car:Destroy()
			end)
			if not ok then warn("[RichCar]", err) end
			release()
			richCars -= 1
			richCarBusy = richCars > 0
		end
		startNext = function()
			local cb = table.remove(queue, 1)
			if not cb then driving = false; return end
			driving = true
			task.spawn(runCar, cb)
		end
		arriveByCar = function(onDrop)
			richCars += 1; richCarBusy = true
			table.insert(queue, onDrop)
			if not driving then startNext() end
			return #queue
		end
	end

	local function spawnCustomer(group, at, startDelay, rich, headless, witch, tutReg)
		local model, hum = makeNPC(rich, headless)
		if not model then return end
		if witch then model:SetAttribute("Witch", true) end   -- 🧙 할로윈 마녀 손님 (HalloweenCostumes가 분장 + 황금 호박)
		local root = model:FindFirstChild("HumanoidRootPart")
		local jitter = (rich and at) and Vector3.zero or Vector3.new(math.random(-3, 3), 0, math.random(-2, 2))   -- the Rich Man steps out right at the car door
		model:PivotTo(CFrame.new((at or pick(SPAWNS)) + jitter))
		model.Parent = folder
		pcall(function() root:SetNetworkOwner(nil) end)
		local c = { model = model, hum = hum, root = root, alive = true, group = group, rich = rich and model:GetAttribute("Rich") == true or nil, headless = headless and model:GetAttribute("Headless") == true or nil, witch = witch or nil,
			superRich = (rich == "super" and model:GetAttribute("SuperRich") == true) or nil }
		if group then table.insert(group.members, c); hum.WalkSpeed = group.speed end
		c.tutReg = tutReg   -- (11/19) 튜토리얼 손님
		c.bubble = bubble(model)
		npc.active[c] = true
		hum.Died:Connect(function() npc.despawn(c) end)
		model.AncestryChanged:Connect(function() if not model:IsDescendantOf(workspace) then npc.despawn(c) end end)
		task.spawn(function()
			local last, still = root.Position, 0
			while c.alive do
				task.wait(2)
				if not root.Parent or root.Position.Y < -30 then npc.despawn(c) return end
				-- 쟁반·분장 등 부품이 붙으면 로블록스가 움직임 계산을 근처 플레이어에게 넘겨버림 → 서버로 되돌림 (뚝뚝 끊김 방지)
				pcall(function() if root:GetNetworkOwner() ~= nil then root:SetNetworkOwner(nil) end end)
				local moved = (root.Position - last).Magnitude > 1
				last = root.Position
				-- standing in line / sitting / eating is fine; walking without moving for 30s is not
				if moved or c.seatRec or c.waitStage or c.queueReg then still = 0 else still += 2 end
				if still >= 30 then npc.despawn(c) return end
			end
		end)
		task.spawn(function()
			if startDelay and startDelay > 0 then task.wait(startDelay) end
			if not c.alive then return end
			local ok, err = pcall(npc.run, c)
			if not ok then warn("[CustomerService]", err); npc.despawn(c) end
		end)
		-- safety: nobody stays forever
		task.delay(C.PatienceOrder + C.PatienceFood + C.EatTime + 180 + (group and 270 or 0), function() if c.alive then npc.despawn(c) end end)
	end

	-- admin panel: "리치맨 부르기"
	do
		local bf = SS:FindFirstChild("SummonRich") or Instance.new("BindableFunction")
		bf.Name = "SummonRich"; bf.Parent = SS
		local MAX_RICH = 16
		local function richCount() local n = 0; for c in pairs(npc.active) do if c.rich then n += 1 end end; return n + richCars end
		bf.OnInvoke = function(kind)
			if kind == "super" then
				if superInside() then return false, "SUPER RICH MAN이 이미 가게에 있어요" end
				if richCount() >= MAX_RICH then return false, string.format("리치맨이 너무 많아요 (최대 %d명)", MAX_RICH) end
				local waiting = arriveByCar(function(dropAt) spawnCustomer(nil, dropAt or pick(SPAWNS), 0, "super") end)
				return true, waiting > 0 and string.format("👑 SUPER RICH MAN을 불렀어요! (앞에 차 %d대 대기 중)", waiting) or "👑 SUPER RICH MAN을 불렀어요! 터널에서 차가 출발해요"
			end
			if richCount() >= MAX_RICH then return false, string.format("리치맨이 너무 많아요 (최대 %d명)", MAX_RICH) end
			local waiting = arriveByCar(function(dropAt) spawnCustomer(nil, dropAt or pick(SPAWNS), 0, true) end)
			return true, waiting > 0 and string.format("리치맨을 불렀어요! (앞에 차 %d대 대기 중)", waiting) or "리치맨을 불렀어요! 터널에서 차가 출발해요"
		end

		-- 30s Rich Man event: everyone else vanishes, only Rich Men come in (by car and on foot)
		local ev = SS:FindFirstChild("RichEvent") or Instance.new("BindableFunction")
		ev.Name = "RichEvent"; ev.Parent = SS
		local EVENT_TIME = 30
		ev.OnInvoke = function()
			if os.clock() < npc.richEventUntil then return false, string.format("이벤트 진행 중 (%d초 남음)", math.ceil(npc.richEventUntil - os.clock())) end
			npc.richEventUntil = os.clock() + EVENT_TIME
			-- clear out the regular customers (players' own orders are untouched)
			local gone = {}
			for c in pairs(npc.active) do if not c.rich then table.insert(gone, c) end end
			for _, c in ipairs(gone) do
				if c.root and c.root.Parent then
					local puff = Instance.new("Part"); puff.Anchored = true; puff.CanCollide = false; puff.CanQuery = false; puff.Transparency = 1
					puff.Size = Vector3.new(1, 1, 1); puff.Position = c.root.Position; puff.Parent = fxFolder
					local pe = Instance.new("ParticleEmitter"); pe.Texture = "rbxasset://textures/particles/smoke_main.dds"; pe.Rate = 0
					pe.Lifetime = NumberRange.new(0.5, 0.8); pe.Speed = NumberRange.new(2, 4); pe.SpreadAngle = Vector2.new(180, 180)
					pe.Size = NumberSequence.new(1.5, 3); pe.Transparency = NumberSequence.new(0.2, 1); pe.Parent = puff
					pe:Emit(14); game:GetService("Debris"):AddItem(puff, 1.5)
				end
				npc.despawn(c)
			end
			if announceRE then
				announceRE:FireAllClients({ kind = "rich", title = "RICH MAN 이벤트!", text = string.format("%d초 동안 Rich Man만 와요! 서둘러 응대하세요!", EVENT_TIME) })
			end
			task.spawn(function()
				-- two limousine runs + a steady stream walking in from the sidewalks
				for _ = 1, 2 do arriveByCar(function(dropAt) spawnCustomer(nil, dropAt or pick(SPAWNS), 0, true) end) end
				while os.clock() < npc.richEventUntil do
					if richCount() < MAX_RICH then spawnCustomer(nil, pick(SPAWNS), 0, true) end
					task.wait(3)
				end
			end)
			return true, string.format("리치맨 이벤트 시작! (%d초, 기존 손님 %d명 퇴장)", EVENT_TIME, #gone)
		end
	end

	-- 헤드리스맨 손님 (할로윈 이벤트 동안, 한 번에 1명)
	local HEADLESS_CHANCE = 0.06
	local HEADLESS_ENABLED = false   -- 할로윈 끝 (2026-11-02): 헤드리스맨·마녀 손님 안 나옴
	local function headlessEventOn()
		if not HEADLESS_ENABLED then return false end
		local okI, Items = pcall(require, RS:WaitForChild("ItemConfig"))
		local g = okI and Items.GachaById and Items.GachaById.limited
		return g ~= nil and Items.isOpen(g)
	end
	local function headlessInside()
		for c in pairs(npc.active) do if (c.headless or c.witch) and c.alive then return true end end
		return false
	end
	do
		local bf = SS:FindFirstChild("SummonHeadless") or Instance.new("BindableFunction")
		bf.Name = "SummonHeadless"; bf.Parent = SS
		bf.OnInvoke = function() spawnCustomer(nil, pick(SPAWNS), 0, false, false, true); return true, "마녀 호출" end   -- (헤드리스맨 → 마녀로 교체)
	end
	-- 관리자 패널: 손님 소환 / 모두 내보내기 / 바닥 청소 / 수 세기
	do
		local bf = SS:FindFirstChild("AdminCustomers") or Instance.new("BindableFunction")
		bf.Name = "AdminCustomers"; bf.Parent = SS
		bf.OnInvoke = function(action, n)
			if action == "spawn" then
				n = math.floor(tonumber(n) or 1); if n ~= n then n = 1 end
				n = math.clamp(n, 1, 10)
				for i = 1, n do task.delay((i - 1) * 0.6, function() spawnCustomer(nil, pick(SPAWNS), 0) end) end
				return true, "손님 " .. n .. "명 소환"
			elseif action == "clear" then
				local gone = {}
				for c in pairs(npc.active) do table.insert(gone, c) end
				for _, c in ipairs(gone) do pcall(npc.despawn, c) end
				return true, "손님 " .. #gone .. "명 내보냄"
			elseif action == "clean" then
				local k = 0
				for _, m in ipairs(dirtyFolder:GetChildren()) do if m.Name == "FloorSpill" then m:Destroy(); k += 1 end end
				return true, "바닥 얼룩 " .. k .. "개 청소"
			elseif action == "count" then
				return npc.count()
			end
			return false, "?"
		end
	end
	task.spawn(function()
		while true do
			-- 사람이 많을수록 손님이 더 자주 옴
			local np = #Players:GetPlayers()
			local speed = math.max(C.SpawnSpeedMin or 1, 1 - (C.SpawnSpeedPerPlayer or 0) * math.max(0, np - 1))
			if rushOn() then speed *= RushCfg.SpawnMult end
			task.wait((C.SpawnInterval[1] + math.random() * (C.SpawnInterval[2] - C.SpawnInterval[1])) * speed)
			if os.clock() < npc.richEventUntil then continue end
			local players = #Players:GetPlayers()
			local cap = math.min(C.MaxCustomers, C.BaseCustomers + C.PerPlayer * players)
			-- 러시아워: 사람 수와 상관없이 서버 최대치까지 계속 옴 (자리·렉 때문에 상한만 둠)
			if rushOn() then cap = RushCfg.MaxCustomers end
			local room = cap - npc.count()
			-- 계산대 줄이 다 차고 기다리는 손님까지 있으면 새 손님은 잠시 보류 (와서 바로 나가는 것 방지)
			local freeLine = 0
			for _, rg in ipairs(REGISTERS) do freeLine += math.max(0, #rg.queue - #rg.line) end
			if freeLine - npc.lineWaiting <= -2 then room = 0 end
			if players > 0 and room > 0 then
				local n = weighted(C.GroupSizes or { 1 }, C.GroupWeights or { 1 })
				while n > room and n > 1 do n = (n >= 4) and 2 or 1 end
				local at = pick(SPAWNS)
				-- 리치맨 러시아워: 리치맨이 자주, 여러 명 동시에 (걸어서 바로 입장)
				local richRush = rushOn() and workspace:GetAttribute("RushRich") == true
				local richNow = 0
				if richRush then for cc in pairs(npc.active) do if cc.rich and cc.alive then richNow += 1 end end end
				if richRush then
					-- 리치맨 러시아워: 리치맨만 옴
					if richNow < RushCfg.RichMax then spawnCustomer(nil, at, 0, true) end
				elseif math.random() < (C.SuperRichChance or 0) and not superInside() and not richInside() and not richCarBusy then
					-- 👑 SUPER RICH MAN: 한 번에 1명, 리무진으로 도착 → 2층 VIP 라운지
					task.spawn(arriveByCar, function(dropAt) spawnCustomer(nil, dropAt or at, 0, "super") end)
				elseif math.random() < HEADLESS_CHANCE and headlessEventOn() and not headlessInside() then
					spawnCustomer(nil, at, 0, false, false, true)   -- 헤드리스맨 대신 마녀
				elseif math.random() < (C.RichChance or 0) and not richInside() and not richCarBusy then
					-- Rich Man always comes alone, chauffeured out of the tunnel to the front door
					task.spawn(arriveByCar, function(dropAt) spawnCustomer(nil, dropAt or at, 0, true) end)
				else
					local g = n > 1 and { size = n, members = {}, speed = 10 + math.random() * 2 } or nil
					for i = 1, n do spawnCustomer(g, at, (i - 1) * 0.9) end
				end
			end
		end
	end)
	refreshBoard()

	-- (11/19) 튜토리얼 도우미: 손님 기다리다 지쳐 나가지 않게
	--   "customer": 계산대 가까이 왔는데 줄이 비었으면 그 계산대 바로 앞에 손님 1명 (재료 바 건너뜀, 인내심 3배)
	--   "mess": 플레이어 바로 옆 바닥에 얼룩 1개 (빗자루로 바로 청소 연습)
	--   튜토리얼 중인 플레이어만, 같은 요청 8초에 한 번, 튜토리얼 손님은 동시에 1명
	do
		local remotesF = game:GetService("ReplicatedStorage"):WaitForChild("Remotes")
		local helpRF = remotesF:FindFirstChild("TutorialHelp") or Instance.new("RemoteFunction")
		helpRF.Name = "TutorialHelp"; helpRF.Parent = remotesF
		local lastAsk = {}
		local used = {}        -- 접속당 사용 횟수 (손님 5, 쓰레기 3)
		local tutSpill = {}    -- 지금 깔려 있는 튜토리얼 쓰레기 (한 번에 1개)
		local LIMIT = { customer = 5, mess = 3 }
		Players.PlayerRemoving:Connect(function(p) lastAsk[p] = nil; used[p] = nil; tutSpill[p] = nil end)
		helpRF.OnServerInvoke = function(plr, kind)
			if plr:GetAttribute("TutorialDone") ~= false then return false end
			local ch = plr.Character; local root = ch and ch:FindFirstChild("HumanoidRootPart")
			if not root then return false end
			kind = tostring(kind)
			local now = os.clock()
			lastAsk[plr] = lastAsk[plr] or {}
			if lastAsk[plr][kind] and now - lastAsk[plr][kind] < 8 then return false end
			used[plr] = used[plr] or {}
			if not LIMIT[kind] or (used[plr][kind] or 0) >= LIMIT[kind] then return false end
			if kind == "customer" then
				local best, bd
				for _, r in ipairs(REGISTERS) do
					local d = (root.Position - r.posModel:GetPivot().Position).Magnitude
					if not bd or d < bd then best, bd = r, d end
				end
				if not best or bd > 14 then return false end
				if #best.line > 0 then return false end
				for c in pairs(npc.active) do if c.tutReg and c.alive then return false end end
				lastAsk[plr][kind] = now
				used[plr].customer = (used[plr].customer or 0) + 1
				spawnCustomer(nil, best.queue[2] or best.front, 0, false, false, false, best)
				return true
			elseif kind == "mess" then
				if tutSpill[plr] and tutSpill[plr].Parent then return false end
				local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
				local ignore = { folder, dirtyFolder, fxFolder }
				for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
				rp.FilterDescendantsInstances = ignore
				local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
				local right = root.CFrame.RightVector * Vector3.new(1, 0, 1)
				for _, off in ipairs({ look * 3 + right * 1.5, right * 3, -right * 3, look * 3 - right * 1.5, -look * 3 }) do
					local hit = workspace:Raycast(root.Position + off + Vector3.new(0, 1, 0), Vector3.new(0, -8, 0), rp)
					if hit and hit.Normal.Y > 0.9 and not hit.Instance:IsA("Seat") and math.abs(hit.Position.Y - (root.Position.Y - 3)) < 1.5 then
						lastAsk[plr][kind] = now
						used[plr].mess = (used[plr].mess or 0) + 1
						spawnFloorSpill(hit.Position)
						for _, m in ipairs(dirtyFolder:GetChildren()) do
							if m.Name == "FloorSpill" and m.PrimaryPart and (m.PrimaryPart.Position - hit.Position).Magnitude < 0.6 then tutSpill[plr] = m end
						end
						return true
					end
				end
				return false
			end
			return false
		end
	end
	----------------------------------------------------------------- (11/21) 🦹 도둑 이벤트
	--   9~12분마다 (패스대에 완성 그릇이 있을 때) 도둑이 길에서 들어와 직원 구역 게이트로 들어가 그릇 하나를 들고 도망
	--   그릇 든 도둑에게 다가가 E(모바일은 터치) 「체포하기」 → 3,000원 + XP 60, 그릇은 패스대로. 놓치면 그 주문만 다시 조리 목록으로 (유저 돈은 안 뺏음)
	--   메인 청크 local 개수 한도(200) 때문에 전부 함수 안에 둠
	--   Studio 테스트: ServerStorage.ThiefTest:Invoke("go") / ("state")
	task.spawn(function()
		local Players = game:GetService("Players")
		local TweenS = game:GetService("TweenService")
		local INTERVAL = { 540, 720 }
		local APPROACH_SPEED, FLEE_SPEED = 11, 11.5
		local REWARD_MONEY, REWARD_XP = 3000, 60
		local PASS_FRONT_Z = 31.5                  -- 패스대 앞 (직원 쪽). 직원 구역 게이트(x -18)는 길찾기가 알아서 지나감
		local thiefFolder = workspace:FindFirstChild("Thieves") or Instance.new("Folder")
		thiefFolder.Name = "Thieves"; thiefFolder.Parent = workspace
		local active = nil
		local lastState = "idle"

		local function announce(icon, title, text)
			if announceRE then announceRE:FireAllClients({ kind = "rich", icon = icon, title = title, text = text }) end
		end
		local function notifyAll(msg) for _, p in ipairs(Players:GetPlayers()) do notify(p, msg) end end

		local function readyOnPass()
			local list = {}
			for i in ipairs(stations.passSlots) do
				local t = stations.occupied[i]
				if type(t) == "table" and t.state == "ready" and t.slot == i and not t.cancelled and tickets:get(t.id) == t and t.bowl and t.bowl.Parent and t.bowl.PrimaryPart then
					table.insert(list, t)
				end
			end
			return list
		end

		local function weldTo(a, b)
			local w = Instance.new("WeldConstraint"); w.Name = "CarryWeld"; w.Part0 = a; w.Part1 = b; w.Parent = b
			return w
		end

		local function dress(model)
			for _, d in ipairs(model:GetChildren()) do
				if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("Accessory") then d:Destroy() end
			end
			local dark, black = Color3.fromRGB(48, 48, 58), Color3.fromRGB(22, 22, 26)
			for _, p in ipairs(model:GetChildren()) do
				if p:IsA("BasePart") then
					local n = p.Name
					if n:find("Torso") or n:find("Arm") or n:find("Hand") then p.Color = dark
					elseif n:find("Leg") or n:find("Foot") then p.Color = black end
				end
			end
			local head = model:FindFirstChild("ClassicHead") or model:FindFirstChild("Head")
			if head then
				-- (11/21) 진짜 아바타 아이템: 비니 + 스키 마스크 (ServerStorage.CustomerAssets.ThiefGear, 스크립트 제거본)
				local gearF = Assets:FindFirstChild("ThiefGear")
				local hum = model:FindFirstChildOfClass("Humanoid")
				if gearF and hum then
					for _, g in ipairs(gearF:GetChildren()) do
						if g:IsA("Accessory") then pcall(function() hum:AddAccessory(g:Clone()) end) end
					end
					for _, d in ipairs(model:GetDescendants()) do
						if d:IsA("BasePart") and d.Parent and d.Parent:IsA("Accessory") then d.CanCollide = false; d.CanQuery = false; d.CanTouch = false; d.Massless = true end
					end
				end
				local bb = Instance.new("BillboardGui"); bb.Name = "ThiefTag"; bb.Size = UDim2.fromOffset(150, 46); bb.StudsOffset = Vector3.new(0, 3, 0)
				bb.AlwaysOnTop = true; bb.MaxDistance = 140; bb.LightInfluence = 0; bb.Parent = head
				local t = Instance.new("TextLabel"); t.Name = "Label"; t.BackgroundColor3 = Color3.fromRGB(200, 30, 30); t.BackgroundTransparency = 0.1
				t.Size = UDim2.fromScale(1, 1); t.Font = Enum.Font.FredokaOne; t.TextScaled = true; t.TextColor3 = Color3.new(1, 1, 1); t.Text = "🦹 도둑"; t.Parent = bb
				local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0.3, 0); tc.Parent = t
				local ts = Instance.new("UIStroke"); ts.Thickness = 2; ts.Color = Color3.fromRGB(90, 0, 0); ts.Parent = t
			end
			local hl = Instance.new("Highlight"); hl.Name = "ThiefHL"; hl.FillTransparency = 1; hl.OutlineColor = Color3.fromRGB(255, 50, 50)
			hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Parent = model
			model.Name = "Thief"
		end

		local function setTag(c, text)
			local head = c.model:FindFirstChild("ClassicHead") or c.model:FindFirstChild("Head")
			local bb = head and head:FindFirstChild("ThiefTag")
			if bb and bb:FindFirstChild("Label") then bb.Label.Text = text end
		end

		local function vanish(c, delayT)
			c.alive = false
			local model = c.model
			task.delay(delayT or 0, function()
				if not model.Parent then return end
				pcall(function() sfx("Wrong", c.root, 0.25, 40) end)
				for _, p in ipairs(model:GetDescendants()) do
					if p:IsA("BasePart") and p.Transparency < 1 then TweenS:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
				end
				task.wait(0.7)
				model:Destroy()
			end)
		end

		-- 훔친 그릇을 패스대로 (자리 없으면 다시 조리)
		local function lose(t, escaped)
			if t.bowl then pcall(function() t.bowl:Destroy() end); t.bowl = nil end
			if tickets:get(t.id) ~= t or t.cancelled then return end
			tickets:setState(t, "ordered"); t.cookedSpice = nil; t.correct = nil; t.skull = nil; t.thief = nil
			refreshBoard()
			if escaped then notifyAll(string.format("🦹 도둑이 #%d 그릇을 들고 도망쳤어요... 다시 조리해 주세요", t.id)) end
		end
		local function giveBack(t)
			if not t or t.state ~= "stolen" then return end
			if tickets:get(t.id) ~= t or t.cancelled or not (t.bowl and t.bowl.Parent and t.bowl.PrimaryPart) then
				if t.bowl then pcall(function() t.bowl:Destroy() end); t.bowl = nil end
				return
			end
			local slot = stations:freePassSlot()
			if not slot then lose(t, false); return end
			stations:returnBowl(t, slot, placeOnTable)
			t.thief = nil
			serving:makePickup(t)
			refreshBoard()
		end

		local function caughtBy(c, p)
			if c.caught then return end
			c.caught = p; c.fleeing = false
			c.alive = false
			pcall(function() c.hum.WalkSpeed = 0; c.hum:MoveTo(c.root.Position) end)
			lastState = "caught by " .. p.Name
			giveBack(c.t)
			pcall(function()
				local xpShown = math.floor(REWARD_XP * (p:GetAttribute("XPMultiplier") or 1) * (p:GetAttribute("XPBoost") or 1) + 0.5)
				workRE:FireClient(p, { money = REWARD_MONEY, xp = xpShown, label = "🚔 도둑 체포" })
				Money.Add(p, REWARD_MONEY, "도둑 체포")
				pcall(Rank.AddWorkXP, p, REWARD_XP, "도둑 체포")
			end)
			pcall(function() sfx("CashRegister", c.root, 0.6, 60) end)
			setTag(c, "😵 잡혔다!")
			announce("🚔", "도둑 체포!", string.format("%s님이 도둑을 잡았어요! (+%s원)", p.DisplayName, tostring(REWARD_MONEY)))
			vanish(c, 1.4)
		end

		local function run()
			if active then return false, "busy" end
			if #readyOnPass() == 0 then return false, "nobowl" end
			local model, hum = makeNPC(false, false)
			if not model then return false, "npc" end
			local root = model:FindFirstChild("HumanoidRootPart")
			dress(model)
			model:PivotTo(CFrame.new(pick(SPAWNS)))
			model.Parent = thiefFolder
			pcall(function() root:SetNetworkOwner(nil) end)
			hum.WalkSpeed = APPROACH_SPEED
			local c = { model = model, hum = hum, root = root, alive = true }
			active = c
			lastState = "approach"
			announce("🦹", "도둑이 나타났어요!", "패스대의 마라탕을 노려요! 그릇을 든 도둑에게 다가가 E(터치)로 체포하세요!")

			local ok, err = pcall(function()
				-- 손님처럼 정문(DOOR_OUT → DOOR_IN)으로 들어와서 직원 구역 게이트로
				if not (npc.walkTo(c, DOOR_OUT) and npc.walkTo(c, DOOR_IN)) then lastState = "stuck in"; vanish(c); return end
				local list = readyOnPass()
				if #list == 0 then
					setTag(c, "🦹 쳇, 없네...")
					lastState = "nothing"
					npc.walkTo(c, DOOR_IN); vanish(c); return
				end
				table.sort(list, function(a, b) return (stations.passSlots[a.slot] - root.Position).Magnitude < (stations.passSlots[b.slot] - root.Position).Magnitude end)
				local t = list[1]
				local sp = stations.passSlots[t.slot]
				if not npc.walkTo(c, Vector3.new(sp.X, 3, PASS_FRONT_Z)) then lastState = "stuck pass"; vanish(c); return end
				if t.state ~= "ready" or not t.slot or not (t.bowl and t.bowl.Parent) then
					list = readyOnPass()
					if #list == 0 then setTag(c, "🦹 쳇, 없네..."); lastState = "nothing2"; npc.walkTo(c, DOOR_IN); vanish(c); return end
					t = list[1]
				end
				stations:release(t); tickets:setState(t, "stolen"); t.carrier = nil
				c.t = t
				local bowl = t.bowl
				local pp = bowl.PrimaryPart:FindFirstChild("Pickup"); if pp then pp:Destroy() end
				local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm") or root
				for _, p in ipairs(bowl:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false; p.CanCollide = false; p.CanQuery = false; p.Massless = true end end
				bowl:PivotTo(hand.CFrame * CFrame.new(0, -0.4, -0.9))
				weldTo(hand, bowl.PrimaryPart)
				bowl.Parent = model
				pcall(function() root:SetNetworkOwner(nil) end)
				refreshBoard()
				setTag(c, "🦹 도둑 (E로 체포!)")
				pcall(function() sfx("Wrong", root, 0.35, 60) end)
				notifyAll(string.format("🦹 도둑이 #%d 그릇을 훔쳤어요! 다가가서 E(터치)로 체포하세요!", t.id))
				c.fleeing = true
				hum.WalkSpeed = FLEE_SPEED
				lastState = "flee"
				-- (11/21) E(모바일은 터치)로 체포
				local pp = Instance.new("ProximityPrompt"); pp.Name = "ArrestPrompt"
				pp.ActionText = "체포하기"; pp.ObjectText = "🦹 도둑"
				pp.KeyboardKeyCode = Enum.KeyCode.E; pp.GamepadKeyCode = Enum.KeyCode.ButtonX
				pp.HoldDuration = 0; pp.MaxActivationDistance = 10; pp.RequiresLineOfSight = false
				pp.Parent = root
				pp.Triggered:Connect(function(p)
					if not c.fleeing or c.caught then return end
					if not near(p, root.Position, 14) then return end
					pp.Enabled = false
					caughtBy(c, p)
				end)
				local exit = pick(SPAWNS)
				local away = npc.walkTo(c, DOOR_IN) and npc.walkTo(c, DOOR_OUT) and npc.walkTo(c, exit)
				if c.caught then return end
				-- 출구 근처(15스터드)까지 갔으면 도망 성공으로 봄
				if not away and c.fleeing and ((root.Position - exit) * Vector3.new(1, 0, 1)).Magnitude < 15 then away = true end
				c.fleeing = false
				if away then
					lastState = "escaped"
					lose(t, true)
					announce("🦹", "도둑이 도망쳤어요...", "다음엔 꼭 잡아요!")
				else
					lastState = "stuck flee"
					giveBack(t)
				end
				vanish(c)
			end)
			if not ok then
				warn("[Thief]", err)
				c.fleeing = false
				if c.t and c.t.state == "stolen" then pcall(giveBack, c.t) end
				if model.Parent then model:Destroy() end
			end
			active = nil
			return true
		end

		-- 개발자 패널(AdminService "thief" 이벤트)용: ServerStorage.ThiefAPI:Invoke("go") -> ok, 메시지
		do
			local api = SS:FindFirstChild("ThiefAPI") or Instance.new("BindableFunction"); api.Name = "ThiefAPI"; api.Parent = SS
			api.OnInvoke = function(cmd)
				if cmd ~= "go" then return false, "?" end
				if active then return false, "이미 도둑이 있어요" end
				if #readyOnPass() == 0 then return false, "패스대에 완성된 그릇이 없어요" end
				task.spawn(function() local ok, err = pcall(run); if not ok then warn("[Thief]", err); active = nil end end)
				return true, "🦹 도둑 등장!"
			end
		end
		if game:GetService("RunService"):IsStudio() then
			local bf = SS:FindFirstChild("ThiefTest") or Instance.new("BindableFunction"); bf.Name = "ThiefTest"; bf.Parent = SS
			bf.OnInvoke = function(cmd)
				if cmd == "go" then
					if active then return false, "busy" end
					if #readyOnPass() == 0 then return false, "nobowl" end
					task.spawn(run); return true
				end
				return lastState .. (active and " (active)" or "")
			end
		end

		while true do
			task.wait(math.random(INTERVAL[1], INTERVAL[2]))
			local waited = 0
			while (#readyOnPass() == 0 or #Players:GetPlayers() == 0) and waited < 300 do task.wait(15); waited += 15 end
			if #readyOnPass() > 0 then
				local ok, err = pcall(run)
				if not ok then warn("[Thief]", err); active = nil end
			end
		end
	end)
end

return Spawner
