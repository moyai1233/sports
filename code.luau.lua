--// CustomerService: NPC 손님 (입장 → 재료 고르기 → 계산대 주문 → 자리 → 식사 → 퇴장)
local ClassicHead = require(game:GetService("ServerStorage"):WaitForChild("ClassicHead"))
--// 플레이어 일: 계산대 POS에서 "주문 받기" → 주방 화구에서 "조리하기" + 마라소스 넣기 → 패스대에서 그릇 들기 → 손님에게 "서빙하기"
--// 역할 제한 없음: 누구나 아무 일이나 할 수 있다. 설정은 ReplicatedStorage.CustomerConfig
local Players = game:GetService("Players")
local Physics = game:GetService("PhysicsService")
local RS = game:GetService("ReplicatedStorage")
local SS = game:GetService("ServerStorage")
local TS = game:GetService("TweenService")

local C = require(RS:WaitForChild("CustomerConfig"))
local Money = require(script.Parent:WaitForChild("MoneyService"))
local Rank = require(script.Parent:WaitForChild("RankService"))
local Assets = SS:WaitForChild("CustomerAssets")
local remotes = RS:WaitForChild("Remotes")
local spiceRE = remotes:WaitForChild("KitchenSpice")
local notifyRE = remotes:FindFirstChild("Notify")

local SFX = RS:WaitForChild("SFX")
local function sfx(name, parent, vol, maxDist)
	local src = SFX:FindFirstChild(name)
	if not src or not parent or not parent.Parent then return end
	local snd = src:Clone(); snd.Volume = vol or 0.5; snd.RollOffMinDistance = 8; snd.RollOffMaxDistance = maxDist or 60
	snd.Parent = parent; snd:Play()
	task.delay(math.max(4, snd.TimeLength + 0.5), function() snd:Destroy() end)
end
local doorPart = workspace:WaitForChild("Shell"):FindFirstChild("DoorHeader")

local FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local OUT = Color3.fromRGB(70, 28, 22)
local CREAM = Color3.fromRGB(255, 249, 238)
local RED = Color3.fromRGB(226, 72, 62)

----------------------------------------------------------------- collision groups
pcall(function() Physics:RegisterCollisionGroup("Customers") end)
pcall(function() Physics:RegisterCollisionGroup("PlayerChars") end)
Physics:CollisionGroupSetCollidable("Customers", "Customers", false)
Physics:CollisionGroupSetCollidable("Customers", "PlayerChars", false)
local function setGroup(model, group)
	for _, p in ipairs(model:GetDescendants()) do if p:IsA("BasePart") then p.CollisionGroup = group end end
end
-- 플레이어 캨릭터 = PlayerChars (손님과 안 부딪힘)
-- ※ 이 스크립트가 늦게 돌면 PlayerAdded를 놓친 플레이어가 있어서(특히 Studio) 이미 들어온 플레이어도 똑같이 처리
local function onChar(ch)
	setGroup(ch, "PlayerChars")
	ch.DescendantAdded:Connect(function(d) if d:IsA("BasePart") then d.CollisionGroup = "PlayerChars" end end)
end
local hooked = {}
local function onPlayer(plr)
	if hooked[plr] then return end
	hooked[plr] = true
	plr.CharacterAdded:Connect(onChar)
	if plr.Character then onChar(plr.Character) end
end
Players.PlayerAdded:Connect(onPlayer)
Players.PlayerRemoving:Connect(function(plr) hooked[plr] = nil end)
for _, plr in ipairs(Players:GetPlayers()) do onPlayer(plr) end

----------------------------------------------------------------- map points
local Y = 3
local function v(x, z) return Vector3.new(x, Y, z) end
local SPAWNS = { v(-26, -50), v(26, -50), v(-14, -52), v(14, -52) }
local DOOR_OUT, DOOR_IN = v(0, -47), v(0, -35)
local BOWL_SPOT = v(24.4, 15.2)   -- in front of the bowl stacks by the ingredient bar
local BAR_SPOTS = { v(21.5, 22), v(21.5, 26.5), v(21.5, 31), v(21.5, 35.5), v(21.5, 40) }
local kitchen = workspace:WaitForChild("Kitchen")
local furniture = workspace:WaitForChild("Furniture1F")

-- (11/18) 계산대 = Kitchen 안의 POS 모델을 전부 찾아서 자동으로 만듦 (포스기를 늘리거나 옮겨도 그대로 동작)
--   줄: 포스기 앞(z 21)부터 뒤로 3칸. 뒤쪽(z 12 이하)에 테이블이 없는 줄은 5칸
local REGISTERS = {}
do
	local list = {}
	for _, m in ipairs(kitchen:GetChildren()) do
		if m.Name == "POS" and m:IsA("Model") then table.insert(list, m) end
	end
	table.sort(list, function(a, b) return a:GetPivot().Position.X < b:GetPivot().Position.X end)
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Include
	op.FilterDescendantsInstances = { furniture }
	for _, m in ipairs(list) do
		local x = m:GetPivot().Position.X
		local q = { v(x, 21), v(x, 18), v(x, 15) }
		for _, z in ipairs({ 12, 9 }) do
			local blocked = #workspace:GetPartBoundsInBox(CFrame.new(x, 5.5, z), Vector3.new(2.5, 4, 2.5), op) > 0
			if blocked then break end
			table.insert(q, v(x, z))
		end
		table.insert(REGISTERS, { pos = x, front = q[1], queue = q, posModel = m })
	end
	if #REGISTERS == 0 then warn("[CustomerService] Kitchen에 POS가 없어요") end
end

----------------------------------------------------------------- seats
local seats = {}   -- {seat=, top=, reservedBy=, upstairs=}
local VIPConfig = require(RS:WaitForChild("VIPConfig"))
local function collectSeats(folder, upstairs)
	if not folder then return end
	for _, chair in ipairs(folder:GetChildren()) do
		local seat = chair:IsA("Model") and chair.Name == "Chair" and chair:FindFirstChildOfClass("Seat")
		if seat and not chair:GetAttribute("VIPOnly") and not seat:GetAttribute("VIPOnly") and not VIPConfig.isVIPOnly(seat) then
			local best, bd
			for _, t in ipairs(folder:GetChildren()) do
				local top = t.Name == "Table" and t:FindFirstChild("Top")
				if top and math.abs(top.Position.Y - seat.Position.Y) < 4 then
					local d = (top.Position - seat.Position) * Vector3.new(1, 0, 1)
					if not bd or d.Magnitude < bd then best, bd = top, d.Magnitude end
				end
			end
			if best and bd < 8 then table.insert(seats, { seat = seat, top = best, upstairs = upstairs }) end
		end
	end
