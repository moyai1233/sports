local Players = game:GetService("Players")
local SS = game:GetService("ServerStorage")
local CS = game:GetService("CollectionService")

local PlayerOrders = {}

function PlayerOrders.start(context)
	local C = context.config
	local Money = context.money
	local REGISTERS = context.registers
	local seats = context.seats
	local Assets = context.assets
	local remotes = context.remotes
	local fxFolder = context.fxFolder
	local BAG_WHITE = context.bagColor
	local SHOP_MIN = context.shopMin
	local SHOP_MAX = context.shopMax
	local tickets = context.tickets
	local stations = context.kitchen
	local serving = context.serving
	local near = context.near
	local notify = context.notify
	local reward = context.reward
	local sfx = context.sfx
	local isCarrying = context.isCarrying
	local releaseCarry = context.releaseCarry
	local makeDirty = context.makeDirty
	local placeOnPass = context.placeOnPass
	local refreshBoard = context.refreshBoard
	local unbag = context.unbag

	local orderRE = remotes:WaitForChild("PlayerOrder")
	local placeRF = remotes:WaitForChild("PlaceOrder")
	local MENU = C.PlayerMenu or {}
	local AUTO_AFTER = C.PlayerOrderAuto or 120
	local SHARE = C.PlayerOrderShare or 0.25
	local BOWL_TOOL = "마라탕 그릇"
	local active = {}      -- [player] = ticket (one open order per player)
	local busy = {}

	local function menuItem(name) for _, m in ipairs(MENU) do if m.name == name then return m end end end
	local function bowlInfo(plr)
		local ch = plr.Character
		local tool = (ch and ch:FindFirstChild(BOWL_TOOL)) or plr.Backpack:FindFirstChild(BOWL_TOOL)
		if not tool then return nil, nil end
		local list = {}
		for k in string.gmatch(tool:GetAttribute("Contents") or "", "[^,]+") do table.insert(list, k) end
		return tool, list
	end
	local function priceOf(it, scoops)
		if it.per100 then
			local grams = math.max(C.MinGram or 200, scoops * (C.GramPerScoop or 50))
			return math.floor(it.per100 * grams / 100 / 100 + 0.5) * 100, grams
		end
		return it.price or 0, nil
	end
	local function atRegister(plr)
		for _, reg in ipairs(REGISTERS) do
			if reg.prompt and near(plr, reg.prompt.Parent.Position, 16) then return true end
		end
		return false
	end

	-- the "serve me" prompt rides on the customer's character (the client only shows it to whoever carries that order)
	local function attachServe(t)
		local plr = t.playerCustomer
		local ch = plr.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then return end
		if t.servePrompt then t.servePrompt:Destroy() end
		ch:SetAttribute("TicketId", t.id)
		local sp = Instance.new("ProximityPrompt")
		sp.Name = "ServePlayer"; sp.ActionText = "서빙하기"; sp.ObjectText = string.format(t.takeout and "%s님 포장 주문 #%d 🥡" or "%s님 주문 #%d", plr.DisplayName, t.id)
		sp.KeyboardKeyCode = Enum.KeyCode.E; sp.HoldDuration = 0.3; sp.MaxActivationDistance = 8; sp.RequiresLineOfSight = false
		sp:SetAttribute("Ticket", t.id)
		sp.Parent = root
		CS:AddTag(sp, "PlayerServe")
		t.servePrompt = sp
		sp.Triggered:Connect(function(carrier)
			if t.state ~= "carried" or not isCarrying(carrier, t.id) then
				notify(carrier, "이 손님 음식을 들고 와야 서빙할 수 있어요"); return
			end
			if not near(carrier, root.Position, 12) then return end
			t.deliver(carrier)
		end)
	end

	local function closeOrder(t)
		local plr = t.playerCustomer
		active[plr] = nil
		if t.servePrompt then t.servePrompt:Destroy(); t.servePrompt = nil end
		plr:SetAttribute("MyOrder", nil)
		if plr.Character then plr.Character:SetAttribute("TicketId", nil) end
	end

	-- the table in front of the seat the customer is sitting on
	local function tableSpot(plr)
		local ch = plr.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		local seat = hum and hum.SeatPart
		if not seat then return nil end
		local rec
		for _, s in ipairs(seats) do if s.seat == seat then rec = s end end
		local top = rec and rec.top
		if not top then
			local bd
			for _, d in ipairs(workspace:GetDescendants()) do
				-- 일반 테이블(Table.Top) + VIP 라운지 낮은 테이블(LowTable)
				if d:IsA("BasePart") and ((d.Name == "Top" and d.Parent and d.Parent.Name == "Table") or d.Name == "LowTable") then
					local dist = ((d.Position - seat.Position) * Vector3.new(1, 0, 1)).Magnitude
					-- 같은 층 테이블만 (2층 VIP석 아래 1층 테이블이 잡히던 문제)
					if math.abs(d.Position.Y - seat.Position.Y) < 4 and dist < 8 and (not bd or dist < bd) then top, bd = d, dist end
				end
			end
		end
		if not top then return nil end
		return seat, top, rec, hum
	end

	-- 클릭할 때마다 한 입씩 먹기 (EatBite 리모트)
	local eaters = {}
	local eatRE = remotes:WaitForChild("EatBite")
	local BITE_GAP = 0.55
	eatRE.OnServerEvent:Connect(function(plr)
		local e = eaters[plr]
		if not e or e.biting or not e.hum.Parent or e.hum.SeatPart ~= e.seat then return end
		local now = os.clock()
		if now - e.last < BITE_GAP then return end
		e.last = now
		e.biting = true
		if e.ch.Parent then e.ch:SetAttribute("BiteAt", workspace:GetServerTimeNow()) end
		task.delay(0.38, function()
			e.biting = false
			if eaters[plr] ~= e then return end
			e.eaten += 1
			-- 이번 입까지 없어져야 할 건더기 수만큼 지우기 (많으면 한 입에 여러 개)
			local total = #e.food
			local target = (e.eaten >= e.toEat) and total or math.floor(total * e.eaten / e.toEat + 0.5)
			while e.removed < target do
				e.removed += 1
				local p = e.food[e.removed]; if p and p.Parent then p:Destroy() end
			end
			-- 건더기가 한 입 수보다 적으면 (볶음밥 등) 남은 걸 조금씩 작게
			if total < e.toEat and e.eaten < e.toEat then
				local left = e.toEat - e.eaten
				for i = e.removed + 1, total do
					local p = e.food[i]
					if p and p.Parent then
						p:SetAttribute("EatBase", p:GetAttribute("EatBase") or p.Size)
						local base = p:GetAttribute("EatBase")
						local k = 0.35 + 0.65 * (left / e.toEat)
						p.Size = base * k
					end
				end
			end
			if e.ch.Parent then e.ch:SetAttribute("BitesLeft", math.max(0, e.toEat - e.eaten)) end
		end)
	end)

	-- eating at the table (no bonus, just the scene); the table gets dirty when they get up
	local function eat(plr, bowl, seat, rec, hum, mala)
		local ch = plr.Character
		local hand = ch and ch:FindFirstChild("RightHand")
		local sticks = Assets:FindFirstChild("Chopsticks")
		if hand and sticks then
			sticks = sticks:Clone(); sticks.Name = "EatChopsticks"
			local grip = hand.CFrame * CFrame.new(0, -0.15, -0.05) * CFrame.Angles(math.rad(-160), 0, math.rad(-10)) * CFrame.new(0, 0.4, 0)
			sticks:PivotTo(grip)
			local main = sticks.PrimaryPart
			local w = Instance.new("Weld"); w.Part0 = hand; w.Part1 = main; w.C0 = hand.CFrame:Inverse() * main.CFrame; w.Parent = main
			sticks.Parent = ch
			-- keep the same name the eating pose script looks for
			sticks.Name = "Chopsticks"
		end
		if ch then ch:SetAttribute("Eating", true) end
		local food = {}
		for _, p in ipairs(bowl:GetDescendants()) do
			if p ~= bowl.PrimaryPart and p.Name:sub(1, 4) ~= "Skin" and ((p:IsA("MeshPart") and p:FindFirstChildOfClass("WeldConstraint")) or p.Name == "Shrimp" or p.Name == "Cream") then table.insert(food, p) end
		end
		if #food == 0 then for _, p in ipairs(bowl:GetDescendants()) do if p:IsA("MeshPart") and p ~= bowl.PrimaryPart and p.Name:sub(1, 4) ~= "Skin" then table.insert(food, p) end end end
		for k = #food, 2, -1 do local j = math.random(1, k); food[k], food[j] = food[j], food[k] end
		-- 메뉴마다 건더기 수가 달라서 (볶음밥 1개 ~ 샹궈 50개+) 한 입 수는 6~12입으로 맞춤
		local toEat = (#food == 0) and 6 or math.clamp(#food, 6, 12)
		-- 플레이어가 클릭할 때마다 한 입 (다 먹거나 일어나면 끝)
		local e = { food = food, removed = 0, eaten = 0, toEat = toEat, last = 0, seat = seat, hum = hum, ch = ch, biting = false, mala = mala }
		eaters[plr] = e
		if ch then ch:SetAttribute("ClickEat", true); ch:SetAttribute("BitesLeft", toEat) end
		notify(plr, "클릭(터치)할 때마다 한 입씩 먹어요!")
		while plr.Parent and hum.Parent and hum.SeatPart == seat and e.eaten < toEat do task.wait(0.2) end
		if eaters[plr] == e then eaters[plr] = nil end
		if e.eaten >= toEat then
			notify(plr, "다 먹었어요! 잘 먹었습니다 🍜")
			-- 업적: 마라탕(샤궈 포함) 다 먹은 횟수 (사이드 메뉴 제외)
			if e.mala then
				local ok, PD = pcall(function() return require(game:GetService("ServerScriptService"):WaitForChild("PlayerData")) end)
				local pd = ok and PD.IsLoaded(plr) and PD.Get(plr, 1)
				if pd then
					pd.MalaEaten = (tonumber(pd.MalaEaten) or 0) + 1
					plr:SetAttribute("MalaEaten", pd.MalaEaten)
					notify(plr, string.format("마라탕 먹은 횟수: %d번", pd.MalaEaten))
				end
			end
		end
		if ch and ch.Parent then
			ch:SetAttribute("ClickEat", nil); ch:SetAttribute("BitesLeft", nil); ch:SetAttribute("BiteAt", nil)
			ch:SetAttribute("Eating", nil)
			local cs2 = ch:FindFirstChild("Chopsticks"); if cs2 then cs2:Destroy() end
		end
		-- 가게 밖(집 등)에서 먹은 포장 음식: 다 먹거나 일어나면 그릇을 바로 치움 (청소 필요 없음) (11/16)
		do
			local sp = seat and seat.Position
			local inShop = sp and sp.X >= SHOP_MIN.X and sp.X <= SHOP_MAX.X and sp.Y >= SHOP_MIN.Y and sp.Y <= SHOP_MAX.Y and sp.Z >= SHOP_MIN.Z and sp.Z <= SHOP_MAX.Z
			if not rec and not inShop then
				if bowl.Parent then
					for _, p in ipairs(bowl:GetDescendants()) do if p:IsA("BasePart") then game:GetService("TweenService"):Create(p, TweenInfo.new(0.35), { Transparency = 1 }):Play() end end
					task.delay(0.4, function() if bowl.Parent then bowl:Destroy() end end)
				end
				return
			end
		end
		-- leave the bowl until they stand up, then it's a mess to clean
		while plr.Parent and hum.Parent and hum.SeatPart == seat do task.wait(1) end
		if not bowl.Parent then return end
		-- VIP 라운지 소파는 NPC 좌석 목록(seats)에 없어서 rec이 없음 → 임시 기록을 만들어 똑같이 청소 대상으로 (11/13)
		if not rec and seat and seat.Parent and not seat:GetAttribute("Reserved") then
			local _, vipTop = nil, nil
			local bd
			for _, d in ipairs(workspace:GetDescendants()) do
				if d:IsA("BasePart") and ((d.Name == "Top" and d.Parent and d.Parent.Name == "Table") or d.Name == "LowTable") then
					local dist = ((d.Position - seat.Position) * Vector3.new(1, 0, 1)).Magnitude
					if math.abs(d.Position.Y - seat.Position.Y) < 4 and dist < 8 and (not bd or dist < bd) then vipTop, bd = d, dist end
				end
			end
			if vipTop then rec = { seat = seat, top = vipTop, upstairs = true, temp = true } end
		end
		if rec and not rec.reservedBy and not rec.seat.Occupant then makeDirty(rec, bowl) else task.delay(20, function() if bowl.Parent then bowl:Destroy() end end) end
	end

	------------------------------------------------------------------ 🥡 포장: 서빙하면 손님 가방에 포장 봉투(툴) → 아무 테이블 앞 의자에 앉아 클릭하면 꺼내 먹기 (11/16)
	local takeoutStore = SS:FindFirstChild("TakeoutStore") or Instance.new("Folder"); takeoutStore.Name = "TakeoutStore"; takeoutStore.Parent = SS
	local takeouts = {}   -- [key] = { bowl, owner, menu, mala }
	local nextKey = 0
	-- 앉은 자리 앞 테이블 윗면 찾기 (가게 테이블 / 집 가구 식탁·책상·커피테이블 등 무엇이든)
	-- 가구 하나 = Root(크기 상자)가 들어 있는 모델 (집 가구), 없으면 가장 가까운 모델 (가게 의자·테이블)
	local function furnOf(inst)
		-- 집 가구는 Fid 속성이 붙은 모델이 한 덩어리 (안에 하위 모델이 여러 개여도)
		local a = inst.Parent
		while a and a ~= workspace do
			if a:IsA("Model") and a:GetAttribute("Fid") then return a end
			a = a.Parent
		end
		a = inst.Parent
		while a and a ~= workspace do
			if a:IsA("Model") and a:FindFirstChild("Root") then return a end
			a = a.Parent
		end
		return inst:FindFirstAncestorWhichIsA("Model")
	end
	-- 의자·소파 방석인지 (그 가구의 Seat 바로 옆·비슷한 높이)
	local function isCushion(furn, pos)
		if not furn then return false end
		for _, s in ipairs(furn:GetDescendants()) do
			if s:IsA("Seat") and ((s.Position - pos) * Vector3.new(1, 0, 1)).Magnitude < 1.15 and math.abs(pos.Y - s.Position.Y) < 0.7 then return true end
		end
		return false
	end
	local SELF_TABLE = { lux_dining = true, gamingdesk = true }   -- 의자와 식탁이 한 가구인 세트
	local function findTableTop(seat, ch)
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then return nil end
		local myFurn = furnOf(seat)
		local excl = { seat }
		for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(excl, p.Character) end end
		local look = (root.CFrame.LookVector * Vector3.new(1, 0, 1))
		if look.Magnitude < 0.1 then return nil end
		look = look.Unit
		local right = look:Cross(Vector3.yAxis)
		for d = 0.9, 3.7, 0.35 do
			for _, lat in ipairs({ 0, 0.5, -0.5 }) do
				local o = root.Position + look * d + right * lat
				local params = RaycastParams.new(); params.FilterType = Enum.RaycastFilterType.Exclude
				local list = table.clone(excl)
				for _ = 1, 10 do
					params.FilterDescendantsInstances = list
					local res = workspace:Raycast(Vector3.new(o.X, seat.Position.Y + 4.2, o.Z), Vector3.new(0, -5.5, 0), params)
					if not res then break end
					local hit = res.Instance
					if hit.Transparency >= 0.9 or hit:IsA("Seat") or hit:IsA("VehicleSeat") or hit:IsDescendantOf(fxFolder) then
						table.insert(list, hit)   -- 투명 상자(Root)·의자·그릇은 통과
					else
						local dy = res.Position.Y - seat.Position.Y
						local furn = furnOf(hit)
						local hd = ((res.Position - seat.Position) * Vector3.new(1, 0, 1)).Magnitude
						-- 내가 앉은 가구 자체(통메시는 충돌이 상자라 등받이 높이에서 맞음)는 가까우면 무시
						-- 내가 앉은 가구 자체는 테이블로 안 침 (침대·소파·리클라이너 발받침 등). 식탁이 붙은 세트 가구만 예외
						local ownBad = false
						if myFurn and furn == myFurn then
							local fid = furn:GetAttribute("Fid") or furn.Name
							-- (11/22) 공원 피크닉 테이블처럼 의자+식탁 한 덩어리 모델은 SelfTable 속성으로 허용
							ownBad = not (SELF_TABLE[fid] or furn:GetAttribute("SelfTable")) or hd < 1.0 or dy < -0.3
						end
						if isCushion(furn, res.Position) or ownBad then
							table.insert(list, hit)   -- 내 의자·옆 의자 방석, 소파 틀은 테이블이 아님 → 통과
						else
							-- 소파 앞 낮은 커피테이블도 (의자 방석보다 조금 낮아도 됨), 바닥·러그는 제외
							if dy > -0.5 and dy < 3.6 and res.Normal.Y > 0.8 then return res.Position, hit end
							break
						end
					end
				end
			end
		end
		return nil
	end
	-- Studio 테스트: ServerStorage.TakeoutTableTest:Invoke(player) -> 앉은 자리 앞 테이블 윗면 위치 (없으면 nil)
	if game:GetService("RunService"):IsStudio() then
		local bf = SS:FindFirstChild("TakeoutTableTest") or Instance.new("BindableFunction"); bf.Name = "TakeoutTableTest"; bf.Parent = SS
		bf.OnInvoke = function(plr)
			local ch = plr.Character; local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			if not seat then return nil end
			return findTableTop(seat, ch)
		end
	end
	local function giveTakeoutTool(plr, key)
		local rec = takeouts[key]; if not rec then return end
		local bp = plr:FindFirstChildOfClass("Backpack"); if not bp then return end
		for _, cont in ipairs({ bp, plr.Character }) do
			if cont then for _, x in ipairs(cont:GetChildren()) do if x:IsA("Tool") and x:GetAttribute("TakeoutKey") == key then return end end end
		end
		local tool = Instance.new("Tool"); tool.Name = "포장 " .. rec.menu; tool.CanBeDropped = false
		tool.ToolTip = "테이블 앞 의자에 앉아서 클릭하면 꺼내 먹어요"
		tool:SetAttribute("TakeoutKey", key); tool:SetAttribute("Takeout", true)
		-- 손에 드는 비닐봉지 (손잡이를 잡고 아래로 대롱)
		local bagSrc = Assets:FindFirstChild("TakeoutBag")
		local bagPart = bagSrc and bagSrc:FindFirstChildWhichIsA("MeshPart", true)
		local h
		if bagPart then
			h = bagPart:Clone(); h.Size = bagPart.Size * (1.7 / bagPart.Size.Y)
		else
			h = Instance.new("Part"); h.Size = Vector3.new(1.15, 1.6, 0.95); h.Color = BAG_WHITE; h.Material = Enum.Material.SmoothPlastic
		end
		h.Name = "Handle"; h.Anchored = false; h.CanCollide = false; h.CanQuery = false; h.CanTouch = false; h.Massless = true; h.Parent = tool
		-- 손잡이 끝을 잡고 봉지가 아래로 대롱
		tool.GripPos = Vector3.new(0, h.Size.Y * 0.42, 0)
		local lastUse = 0
		tool.Activated:Connect(function()
			if os.clock() - lastUse < 0.6 then return end   -- 연타 막기 (테이블 찾기 + 알림 도배)
			lastUse = os.clock()
			local r2 = takeouts[key]
			if not r2 or r2.owner ~= plr then tool:Destroy(); return end
			if eaters[plr] then return end
			local ch = plr.Character
			local hum = ch and ch:FindFirstChildOfClass("Humanoid")
			local seat = hum and hum.SeatPart
			if not seat or seat:IsA("VehicleSeat") then notify(plr, "🪑 테이블 앞 의자에 앉아서 먹어요"); return end
			local top = findTableTop(seat, ch)
			if not top then notify(plr, "앞에 테이블이 있는 자리에 앉아야 먹을 수 있어요"); return end
			local bowl = r2.bowl
			takeouts[key] = nil
			tool:Destroy()
			if not (bowl and bowl.Parent and bowl.PrimaryPart) then notify(plr, "음식을 찾지 못했어요"); return end
			unbag(bowl)
			bowl.PrimaryPart.Anchored = true
			bowl:PivotTo(CFrame.new(top + Vector3.new(0, 0.46, 0)))
			bowl.Parent = fxFolder
			local rec
			for _, s in ipairs(seats) do if s.seat == seat then rec = s end end
			sfx("OrderReady", bowl.PrimaryPart, 0.5, 40)
			task.spawn(eat, plr, bowl, seat, rec, hum, r2.mala)
		end)
		tool.Parent = bp
	end
	-- 리스폰하면 가방이 비워지므로 포장 봉투 다시 넣어주기 / 나가면 보관한 음식 정리
	local function regive(plr) for key, r2 in pairs(takeouts) do if r2.owner == plr then giveTakeoutTool(plr, key) end end end
	Players.PlayerAdded:Connect(function(plr) plr.CharacterAdded:Connect(function() task.wait(1); regive(plr) end) end)
	for _, plr in ipairs(Players:GetPlayers()) do plr.CharacterAdded:Connect(function() task.wait(1); regive(plr) end) end
	Players.PlayerRemoving:Connect(function(plr)
		for key, r2 in pairs(takeouts) do if r2.owner == plr then if r2.bowl then r2.bowl:Destroy() end; takeouts[key] = nil end end
	end)
	local function deliverTakeout(t, carrier)
		local plr = t.playerCustomer
		local bowl = serving:storeTakeout(t, takeoutStore)
		if not bowl then return false end
		nextKey += 1
		local key = tostring(plr.UserId) .. "_" .. nextKey
		takeouts[key] = { bowl = bowl, owner = plr, menu = t.menu, mala = not t.side }
		serving:finishPlayerDelivery(t, carrier, "포장 전달 완료! %s님 음식")
		giveTakeoutTool(plr, key)
		notify(plr, "🥡 포장 음식을 받았어요! 가방에서 꺼내 테이블 앞 의자에 앉아 클릭하면 먹어요")
		closeOrder(t)
		return true
	end

	local function makeDeliver(t)
		return function(carrier)
			if t.takeout then return deliverTakeout(t, carrier) end
			local plr = t.playerCustomer
			local seat, top, rec, hum = tableSpot(plr)
			if not seat then
				if carrier then notify(carrier, "손님이 아직 자리에 앉지 않았어요") end
				return false
			end
			local bowl = serving:placePlayerMeal(t, seat, top)
			if not bowl then return false end
			serving:finishPlayerDelivery(t, carrier, "서빙 완료! %s님 음식")
			notify(plr, "음식이 나왔어요! 맛있게 드세요")
			closeOrder(t)
			task.spawn(eat, plr, bowl, seat, rec, hum, not t.side)
			return true
		end
	end

	local function readyNow(t)
		-- drinks: nothing to cook, straight onto the pass
		while not t.cancelled and t.state == "pouring" do
			if stations:freePassSlot() then placeOnPass(t) else task.wait(1) end
		end
	end

	-- F "주문하기" on every register
	for _, reg in ipairs(REGISTERS) do
		local part = reg.prompt and reg.prompt.Parent
		if part then
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "PlaceOrder"; pp.ActionText = "주문하기"; pp.ObjectText = "손님 주문"
			pp.KeyboardKeyCode = Enum.KeyCode.F; pp.GamepadKeyCode = Enum.KeyCode.ButtonY
			pp.HoldDuration = 0; pp.MaxActivationDistance = 8; pp.RequiresLineOfSight = false
			pp.UIOffset = Vector2.new(0, 72)
			pp.Parent = part
			pp.Triggered:Connect(function(plr)
				if not near(plr, part.Position, 14) then return end
				if active[plr] then notify(plr, string.format("이미 주문한 음식(#%d)이 나오고 있어요", active[plr].id)); return end
				if plr:GetAttribute("CarryTicket") then notify(plr, "서빙 중에는 주문할 수 없어요"); return end
				local _, list = bowlInfo(plr)
				local scoops = list and #list or 0
				local items = {}
				for _, it in ipairs(MENU) do
					local price, grams = priceOf(it, scoops)
					table.insert(items, { name = it.name, price = price, grams = grams, mala = it.mala == true, instant = it.instant == true, ok = (not it.mala) or scoops > 0 })
				end
				orderRE:FireClient(plr, "open", { items = items, scoops = scoops, hasBowl = list ~= nil, money = Money.Get(plr) })
			end)
		end
	end

	-- 음료: 주문하면 바로 가방(툴바)에 들어옴 -> 클릭해서 마시기
	local MAX_DRINKS = 3
	local function drinkCount(plr)
		local n = 0
		for _, cont in ipairs({ plr:FindFirstChildOfClass("Backpack"), plr.Character }) do
			if cont then for _, x in ipairs(cont:GetChildren()) do if x:IsA("Tool") and x:GetAttribute("Drink") then n += 1 end end end
		end
		return n
	end
	local function orderDrink(plr, it)
		local src = SS:FindFirstChild("DrinkTool")
		local bp = plr:FindFirstChildOfClass("Backpack")
		if not src or not bp then return false, "잠시 후 다시 시도해 주세요" end
		if drinkCount(plr) >= MAX_DRINKS then return false, string.format("음료는 %d개까지 들 수 있어요", MAX_DRINKS) end
		if not Money.TryRemove(plr, it.price, "주문: " .. it.name) then return false, "돈이 부족해요" end
		local tool = src:Clone(); tool.Name = "환타"
		tool.Parent = bp
		for _, reg in ipairs(REGISTERS) do if reg.prompt and near(plr, reg.prompt.Parent.Position, 16) then sfx("CashRegister", reg.prompt.Parent, 0.6) break end end
		return true, "drink"
	end

	placeRF.OnServerInvoke = function(plr, name, spice, takeout)
		if busy[plr] then return false, "잠시만요" end
		local it = type(name) == "string" and menuItem(name)
		if not it then return false, "없는 메뉴예요" end
		if it.instant then
			if not atRegister(plr) then return false, "계산대 앞에서 주문해요" end
			busy[plr] = true
			local ok, a, b = pcall(orderDrink, plr, it)
			busy[plr] = nil
			if not ok then warn("[CustomerService] drink", a); return false, "오류가 났어요" end
			return a, b
		end
		if active[plr] then return false, "이미 주문한 음식이 있어요" end
		if not atRegister(plr) then return false, "계산대 앞에서 주문해요" end
		if takeout == true then
			-- 포장 음식은 한 사람당 5개까지 (서버에 보관하는 음식 모델이 끝없이 쌓이지 않게)
			local held = 0
			for _, r2 in pairs(takeouts) do if r2.owner == plr then held += 1 end end
			if held >= 5 then return false, "포장 음식은 5개까지만 들 수 있어요 (먼저 먹어요!)" end
		end
		local tool, list = bowlInfo(plr)
		if it.mala and (not list or #list == 0) then return false, "재료 바에서 그릇에 재료를 먼저 담아요" end
		local price, grams = priceOf(it, it.mala and #list or 0)
		busy[plr] = true
		local paid = Money.TryRemove(plr, price, "주문: " .. it.name)
		busy[plr] = nil
		if not paid then return false, "돈이 부족해요" end
		local kinds
		if it.mala then
			local seen = {}; kinds = {}
			for _, k in ipairs(list) do if not seen[k] then seen[k] = true; table.insert(kinds, k) end end
			tool:Destroy()   -- the bowl goes to the kitchen
		end
		local t = tickets:register({
			menu = it.name, side = not it.mala, spice = it.mala and (function() local s = math.floor(tonumber(spice) or 2); if s ~= s then s = 2 end; return math.clamp(s, 0, 4) end)() or 0,
			weight = grams or 0, kinds = kinds, list = it.mala and table.clone(list) or nil, correct = true,
			playerCustomer = plr, price = price, share = math.floor(price * SHARE / 10 + 0.5) * 10, orderedAt = os.clock(),
			takeout = (takeout == true) or nil,
		}, it.instant and "pouring" or "ordered")
		t.deliver = makeDeliver(t)
		active[plr] = t
		plr:SetAttribute("MyOrder", t.id)
		attachServe(t)
		for _, reg in ipairs(REGISTERS) do if reg.prompt and near(plr, reg.prompt.Parent.Position, 16) then sfx("CashRegister", reg.prompt.Parent, 0.6) break end end
		refreshBoard()
		if it.instant then task.spawn(readyNow, t) end
		return true, t.id
	end

	-- a cancelled order (customer left) that still shows up on the pass or in someone's hands: clear it away
	local orphans = {}
	local function clearTicket(t)
		stations:release(t)
		if t.carrier and t.carrier.Parent and isCarrying(t.carrier, t.id) then
			releaseCarry(t.carrier, t.id)
			notify(t.carrier, "주문한 손님이 나가서 음식을 치웠어요")
		end
		if t.bowl and t.bowl.Parent then t.bowl:Destroy() end
		tickets:setState(t, "done"); tickets:remove(t.id)
		refreshBoard()
	end

	-- 플레이어 손님이 주문만 하고 자리에 안 앉으면 음식이 패스대 칸을 계속 막음 →
	--   음식이 나온 뒤 SEAT_LIMIT초 안에 안 앉으면 치움 (음식값 절반 환불, 들고 있던 직원은 서빙 보상 그대로)
	local SEAT_LIMIT = C.PlayerSeatLimit or 90
	local function seatWatch(plr, t)
		if t.takeout then return false end   -- 포장은 안 앉아도 됨
		if t.state ~= "ready" and t.state ~= "carried" then return false end
		if tableSpot(plr) then return false end   -- 앉아 있으면 아래에서 바로 서빙됨
		t.firstReady = t.firstReady or os.clock()
		local waited = os.clock() - t.firstReady
		local left = math.max(0, math.ceil(SEAT_LIMIT - waited))
		if left > 0 then
			if not t.seatToldAt or os.clock() - t.seatToldAt >= 20 then
				t.seatToldAt = os.clock()
				notify(plr, string.format("🍜 주문한 음식이 나왔어요! 빈 자리에 앉아야 받을 수 있어요 (%d초 남음)", left))
			end
			return false
		end
		-- 시간 초과: 치우기
		local c = t.carrier
		if t.state == "carried" and c and c.Parent and isCarrying(c, t.id) then
			releaseCarry(c, t.id)
			if c ~= plr then
				reward(c, "Serve", t.share or 0, "서빙")
				notify(c, "손님이 자리에 안 앉아서 음식을 치웠어요 (서빙 보상은 드렸어요)")
			end
		end
		stations:release(t)
		if t.bowl and t.bowl.Parent then t.bowl:Destroy() end
		tickets:cancel(t); tickets:setState(t, "done"); tickets:remove(t.id)
		closeOrder(t)
		local back = math.floor((t.price or 0) * 0.5 / 10) * 10
		if back > 0 then Money.Add(plr, back, "주문 취소 환불") end
		notify(plr, string.format("자리에 앉지 않아서 음식을 치웠어요 (%s원 환불). 다음엔 주문 후 자리에 앉아주세요!", tostring(back)))
		refreshBoard()
		return true
	end

	-- nobody started cooking it: the kitchen makes it, and it's brought to the table once the customer is seated
	task.spawn(function()
		while true do
			task.wait(2)
			for t in pairs(orphans) do
				if t.state == "ready" or t.state == "carried" or t.state == "ordered" then clearTicket(t); orphans[t] = nil
				elseif t.state == "done" then orphans[t] = nil end
			end
			for plr, t in pairs(active) do
				if t.cancelled or not plr.Parent then
					active[plr] = nil
				elseif seatWatch(plr, t) then
					-- 자리에 안 앉아서 치움 (위에서 처리)
				elseif t.state == "ordered" and not t.auto and os.clock() - t.orderedAt > AUTO_AFTER then
					if stations:freePassSlot() then
						t.auto = true
						placeOnPass(t)
						notify(plr, "주문하신 음식이 나왔어요! 자리에 앉아 있으면 바로 가져다드려요")
					end
				elseif t.state == "ready" then
					-- waiting on the pass too long (drinks, or nobody carried it): brought over automatically
					t.carriedAt = nil
					t.readyAt = t.readyAt or os.clock()
					if t.auto or os.clock() - t.readyAt > AUTO_AFTER * 0.5 then t.deliver(nil) end
				elseif t.state == "carried" then
					t.readyAt = nil
					t.carriedAt = t.carriedAt or os.clock()
					local c = t.carrier
					if c == plr and isCarrying(plr, t.id) and t.takeout then
						t.deliver(plr)   -- 내 포장 음식을 직접 들면 바로 가방으로
					elseif c == plr and isCarrying(plr, t.id) then
						if not t.selfTold then t.selfTold = true; notify(plr, "자리에 앉으면 테이블에 놓여요") end
						-- picked up their own order: it goes on the table as soon as they sit down (no serving reward)
						if tableSpot(plr) then
							releaseCarry(plr, t.id)
							t.deliver(nil)
						end
					elseif not (c and c.Parent and isCarrying(c, t.id)) then
						-- carrier vanished without the order: back onto the pass
						if t.bowl and t.bowl.Parent then t.bowl:Destroy() end
						t.carrier = nil; t.carriedAt = nil
						placeOnPass(t)
					elseif t.takeout and os.clock() - t.carriedAt > 45 then
						-- 포장은 자리가 필요 없음: 들고 다닌 지 오래되면 손님 가방으로 바로 (직원은 서빙 보상)
						t.deliver(c)
					elseif os.clock() - t.carriedAt > 60 and not tableSpot(plr) then
						-- carried around for a minute and the customer still isn't seated: put it back on the pass
						releaseCarry(c, t.id)
						if t.bowl and t.bowl.Parent then t.bowl:Destroy() end
						t.carrier = nil; t.carriedAt = nil
						if placeOnPass(t) then
							notify(c, "손님이 자리에 앉지 않아서 음식을 픽업대에 다시 올려뒀어요")
						else
							tickets:setState(t, "ordered"); t.auto = false; t.orderedAt = os.clock() - AUTO_AFTER
						end
					end
				end
			end
		end
	end)

	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function() task.wait(0.5); local t = active[plr]; if t then attachServe(t) end end)
	end)
	for _, plr in ipairs(Players:GetPlayers()) do
		plr.CharacterAdded:Connect(function() task.wait(0.5); local t = active[plr]; if t then attachServe(t) end end)
	end
	-- leaving before the food came: refund if the kitchen hadn't started
	Players.PlayerRemoving:Connect(function(plr)
		local t = active[plr]
		if not t then return end
		if t.state == "ordered" or t.state == "pouring" then Money.Add(plr, t.price, "주문 취소 환불") end
		tickets:cancel(t)
		active[plr] = nil
		if t.servePrompt then t.servePrompt:Destroy(); t.servePrompt = nil end
		orphans[t] = true
	end)
end

return PlayerOrders