end
collectSeats(furniture, false)
collectSeats(workspace:FindFirstChild("Furniture2F"), true)   -- 2nd floor (VIP lounge sofas are left out)
-- 👑 SUPER RICH MAN 전용: 2층 VIP 라운지 소파 (VIPOnly) + 앞의 낮은 테이블(LowTable) (11/16)
local vipSeats = {}
do
	local lows = {}
	for _, d in ipairs(workspace:GetDescendants()) do if d:IsA("BasePart") and d.Name == "LowTable" then table.insert(lows, d) end end
	for _, s in ipairs(workspace:GetDescendants()) do
		if s:IsA("Seat") and VIPConfig.isVIPOnly(s) and s:IsDescendantOf(workspace:FindFirstChild("Furniture2F") or workspace) then
			local best, bd
			for _, t in ipairs(lows) do
				if math.abs(t.Position.Y - s.Position.Y) < 4 then
					local d = ((t.Position - s.Position) * Vector3.new(1, 0, 1)).Magnitude
					if not bd or d < bd then best, bd = t, d end
				end
			end
			if best and bd < 8 then table.insert(vipSeats, { seat = s, top = best, upstairs = true, vip = true }) end
		end
	end
	print("[CustomerService] VIP 라운지 좌석", #vipSeats, "석")
end

-- 안전장치: 식당 좌석이 제자리를 벗어나면(예: 앉은 채 집으로 순간이동해 끌려감) 되돌림
--   멀리 끌려간 건 앉은 사람이 있어도 되돌림(앉은 손님도 같이 돌아옴), 조금 밀린 건 비었을 때만
do
	local homes = {}
	for _, f in ipairs({ furniture, workspace:FindFirstChild("Furniture2F") }) do
		if f then for _, s in ipairs(f:GetDescendants()) do if s:IsA("Seat") then homes[s] = s.CFrame end end end
	end
	task.spawn(function()
		while true do
			task.wait(3)
			for s, cf in pairs(homes) do
				if s.Parent then
					local d = (s.Position - cf.Position).Magnitude
					if d > 20 or (d > 1 and not s.Occupant) then
						pcall(function() s.AssemblyLinearVelocity = Vector3.zero; s.CFrame = cf end)
					end
				else homes[s] = nil end
			end
		end
	end)
end

----------------------------------------------------------------- folders / helpers
local folder = workspace:FindFirstChild("Customers") or Instance.new("Folder")
folder.Name = "Customers"; folder.Parent = workspace
local fxFolder = workspace:FindFirstChild("KitchenFX") or Instance.new("Folder")
fxFolder.Name = "KitchenFX"; fxFolder.Parent = workspace

local function notify(plr, msg) if notifyRE then notifyRE:FireClient(plr, msg) end end
local workRE = remotes:FindFirstChild("WorkReward") or Instance.new("RemoteEvent")
workRE.Name = "WorkReward"; workRE.Parent = remotes
-- (11/18) 계산대 모드: 「계산대 이용하기」→ 포스기 UI(POSClient) → 말풍선 눌러 주문 불러오기 → 메뉴·맵기 맞게 골라 결제
local posRE = remotes:FindFirstChild("POS") or Instance.new("RemoteEvent")
posRE.Name = "POS"; posRE.Parent = remotes
local posRF = remotes:FindFirstChild("POSCheckout") or Instance.new("RemoteFunction")
posRF.Name = "POSCheckout"; posRF.Parent = remotes
local announceRE = remotes:FindFirstChild("Announce")
-- 러시아워 (RushHourService가 workspace 속성으로 알려줌)
local RushCfg = require(RS:WaitForChild("RushHourConfig"))
local function rushOn() return workspace:GetServerTimeNow() < (workspace:GetAttribute("RushUntil") or 0) end
local function rushTipMult() if not rushOn() then return 1 end; return workspace:GetAttribute("RushSpecial") and RushCfg.SpecialTipMult or RushCfg.TipMult end
local function reward(plr, kind, extraMoney, label, mult)
	local r = C.Reward[kind]
	if not r or not plr.Parent then return end
	mult = mult or 1
	local money = math.floor((r.Money + (extraMoney or 0)) * mult)
	local baseXP = r.XP * mult
	local xp = math.floor(baseXP * (plr:GetAttribute("XPMultiplier") or 1) * (plr:GetAttribute("XPBoost") or 1) + 0.5)
	workRE:FireClient(plr, { money = money, xp = xp, label = mult > 1 and (label .. " x" .. mult) or label })
	Money.Add(plr, money, label)
	pcall(Rank.AddWorkXP, plr, baseXP, label)
	local ob = SS:FindFirstChild("OnboardStep"); if ob then ob:Fire(plr, kind) end
end
local SkinStyle = require(RS:WaitForChild("SkinStyle"))
-- 스킨: 그 플레이어가 낀 스킨 style (없으면 nil)
local function skinOf(plr, slot)
	local bf = SS:FindFirstChild("SkinOf")
	if not (bf and plr) then return nil end
	local ok, st = pcall(function() return bf:Invoke(plr, slot) end)
	return ok and st or nil
end
local function skinPot(r)
	local st = skinOf(r.cook, "pot")
	if st and r.pot and r.pot.PrimaryPart then pcall(SkinStyle.apply, r.pot.PrimaryPart, st, { gems = 12 }) end
end
local function richMult(t)
	if t and t.superRich then return C.SuperRichMult or 15 end
	return (t and t.rich) and (C.RichMult or 10) or 1
end
-- 헤드리스맨 손님: 주문 받기 / 조리 / 서빙 할 때마다 호박 3개 (할로윈 이벤트)
local HEADLESS_PUMPKINS = 3
local function pumpkinBonus(plr, t)
	if not (t and t.headless and plr and plr.Parent) then return end
	local api = SS:FindFirstChild("PumpkinAPI"); if not api then return end
	local ok = api:Invoke("earn", plr, HEADLESS_PUMPKINS)
	if ok then
		local re = remotes:FindFirstChild("PumpkinPickup")
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if re and root then re:FireClient(plr, root.Position + Vector3.new(0, 3, 0), HEADLESS_PUMPKINS, nil) end
	end
end
local function near(plr, pos, dist)
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and (root.Position - pos).Magnitude <= dist
end
local function pick(list) return list[math.random(#list)] end
local function weighted(items, weights)
	local total = 0
	for _, w in ipairs(weights) do total += w end
	local r = math.random() * total
	for i, w in ipairs(weights) do r -= w; if r <= 0 then return items[i] end end
	return items[1]
end

local function label(parent, text, size, color, stroke)
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1; t.FontFace = FONT; t.Text = text; t.TextScaled = true
	t.TextColor3 = color or OUT; t.Size = size or UDim2.fromScale(1, 1); t.Parent = parent
	if stroke then local s = Instance.new("UIStroke"); s.Color = stroke; s.Thickness = 2; s.Parent = t end
	return t
end

----------------------------------------------------------------- tickets
local customerModules = script.Parent:WaitForChild("Customer")
local tickets = require(customerModules:WaitForChild("Tickets")).new()

-- kitchen board (over the pass window)
local boardPart = Instance.new("Part")
boardPart.Name = "OrderBoardAnchor"; boardPart.Anchored = true; boardPart.CanCollide = false; boardPart.CanQuery = false; boardPart.CanTouch = false
boardPart.Transparency = 1; boardPart.Size = Vector3.new(1, 1, 1); boardPart.Position = Vector3.new(-5, 11.5, 36)   -- not parented: no order board over the kitchen
local board = Instance.new("BillboardGui")
board.Size = UDim2.fromOffset(330, 130); board.LightInfluence = 0; board.MaxDistance = 70; board.AlwaysOnTop = false; board.Parent = boardPart
local boardBg = Instance.new("Frame"); boardBg.Size = UDim2.fromScale(1, 1); boardBg.BackgroundColor3 = CREAM; boardBg.Parent = board
do local s = Instance.new("UIStroke"); s.Color = OUT; s.Thickness = 3; s.Parent = boardBg end
local boardTitle = label(boardBg, "주문 0건", UDim2.fromScale(1, 0.3), RED)
local boardList = label(boardBg, "", UDim2.new(1, -10, 0.68, 0), OUT)
boardList.Position = UDim2.new(0, 5, 0.3, 0); boardList.TextYAlignment = Enum.TextYAlignment.Top; boardList.TextWrapped = true
local function refreshBoard()
	local lines, count = {}, 0
	local all = {}
	for _, t in tickets:entries() do if t.state ~= "done" then table.insert(all, t) end end
	table.sort(all, function(a, b) return a.id < b.id end)
	for _, t in ipairs(all) do
		count += 1
		if #lines < 4 then
			local st = ({ ordered = "대기", cooking = "조리 중", spice = "맵기", ready = "완성", carried = "서빙 중" })[t.state] or ""
			table.insert(lines, string.format("#%d %s %s · %s", t.id, t.menu, t.side and "" or C.SpiceShort[t.spice], st))
		end
	end
	boardTitle.Text = string.format("주문 %d건", count)
	boardList.Text = table.concat(lines, "\n")
end

local Spawner = require(customerModules:WaitForChild("Spawner"))
local makeNPC = Spawner.createNPCFactory({
	assets = Assets,
	config = C,
	classicHead = ClassicHead,
	setGroup = setGroup,
	pick = pick,
})

local function bubble(npc)
	local head = npc:FindFirstChild("Head")
	local g = Instance.new("BillboardGui")
	g.Name = "Bubble"; g.Size = UDim2.new(4.2, 0, 1.15, 0); g.StudsOffset = Vector3.new(0, 2.4, 0)   -- 스터드 크기: 멀수록 작아짐 (모바일에서 화면을 덜 가림)
	g.LightInfluence = 0; g.MaxDistance = 34; g.Enabled = false; g.Parent = head
	local bg = Instance.new("Frame"); bg.Name = "Bg"; bg.Size = UDim2.fromScale(1, 0.72); bg.BackgroundColor3 = CREAM; bg.Parent = g
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0.3, 0); c.Parent = bg
	local s = Instance.new("UIStroke"); s.Color = OUT; s.Thickness = 2.5; s.Parent = bg
	local t = label(bg, "", UDim2.new(1, -8, 1, -4), OUT); t.Name = "Text"; t.Position = UDim2.fromOffset(4, 2)
	local bar = Instance.new("Frame"); bar.Name = "Bar"; bar.Position = UDim2.fromScale(0.18, 0.8); bar.Size = UDim2.fromScale(0.64, 0.11)
	bar.BackgroundColor3 = Color3.fromRGB(80, 40, 30); bar.Visible = false; bar.Parent = g
	local bc = Instance.new("UICorner"); bc.CornerRadius = UDim.new(1, 0); bc.Parent = bar
	local fill = Instance.new("Frame"); fill.Name = "Fill"; fill.Size = UDim2.fromScale(1, 1); fill.BackgroundColor3 = Color3.fromRGB(120, 220, 100); fill.Parent = bar
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = fill
	return g
end
local function say(c, text, showBar)
	local g = c.bubble
	-- 이미 사라진 손님(리치맨 이벤트로 퇴장 등)의 말풍선은 무시
	if not g or not c.alive or not g:FindFirstChild("Bg") then return end
	g.Enabled = text ~= nil
	if text then g.Bg.Text.Text = text end
	g.Bg.Visible = text ~= nil and text ~= ""
	g.Bar.Visible = showBar == true
end

local Customers = require(customerModules:WaitForChild("Customers"))
Customers.prepareVIPSeats(vipSeats)

----------------------------------------------------------------- customer bowl (OGBowls)
local emptyBowl = Assets:WaitForChild("EmptyBowl")
local bowlUp = emptyBowl.CFrame.Rotation            -- the bowl's upright rotation
local ingLib = SS:FindFirstChild("IngredientMeshes")
local miniCache = {}
local SPEC = {
	bokchoy = 0.95, fishball = 0.36, sprout = 0.8, napa = 0.85, enoki = 0.85, woodear = 0.55, shiitake = 0.5, broccoli = 0.5,
	corn = 0.5, potato = 0.5, kingoyster = 0.6, cabbage = 0.6, lotus = 0.55, spinach = 0.8, pumpkin = 0.55, fishcake = 0.7,
	quail = 0.34, fuzhu = 0.95, drytofu = 0.95, friedtofu = 0.42, fenmozi = 0.8, widenoodle = 0.85, glassnoodle = 0.85,
	ricecake = 0.6, dumpling = 0.6, sausage = 0.62, crabstick = 0.72, spam = 0.52, cilantro = 0.45, peanut = 0.3,
}
local function miniPiece(key)
	if miniCache[key] == nil then
		local src = ingLib and ingLib:FindFirstChild(key)
		local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
		if mp then
			local t = mp:Clone()
			for _, ch in ipairs(t:GetChildren()) do if not ch:IsA("SurfaceAppearance") then ch:Destroy() end end
			t.Size = t.Size * ((SPEC[key] or 0.5) * 0.8 / math.max(t.Size.X, t.Size.Y, t.Size.Z))
			t.Anchored = false; t.CanCollide = false; t.CanTouch = false; t.CanQuery = false; t.Massless = true; t.CastShadow = false
			-- thinnest side up so pieces lie flat in the bowl
			local sz, r0 = t.Size, CFrame.new()
			if sz.X <= sz.Y and sz.X <= sz.Z then r0 = CFrame.Angles(0, 0, math.pi / 2)
			elseif sz.Z <= sz.Y and sz.Z <= sz.X then r0 = CFrame.Angles(math.pi / 2, 0, 0) end
			miniCache[key] = { part = t, r0 = r0 }
		else
			miniCache[key] = false
		end
	end
	if not miniCache[key] then return nil end
	return miniCache[key].part:Clone(), miniCache[key].r0
end
local INGREDIENT_KEYS = { "bokchoy", "fishball", "sprout", "enoki", "woodear", "fishcake", "fuzhu", "quail", "ricecake", "broccoli", "lotus", "friedtofu", "glassnoodle", "crabstick", "potato", "napa", "kingoyster", "fenmozi", "dumpling", "sausage", "spinach", "shiitake" }

local function holdBowl(c)
	local torso = c.model:FindFirstChild("UpperTorso")
	if not torso then return end
	local bowl = emptyBowl:Clone()
	bowl.Name = "HeldBowl"
	local fwd = (torso.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	local yaw = CFrame.lookAt(Vector3.zero, fwd)
	bowl.CFrame = CFrame.new((torso.CFrame * CFrame.new(0, -0.35, -1.3)).Position) * yaw * bowlUp
	bowl.CollisionGroup = "Customers"
	local w = Instance.new("WeldConstraint"); w.Part0 = torso; w.Part1 = bowl; w.Parent = bowl
	bowl.Parent = c.model
	c.heldBowl = bowl
	c.model:SetAttribute("HoldingBowl", true)
end
-- after picking at the bar: a few ingredients appear in the bowl
local function fillBowl(c)
	local bowl = c.heldBowl
	if not bowl then return end
	local up, ax1, ax2 = bowl.CFrame.RightVector, bowl.CFrame.UpVector, bowl.CFrame.LookVector   -- local X = up
	local kinds = {}
	local pool = table.clone(INGREDIENT_KEYS)
	for i = 1, math.random(4, 6) do table.insert(kinds, table.remove(pool, math.random(#pool))) end
	c.bowlKinds = kinds
	local total = 0
	for _, key in ipairs(kinds) do
		for j = 1, math.random(2, 4) do
			local p, r0 = miniPiece(key)
			if p then
				total += 1
				local r = math.sqrt(math.random()) * 0.6
				local a = math.random() * math.pi * 2
				local h = 0.05 + (1 - r / 0.6) * 0.22 + math.min(total, 14) * 0.012
				local pos = bowl.CFrame.Position + up * h + (ax1 * math.cos(a) + ax2 * math.sin(a)) * r
				local flat = CFrame.fromMatrix(pos, ax1, up)
				p.CFrame = flat * CFrame.Angles(0, math.random() * math.pi * 2, 0) * CFrame.Angles(math.random() * 0.5 - 0.25, 0, math.random() * 0.5 - 0.25) * r0
				p.CollisionGroup = "Customers"
				local w = Instance.new("WeldConstraint"); w.Part0 = bowl; w.Part1 = p; w.Parent = p
				p.Parent = bowl
			end
		end
	end
end
-- at the counter: the bowl goes onto the scale, then into the kitchen
local scales = {}
for _, p in ipairs(kitchen:GetChildren()) do if p.Name == "ScalePlate" and p:IsA("BasePart") then table.insert(scales, p) end end
local function handOver(c, reg)
	local bowl = c.heldBowl
	if not bowl then return end
	c.heldBowl = nil
	if c.model then c.model:SetAttribute("HoldingBowl", nil) end
	local best, bd
	for _, sp in ipairs(scales) do
		local d = math.abs(sp.Position.X - reg.pos) + math.abs(sp.Position.Z - 26)
		if not bd or d < bd then best, bd = sp, d end
	end
	for _, w in ipairs(bowl:GetChildren()) do if w:IsA("WeldConstraint") and w.Part0 ~= bowl then w:Destroy() end end
	if best then
		bowl.Anchored = true
		bowl.CFrame = CFrame.new(best.Position + Vector3.new(0, best.Size.Y / 2 + 0.45, 0)) * bowlUp
		bowl.Parent = fxFolder
		task.delay(3, function() if bowl.Parent then bowl:Destroy() end end)
	else
		bowl:Destroy()
	end
end

----------------------------------------------------------------- dirty tables (cleaned with the broom)
local UpgradeCfg = require(RS:WaitForChild("UpgradeConfig"))
local CS = game:GetService("CollectionService")
local dirtyFolder = workspace:FindFirstChild("DirtyTables") or Instance.new("Folder")
dirtyFolder.Name = "DirtyTables"; dirtyFolder.Parent = workspace
local AUTO_CLEAN = 150     -- nobody cleans: the mess disappears by itself after this long

local function freeSeatRec(rec)
	rec.reservedBy = nil; rec.dirty = nil
	rec.seat:SetAttribute("Reserved", nil)
	local pp = rec.seat:FindFirstChild("SitPrompt"); if pp then pp.Enabled = rec.seat.Occupant == nil end
end

local function makeDirty(rec, bowl)
	-- the chair stays blocked until somebody cleans up
	rec.reservedBy = "dirty"; rec.dirty = true
	rec.seat:SetAttribute("Reserved", true)
	local pp = rec.seat:FindFirstChild("SitPrompt"); if pp then pp.Enabled = false end
	local mess = Instance.new("Model"); mess.Name = "Mess"
	bowl.Parent = mess
	local tag = bowl.PrimaryPart:FindFirstChild("Tag"); if tag then tag:Destroy() end
	-- a few broth stains, a crumpled napkin
	local top = rec.top
	local topY = top.Position.Y + top.Size.Y / 2
	local base = bowl.PrimaryPart.Position
	for i = 1, math.random(3, 5) do
		local a = math.random() * math.pi * 2; local r = 0.9 + math.random() * 0.6
		local p = Instance.new("Part"); p.Name = "Stain"; p.Shape = Enum.PartType.Cylinder; p.Anchored = true
		p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
		local d = 0.25 + math.random() * 0.35
		p.Size = Vector3.new(0.02, d, d * (0.7 + math.random() * 0.5))
		p.Color = Color3.fromRGB(150 + math.random(0, 40), 60, 30); p.Material = Enum.Material.Glass; p.Transparency = 0.25
		p.CFrame = CFrame.new(base.X + math.cos(a) * r, topY + 0.012, base.Z + math.sin(a) * r) * CFrame.Angles(0, math.random() * 6.28, math.rad(90))
		p.Parent = mess
	end
	local nap = Instance.new("Part"); nap.Name = "Napkin"; nap.Anchored = true; nap.CanCollide = false; nap.CanTouch = false; nap.CanQuery = false
	nap.Size = Vector3.new(0.32, 0.18, 0.28); nap.Color = Color3.fromRGB(245, 243, 236); nap.Material = Enum.Material.Fabric
	nap.CFrame = CFrame.new(base + Vector3.new(0.9, 0, -0.5)) * CFrame.Angles(math.random(), math.random(), math.random())
	nap.Position = Vector3.new(nap.Position.X, topY + 0.09, nap.Position.Z)
	nap.Parent = mess
	mess.Parent = dirtyFolder

	local ppc = Instance.new("ProximityPrompt")
	ppc.Name = "Clean"; ppc.ActionText = "청소하기"; ppc.ObjectText = "지저분한 테이블"
	ppc.KeyboardKeyCode = Enum.KeyCode.E; ppc.HoldDuration = UpgradeCfg.cleanTime(0); ppc.MaxActivationDistance = 8; ppc.RequiresLineOfSight = false
	ppc.Parent = bowl.PrimaryPart
	CS:AddTag(ppc, "CleanPrompt")
	local holdStart = setmetatable({}, { __mode = "k" })
	ppc.PromptButtonHoldBegan:Connect(function(plr) holdStart[plr] = os.clock() end)
	local done = false
	local function finish()
		if done then return end
		done = true
		mess:Destroy()
		freeSeatRec(rec)
	end
	ppc.Triggered:Connect(function(plr)
		if done or not plr.Parent then return end
		local ch = plr.Character
		if not (ch and ch:FindFirstChild("빗자루")) then notify(plr, "빗자루를 들고 청소해요"); return end
		if not near(plr, bowl.PrimaryPart.Position, 14) then return end
		local lv = tonumber(plr:GetAttribute("UpgBroom")) or 0
		if os.clock() - (holdStart[plr] or 0) < UpgradeCfg.cleanTime(lv) * 0.75 then return end   -- held long enough?
		local money, xp = UpgradeCfg.cleanReward(lv), UpgradeCfg.cleanXP(lv)
		finish()
		workRE:FireClient(plr, { money = money, xp = math.floor(xp * (plr:GetAttribute("XPMultiplier") or 1) * (plr:GetAttribute("XPBoost") or 1) + 0.5), label = "청소" })
		Money.Add(plr, money, "청소")
		pcall(Rank.AddWorkXP, plr, xp, "청소")
		local ew = SS:FindFirstChild("EmployeeWork"); if ew then ew:Fire(plr, "Clean") end   -- 우수직원 점수
	end)
	task.delay(AUTO_CLEAN, finish)
end

local npc = Customers.new({
	config = C,
	doorIn = DOOR_IN,
	doorOut = DOOR_OUT,
	spawnPoints = SPAWNS,
	bowlSpot = BOWL_SPOT,
	barSpots = BAR_SPOTS,
	registers = REGISTERS,
	seats = seats,
	vipSeats = vipSeats,
	pick = pick,
	weighted = weighted,
	sfx = sfx,
	say = say,
	doorPart = doorPart,
	announce = announceRE,
	rushOn = rushOn,
	tickets = tickets,
	refreshBoard = refreshBoard,
	makeDirty = makeDirty,
	holdBowl = holdBowl,
	fillBowl = fillBowl,
})

----------------------------------------------------------------- floor spills (also swept with the broom)
local FLOOR_MAX = 6           -- at most this many spills at once
local FLOOR_EVERY = { 25, 45 } -- a new spill every this many seconds (while customers are inside)
local FLOOR_FADE = 240        -- an untouched spill dries up after this long
local floorSpills = 0
local SPILL_COLORS = {
	Color3.fromRGB(200, 80, 35),   -- mala broth
	Color3.fromRGB(150, 70, 35),   -- sauce
	Color3.fromRGB(120, 95, 65),   -- dirt
}

local function floorSpot()
	-- next to a random chair, on the aisle side, raycast down to the real floor
	if #seats == 0 then return nil end
	local rec = seats[math.random(#seats)]
	local away = ((rec.seat.Position - rec.top.Position) * Vector3.new(1, 0, 1))
	if away.Magnitude < 0.1 then return nil end
	away = away.Unit
	local side = Vector3.new(-away.Z, 0, away.X) * (math.random() - 0.5) * 2.5
	local probe = rec.seat.Position + away * (3.0 + math.random() * 1.4) + side + Vector3.new(0, 3, 0)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore = { folder, dirtyFolder, fxFolder }
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(ignore, p.Character) end end
	rp.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(probe, Vector3.new(0, -8, 0), rp)
	if not hit or hit.Normal.Y < 0.9 or hit.Instance:IsA("Seat") then return nil end
	if math.abs(hit.Position.Y - (rec.seat.Position.Y - 1.5)) > 1.6 then return nil end   -- landed on a table/chair, not the floor
	-- keep it in the open: nothing (chair legs, table legs, plants...) standing on that spot
	local op = OverlapParams.new(); op.FilterType = Enum.RaycastFilterType.Exclude; op.FilterDescendantsInstances = ignore
	for _, part in ipairs(workspace:GetPartBoundsInBox(CFrame.new(hit.Position + Vector3.new(0, 1.3, 0)), Vector3.new(2.2, 2.2, 2.2), op)) do
		if part ~= hit.Instance and part.Transparency < 1 and part.CanCollide and math.max(part.Size.X, part.Size.Y, part.Size.Z) < 200 then return nil end   -- 거대한 배경(산) 무시
	end
	return hit.Position
end

local function spawnFloorSpill(atPos)
	-- (11/19) atPos: 튜토리얼 청소 연습용 (플레이어 바로 옆)
	if not atPos and floorSpills >= FLOOR_MAX then return end
	local pos = atPos
	if not pos then for i = 1, 6 do pos = floorSpot(); if pos then break end end end
	if not pos then return end
	floorSpills += 1
	local m = Instance.new("Model"); m.Name = "FloorSpill"
	local col = SPILL_COLORS[math.random(#SPILL_COLORS)]
	local anchor
	for i = 1, math.random(3, 5) do
		local p = Instance.new("Part"); p.Name = "Splat"; p.Shape = Enum.PartType.Cylinder; p.Anchored = true
		p.CanCollide = false; p.CanTouch = false; p.CanQuery = false; p.CastShadow = false
		local d = (i == 1) and (1.2 + math.random() * 0.6) or (0.35 + math.random() * 0.5)
		p.Size = Vector3.new(0.02, d, d * (0.6 + math.random() * 0.5))
		p.Color = col:Lerp(Color3.new(0, 0, 0), math.random() * 0.1); p.Material = Enum.Material.Glass
		p.Transparency = (i == 1) and 0.15 or 0.1; p.Reflectance = 0.15
		local off = (i == 1) and Vector3.zero or Vector3.new((math.random() - 0.5) * 1.8, 0, (math.random() - 0.5) * 1.8)
		p.CFrame = CFrame.new(pos + off + Vector3.new(0, 0.012 + i * 0.002, 0)) * CFrame.Angles(0, math.random() * 6.28, math.rad(90))
		p.Parent = m
		if i == 1 then anchor = p end
	end
	-- a dropped noodle or two
	for i = 1, math.random(0, 2) do
		local n = Instance.new("Part"); n.Name = "Noodle"; n.Anchored = true; n.CanCollide = false; n.CanTouch = false; n.CanQuery = false; n.CastShadow = false
		n.Size = Vector3.new(0.5 + math.random() * 0.3, 0.04, 0.04); n.Color = Color3.fromRGB(240, 220, 160); n.Material = Enum.Material.SmoothPlastic
		n.CFrame = CFrame.new(pos + Vector3.new((math.random() - 0.5) * 0.8, 0.04, (math.random() - 0.5) * 0.8)) * CFrame.Angles(0, math.random() * 6.28, 0)
		n.Parent = m
	end
	m.PrimaryPart = anchor
	m.Parent = dirtyFolder

	local pp = Instance.new("ProximityPrompt")
	pp.Name = "Clean"; pp.ActionText = "쓸기"; pp.ObjectText = "바닥 얼룩"
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = UpgradeCfg.cleanTime(0); pp.MaxActivationDistance = 7; pp.RequiresLineOfSight = false
	pp.Parent = anchor
	CS:AddTag(pp, "CleanPrompt")
	local holdStart, done = {}, false
	local function finish()
		if done then return end
		done = true
		floorSpills -= 1
		m:Destroy()
	end
	m.Destroying:Connect(function() if not done then done = true; floorSpills -= 1 end end)   -- 관리자 청소 등으로 지워져도 개수 맞게
	pp.PromptButtonHoldBegan:Connect(function(plr) holdStart[plr] = os.clock() end)
	pp.Triggered:Connect(function(plr)
		if done or not plr.Parent then return end
		local ch = plr.Character
		if not (ch and ch:FindFirstChild("빗자루")) then notify(plr, "빗자루를 들고 쓸어요"); return end
		if not near(plr, anchor.Position, 12) then return end
		local lv = tonumber(plr:GetAttribute("UpgBroom")) or 0
		if os.clock() - (holdStart[plr] or 0) < UpgradeCfg.cleanTime(lv) * 0.75 then return end
		-- floor spills pay a bit less than a whole table
		local money = math.floor(UpgradeCfg.cleanReward(lv) * 0.6 / 10 + 0.5) * 10
		local xp = math.max(1, math.floor(UpgradeCfg.cleanXP(lv) * 0.6 + 0.5))
		finish()
		workRE:FireClient(plr, { money = money, xp = math.floor(xp * (plr:GetAttribute("XPMultiplier") or 1) * (plr:GetAttribute("XPBoost") or 1) + 0.5), label = "바닥 청소" })
		Money.Add(plr, money, "바닥 청소")
		pcall(Rank.AddWorkXP, plr, xp, "바닥 청소")
		local ew = SS:FindFirstChild("EmployeeWork"); if ew then ew:Fire(plr, "FloorClean") end   -- 우수직원 점수
	end)
	-- dries up slowly if nobody sweeps it
	task.delay(FLOOR_FADE, function()
		if done then return end
		for i = 1, 10 do
			if done then return end
			for _, p in ipairs(m:GetChildren()) do if p:IsA("BasePart") then p.Transparency = math.min(1, p.Transparency + 0.08) end end
			task.wait(0.5)
		end
		finish()
	end)
end

task.spawn(function()
	task.wait(10)
	while true do
		task.wait(FLOOR_EVERY[1] + math.random() * (FLOOR_EVERY[2] - FLOOR_EVERY[1]))
		if #Players:GetPlayers() > 0 and next(npc.active) ~= nil then pcall(spawnFloorSpill) end
	end
end)

----------------------------------------------------------------- carrying (one bowl, or two with the 양손 서빙 upgrade)
local CarryCfg = require(RS:WaitForChild("CarryConfig"))
local CARRY_SLOTS = CarryCfg.Slots   -- 8칸: 손(1·2) / 머리(3) / 쟁반(5까지) / 서빙 카트(8까지)
local function isCarrying(plr, id) return CarryCfg.isCarrying(plr, id) end
-- (re)attach every bowl this player carries: one in the middle, or two side by side
-- 쟁반 서빙: 양손 쟁반 (그릇은 쟁반 위에서 조금 작게) / 서빙 카트: 카트 선반 2층에 4개씩
local TRAY_SCALE = CarryCfg.TrayScale
local CART_SCALE = CarryCfg.CartScale
-- 들고 다니는 동안 그릇 크기 (CarryScale = 지금 배율, 내려놓을 때 원래대로)
local function carryScaleOf(bowl) return bowl:GetAttribute("CarryScale") or (bowl:GetAttribute("TrayScaled") and 0.72) or 1 end
local function setCarryScale(bowl, target)
	local cur = carryScaleOf(bowl)
	if math.abs(cur - target) > 0.001 then pcall(function() bowl:ScaleTo(bowl:GetScale() * target / cur) end) end
	bowl:SetAttribute("TrayScaled", nil)
	bowl:SetAttribute("CarryScale", (math.abs(target - 1) > 0.001) and target or nil)
end
local TRAY_ROLL_DEG = 16   -- TwoHandHold 의 TRAY_ROLL 과 같게
local function setTrays(ch, torso, fwd, on)
	for _, n in ipairs({ "CarryTrayR", "CarryTrayL" }) do
		local tr = ch:FindFirstChild(n)
		if not on then
			if tr then tr:Destroy() end
		else
			if not tr then
				local src = RS:FindFirstChild("CarryTray")
				tr = src and src:Clone() or Instance.new("Part")
				tr.Name = n; tr.CanCollide = false; tr.CanQuery = false; tr.CanTouch = false; tr.Massless = true; tr.Anchored = false
				tr.Size = Vector3.new(2.5, 0.14, 1.45)
				if not src then tr.Material = Enum.Material.Metal; tr.Color = Color3.fromRGB(200, 205, 210) end
				tr.Parent = ch
			end
			-- 이미 붙어 있으면 그대로 (다시 붙이면 캐릭터가 서버 위치로 순간이동하며 끼임)
			if tr:FindFirstChild("TrayWeld") then continue end
			-- 양식 웨이터처럼: 양손을 머리 위로 든 손바닥 위에 쟁반 (긴 쪽이 좌우). 팔 자세는 클라이언트 TwoHandHold
			local isR = (n == "CarryTrayR")
			-- 팔을 머리 위로 든 손 바로 위 높이 (몸통 기준), 쟁반은 수평 + 긴 쪽이 좌우
			local pos = (torso.CFrame * CFrame.new(isR and 1.95 or -1.95, 2.22, -0.05)).Position
			local right = fwd:Cross(Vector3.yAxis).Unit
			tr.CFrame = CFrame.fromMatrix(pos, right, Vector3.yAxis)
			local w = Instance.new("WeldConstraint"); w.Name = "TrayWeld"; w.Part0 = torso; w.Part1 = tr; w.Parent = tr
		end
	end
end

local function carryLayout(plr)
	local ch = plr.Character
	local torso = ch and (ch:FindFirstChild("UpperTorso") or ch:FindFirstChild("Torso"))
	if not torso then return end
	local list = {}
	for _, a in ipairs(CARRY_SLOTS) do
		local id = plr:GetAttribute(a)
		local t = id and tickets:get(id)
		if t and t.bowl and t.bowl.Parent then table.insert(list, t) end
	end
	local fwd = (torso.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	-- side by side: spread by the actual dish widths (a wide 꿔바로우 plate needs more room than a bowl)
	local spread = 0
	if #list >= 2 then
		local w1 = list[1].bowl:GetExtentsSize(); local w2 = list[2].bowl:GetExtentsSize()
		spread = math.max(0.68, (math.min(w1.X, w1.Z) + math.min(w2.X, w2.Z)) / 4 + 0.05)
	end
	-- 서빙 카트 패스가 있으면: 그릇을 들면 카트가 자동으로 나오고, 다 내려놓으면 사라짐 (ServeCartService)
	local cartSet = SS:FindFirstChild("CartSet")
	if cartSet then
		local want = (#list > 0) and plr:GetAttribute("HasCartPass") == true
		if want ~= (plr:GetAttribute("CartOn") == true) then pcall(function() cartSet:Invoke(plr, want) end) end
	end
	local cart = plr:GetAttribute("CartOn") and ch:FindFirstChild("ServeCart") or nil
	local trayMode = (not cart) and (tonumber(plr:GetAttribute("UpgTray")) or 0) >= 1 and #list > 0
	setTrays(ch, torso, fwd, trayMode)
	ch:SetAttribute("TrayHold", trayMode or nil)
	local head = ch:FindFirstChild("Head")
	for i, t in ipairs(list) do
		-- (11/19) 손에 들 때는 개수도 키에 넣음: 1개 → 2개가 되면 먼저 든 그릇도 가운데에서 오른손으로 다시 옮김 (예전엔 가운데 몸통 앞에 남았음)
		local slotKey = (cart and "C" or (trayMode and "T" or "H")) .. i .. ((not cart and not trayMode) and ("/" .. math.min(#list, 2)) or "")
		local cw = t.bowl.PrimaryPart:FindFirstChild("CarryWeld")
		if cw and cw.Part0 and cw.Part0.Parent and cw.Part0:IsDescendantOf(ch) and t.bowl:GetAttribute("CarrySlot") == slotKey then t.bowl.Parent = ch; continue end
		t.bowl:SetAttribute("CarrySlot", slotKey)
		-- 먼저 몸에서 떼고(고정) → 크기 바꾸기 → 다시 붙이기. 붙은 채로 크기를 바꾸면 캐릭터가 순간이동하며 끼임
		for _, w in ipairs(t.bowl:GetDescendants()) do if w.Name == "CarryWeld" then w:Destroy() end end
		t.bowl.PrimaryPart.Anchored = true
		-- 쟁반·카트 위에서는 그릇을 조금 작게 (내려놓을 때 원래 크기로)
		setCarryScale(t.bowl, cart and CART_SCALE or (trayMode and TRAY_SCALE or 1))
		-- 들고 있는 그릇은 무게·충돌 없음 (벽·의자에 걸려 끼이지 않게)
		for _, p in ipairs(t.bowl:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false; p.Massless = true end end
		local anchorPart = torso
		if cart then
			-- 서빙 카트: 윗칸 4개 먼저, 그다음 아랫칸 4개 (Spot1..8)
			local spot = cart:FindFirstChild("Spot" .. i)
			local bbCF, bbSize = t.bowl:GetBoundingBox()
			local pivotToBottom = t.bowl:GetPivot().Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
			local base = spot and (spot.Position - Vector3.new(0, spot.Size.Y / 2, 0)) or (torso.CFrame * CFrame.new(0, -0.35, -1.3)).Position
			t.bowl:PivotTo(CFrame.new(base + Vector3.new(0, pivotToBottom + 0.02, 0)) * CFrame.lookAt(Vector3.zero, fwd))
			anchorPart = spot or torso
		elseif trayMode then
			-- 오른쪽 쟁반 1·3·5번 (바깥 · 안 · 가운데), 왼쪽 쟁반 2·4번
			local tray = ch:FindFirstChild((i % 2 == 1) and "CarryTrayR" or "CarryTrayL")
			local bbCF, bbSize = t.bowl:GetBoundingBox()
			local pivotToBottom = t.bowl:GetPivot().Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
			local z = (i <= 2) and 0.6 or -0.6   -- 쟁반 위 바깥쪽 먼저, 그다음 안쪽 (1·3 오른쪽, 2·4 왼쪽)
			local base = tray and (tray.CFrame * CFrame.new(z, tray.Size.Y / 2, 0)).Position or (torso.CFrame * CFrame.new(0, -0.35, -1.3)).Position
			t.bowl:PivotTo(CFrame.new(base + Vector3.new(0, pivotToBottom + 0.01, 0)) * CFrame.lookAt(Vector3.zero, fwd))
			anchorPart = tray or torso
		elseif i == 3 and head then
			-- 세 번째 그릇: 머리 위에 이고 감
			local bbCF, bbSize = t.bowl:GetBoundingBox()
			local pivotToBottom = t.bowl:GetPivot().Position.Y - (bbCF.Position.Y - bbSize.Y / 2)
			-- 머리 꼭대기: 머리에 붙은 모자/머리카락 위로 (너무 큰 모자는 1.8스터드까지만)
			local headTop = head.Position.Y + head.Size.Y / 2
			local topY = headTop
			for _, acc in ipairs(ch:GetChildren()) do
				local h = acc:IsA("Accessory") and acc:FindFirstChild("Handle")
				-- 머리 쪽 장신구 (가운데가 목보다 위 + 머리 가까이)
				local nearHead = h and h:IsA("BasePart") and h.Position.Y >= head.Position.Y - head.Size.Y / 2
					and (Vector3.new(h.Position.X, 0, h.Position.Z) - Vector3.new(head.Position.X, 0, head.Position.Z)).Magnitude < 2.5
				if nearHead and h.Transparency < 1 then
					local cf, sz = h.CFrame, h.Size
					local halfY = math.abs(cf.RightVector.Y) * sz.X / 2 + math.abs(cf.UpVector.Y) * sz.Y / 2 + math.abs(cf.LookVector.Y) * sz.Z / 2
					topY = math.max(topY, h.Position.Y + halfY)
				end
			end
			topY = math.min(topY, headTop + 1.8)
			local top = Vector3.new(head.Position.X, topY + 0.02, head.Position.Z)
			t.bowl:PivotTo(CFrame.new(top + Vector3.new(0, pivotToBottom, 0)) * CFrame.lookAt(Vector3.zero, fwd))
			anchorPart = head
		else
			-- 2개: 각 손 앞 (어깨 너비만큼 벌림 - 큰 아바타도 몸통에 안 박히게)
			local sa = torso:FindFirstChild("RightShoulderRigAttachment")
			local sx = sa and math.abs(sa.Position.X) or 1
			local x = (#list >= 2) and ((i == 1) and 1 or -1) * math.max(spread, sx * 0.95 + 0.15) or 0
			t.bowl:PivotTo(CFrame.new((torso.CFrame * CFrame.new(x, -0.35, -1.3)).Position) * CFrame.lookAt(Vector3.zero, fwd))
		end
		local w = Instance.new("WeldConstraint"); w.Name = "CarryWeld"; w.Part0 = anchorPart; w.Part1 = t.bowl.PrimaryPart; w.Parent = t.bowl.PrimaryPart
		t.bowl.PrimaryPart.Anchored = false
		t.bowl.Parent = ch
	end
	ch:SetAttribute("HoldingBowl", #list > 0 or nil)
	ch:SetAttribute("HoldTwo", ((not cart) and (not trayMode) and #list >= 2) or nil)   -- 팔을 양쪽으로 벌려 한 손에 하나씩 (TwoHandHold)
end
-- a carried ticket is gone (served / dropped): free its slot, keep slot 1 filled first
local function releaseCarry(plr, id)
	-- 남은 그릇을 앞 칸부터 다시 채움 (손 먼저, 머리는 마지막)
	local left = {}
	for _, a in ipairs(CARRY_SLOTS) do
		local v = plr:GetAttribute(a)
		if v and v ~= id then table.insert(left, v) end
	end
	for k, a in ipairs(CARRY_SLOTS) do
		if plr:GetAttribute(a) ~= left[k] then plr:SetAttribute(a, left[k]) end
	end
	carryLayout(plr)
end

-- 서빙 카트를 켜고 끌 때 들고 있는 그릇 자리 다시 잡기: ServerStorage.CarryRelayout:Fire(player)
do
	local ev = SS:FindFirstChild("CarryRelayout") or Instance.new("BindableEvent"); ev.Name = "CarryRelayout"; ev.Parent = SS
	ev.Event:Connect(function(plr) if plr and plr.Parent then pcall(carryLayout, plr) end end)
end

-- Studio 테스트용: ServerStorage.CarryTest:Invoke(player, n) = 가짜 그릇 n개 들기 / (player, 0) = 내려놓기
if game:GetService("RunService"):IsStudio() then
	local bf = SS:FindFirstChild("CarryTest") or Instance.new("BindableFunction"); bf.Name = "CarryTest"; bf.Parent = SS
	bf.OnInvoke = function(plr, n)
		for k, a in ipairs(CARRY_SLOTS) do
			local id = plr:GetAttribute(a)
			if id and id < 0 then local t = tickets:get(id); if t and t.bowl then t.bowl:Destroy() end; tickets:remove(id); plr:SetAttribute(a, nil) end
		end
		for k = 1, math.min(n or 0, #CARRY_SLOTS) do
			local id = -k
			local bowl = Assets.Bowl:Clone(); bowl.Parent = workspace
			tickets:register({ bowl = bowl, carrier = plr, menu = "테스트", spice = 0, weight = 0, price = 0 }, "carried", id)
			plr:SetAttribute(CARRY_SLOTS[k], id)
		end
		carryLayout(plr)
		return true
	end
end

local CHAT_EAT = { "와 맛있다", "국물 미쳤다", "맵다 맵다", "역시 여기야", "한 입만!" }

-- 서빙한 그릇을 테이블에 내려놓기 (들고 있던 동안 플레이어 화면이 위치를 잡고 있어서, 놓은 뒤 한 번 더 밀어줘야 화면에서도 테이블로 감)
local function placeOnTable(bowl, cf)
	-- 들고 있던 그릇을 그대로 옮기면, 플레이어 화면에서는 아직 손에 붙어 있어서 캐릭터가 테이블 쪽으로 끌려가며 끼임
	-- → 몸에서 뗀 뒤 복사본을 테이블에 놓고, 들고 있던 원본은 지움
	for _, w in ipairs(bowl:GetDescendants()) do if w.Name == "CarryWeld" then w:Destroy() end end
	local placed = bowl:Clone()
	bowl:Destroy()
	for _, p in ipairs(placed:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = (p == placed.PrimaryPart) end end
	setCarryScale(placed, 1)   -- 쟁반·카트에서 작아졌던 그릇을 원래 크기로
	placed:SetAttribute("CarrySlot", nil)
	placed.PrimaryPart.Anchored = true
	placed:PivotTo(cf)
	placed.Parent = fxFolder
	return placed
end

if game:GetService("RunService"):IsStudio() then
	local bf = SS:FindFirstChild("CarryServeTest") or Instance.new("BindableFunction"); bf.Name = "CarryServeTest"; bf.Parent = SS
	bf.OnInvoke = function(plr)
		local id = plr:GetAttribute("CarryTicket"); local t = id and tickets:get(id)
		if not t then return "none" end
		local root = plr.Character.HumanoidRootPart
		t.bowl = placeOnTable(t.bowl, CFrame.new(root.Position + root.CFrame.LookVector * 8))
		tickets:setState(t, "done"); releaseCarry(plr, id)
		return "served"
	end
end

local Kitchen = require(customerModules:WaitForChild("Kitchen"))
local stations = Kitchen.new(fxFolder, tickets)
local Serving = require(customerModules:WaitForChild("Serving"))
local serving = Serving.new({
	kitchen = stations,
	tickets = tickets,
	placeOnTable = placeOnTable,
	releaseCarry = releaseCarry,
	carryLayout = carryLayout,
	near = near,
	notify = notify,
	skinOf = skinOf,
	skinStyle = SkinStyle,
	carryConfig = CarryCfg,
	refreshBoard = refreshBoard,
	reward = reward,
})

local function serveTo(c, plr)
	if not serving:deliverToNPC(c, plr) then return false end
	local t = c.ticket
	-- 💀 해골 소스 (11/19): 한 입 먹고 불타면서 비명 지르며 뛰쳐나감. 보상 없음 (연출: SkullService)
	if t.skull then
		c.served = true; c.skullRun = true
		c.model:SetAttribute("TicketId", nil)
		local be = SS:FindFirstChild("SkullServed"); if be then be:Fire(c.model, plr) end
		-- (11/22) 서빙한 사람은 손님이 도망가도 정상 팁 (같이 일하는 알바생이 손해 보지 않게)
		reward(plr, "Serve", math.floor(C.TipMax * math.clamp(1 - (os.clock() - (c.foodWaitStart or os.clock())) / C.PatienceFood, 0, 1) * rushTipMult() / 10 + 0.5) * 10, "서빙", richMult(t)); pumpkinBonus(plr, t)
		notify(plr, "💀 해골 소스! 손님이 불타며 도망갔어요")
		task.spawn(function()
			task.wait(1.4)
			if not c.alive then return end
			sfx("Wrong", c.root, 0.6, 40)
			if c.hum then c.hum.WalkSpeed = 24 end
			npc.leave(c, false)
		end)
		return true
	end
	-- tip: faster and correct = more
	local waited = os.clock() - (c.foodWaitStart or os.clock())
	local speed = math.clamp(1 - waited / C.PatienceFood, 0, 1)
	local tip = math.floor(C.TipMax * speed * (t.correct and 1 or C.WrongSpicePenalty) * rushTipMult() / 10 + 0.5) * 10
	reward(plr, "Serve", tip, "서빙", richMult(t)); pumpkinBonus(plr, t)
	if rushOn() then plr:SetAttribute("RushServed", (tonumber(plr:GetAttribute("RushServed")) or 0) + 1) end
	-- 리치맨/슈퍼 리치맨: 실제로 받은 팁(배율 적용)을 보여줌 (예전엔 배율 전 팁만 떠서 "리치맨이 200원 줌"으로 보였음) (11/18)
	local tipMult = richMult(t)
	if tip > 0 and tipMult > 1 then
		notify(plr, string.format(t.superRich and "👑 SUPER RICH MAN 팁! +%s원 (x%d)" or "💰 RICH MAN 팁! +%s원 (x%d)", tostring(tip * tipMult), tipMult))
	else
		notify(plr, tip > 0 and string.format("서빙 완료! 팁 +%s원", tostring(tip)) or "서빙 완료!")
	end
	if t.superRich then
		-- 👑 황금 팁: 룰렛 1회 + 전체 공지
		task.spawn(function()
			local bf = SS:FindFirstChild("GrantFreeSpins")
			if bf then pcall(function() bf:Invoke(plr, "original", 1) end) end
			notify(plr, "👑 SUPER RICH MAN의 황금 팁! 룰렛 1회를 받았어요")
		end)
		if announceRE then announceRE:FireAllClients({ kind = "rich", icon = "👑", title = "SUPER RICH MAN 만족!", text = string.format("%s님이 응대 성공! 보상 %d배 + 룰렛 1회", plr.DisplayName, C.SuperRichMult or 15) }) end
	end
	say(c, t.correct and "맛있겠다!" or "맵기가 좀 다른데...", false)
	if not t.correct then sfx("Wrong", c.root, 0.3, 40) end
	task.spawn(function()
		task.wait(2)
		if not c.alive then return end
		say(c, nil)
		c.model:SetAttribute("TicketId", nil)
		c.served = true
		-- a group starts eating only once everyone's food is on the table
		if c.group then
			local t0, said = os.clock(), false
			while c.alive and not c.leaving and os.clock() - t0 < 240 do
				local waiting = false
				for _, m in ipairs(c.group.members) do
					if m ~= c and m.alive and not m.leaving and not m.served then waiting = true end
				end
				if not waiting then break end
				if not said then
					said = true
					say(c, pick({ "다 나오면 같이 먹자", "기다릴게~", "먼저 안 먹어!" }), false)
					task.delay(2.5, function() if c.alive and not c.leaving and not c.model:GetAttribute("Eating") then say(c, nil) end end)
				end
				task.wait(0.5)
			end
			if not c.alive or c.leaving then return end
			-- small pause so the whole table picks up their chopsticks together
			task.wait(0.3 + math.random() * 0.6)
		end
		local hand = c.model:FindFirstChild("RightHand")
		local sticks = Assets:FindFirstChild("Chopsticks")
		local isDrink = c.ticket and c.ticket.menu == "음료"
		if isDrink then
			-- 음료는 젖가락 없이 캔을 손에 들고 후루룩
			sticks = nil
			local canPart = c.tableBowl and c.tableBowl:FindFirstChild("Can")
			if hand and canPart then
				for _, x in ipairs(canPart:GetChildren()) do if x:IsA("WeldConstraint") then x:Destroy() end end
				canPart.Anchored = false
				canPart.CFrame = hand.CFrame * CFrame.new(0, -0.35, -0.25)
				local w = Instance.new("WeldConstraint"); w.Part0 = hand; w.Part1 = canPart; w.Parent = canPart
				canPart.Parent = c.model
			end
		end
		if hand and sticks then
			sticks = sticks:Clone()
			-- held in the fist, sticks running out past the fingers
			local grip = hand.CFrame * CFrame.new(0, -0.15, -0.05) * CFrame.Angles(math.rad(-160), 0, math.rad(-10)) * CFrame.new(0, 0.4, 0)
			sticks:PivotTo(grip)
			local main = sticks.PrimaryPart
			local w = Instance.new("Weld"); w.Part0 = hand; w.Part1 = main; w.C0 = hand.CFrame:Inverse() * main.CFrame; w.Parent = main
			sticks.Parent = c.model
		end
		c.model:SetAttribute("Eating", true)            -- TwoHandHold (client) moves the arm bowl -> mouth
		-- the food in the bowl disappears a little at a time
		local food = {}
		if c.tableBowl and not isDrink then for _, p in ipairs(c.tableBowl:GetDescendants()) do if p:IsA("MeshPart") and p.Name:sub(1, 4) ~= "Skin" then table.insert(food, p) end end end
		local nextSip = os.clock() + 1
		for i = #food, 2, -1 do local j = math.random(1, i); food[i], food[j] = food[j], food[i] end
		local toEat = math.floor(#food * 0.85)
		local tEnd = os.clock() + C.EatTime
		local nextChat = os.clock() + 4 + math.random() * 6
		local eaten = 0
		while c.alive and os.clock() < tEnd do
			task.wait(0.5)
			local due = math.floor(toEat * (1 - (tEnd - os.clock()) / C.EatTime))
			while eaten < due do eaten += 1; local p = food[eaten]; if p and p.Parent then p:Destroy() end end
			if isDrink and os.clock() > nextSip then nextSip = os.clock() + 3 + math.random() * 2; sfx("Slurp", hand or c.root, 0.5, 40) end
			if os.clock() > nextChat then nextChat = os.clock() + 8 + math.random() * 8; if math.random() < 0.6 then npc.chat(c, CHAT_EAT, false) end end
		end
		if c.model then c.model:SetAttribute("Eating", nil) end
		if isDrink and c.model then local cp = c.model:FindFirstChild("Can"); if cp then cp:Destroy() end end   -- 다 마신 캔은 치움
		c.doneEating = true
		-- friends leave together (but nobody waits forever)
		if c.group and c.alive then
			local t0 = os.clock()
			local said = false
			while c.alive and os.clock() - t0 < 30 do
				local waiting = false
				for _, m in ipairs(c.group.members) do
					if m ~= c and m.alive and not m.leaving and m.seatRec and not m.doneEating then waiting = true end
				end
				if not waiting then break end
				if not said then said = true; say(c, "천천히 먹어~", false); task.delay(2.5, function() if c.alive and not c.leaving then say(c, nil) end end) end
				task.wait(1)
			end
		end
		if c.alive then npc.leave(c, false) end
	end)
	return true
end

----------------------------------------------------------------- 1) take order at the POS
for i, reg in ipairs(REGISTERS) do
	reg.line = {}
	local anchor = reg.posModel and (reg.posModel.PrimaryPart or reg.posModel:FindFirstChildWhichIsA("BasePart"))
	if anchor then
		local pp = Instance.new("ProximityPrompt")
		pp.Name = "TakeOrder"; pp.ActionText = "주문 받기"; pp.ObjectText = "계산대 " .. i   -- (11/21) E 한 번 = 주문 접수 (포스기 창 끔)
		pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0; pp.MaxActivationDistance = 9; pp.RequiresLineOfSight = false   -- (손님용 F 주문하기 8보다 멀리서도 보이게)
		-- 계산대 앞이 붐빔 때(리치맨 이벤트) 근처 서빙·그릇·의자 E 버튼에 가려지지 않게 항상 보이기
		pp.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow
		pp.Enabled = false; pp.Parent = anchor
		reg.prompt = pp
		reg.anchor = anchor
		-- 맨 앞에서 주문 기다리는 손님 (포스기 말풍선이 보고 붙음)
		local fv = anchor:FindFirstChild("Front") or Instance.new("ObjectValue"); fv.Name = "Front"; fv.Parent = anchor
		reg.frontValue = fv
		anchor:SetAttribute("RegIndex", i)
		-- (11/18) E → 계산대 모드 열기. 실제 주문 접수는 포스기에서 맞게 결제했을 때(posRF)
		pp.Triggered:Connect(function(plr)
			if not near(plr, anchor.Position, 12) then return end
			-- (11/21) 예전처럼 E 한 번이면 맨 앞 손님 주문 접수 (포스기 창 안 띄움). 되돌리려면 아래 3줄 대신 POSReg/posRE open 사용
			local c = reg.line[1]
			if not c or not c.alive or c.waitStage ~= "order" then notify(plr, "손님을 기다리는 중이에요"); return end
			local perfect = c.orderReadyAt ~= nil and (os.clock() - c.orderReadyAt) <= 10
			reg.takeOrder(plr, { perfect = perfect, extra = perfect and math.floor(C.Reward.TakeOrder.Money * 0.2) or 0 })
		end)
		reg.takeOrder = function(plr, bonus)
			-- 계산대 두 개 사이에서 한 번에 둘 다 눌리는 것 방지 (11/14)
			local lt = plr:GetAttribute("LastTakeOrder")
			if lt and os.clock() - lt < 0.35 then return end
			local c = reg.line[1]
			if not c or not c.alive or c.waitStage ~= "order" then return end
			c.waitStage = nil
			plr:SetAttribute("LastTakeOrder", os.clock())
			table.remove(reg.line, 1); c.queueReg = nil
			local t = c.ticket
			tickets:register(t, "ordered")
			t.orderedBy = plr
			t.kinds = c.bowlKinds
			handOver(c, reg)
			refreshBoard()
			reward(plr, "TakeOrder", (bonus and bonus.extra) or 0, (bonus and bonus.perfect) and "완벽 주문" or "주문 받기", richMult(t)); pumpkinBonus(plr, t)
			sfx("CashRegister", anchor, 0.6)
			notify(plr, string.format("주문 #%d 접수", t.id))
			npc.seatAfterOrder(c, t, function()
				-- serve prompt on the customer
				local sp = Instance.new("ProximityPrompt")
				sp.Name = "Serve"; sp.ActionText = "서빙하기"; sp.ObjectText = "주문 #" .. t.id
				sp.KeyboardKeyCode = Enum.KeyCode.E; sp.HoldDuration = 0.3; sp.MaxActivationDistance = 8; sp.RequiresLineOfSight = false
				sp.Parent = c.root
				c.servePrompt = sp
				sp.Triggered:Connect(function(plr2)
					if not near(plr2, c.root.Position, 12) then return end
					local carrying = plr2:GetAttribute("CarryTicket")
					if not carrying then notify(plr2, "먼저 패스대에서 그릇을 들어주세요"); return end
					if not isCarrying(plr2, t.id) then
						local ids = CarryCfg.ids(plr2)
						if #ids == 1 then notify(plr2, string.format("들고 있는 건 #%d, 이 손님은 #%d예요", ids[1], t.id))
						else
							local s = {}
							for _, v in ipairs(ids) do table.insert(s, "#" .. v) end
							notify(plr2, string.format("이 손님은 #%d예요 · 들고 있는 그릇: %s", t.id, table.concat(s, ", ")))
						end
						return
					end
					serveTo(c, plr2)
				end)
			end)
		end
	end
end
-- (11/18) 포스기 결제: 메뉴·맵기가 손님 주문과 맞으면 접수. 틀리면 손님이 다시 말해줌
--   맞게 + 빨리(맨 앞에 선 뒤 10초 안) + 한 번에 = 「완벽 주문」 보너스
posRF.OnServerInvoke = function(plr, regIdx, npc, menu, spice)
	regIdx = tonumber(regIdx)
	local reg = regIdx and REGISTERS[regIdx]
	if not reg or not reg.anchor or plr:GetAttribute("POSReg") ~= regIdx then return false, "far" end
	if not near(plr, reg.anchor.Position, 16) then return false, "far" end
	local c = reg.line[1]
	if not c or not c.alive or c.waitStage ~= "order" or c.model ~= npc then return false, "gone" end
	local now = os.clock()
	if c.posLast and now - c.posLast < 0.4 then return false, "wait" end
	c.posLast = now
	local t = c.ticket
	if type(menu) ~= "string" then return false, "wrong" end
	local ok = (menu == t.menu) and (t.side or tonumber(spice) == t.spice)
	if not ok then
		c.posMistakes = (c.posMistakes or 0) + 1
		local want = t.side and t.menu or (t.menu .. " · " .. C.SpiceShort[t.spice])
		say(c, "아니에요! " .. want .. "요!", true)
		task.delay(1.8, function()
			if c.alive and c.waitStage == "order" then
				if t.side then say(c, string.format("%s 하나 주세요!", t.menu), true)
				else say(c, string.format("%s · %s\n%dg 주문할게요!", t.menu, C.SpiceShort[t.spice], t.weight), true) end
			end
		end)
		return false, "wrong"
	end
	local perfect = (c.posMistakes or 0) == 0 and c.orderReadyAt ~= nil and (now - c.orderReadyAt) <= 10
	local extra = perfect and math.floor(C.Reward.TakeOrder.Money * 0.2) or 0   -- (11/21: 0.6 → 0.2) 결제 버튼만 누르면 돼서 거의 매번 완벽 주문
	reg.takeOrder(plr, { perfect = perfect, extra = extra })
	if t.state == "ordered" then return true, t.id, perfect end
	return false, "gone"
end
posRE.OnServerEvent:Connect(function(plr, action)
	if action == "close" then plr:SetAttribute("POSReg", nil) end
end)
-- 줄 감시 (11/15): 맨 앞 손님이 계산대까지 못 와서 줄 전체가 멈추는 것 방지
--   · 죽었거나 이미 다른 단계로 간 손님은 줄에서 빼기
--   · 맨 앞 손님이 12초 넘게 '주문할게요' 상태가 아니면 → 계산대 앞으로 옮기고 바로 주문 받게
task.spawn(function()
	while true do
		task.wait(2)
		for _, reg in ipairs(REGISTERS) do
			local ghosts = {}
			for i = #reg.line, 1, -1 do
				local q = reg.line[i]
				if not q or not q.alive or not q.ticket or q.ticket.state ~= "queue" or not (q.model and q.model.Parent) then
					table.remove(reg.line, i)
					if q and q.queueReg == reg then q.queueReg = nil end
				else
					-- 줄에 이름만 있고 실제로는 멀리(30스터드+) 20초 넘게 있는 손님 → 내보내서 자리 비움
					local spot = reg.queue[math.min(i, #reg.queue)]
					local far = (not q.root) or (q.root.Position - spot).Magnitude > 30
					if far then
						q.farSince = q.farSince or os.clock()
						if os.clock() - q.farSince > 20 then table.insert(ghosts, q) end
					else
						q.farSince = nil
					end
				end
			end
			for _, q in ipairs(ghosts) do
				warn("[CustomerService] 줄에만 있고 멀리 있던 손님 정리 (계산대 " .. tostring(table.find(REGISTERS, reg)) .. ")")
				task.spawn(npc.leave, q, false)
			end
			local c = reg.line[1]
			if c and c.waitStage ~= "order" then
				c.frontSince = c.frontSince or os.clock()
				if os.clock() - c.frontSince > 12 then
					c.frontSince = nil
					c.forcedFront = true
					local spot = reg.queue[1]
					pcall(function()
						local y = c.root.Position.Y
						if math.abs(y - spot.Y) > 6 then y = spot.Y end   -- (다른 층에 있으면 1층 계산대 높이로)
						c.root.CFrame = CFrame.lookAt(Vector3.new(spot.X, y, spot.Z), Vector3.new(spot.X, y, spot.Z + 1))
						c.hum:MoveTo(c.root.Position)
					end)
					local tk = c.ticket
					if tk.side then say(c, string.format("%s 하나 주세요!", tk.menu), true)
					else say(c, string.format("%s · %s\n%dg 주문할게요!", tk.menu, C.SpiceShort[tk.spice], tk.weight), true) end
					npc.patience(c, C.PatienceOrder, "order", function() npc.leave(c, true) end)
					warn("[CustomerService] 줄 맨 앞 손님이 막혀서 계산대로 옮김 (계산대 " .. tostring(table.find(REGISTERS, reg)) .. ")")
				end
			elseif c then
				c.frontSince = nil
			end
		end
	end
end)
-- show the POS prompt only when someone is waiting at the front
task.spawn(function()
	while true do
		for _, reg in ipairs(REGISTERS) do
			if reg.prompt then
				local c = reg.line[1]
				local waiting = c ~= nil and c.alive and c.waitStage == "order"
				reg.prompt.Enabled = true   -- (11/18) 손님이 없어도 포스기는 언제든 열 수 있음
				if reg.frontValue then
					local want = waiting and c.model or nil
					if reg.frontValue.Value ~= want then reg.frontValue.Value = want end
				end
			end
		end
		task.wait(0.3)
	end
end)

----------------------------------------------------------------- 2) cook at the ranges
stations:setupRanges(kitchen)

local BROTH = {
	[0] = { broth = Color3.fromRGB(232, 214, 178), oil = Color3.fromRGB(245, 228, 188), ring = Color3.fromRGB(220, 200, 160), drop = Color3.fromRGB(250, 235, 170) },
	[1] = { broth = Color3.fromRGB(222, 142, 78), oil = Color3.fromRGB(236, 158, 74), ring = Color3.fromRGB(215, 140, 80), drop = Color3.fromRGB(255, 190, 90) },
	[2] = { broth = Color3.fromRGB(196, 72, 32), oil = Color3.fromRGB(222, 92, 32), ring = Color3.fromRGB(200, 80, 35), drop = Color3.fromRGB(255, 150, 45) },
	[3] = { broth = Color3.fromRGB(150, 28, 14), oil = Color3.fromRGB(200, 52, 16), ring = Color3.fromRGB(180, 45, 20), drop = Color3.fromRGB(255, 135, 30) },
	[4] = { broth = Color3.fromRGB(104, 14, 9), oil = Color3.fromRGB(165, 24, 10), ring = Color3.fromRGB(140, 25, 12), drop = Color3.fromRGB(240, 90, 20) },
	[5] = { broth = Color3.fromRGB(28, 6, 26), oil = Color3.fromRGB(90, 10, 60), ring = Color3.fromRGB(70, 0, 50), drop = Color3.fromRGB(120, 255, 90) },   -- 💀 해골 소스 (11/19 게임패스)
}
local function tintBroth(bowl, level)
	level = math.clamp(level or 2, 0, 5)
	local c = BROTH[level]
	local chiliShow = ({ [0] = 0, 1, 3, 5, 6, 6 })[level]
	local chiliN, flakeI = 0, 0
	for _, p in ipairs(bowl:GetChildren()) do
		if p.Name == "Broth" then p.Color = c.broth
		elseif p.Name == "ChiliOil" then p.Color = c.oil; p.Transparency = level == 0 and 0.6 or 0.45
		elseif p.Name == "OilRing" then p.Color = c.ring
		elseif p.Name == "OilDrop" then p.Color = c.drop; p.Transparency = level == 0 and 0.5 or 0.15
		elseif p.Name == "Flake" then flakeI += 1; p.Transparency = (flakeI > level * 7) and 1 or 0
		elseif p.Name == "Peppercorn" then p.Transparency = level < 2 and 1 or 0
		elseif p.Name == "DriedChili" then chiliN += 1; p.Transparency = chiliN > chiliShow and 1 or 0
		elseif p.Name == "ChiliCap" then p.Transparency = chiliN > chiliShow and 1 or 0 end
	end
end

local function weldTo(body, p)
	local w = Instance.new("Weld"); w.Part0 = body; w.Part1 = p; w.C0 = body.CFrame:Inverse() * p.CFrame; w.Parent = p
end
-- 마라샹궈: no broth - a glossy heap of stir-fried ingredients on a wide shallow plate, chilies & peppercorns on top
local function buildShangguo(t)
	local plate = Assets.ShangguoPlate:Clone()
	local body = plate.PrimaryPart
	plate:PivotTo(CFrame.new())                       -- build at the origin, moved to the pass afterwards
	local level = math.clamp(t.cookedSpice or t.spice or 2, 0, 5)
	local c = BROTH[level]
	local floorY = body.Position.Y + 0.08
	local sauce = plate:FindFirstChild("Sauce")
	if sauce then
		sauce.Color = c.broth:Lerp(Color3.new(0, 0, 0), 0.15); sauce.Transparency = level == 0 and 0.4 or 0.05; sauce.Reflectance = 0.3
		sauce.Size = Vector3.new(0.02, 1.7, 1.7)
	end
	local RMAX, PEAK = 0.78, 0.5
	local function top(r) return floorY + 0.05 + (1 - math.clamp(r / RMAX, 0, 1)) * PEAK + 0.1 end
	-- the customer's picks plus the usual 샹궈 fillers, piled into a dense heap
	local kinds = (t.kinds and #t.kinds > 0) and table.clone(t.kinds) or { "fishball", "fuzhu", "quail" }
	for _, k in ipairs({ "lotus", "potato", "widenoodle", "sausage", "friedtofu" }) do table.insert(kinds, k) end
	local heap = {}
	local per = math.max(3, math.ceil(30 / #kinds))
	for _, k in ipairs(kinds) do
		for j = 1, per do
			local p, r0 = miniPiece(k)
			if p then
				p.Size = p.Size * 1.2
				table.insert(heap, p)
				local r = math.sqrt(math.random()) * RMAX; local a = math.random() * math.pi * 2
				local h = floorY + 0.05 + (1 - r / RMAX) * PEAK * (0.6 + math.random() * 0.4)
				p.CFrame = CFrame.new(math.cos(a) * r, h, math.sin(a) * r) * CFrame.Angles(0, math.random() * 6.28, 0)
					* CFrame.Angles(math.random() * 0.8 - 0.4, 0, math.random() * 0.8 - 0.4) * r0
				p.Parent = plate
			end
		end
	end
	local function onHeap()
		if #heap == 0 then local a = math.random() * 6.28; return Vector3.new(math.cos(a) * 0.4, top(0.4), math.sin(a) * 0.4) end
		local h = heap[math.random(1, #heap)]
		local ext = math.max(h.Size.X, h.Size.Y, h.Size.Z)
		return h.Position + Vector3.new((math.random() - 0.5) * ext * 0.6, ext * 0.22, (math.random() - 0.5) * ext * 0.6)
	end
	local function bit(name, size, color, mat, shape, yo)
		local p = Instance.new("Part"); p.Name = name; p.Size = size; p.Color = color; p.Material = mat or Enum.Material.SmoothPlastic
		if shape then p.Shape = shape end
		p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.Massless = true; p.CastShadow = false
		p.CFrame = CFrame.new(onHeap() + Vector3.new(0, yo or 0, 0)) * CFrame.Angles(math.random() * 6.28, math.random() * 6.28, math.random() * 6.28)
		p.Parent = plate
		return p
	end
	for i = 1, ({ [0] = 0, 3, 6, 9, 12, 14 })[level] or 12 do          -- dried chilies, more with more heat
		local ch = bit("DriedChili", Vector3.new(0.34, 0.09, 0.09), Color3.fromRGB(150 + math.random(0, 40), 20, 15), nil, Enum.PartType.Cylinder)
		ch.CFrame = CFrame.new(ch.Position) * CFrame.Angles(0, math.random() * 6.28, (math.random() - 0.5) * 0.4)
		local cap = Instance.new("Part"); cap.Name = "ChiliCap"; cap.Shape = Enum.PartType.Cylinder; cap.Size = Vector3.new(0.05, 0.1, 0.1)
		cap.Color = Color3.fromRGB(70, 90, 30); cap.Material = Enum.Material.SmoothPlastic
		cap.CanCollide = false; cap.CanQuery = false; cap.CanTouch = false; cap.Massless = true; cap.CastShadow = false
		cap.CFrame = ch.CFrame * CFrame.new(0.19, 0, 0); cap.Parent = plate
	end
	for i = 1, (level >= 1 and 6 + level * 3 or 0) do        -- sichuan peppercorns
		bit("Peppercorn", Vector3.new(0.07, 0.07, 0.07), Color3.fromRGB(95, 30, 22), nil, Enum.PartType.Ball)
	end
	for i = 1, 40 do                                          -- glossy chili-oil glaze over the heap
		local d = bit("OilDrop", Vector3.new(0.03, 0.2, 0.2), c.oil, Enum.Material.Glass, Enum.PartType.Ball, -0.03)
		d.Size = Vector3.new(0.2, 0.05, 0.2); d.Shape = Enum.PartType.Block
		d.Transparency = level == 0 and 0.55 or 0.15; d.Reflectance = 0.3
	end
	for i = 1, 20 + level * 14 do                             -- chili flakes stuck to everything
		bit("Flake", Vector3.new(0.07, 0.02, 0.05), Color3.fromRGB(170 + math.random(0, 50), 30, 20))
	end
	for i = 1, 26 do bit("Sesame", Vector3.new(0.05, 0.025, 0.035), Color3.fromRGB(245, 236, 210)) end
	for _, k in ipairs({ "cilantro", "cilantro", "cilantro", "peanut", "peanut", "peanut", "peanut" }) do
		local p, r0 = miniPiece(k)
		if p then
			p.CFrame = CFrame.new(onHeap() + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, math.random() * 6.28, 0) * r0
			p.Parent = plate
		end
	end
	for _, p in ipairs(plate:GetChildren()) do
		if p:IsA("BasePart") and p ~= body and not p:FindFirstChildOfClass("WeldConstraint") then p.Anchored = false; weldTo(body, p) end
	end
	return plate
end

-- 🥡 포장 주문: 그릇을 반투명 비닐봉지로 감싸기 (그릇에 용접 → 같이 움직임, 먹을 때 벗김) (11/16)
local BAG_WHITE = Color3.fromRGB(250, 250, 246)
local BAG_H = 2.2   -- 패스대·들고 갈 때 봉지 높이
local function bagify(bowl)
	if not (bowl and bowl.PrimaryPart) or bowl:FindFirstChild("TakeoutBag") then return end
	local body = bowl.PrimaryPart
	-- 월드 축 기준 크기 (그릇 몸통이 옆으로 누운 실린더라서 직접 계산)
	local mn, mx
	for _, p in ipairs(bowl:GetDescendants()) do
		if p:IsA("BasePart") and p.Transparency < 1 then
			local cf, s = p.CFrame, p.Size / 2
			local ex = Vector3.new(
				math.abs(cf.RightVector.X) * s.X + math.abs(cf.UpVector.X) * s.Y + math.abs(cf.LookVector.X) * s.Z,
				math.abs(cf.RightVector.Y) * s.X + math.abs(cf.UpVector.Y) * s.Y + math.abs(cf.LookVector.Y) * s.Z,
				math.abs(cf.RightVector.Z) * s.X + math.abs(cf.UpVector.Z) * s.Y + math.abs(cf.LookVector.Z) * s.Z)
			local a, b = cf.Position - ex, cf.Position + ex
			mn = mn and mn:Min(a) or a; mx = mx and mx:Max(b) or b
		end
	end
	if not mn then return end
	local mid = (mx + mn) / 2
	local src = Assets:FindFirstChild("TakeoutBag")
	local srcPart = src and src:FindFirstChildWhichIsA("MeshPart", true)
	if not srcPart then return end
	-- 음식은 봉지 안에 숨김 (먹을 때 unbag 으로 되돌림)
	for _, p in ipairs(bowl:GetDescendants()) do
		if p:IsA("BasePart") or p:IsA("Decal") or p:IsA("Texture") then p:SetAttribute("BagT", p.Transparency); p.Transparency = 1 end
	end
	local bp = srcPart:Clone(); bp.Name = "TakeoutBag"
	bp.Size = srcPart.Size * (BAG_H / srcPart.Size.Y)
	bp.CFrame = CFrame.new(mid.X, mn.Y + bp.Size.Y / 2, mid.Z) * srcPart.CFrame.Rotation
	bp.Anchored = false; bp.CanCollide = false; bp.CanQuery = false; bp.CanTouch = false; bp.Massless = true
	local wc = Instance.new("WeldConstraint"); wc.Part0 = body; wc.Part1 = bp; wc.Parent = bp
	bp.Parent = bowl
end
-- 봉지 벗기기 (숨겨 둔 음식 다시 보이게)
local function unbag(bowl)
	if not bowl then return end
	local bag = bowl:FindFirstChild("TakeoutBag"); if bag then bag:Destroy() end
	for _, p in ipairs(bowl:GetDescendants()) do
		local t = p:GetAttribute("BagT")
		if t ~= nil then p.Transparency = t; p:SetAttribute("BagT", nil) end
	end
end

-- 음식 모델 만들기 (패스대에 올릴 때 + 주문 창 메뉴 사진)
local function buildDish(t)
	local bowl
	local dishes = Assets:FindFirstChild("Dishes")
	local sideModel = t.side and dishes and dishes:FindFirstChild(({ ["꿔바로우"] = "Guobaorou", ["볶음밥"] = "FriedRice", ["크림새우"] = "CreamShrimp", ["음료"] = "Drink" })[t.menu] or "")
	if sideModel then
		bowl = sideModel:Clone()
		for _, p in ipairs(bowl:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = false end end
	elseif t.menu == "마라샹궈" and Assets:FindFirstChild("ShangguoPlate") then
		bowl = buildShangguo(t)
	else
	bowl = Assets.Bowl:Clone()
	tintBroth(bowl, t.cookedSpice or t.spice)
	do
		-- cooked malatang: noodles + bok choy underneath, the customer's picks on top, cilantro & peanuts to finish
		local body = bowl.PrimaryPart
		local up, ax1, ax2 = body.CFrame.RightVector, body.CFrame.UpVector, body.CFrame.LookVector
		local kinds = (t.kinds and #t.kinds > 0) and t.kinds or { "fishball", "fuzhu", "quail" }
		local plan
		if t.list and #t.list > 0 then
			-- 플레이어 주문: 그릇에 담은 그대로 (재료 종류 + 개수), 안 담은 건 안 넣음
			local count, order = {}, {}
			for _, k in ipairs(t.list) do if not count[k] then count[k] = 0; table.insert(order, k) end; count[k] += 1 end
			plan = {}
			for i, k in ipairs(order) do table.insert(plan, { k, count[k], 0.06 + (i - 1) * 0.008, true }) end
		else
			plan = { {"glassnoodle", 3, 0.0}, {"bokchoy", 2, 0.03} }
			for _, k in ipairs(kinds) do table.insert(plan, { k, 3, 0.06 }) end
			table.insert(plan, { "cilantro", 3, 0.14 })
			table.insert(plan, { "peanut", 2, 0.14 })
		end
		local placed = 0
		for _, item in ipairs(plan) do
			for j = 1, item[2] do
				local p, r0 = miniPiece(item[1])
				if p then
					placed += 1
					local r = math.sqrt(math.random()) * 0.62
					local ang = math.random() * math.pi * 2
					-- lower layers sit half in the broth (surface ~0.27), the mound rises in the middle
					local h = 0.21 + item[3] + (1 - r / 0.62) * 0.12 + math.random() * 0.04
					local pos = body.Position + up * h + (ax1 * math.cos(ang) + ax2 * math.sin(ang)) * r
					p.CFrame = CFrame.fromMatrix(pos, ax1, up) * CFrame.Angles(0, math.random() * 6.28, 0) * CFrame.Angles(math.random() * 0.5 - 0.25, 0, math.random() * 0.5 - 0.25) * r0
					if item[4] then
						-- 플레이어 그릇: 담을 때와 비슷한 크기로, 국물 위로 보이게
						local mx = math.max(p.Size.X, p.Size.Y, p.Size.Z)
						if mx > 0 then p.Size = p.Size * (0.42 / mx) end
						local h2 = 0.27 + item[3] + (1 - r / 0.62) * 0.1 + math.min(placed, 15) * 0.006
						p.CFrame = p.CFrame + up * (h2 - h)
					else
						p.Size = p.Size * 0.9
					end
					local w = Instance.new("WeldConstraint"); w.Part0 = body; w.Part1 = p; w.Parent = p
					p.Parent = bowl
				end
			end
		end
	end
	end
if t.cookedSpice == 5 then   -- 💀 해골 소스: 건더기(야채·고기)까지 시커멓게 물듦
		pcall(function()
			for _, p in ipairs(bowl:GetDescendants()) do
				if p:IsA("MeshPart") and p ~= bowl.PrimaryPart and p.Name:sub(1, 4) ~= "Skin" then
					for _, x in ipairs(p:GetChildren()) do if x:IsA("SurfaceAppearance") then x:Destroy() end end
					p.TextureID = ""
					local k = math.random(0, 18)
					p.Color = Color3.fromRGB(26 + k, 10 + k // 3, 30 + k); p.Material = Enum.Material.SmoothPlastic; p.Reflectance = 0.08
				end
			end
		end)
	end
	return bowl
end

local function placeOnPass(t)
	local bowl = stations:placeOnPass(t, buildDish, bagify)
	if not bowl then return false end
	sfx("OrderReady", bowl.PrimaryPart, 0.7, 80)
	local tag = Instance.new("BillboardGui"); tag.Name = "Tag"; tag.Size = UDim2.fromOffset(64, 30); tag.StudsOffset = Vector3.new(0, 1, 0); tag.LightInfluence = 0; tag.MaxDistance = 35; tag.Parent = bowl.PrimaryPart
	local tf = Instance.new("Frame"); tf.Size = UDim2.fromScale(1, 1); tf.BackgroundColor3 = RED; tf.Parent = tag
	local tc = Instance.new("UICorner"); tc.CornerRadius = UDim.new(0.4, 0); tc.Parent = tf
	label(tf, "#" .. t.id, UDim2.fromScale(1, 1), CREAM)
	refreshBoard()
	serving:makePickup(t)
	return true
end

do
	local bf = SS:FindFirstChild("PutBackCarry") or Instance.new("BindableFunction"); bf.Name = "PutBackCarry"; bf.Parent = SS
	bf.OnInvoke = function(plr) return serving:putBack(plr) end
end

-- cooking show: pot on the flame -> broth poured -> the customer's ingredients drop in -> boil -> spice -> into the bowl
local function potLocal(r, cf) return r.pot.PrimaryPart.CFrame * cf end
local function brothCF(r, y) return potLocal(r, CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90))) end

----------------------------------------------------------------- 직접 조리 (11/18): 재료 고르기 → 불 조절 → 마라소스 붓기
--   C.InteractiveCook = false 면 예전 자동 조리 그대로. 클라가 안 따라오면(시간 초과 / 멀어짐 / ✕) 자동 조리로 넘어감
--   판정은 전부 서버: 고른 재료, 불 조절 최소 시간, 소스 붓기(누른 시간 × 속도 → 맵기 단계)
local cookRF = remotes:FindFirstChild("CookAct") or Instance.new("RemoteFunction"); cookRF.Name = "CookAct"; cookRF.Parent = remotes
local cookRE = remotes:FindFirstChild("CookUI") or Instance.new("RemoteEvent"); cookRE.Name = "CookUI"; cookRE.Parent = remotes
if ingLib and not RS:FindFirstChild("CookIngredientMeshes") then
	-- 재료 카드 3D 미리보기용 (MeshPart + SurfaceAppearance 만)
	local cp = Instance.new("Folder"); cp.Name = "CookIngredientMeshes"
	for _, m in ipairs(ingLib:GetChildren()) do
		local mp = m:FindFirstChildWhichIsA("MeshPart", true)
		if mp then
			local c = mp:Clone()
			for _, k in ipairs(c:GetChildren()) do if not k:IsA("SurfaceAppearance") then k:Destroy() end end
			c.Name = m.Name; c.Anchored = true; c.CanCollide = false; c.Parent = cp
		end
	end
	cp.Parent = RS
end
local IA_TIMEOUT = 45
local HEAT_MIN = 3
local function iaOn(r, t) return C.InteractiveCook and r.ia ~= nil and r.ia.t == t and not r.ia.auto end
local function iaSend(r, kind, data)
	local ia = r.ia; if not ia or ia.auto or not ia.plr.Parent then return end
	cookRE:FireClient(ia.plr, kind, data)
end
local function iaAuto(r, why)
	local ia = r.ia; if not ia or ia.auto then return end
	ia.auto = true
	print("[Cook] 자동 조리로 전환:", why, ia.stage)
	if ia.plr.Parent then cookRE:FireClient(ia.plr, "auto", { why = why }) end
end
local function waitGate(r, t, name, data)
	if not iaOn(r, t) then return end
	local ia = r.ia
	ia.stage = name; ia.stageAt = os.clock(); ia.done = nil
	data = data or {}; data.stage = name; data.id = t.id; data.pot = r.pot
	iaSend(r, "stage", data)
	while r.ticket == t and r.ia == ia and not ia.auto and ia.done ~= name do
		if os.clock() - ia.stageAt > IA_TIMEOUT or not ia.plr.Parent then iaAuto(r, "timeout"); break end
		if not near(ia.plr, r.anchor.Position, 18) then iaAuto(r, "far"); break end
		task.wait(0.1)
	end
end
local function iaOptions(kinds)
	local need, uniq = {}, {}
	for _, k in ipairs(kinds) do if not need[k] then need[k] = true; table.insert(uniq, k) end end
	local opts = table.clone(uniq)
	local pool = {}
	for _, k in ipairs(INGREDIENT_KEYS) do if not need[k] and k ~= "glassnoodle" then table.insert(pool, k) end end
	local total = math.min(10, math.max(6, #uniq + 3))
	while #opts < total and #pool > 0 do table.insert(opts, table.remove(pool, math.random(#pool))) end
	for i = #opts, 2, -1 do local j = math.random(i); opts[i], opts[j] = opts[j], opts[i] end
	return need, opts, uniq
end
-- 재료 단계: 직접 조리면 true (못 고른 재료는 자동으로 넣음), 아니면 false → 예전 자동 넣기
local function iaIngredients(r, t, kinds, dropOne, first)
	if not C.CookPickIngredients or not iaOn(r, t) then return false end   -- 11/18: 재료는 자동 (고르기 게임 끔)
	local ia = r.ia
	if first then dropOne(first) end
	local need, opts, uniq = iaOptions(kinds)
	ia.need = need; ia.picked = {}; ia.drop = dropOne; ia.coolUntil = 0
	r.txt.Text = string.format("#%d 재료 고르는 중", t.id)
	waitGate(r, t, "ingredients", { opts = opts, need = uniq })
	ia.drop = nil
	for _, k in ipairs(uniq) do
		if not ia.picked[k] then
			if r.ticket ~= t or not r.pot then return true end
			dropOne(k); task.wait(0.15); dropOne(k); task.wait(0.15)
		end
	end
	return true
end
-- 불 조절 단계: 직접 끝내면 true (남은 조리 시간 짧게)
local function iaHeat(r, t, kind)
	if not iaOn(r, t) then return false end
	waitGate(r, t, "heat", { kind = kind })
	return r.ia ~= nil and r.ia.t == t and not r.ia.auto
end
-- 마라소스 단계: 직접 붓기. 시간 초과면 예전 "마라소스 넣기" 버튼으로
local function iaSpiceStage(r, t)
	if not iaOn(r, t) then return false end
	local ia = r.ia
	ia.stage = "pour"; ia.stageAt = os.clock(); ia.pourAt = nil
	ia.speed = 0.3 + math.random() * 0.1
	r.spiceUser = ia.plr; r.spiceAsked = os.clock()
	r.txt.Text = string.format("#%d 마라소스 붓는 중", t.id)
	iaSend(r, "stage", { stage = "pour", id = t.id, spice = t.spice, speed = ia.speed, pot = r.pot })
	task.spawn(function()
		while r.ticket == t and r.state == "spice" and r.ia == ia and not ia.auto do
			if os.clock() - ia.stageAt > IA_TIMEOUT * 2 or not ia.plr.Parent or not near(ia.plr, r.anchor.Position, 18) then iaAuto(r, "timeout"); break end
			task.wait(0.25)
		end
		if r.ticket == t and r.state == "spice" then r.txt.Text = string.format("#%d 마라소스 넣기!", t.id); r.prompt.Enabled = true end
	end)
	return true
end
local function iaResult(r, t, info)
	local ia = r.ia
	if not ia or ia.t ~= t or not ia.plr.Parent then return end
	ia.resulted = true
	if ia.auto then return end
	local rw = C.Reward and C.Reward.Cook
	info.money = (t.playerCustomer ~= ia.plr and rw) and math.floor((rw.Money + (t.share or 0)) * richMult(t)) or 0
	info.id = t.id; info.menu = t.menu; info.spice = t.spice; info.mistakes = ia.mistakes or 0
	cookRE:FireClient(ia.plr, "result", info)
end

local function wokFloor(body, rad)
	return body.Position.Y - 0.28 + 0.2 * rad + 0.13 * rad * rad
end
local function startStirFry(r, t)
	r.pot = Assets.Wok:Clone()
	skinPot(r)
	local seat = CFrame.new(r.seatPos)
	r.pot:PivotTo(seat * CFrame.new(0, 0.8, 0))
	r.pot.PrimaryPart.Anchored = true
	r.pot.Parent = fxFolder
	for i = 1, 8 do if not r.pot then return end; r.pot:PivotTo(seat * CFrame.new(0, 0.8 * (1 - i / 8) ^ 2, 0)); task.wait(0.025) end
	if not r.pot then return end
	r.pot:PivotTo(seat)
	Kitchen.setFlame(r, true)
	local body = r.pot.PrimaryPart
	local restCF = body.CFrame
	local oil = r.pot.Oil
	local steam = body.SteamAtt.Steam
	local sizzle = body:FindFirstChild("Boil")
	-- 1) oil into the hot wok
	r.txt.Text = string.format("#%d 웍에 기름 두르는 중", t.id)
	TS:Create(oil, TweenInfo.new(0.8), { Transparency = 0.35 }):Play()
	if sizzle then sizzle:Play() end
	steam.Rate = 3
	task.wait(0.5)
	if r.ticket ~= t then return end
	-- 2) the customer's ingredients go in
	r.txt.Text = string.format("#%d 재료 넣는 중", t.id)
	local kinds = (t.kinds and #t.kinds > 0) and t.kinds or { "lotus", "fishball", "broccoli" }
	local list = {}
	for _, k in ipairs(kinds) do table.insert(list, k); table.insert(list, k) end
	r.pieces = {}
	local floor = body.Position.Y - body.Size.Y / 2 + 0.14
	local function dropOne(key)
		if r.ticket ~= t or not r.pot then return false end
		local p, r0 = miniPiece(key)
		if not p then return false end
		do
			p.Anchored = true
			local ang, rad = math.random() * math.pi * 2, math.sqrt(math.random()) * 0.7
			local land = Vector3.new(body.Position.X + math.cos(ang) * rad, wokFloor(body, rad) + 0.1 + math.random() * 0.05, body.Position.Z + math.sin(ang) * rad)
			local rot = CFrame.Angles(0, math.random() * 6.28, 0) * r0
			p.CFrame = CFrame.new(land + Vector3.new(0, 1.8, 0)) * rot
			p.Parent = r.pot
			TS:Create(p, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(land) * rot }):Play()
			table.insert(r.pieces, { p = p, land = land, rot = rot })
			task.delay(0.28, function()
				local sp = body.Parent and body:FindFirstChild("Splash")
				if sp then sp.PlaybackSpeed = 0.9 + math.random() * 0.3; sp:Play() end
			end)
		end
		return true
	end
	if not iaIngredients(r, t, kinds, dropOne) then
		for _, key in ipairs(list) do
			if r.ticket ~= t or not r.pot then return end
			if dropOne(key) then task.wait(0.1) end
		end
	end
	if r.ticket ~= t or not r.pot then return end
	-- 3) toss over high heat: the wok flicks and everything jumps
	r.txt.Text = string.format("#%d 센 불에 볶는 중", t.id)
	steam.Rate = 8
	local quick = iaHeat(r, t, "wok")
	if r.ticket ~= t or not r.pot then return end
	local t0 = os.clock()
	local rest = quick and 1.5 or math.max(2, C.CookTime - 3)
	while os.clock() - t0 < rest do
		if r.ticket ~= t or not r.pot then return end
		body.CFrame = restCF * CFrame.new(0.06, 0.1, 0) * CFrame.Angles(0, 0, math.rad(-8))
		for _, it in ipairs(r.pieces) do
			if it.p.Parent then
				local spin = it.rot * CFrame.Angles(math.random() * 3, math.random() * 3, 0)
				it.rot = spin
				local peak = it.land + Vector3.new((math.random() - 0.5) * 0.3, 0.5 + math.random() * 0.6, (math.random() - 0.5) * 0.3)
				TS:Create(it.p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * spin }):Play()
				task.delay(0.22, function()
					if it.p.Parent then TS:Create(it.p, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(it.land) * spin }):Play() end
				end)
			end
		end
		task.wait(0.15)
		if not r.pot then return end
		body.CFrame = restCF
		task.wait(0.85)
	end
	if r.ticket ~= t then return end
	r.state = "spice"; tickets:setState(t, "spice")
	r.txt.Text = string.format("#%d 마라소스 넣기!", t.id)
	r.prompt.ActionText = "마라소스 넣기"; r.prompt.ObjectText = string.format("#%d %s", t.id, t.menu)
	if not iaSpiceStage(r, t) then r.prompt.Enabled = true end
	refreshBoard()
end

local finishCooking   -- defined below
local function sideBits(dish)
	-- pieces that go into the wok for each side dish
	local gen = Assets:FindFirstChild("Dishes") and Assets.Dishes:FindFirstChild("DishGen_원본")
	local out = {}
	local function mesh(name, size)
		local src = gen and gen:FindFirstChild(name)
		local mp = src and src:FindFirstChildWhichIsA("MeshPart", true)
		if not mp then return nil end
		local p = mp:Clone(); for _, k in ipairs(p:GetChildren()) do if not k:IsA("SurfaceAppearance") then k:Destroy() end end
		p.Size = size; p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		return p
	end
	local function blob(size, color)
		local p = Instance.new("Part"); p.Size = size; p.Color = color; p.Material = Enum.Material.SmoothPlastic; p.Shape = Enum.PartType.Ball
		p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
		return p
	end
	if dish == "크림새우" and gen and gen:FindFirstChild("ShrimpGen") then
		-- 튀김새우 메시 (11/16)
		for i = 1, 7 do local p = mesh("ShrimpGen", Vector3.new(0.6, 0.25, 0.21)); if p then table.insert(out, p) end end
	elseif dish == "크림새우" then
		for i = 1, 7 do
			local p = Instance.new("Part"); p.Shape = Enum.PartType.Ball; p.Size = Vector3.new(0.34, 0.26, 0.3)
			p.Color = Color3.fromRGB(240, 170, 120); p.Material = Enum.Material.SmoothPlastic
			p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false; p.CastShadow = false
			table.insert(out, p)
		end
	elseif dish == "꿔바로우" then
		for i = 1, 5 do local p = mesh("CutletGen", Vector3.new(0.62, 0.1, 0.42)); if p then table.insert(out, p) end end
	else
		for i = 1, 4 do table.insert(out, blob(Vector3.new(0.3, 0.12, 0.26), Color3.fromRGB(250, 214, 80))) end      -- scrambled egg
		for i = 1, 6 do local p = mesh("FriedRiceGen", Vector3.new(0.5, 0.2, 0.5)); if p then table.insert(out, p) end end
		for i = 1, 6 do table.insert(out, blob(Vector3.new(0.08, 0.08, 0.08), Color3.fromRGB(110, 180, 70))) end    -- peas / scallion
	end
	return out
end

local function startSideDish(r, t)
	r.pot = Assets.Wok:Clone()
	skinPot(r)
	local seat = CFrame.new(r.seatPos)
	r.pot:PivotTo(seat * CFrame.new(0, 0.8, 0))
	r.pot.PrimaryPart.Anchored = true
	r.pot.Parent = fxFolder
	for i = 1, 8 do if not r.pot then return end; r.pot:PivotTo(seat * CFrame.new(0, 0.8 * (1 - i / 8) ^ 2, 0)); task.wait(0.025) end
	if not r.pot then return end
	r.pot:PivotTo(seat)
	Kitchen.setFlame(r, true)
	local body = r.pot.PrimaryPart
	local restCF = body.CFrame
	local oil, sauce = r.pot.Oil, r.pot.Broth
	local steam = body.SteamAtt.Steam
	local sizzle = body:FindFirstChild("Boil")
	local deep = t.menu == "꿔바로우" or t.menu == "크림새우"
	local cream = t.menu == "크림새우"
	-- 1) oil: a deep golden pool for frying the pork, a thin film for the rice
	r.txt.Text = string.format(deep and "#%d 튀김 기름 데우는 중" or "#%d 웍에 기름 두르는 중", t.id)
	oil.Color = Color3.fromRGB(226, 172, 62)
	local fry
	if deep then
		-- fill the wok halfway with oil and let it bubble
		-- a separate anchored disk (resizing the welded template disk at runtime misbehaves)
		local pool = oil:Clone()
		for _, k in ipairs(pool:GetChildren()) do k:Destroy() end
		pool.Name = "FryOil"; pool.Anchored = true; pool.Transparency = 1
		pool.Size = Vector3.new(0.02, 1.85, 1.85)
		pool.CFrame = CFrame.new(body.Position + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pool.Parent = r.pot
		oil = pool
		local att = Instance.new("Attachment"); att.Name = "FryAtt"; att.WorldPosition = body.Position + Vector3.new(0, 0.04, 0); att.Parent = body
		fry = Instance.new("ParticleEmitter"); fry.Name = "Fry"
		fry.Shape = Enum.ParticleEmitterShape.Disc; fry.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume; fry.ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward
		fry.Orientation = Enum.ParticleOrientation.FacingCamera
		fry.Color = ColorSequence.new(Color3.fromRGB(255, 236, 170)); fry.LightEmission = 0.3
		fry.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.09) })
		fry.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		fry.Lifetime = NumberRange.new(0.25, 0.45); fry.Speed = NumberRange.new(0.3, 0.6); fry.Rate = 0
		fry.EmissionDirection = Enum.NormalId.Top; att.CFrame = CFrame.new(att.Position) * CFrame.Angles(0, 0, 0)
		fry.Parent = att
	end
	TS:Create(oil, TweenInfo.new(0.8), { Transparency = deep and 0.15 or 0.35 }):Play()
	if sizzle then sizzle:Play() end
	steam.Rate = 3
	task.wait(0.5)
	if r.ticket ~= t then return end
	-- 2) in it goes
	r.txt.Text = string.format(deep and (cream and "#%d 새우 튀기는 중" or "#%d 고기 튀기는 중") or "#%d 계란이랑 밥 넣는 중", t.id)
	r.pieces = {}
	local floor = deep and (body.Position.Y - 0.02) or (body.Position.Y - body.Size.Y / 2 + 0.14)
	if fry then fry.Rate = 70 end
	for _, p in ipairs(sideBits(t.menu)) do
		if r.ticket ~= t or not r.pot then return end
		local ang, rad = math.random() * math.pi * 2, math.sqrt(math.random()) * 0.62
		local land = Vector3.new(body.Position.X + math.cos(ang) * rad, (deep and floor or wokFloor(body, rad) + 0.1) + math.random() * 0.05, body.Position.Z + math.sin(ang) * rad)
		local rot = CFrame.Angles(0, math.random() * 6.28, 0)
		p.CFrame = CFrame.new(land + Vector3.new(0, 1.6, 0)) * rot
		p.Parent = r.pot
		TS:Create(p, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(land) * rot }):Play()
		table.insert(r.pieces, { p = p, land = land, rot = rot })
		task.delay(0.26, function()
			local sp = body.Parent and body:FindFirstChild("Splash")
			if sp then sp.PlaybackSpeed = 0.85 + math.random() * 0.3; sp:Play() end
		end)
		task.wait(deep and 0.18 or 0.08)
	end
	-- 3) fry / toss
	r.txt.Text = string.format(deep and "#%d 바삭하게 튀기는 중" or "#%d 센 불에 볶는 중", t.id)
	steam.Rate = deep and 5 or 8
	local quick = iaHeat(r, t, deep and "fry" or "wok")
	if r.ticket ~= t or not r.pot then return end
	local t0 = os.clock()
	local rest = quick and 2 or math.max(2, C.CookTime - 3)
	local flipped = false
	while os.clock() - t0 < rest do
		if r.ticket ~= t or not r.pot then return end
		if deep then
			-- pieces bob in the oil; halfway through they get flipped over once
			for i, it in ipairs(r.pieces) do
				if it.p.Parent then it.p.CFrame = CFrame.new(it.land + Vector3.new(0, math.sin(os.clock() * 7 + i) * 0.02, 0)) * it.rot end
			end
			if not flipped and os.clock() - t0 > rest / 2 then
				flipped = true
				for _, it in ipairs(r.pieces) do
					it.rot = it.rot * CFrame.Angles(math.pi, 0, 0)
					local peak = it.land + Vector3.new(0, 0.5, 0)
					TS:Create(it.p, TweenInfo.new(0.18), { CFrame = CFrame.new(peak) * it.rot }):Play()
					task.delay(0.18, function() if it.p.Parent then TS:Create(it.p, TweenInfo.new(0.2), { CFrame = CFrame.new(it.land) * it.rot }):Play() end end)
				end
			end
			task.wait(0.1)
		else
			body.CFrame = restCF * CFrame.new(0.06, 0.1, 0) * CFrame.Angles(0, 0, math.rad(-8))
			for _, it in ipairs(r.pieces) do
				if it.p.Parent then
					local spin = it.rot * CFrame.Angles(math.random() * 2, math.random() * 2, 0)
					it.rot = spin
					local peak = it.land + Vector3.new((math.random() - 0.5) * 0.3, 0.45 + math.random() * 0.5, (math.random() - 0.5) * 0.3)
					TS:Create(it.p, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(peak) * spin }):Play()
					task.delay(0.22, function() if it.p.Parent then TS:Create(it.p, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(it.land) * spin }):Play() end end)
				end
			end
			task.wait(0.15)
			if not r.pot then return end
			body.CFrame = restCF
			task.wait(0.85)
		end
	end
	if r.ticket ~= t or not r.pot then return end
	-- 4) finish: glaze for the pork, a last toss for the rice
	if deep then
		r.txt.Text = string.format(cream and "#%d 크림소스 버무리는 중" or "#%d 새콤달콤 소스 입히는 중", t.id)
		if cream then for _, it in ipairs(r.pieces) do if it.p.Parent then it.p.Color = Color3.fromRGB(226, 128, 58) end end end
		local glaze = sauce:Clone()
		for _, k in ipairs(glaze:GetChildren()) do k:Destroy() end
		glaze.Name = "Glaze"; glaze.Anchored = true; glaze.Transparency = 1
		glaze.Color = cream and Color3.fromRGB(250, 232, 160) or Color3.fromRGB(236, 120, 40); glaze.Size = Vector3.new(0.02, 1.2, 1.2)
		glaze.CFrame = CFrame.new(body.Position.X, body.Position.Y - body.Size.Y / 2 + 0.15, body.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
		glaze.Parent = r.pot
		TS:Create(glaze, TweenInfo.new(0.8), { Transparency = 0.1 }):Play()
		TS:Create(oil, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		if fry then fry.Rate = 0 end
		-- oil drains: the pork settles into the glaze and gets a toss
		local bottom = body.Position.Y - body.Size.Y / 2 + 0.16
		for _, it in ipairs(r.pieces) do
			if it.p.Parent then
				local d = (it.land - body.Position) * Vector3.new(0.6, 0, 0.6)
				it.land = Vector3.new(body.Position.X + d.X, bottom + 0.05, body.Position.Z + d.Z)
				TS:Create(it.p, TweenInfo.new(0.5, Enum.EasingStyle.Quad), { CFrame = CFrame.new(it.land) * it.rot }):Play()
			end
		end
		task.wait(0.6)
	end
	-- straight onto the pass (wait if it's full)
	r.state = "finishing"; tickets:setState(t, "spice")
	r.txt.Text = string.format("#%d 접시에 담는 중", t.id)
	local waited = 0
	while not stations:freePassSlot() and r.ticket == t do
		r.txt.Text = string.format("#%d 패스대가 꽉 찼어요", t.id)
		task.wait(1); waited += 1
	end
	if r.ticket ~= t then return end
	t.correct = true
	if not placeOnPass(t, r) then return end
	local cook = r.cook
	if cook and cook.Parent then
		if t.playerCustomer ~= cook then reward(cook, "Cook", t.share or 0, "조리", richMult(t)); pumpkinBonus(cook, t) end   -- 내 주문 셀프 조리는 보상 없음 (돈 2배 패스로 자가 주문 무한 수익 방지)
		notify(cook, string.format("#%d %s 완성! 패스대에 올렸어요", t.id, t.menu))
	end
	iaResult(r, t, { correct = true, side = true })
	finishCooking(r)
end

local function startCooking(r, t)
	if t.side and Assets:FindFirstChild("Wok") then return startSideDish(r, t) end
	if t.menu == "마라샹궈" and Assets:FindFirstChild("Wok") then return startStirFry(r, t) end
	local body0 = Assets.Pot
	r.pot = body0:Clone()
	skinPot(r)
	-- lower the pot onto the burner
	local seat = CFrame.new(r.seatPos)   -- over the left burner
	r.pot:PivotTo(seat * CFrame.new(0, 0.8, 0))
	r.pot.PrimaryPart.Anchored = true
	r.pot.Parent = fxFolder
	for i = 1, 8 do r.pot:PivotTo(seat * CFrame.new(0, 0.8 * (1 - i / 8) ^ 2, 0)); task.wait(0.025) end
	r.pot:PivotTo(seat)
	Kitchen.setFlame(r, true)
	local body = r.pot.PrimaryPart
	local broth, oil = r.pot.Broth, r.pot.Oil
	local emptyY, fullY = broth:GetAttribute("EmptyY"), broth:GetAttribute("FullY")
	local boil = body:FindFirstChild("Boil"); if boil then boil:Play() end
	local steam = body.SteamAtt.Steam

	-- 1) pour the broth (milky bone broth, the spice comes later)
	r.txt.Text = string.format("#%d 육수 붓는 중", t.id)
	broth.Color = Color3.fromRGB(236, 214, 170)
	broth.Transparency = 0
	local steps = 14
	for i = 1, steps do
		if r.ticket ~= t then return end
		broth.CFrame = brothCF(r, emptyY + (fullY - emptyY) * (i / steps))
		task.wait(0.6 / steps)
	end
	oil.CFrame = brothCF(r, fullY + 0.03)
	steam.Rate = 2

	-- 2) drop the customer's ingredients in
	r.txt.Text = string.format("#%d 재료 넣는 중", t.id)
	local kinds = (t.kinds and #t.kinds > 0) and t.kinds or { "fishball", "bokchoy", "fuzhu" }
	local list = { "glassnoodle" }
	for _, k in ipairs(kinds) do table.insert(list, k); table.insert(list, k) end
	r.pieces = {}
	local up = Vector3.new(0, 1, 0)
	local function dropOne(key)
		if r.ticket ~= t or not r.pot then return false end
		local p, r0 = miniPiece(key)
		if not p then return false end
		do
			p.Anchored = true
			local ang, rad = math.random() * math.pi * 2, math.sqrt(math.random()) * 0.6
			local land = body.Position + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad) + up * (fullY + 0.02 + body.Size.Y * 0 )
			land = Vector3.new(land.X, broth.Position.Y + 0.03 + math.random() * 0.06, land.Z)
			local rot = CFrame.Angles(0, math.random() * 6.28, 0) * CFrame.Angles(math.random() * 0.5 - 0.25, 0, math.random() * 0.5 - 0.25) * r0
			p.CFrame = CFrame.new(land + up * 1.8) * rot
			p.Parent = r.pot
			TS:Create(p, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.new(land) * rot }):Play()
			table.insert(r.pieces, p)
			task.delay(0.3, function()
				local sp = body:FindFirstChild("Splash")
				if sp and r.pot then sp.PlaybackSpeed = 0.9 + math.random() * 0.3; sp:Play() end
			end)
		end
		return true
	end
	if not iaIngredients(r, t, kinds, dropOne, "glassnoodle") then
		for _, key in ipairs(list) do
			if r.ticket ~= t then return end
			if dropOne(key) then task.wait(0.1) end
		end
	end

	-- 3) rolling boil
	if r.ticket ~= t or not r.pot then return end   -- 재료 넣는 사이 주문이 취소돼 냄비가 치워졌으면 멈춤 (오류 리포트: nil SetAttribute)
	r.txt.Text = string.format("#%d 보글보글 끓이는 중", t.id)
	r.pot:SetAttribute("Boiling", true); r.pot:SetAttribute("Heat", 1.3)
	steam.Rate = 7
	local quick = iaHeat(r, t, "soup")
	if r.ticket ~= t or not r.pot then return end
	local t0 = os.clock()
	local rest = quick and 1.5 or math.max(2, C.CookTime - 3)
	while os.clock() - t0 < rest do
		if r.ticket ~= t then return end
		-- ingredients bob gently in the boil
		for i, p in ipairs(r.pieces) do
			if p.Parent then p.CFrame = p.CFrame + Vector3.new(0, math.sin((os.clock() - t0) * 6 + i) * 0.004, 0) end
		end
		task.wait(0.1)
	end
	if r.ticket ~= t then return end
	r.state = "spice"; tickets:setState(t, "spice")
	r.txt.Text = string.format("#%d 마라소스 넣기!", t.id)
	r.prompt.ActionText = "마라소스 넣기"; r.prompt.ObjectText = string.format("#%d %s", t.id, t.menu)
	if not iaSpiceStage(r, t) then r.prompt.Enabled = true end
	refreshBoard()
end

function finishCooking(r)
	Kitchen.finishRange(r, cookRE)
end

local function iaOf(plr)
	for i, rr in ipairs(stations.ranges) do if rr.ia and rr.ia.plr == plr and not rr.ia.auto then return rr, i end end
end
-- 화구 idx 에서 맨 앞 주문 조리 시작 (프롬프트 / 직접 조리 "다음 주문")
local function startAt(plr, idx)
	local r = stations.ranges[idx]
	if not r or r.state ~= "idle" then return false, "busy" end
	local t = tickets:firstOrdered()
	if not t then return false, "none" end
	stations:beginRange(r, t, plr)
	refreshBoard()
	r.prompt.Enabled = false
	r.bb.Enabled = true
	r.fill.Size = UDim2.fromScale(0, 1)
	TS:Create(r.fill, TweenInfo.new(C.CookTime, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
	if C.InteractiveCook and not iaOf(plr) then
		r.ia = { plr = plr, t = t, mistakes = 0, stage = "start", stageAt = os.clock() }
		local uniq, seen = {}, {}
		for _, k in ipairs(t.kinds or {}) do if not seen[k] then seen[k] = true; table.insert(uniq, k) end end
		cookRE:FireClient(plr, "begin", {
			range = idx, id = t.id, menu = t.menu, kinds = uniq, spice = t.spice, weight = t.weight,
			side = t.side and true or false, wok = (t.menu == "마라샤궈"), rich = (t.rich or t.superRich) and true or false,
			seat = r.seatPos, anchor = r.anchor.Position,
		})
	end
	task.spawn(startCooking, r, t)
	return true
end
-- Studio 테스트용: ServerStorage.CookTest:Invoke(menu, spice, kinds, side) = 가짜 주문 하나 넣기
if game:GetService("RunService"):IsStudio() then
	local bf = SS:FindFirstChild("CookTest") or Instance.new("BindableFunction"); bf.Name = "CookTest"; bf.Parent = SS
	bf.OnInvoke = function(menu, spice, kinds, side)
		if menu == "carrytest" then   -- (Studio 테스트) 그릇 n개 들려 보기: CookTest:Invoke("carrytest", 플레이어, n)
			local plr, n = spice, kinds or 2
			for k = 1, n do
				local tk = tickets:register({ carrier = plr, menu = "마라탕", spice = 2, cookedSpice = 2, weight = 500, price = 0, share = 0, kinds = { "bokchoy", "fishball" } }, "carried")
				local id = tk.id
				tk.bowl = buildDish(tk); tk.bowl.Parent = workspace
				for _, slot in ipairs(CARRY_SLOTS) do if not plr:GetAttribute(slot) then plr:SetAttribute(slot, id); break end end   -- 빈 칸부터
			end
			carryLayout(plr)
			return true
		end
		if menu == "skullbowl" then local tk = { id = 999, menu = spice or "마라탕", spice = 5, cookedSpice = 5, kinds = { "bokchoy", "fishball", "enoki", "beef", "tofu" } }; local bw = buildDish(tk); bw:PivotTo(kinds); for _, p in ipairs(bw:GetDescendants()) do if p:IsA("BasePart") then p.Anchored = true end end; bw.Parent = workspace; return bw end   -- (Studio 테스트) 해골 그릇 미리보기
		local ticket = tickets:register({ menu = menu or "마라탕", spice = spice or 2, weight = 500, price = 0, share = 0,
			kinds = kinds or { "bokchoy", "fishball", "enoki" }, side = side }, "ordered")
		refreshBoard()
		return ticket.id
	end
end

for idx, r in ipairs(stations.ranges) do
	r.prompt.Triggered:Connect(function(plr)
		if not near(plr, r.anchor.Position, 12) then return end
		if r.state == "idle" then
			local ok, why = startAt(plr, idx)
			if not ok and why == "none" then notify(plr, "대기 중인 주문이 없어요") end
		elseif r.state == "spice" then
			r.spiceUser = plr; r.spiceAsked = os.clock()
			spiceRE:FireClient(plr, "open", { range = idx, id = r.ticket.id, menu = r.ticket.menu, spice = r.ticket.spice, weight = r.ticket.weight })
		end
	end)
end

local applySpice   -- 아래에서 정의 (맵기 창 / 직접 붓기 공용)
spiceRE.OnServerEvent:Connect(function(plr, action, rangeIdx, level)
	if action ~= "pick" then return end
	local r = stations.ranges[tonumber(rangeIdx) or 0]
	level = math.floor(tonumber(level) or -1)
	if level ~= level then return end   -- NaN 막기
	if not r or r.state ~= "spice" or r.spiceUser ~= plr or level < 0 or level > ((level == 5 and plr:GetAttribute("SkullSauce") == true) and 5 or 4) then return end   -- 5 = 💀 해골 소스 (게임패스)
	if os.clock() - (r.spiceAsked or 0) > 30 or not near(plr, r.anchor.Position, 14) then return end
	if not stations:freePassSlot() then notify(plr, "패스대가 꽉 찼어요. 그릇을 먼저 가져가 주세요"); return end
	if level == 5 then   -- 💀 해골 소스: 30초에 한 번 (트롤링 방지)
		local now = workspace:GetServerTimeNow()
		local nxt = tonumber(plr:GetAttribute("SkullReadyAt")) or 0
		if now < nxt then notify(plr, string.format("💀 해골 소스는 %d초 뒤에 다시 쓸 수 있어요", math.ceil(nxt - now))); return end
		plr:SetAttribute("SkullReadyAt", now + 30)
	end
	applySpice(plr, r, level)
end)

function applySpice(plr, r, level)
	local t = r.ticket
	t.cookedSpice = level
	r.state = "finishing"
	r.prompt.Enabled = false
	r.txt.Text = string.format("#%d 맵기 %d단계 넣는 중", t.id, level)
	-- chili goes in: red dust pours, broth turns to the chosen colour, chili oil spreads
	task.spawn(function()
		local pot = r.pot
		if pot then
			local body = pot.PrimaryPart
			local c = BROTH[level]
			if level > 0 then body.SpiceAtt.Spice:Emit(25 + level * 20) end
			TS:Create(pot.Broth, TweenInfo.new(1.1), { Color = c.broth }):Play()
			if pot.Name == "Wok" then
				local wb = pot.PrimaryPart
				local glaze = pot.Broth:Clone()
				for _, k in ipairs(glaze:GetChildren()) do k:Destroy() end
				glaze.Name = "MalaSauce"; glaze.Anchored = true; glaze.Transparency = 1; glaze.Color = c.broth
				glaze.Size = Vector3.new(0.02, 1.25, 1.25)
				glaze.CFrame = CFrame.new(wb.Position.X, wb.Position.Y - wb.Size.Y / 2 + 0.15, wb.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
				glaze.Parent = pot
				TS:Create(glaze, TweenInfo.new(0.8), { Transparency = 0.1 }):Play()
			end
			pot.Oil.Color = c.oil
			TS:Create(pot.Oil, TweenInfo.new(1.1), { Transparency = level == 0 and 0.75 or 0.45 }):Play()
			pot:SetAttribute("Heat", 1.6 + level * 0.15)
		end
		task.wait(1)
		if r.ticket ~= t then return end
		if not placeOnPass(t, r) then notify(plr, "패스대가 꽉 찼어요"); r.state = "spice"; r.prompt.Enabled = true; return end
		t.correct = (level == t.spice)
		t.skull = (level == 5) or nil
		-- (11/22) 💀 지옥맛(해골 소스 패스) = 조리 보상 2배 (쿨타임 30초 그대로)
		if t.playerCustomer ~= plr then reward(plr, "Cook", t.share or 0, t.skull and "💀 지옥맛 조리" or "조리", richMult(t) * (t.skull and 2 or 1)); pumpkinBonus(plr, t) end
		notify(plr, t.skull and string.format("💀 #%d 해골 소스 완성... 손님 각오하세요", t.id) or t.correct and string.format("#%d 완성! 패스대에 올렸어요", t.id) or string.format("#%d 완성 (맵기가 주문과 달라요)", t.id))
		iaResult(r, t, { correct = t.correct, level = level })
		finishCooking(r)
	end)
end

-- 직접 조리 클라 요청 (판정은 여기서)
cookRF.OnServerInvoke = function(plr, action, a1)
	local r = iaOf(plr)
	if action == "next" then
		if r then return false, "busy" end
		local idx = tonumber(a1)
		local rr = idx and stations.ranges[idx]
		if not rr then return false, "bad" end
		if not near(plr, rr.anchor.Position, 14) then return false, "far" end
		return startAt(plr, idx)
	end
	if not r then return false, "none" end
	local ia, t = r.ia, r.ticket
	if ia.auto or ia.t ~= t then return false, "auto" end
	if action == "cancel" then
		iaAuto(r, "cancel"); return true
	elseif action == "pick" then
		if ia.stage ~= "ingredients" or not ia.need then return false, "stage" end
		if os.clock() < (ia.coolUntil or 0) then return false, "cool" end
		local key = tostring(a1)
		if ia.picked[key] then return false, "dup" end
		if ia.need[key] then
			ia.picked[key] = true
			ia.coolUntil = os.clock() + 0.15
			local drop = ia.drop
			if drop then task.spawn(function() drop(key); task.wait(0.18); drop(key) end) end
			local left = 0
			for k in pairs(ia.need) do if not ia.picked[k] then left += 1 end end
			if left == 0 then task.delay(0.6, function() if r.ia == ia and ia.stage == "ingredients" then ia.done = "ingredients" end end) end
			return true, (left == 0) and "done" or "good", left
		end
		ia.mistakes += 1
		ia.coolUntil = os.clock() + 0.8
		return true, "wrong", ia.mistakes
	elseif action == "heatdone" then
		if ia.stage ~= "heat" then return false, "stage" end
		if os.clock() - ia.stageAt < HEAT_MIN then return false, "early" end
		ia.done = "heat"
		return true
	elseif action == "pourdown" then
		if ia.stage ~= "pour" or r.state ~= "spice" then return false, "stage" end
		if not stations:freePassSlot() then notify(plr, "패스대가 꽉 찼어요. 그릇을 먼저 가져가 주세요"); return false, "full" end
		local now = workspace:GetServerTimeNow()
		local ts = tonumber(a1)
		if not ts or ts ~= ts or ts > now + 0.05 or ts < now - 1.5 then ts = now end
		ia.pourAt = ts
		return true
	elseif action == "pourup" then
		if ia.stage ~= "pour" or r.state ~= "spice" or not ia.pourAt then return false, "stage" end
		local now = workspace:GetServerTimeNow()
		local ts = tonumber(a1)
		if not ts or ts ~= ts or ts > now + 0.05 or ts < ia.pourAt then ts = now end
		local fill = (ts - ia.pourAt) * ia.speed
		ia.pourAt = nil
		if fill < 0.03 then return false, "tiny" end
		if not stations:freePassSlot() then notify(plr, "패스대가 꽉 찼어요. 그릇을 먼저 가져가 주세요"); return false, "full" end
		local level = math.clamp(math.floor(fill * 5), 0, 4)
		ia.stage = "done"
		r.spiceUser = plr
		applySpice(plr, r, level)
		return true, level, level == t.spice, fill
	end
	return false, "bad"
end

-- tickets whose customer left: clear pots / pass bowls
task.spawn(function()
	while true do
		task.wait(1)
		for id, t in tickets:entries() do
			if t.cancelled then
				for _, r in ipairs(stations.ranges) do
					if r.ticket == t then
						finishCooking(r)
					end
				end
				if t.slot then stations:clearPassSlot(t.slot) end
				if t.bowl and t.bowl.Parent then
					local carrier = t.carrier
					t.bowl:Destroy()
					if carrier then releaseCarry(carrier, t.id) end
				end
				tickets:remove(id)
			elseif t.state == "done" and not t.cancelled then
				tickets:remove(id)
			end
		end
		refreshBoard()
	end
end)
-- KitchenWatchdog: 오래 켜진 서버에서 화구/패스대가 영영 막히는 것 방지 (5초마다 점검)
--   1) 패스대 칸: 주인 티켓이 취소·완료·운반 중이거나, 그릇 없이 10초 넘게 잡혀 있으면 비움 (그릇 만들다 오류 난 칸 누수)
--   2) 화구: 티켓이 없거나 취소된 채로 멈춰 있으면 정리 / "넣는 중" 20초 넘게 멈추면 정리
--   3) 화구가 "마라소스 넣기" 상태로 3분 넘게 아무도 안 하면: 패스대에 자리가 있을 때 주문 맵기로 자동 완성 (보상 없음)
do
	local slotSeen, rangeSeen = {}, {}
	local function stale(t) return (not t) or t.cancelled or tickets:get(t.id) ~= t or t.state == "done" end
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			-- 1) 패스대
			for i in ipairs(stations.passSlots) do
				local t = stations.occupied[i]
				if t then
					local bad = (type(t) ~= "table") or t.cancelled or t.state == "done" or t.state == "carried"
					if not bad and (t.slot ~= i or not (t.bowl and t.bowl.Parent)) then
						slotSeen[i] = slotSeen[i] or now
						if now - slotSeen[i] > 10 then bad = true end
					else
						slotSeen[i] = nil
					end
					if bad then
						stations:clearPassSlot(i); slotSeen[i] = nil
						if type(t) == "table" and t.slot == i and t.state ~= "carried" then t.slot = nil end
						warn("[KitchenWatchdog] 패스대 칸 정리", i)
					end
				else
					slotSeen[i] = nil
				end
			end
			-- 2) 3) 화구
			for idx, r in ipairs(stations.ranges) do
				if r.state ~= "idle" then
					local key = tostring(r.state) .. ":" .. tostring(r.ticket and r.ticket.id)
					local seen = rangeSeen[idx]
					if not seen or seen.key ~= key then seen = { key = key, t = now }; rangeSeen[idx] = seen end
					local age = now - seen.t
					if stale(r.ticket) and age > 3 then
						warn("[KitchenWatchdog] 화구 정리 (티켓 없음)", idx, key)
						pcall(finishCooking, r)
					elseif r.state == "finishing" and age > 20 then
						warn("[KitchenWatchdog] 화구 정리 (넣는 중 멈춤)", idx, key)
						local t = r.ticket
						pcall(finishCooking, r)
						if t and t.state ~= "ready" and t.state ~= "carried" and t.state ~= "done" then tickets:setState(t, "ordered") end   -- 다시 조리하게
					elseif r.state == "spice" and age > 180 and stations:freePassSlot() then
						local t = r.ticket
						warn("[KitchenWatchdog] 마라소스 자동 완성", idx, key)
						t.cookedSpice = t.spice or 0
						t.correct = true
						local ok = pcall(placeOnPass, t, r)
						if ok and t.slot then pcall(finishCooking, r) end
					end
				else
					rangeSeen[idx] = nil
				end
			end
		end
	end)
end

-- a carrier who dies/respawns loses the bowl: the order goes back to the kitchen to be cooked again
local function dropCarry(plr)
	for _, a in ipairs(CARRY_SLOTS) do
		local id = plr:GetAttribute(a)
		plr:SetAttribute(a, nil)
		local t = id and tickets:get(id)
		if t and t.state == "carried" and t.carrier == plr then
			if t.bowl then t.bowl:Destroy(); t.bowl = nil end
			t.carrier = nil; t.carriedAt = nil; t.readyAt = nil
			tickets:setState(t, "cooked")          -- not "ordered": nobody may cook (and get paid for) it twice
			if placeOnPass(t) then
				notify(plr, string.format("들고 있던 #%d 음식은 픽업대로 돌아갔어요", t.id))
			else
				-- pass is full: wait for a slot
				task.spawn(function()
					while t.state == "cooked" and not t.cancelled do
						if placeOnPass(t) then break end
						task.wait(1)
					end
				end)
			end
		end
	end
	refreshBoard()
end
-- 손님 음식을 들고 가게 밖(집 등)으로 나가면: 경고 → 8초 안에 안 돌아오면 픽업대로 되돌림 (11/16)
--   카트 8칸에 음식을 꽉 채워 집으로 가져가는 일 방지
local SHOP_MIN, SHOP_MAX = Vector3.new(-48, -20, -66), Vector3.new(48, 75, 78)   -- 가게 건물(±12 여유)
local OUT_GRACE = 8
do
	local outSince = {}
	task.spawn(function()
		while true do
			task.wait(1)
			for _, plr in ipairs(Players:GetPlayers()) do
				local holding = false
				for _, a in ipairs(CARRY_SLOTS) do local v = plr:GetAttribute(a); if v and v > 0 then holding = true; break end end
				local ch = plr.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				local p = root and root.Position
				local inside = p and p.X >= SHOP_MIN.X and p.X <= SHOP_MAX.X and p.Y >= SHOP_MIN.Y and p.Y <= SHOP_MAX.Y and p.Z >= SHOP_MIN.Z and p.Z <= SHOP_MAX.Z
				if holding and p and not inside then
					if not outSince[plr] then
						outSince[plr] = os.clock()
						notify(plr, string.format("⚠️ 손님 음식은 가게 밖으로 가져갈 수 없어요! %d초 안에 돌아가지 않으면 픽업대로 돌아가요", OUT_GRACE))
					elseif os.clock() - outSince[plr] >= OUT_GRACE then
						outSince[plr] = nil
						dropCarry(plr)
						pcall(carryLayout, plr)
						notify(plr, "가게 밖에 오래 있어서 들고 있던 음식을 픽업대로 돌려보냈어요")
					end
				else
					outSince[plr] = nil
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(plr) outSince[plr] = nil end)
end

local function hookChar(plr) plr.CharacterRemoving:Connect(function() dropCarry(plr) end) end
Players.PlayerAdded:Connect(hookChar)
for _, plr in ipairs(Players:GetPlayers()) do hookChar(plr) end
-- a carrier who leaves the game: the customer gives up
Players.PlayerRemoving:Connect(function(plr)
	for _, t in tickets:entries() do
		if t.carrier == plr and t.state == "carried" then
			if t.playerCustomer then tickets:setState(t, "ordered"); t.carrier = nil; t.bowl = nil
			else tickets:cancel(t); if t.npc then task.spawn(npc.leave, t.npc, true) end end
		end
	end
end)

----------------------------------------------------------------- player customers (players order at the register too)
local PlayerOrders = require(customerModules:WaitForChild("PlayerOrders"))
PlayerOrders.start({
	config = C,
	money = Money,
	registers = REGISTERS,
	seats = seats,
	assets = Assets,
	remotes = remotes,
	fxFolder = fxFolder,
	bagColor = BAG_WHITE,
	shopMin = SHOP_MIN,
	shopMax = SHOP_MAX,
	tickets = tickets,
	kitchen = stations,
	serving = serving,
	near = near,
	notify = notify,
	reward = reward,
	sfx = sfx,
	isCarrying = isCarrying,
	releaseCarry = releaseCarry,
	makeDirty = makeDirty,
	placeOnPass = placeOnPass,
	refreshBoard = refreshBoard,
	unbag = unbag,
})

-- 주문 창 메뉴 사진용 음식 모델 (PlayerOrderClient 가 ViewportFrame 에 띄움) (11/16)
task.spawn(function()
	local folder = RS:FindFirstChild("MenuPreviews") or Instance.new("Folder"); folder.Name = "MenuPreviews"
	for _, m in ipairs(C.PlayerMenu or {}) do
		if not folder:FindFirstChild(m.name) then
			local ok, b = pcall(buildDish, { id = 0, menu = m.name, side = not m.mala, spice = 2, cookedSpice = 2 })
			if ok and b then
				for _, p in ipairs(b:GetDescendants()) do
					if p:IsA("BasePart") then p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.CanTouch = false
					elseif p:IsA("BillboardGui") or p:IsA("ProximityPrompt") or p:IsA("Sound") or p:IsA("Script") or p:IsA("LocalScript") then p:Destroy() end
				end
				b.Name = m.name; b.Parent = folder
			else
				warn("[MenuPreviews] 못 만듦", m.name, b)
			end
		end
	end
	folder.Parent = RS
end)

Spawner.start({
	customers = npc,
	makeNPC = makeNPC,
	config = C,
	rushConfig = RushCfg,
	registers = REGISTERS,
	spawnPoints = SPAWNS,
	groundY = Y,
	doorIn = DOOR_IN,
	doorOut = DOOR_OUT,
	assets = Assets,
	folder = folder,
	dirtyFolder = dirtyFolder,
	fxFolder = fxFolder,
	announce = announceRE,
	workEvent = workRE,
	tickets = tickets,
	kitchen = stations,
	serving = serving,
	money = Money,
	rank = Rank,
	bubble = bubble,
	pick = pick,
	weighted = weighted,
	rushOn = rushOn,
	spawnFloorSpill = spawnFloorSpill,
	refreshBoard = refreshBoard,
	near = near,
	notify = notify,
	sfx = sfx,
	placeOnTable = placeOnTable,
})
