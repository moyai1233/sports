local Serving = {}
Serving.__index = Serving

function Serving.new(context)
	return setmetatable(context, Serving)
end

function Serving:makePickup(t)
	local bowl = t.bowl
	if not (bowl and bowl.PrimaryPart) then return end
	local tag = bowl.PrimaryPart:FindFirstChild("Tag")
	local pp = Instance.new("ProximityPrompt")
	pp.Name = "Pickup"; pp.ActionText = t.takeout and "포장 들기" or "그릇 들기"; pp.ObjectText = string.format(t.takeout and "#%d 🥡 %s (포장)" or "#%d %s", t.id, t.menu)
	pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.25; pp.MaxActivationDistance = 7; pp.RequiresLineOfSight = false
	pp.Parent = bowl.PrimaryPart
	pp.Triggered:Connect(function(plr)
		if t.state ~= "ready" or t.bowl ~= bowl then return end
		if not self.near(plr, bowl.PrimaryPart.Position, 12) then return end
		-- 들 수 있는 개수 안에서 빈 칸 (CarryConfig.capacity: 1 / 2 / 3 / 쟁반 5 / 카트 8)
		local cap = self.carryConfig.capacity(plr)
		local carrySlot
		for k = 1, cap do
			local attr = self.carryConfig.Slots[k]
			if not plr:GetAttribute(attr) then
				carrySlot = attr
				break
			end
		end
		if not carrySlot then
			local msg
			if plr:GetAttribute("CartOn") then msg = "서빙 카트가 꽉 찼어요 (8개)"
			elseif cap >= self.carryConfig.TrayMax then msg = "쟁반 두 개가 꽉 찼어요 (4개) · 서빙 카트로 8개까지!"
			elseif cap == 3 then msg = "양손도 머리도 꽉 찼어요 (쟁반 서빙 업그레이드로 4개까지!)"
			elseif cap == 2 then msg = "양손이 꽉 찼어요 (머리 서빙 업그레이드로 3개까지!)"
			else msg = "이미 그릇을 들고 있어요 (양손 서빙 업그레이드로 2개까지!)" end
			self.notify(plr, msg)
			return
		end
		local ch = plr.Character
		local hand = ch and (ch:FindFirstChild("RightHand") or ch:FindFirstChild("Right Arm"))
		if not hand then return end
		-- 패스대에서 운반자로 티켓을 넘긴 뒤 그릇을 손에 배치한다.
		self.kitchen:release(t)
		t.carrier = plr
		self.tickets:setState(t, "carried")
		plr:SetAttribute(carrySlot, t.id)

		local hum = ch:FindFirstChildOfClass("Humanoid"); if hum then hum:UnequipTools() end
		pp:Destroy(); if tag then tag.Enabled = true end
		do
			local st = self.skinOf(plr, "bowl")
			if st and bowl:FindFirstChild("Broth") and bowl.PrimaryPart then pcall(self.skinStyle.apply, bowl.PrimaryPart, st, { gems = 10 }) end
		end
		self.carryLayout(plr)
		self.refreshBoard()
		self.notify(plr, string.format("#%d 손님에게 가져다주세요", t.id))
	end)
	return true
end

-- 든 음식 그릇 내려놓기: 마지막에 든 그릇을 패스대 빈 칸에 돌려놓음 (주문은 그대로, 누구나 다시 들 수 있음)
--   ServerStorage.PutBackCarry:Invoke(player) -> ok, 메시지   (BowlService의 내려놓기 버튼에서 호출)
function Serving:putBack(plr)
	local id
	for k = #self.carryConfig.Slots, 1, -1 do
		id = plr:GetAttribute(self.carryConfig.Slots[k])
		if id then break end
	end
	local t = id and self.tickets:get(id)
	if not t or t.state ~= "carried" or t.carrier ~= plr or t.cancelled
		or not (t.bowl and t.bowl.Parent and t.bowl.PrimaryPart) then
		return false, "내려놓을 그릇이 없어요"
	end
	if id < 0 then   -- Studio 테스트 그릇
		t.bowl:Destroy()
		self.tickets:remove(id)
		self.releaseCarry(plr, id)
		return true
	end

	local passSlot = self.kitchen:freePassSlot()
	if not passSlot then return false, "패스대가 꽉 차서 내려놓을 수 없어요" end
	-- 들고 있던 그릇을 그대로 옮기면 플레이어 화면에서는 허공에 남음 → 서빙 때와 같이 복사본을 패스대에 놓고 원본은 지움
	self.kitchen:returnBowl(t, passSlot, self.placeOnTable)
	self.releaseCarry(plr, id)
	self:makePickup(t)
	self.refreshBoard()
	return true, string.format("#%d 그릇을 패스대에 내려놨어요", t.id)
end

function Serving:deliverToNPC(c, plr)
	local t = c.ticket
	if not t or t.state ~= "carried" or t.carrier ~= plr then return false end
	local bowl = t.bowl
	-- put the bowl on the table in front of the customer
	local seatPos, top = c.seatRec.seat.Position, c.seatRec.top
	local dir = (top.Position - seatPos) * Vector3.new(1, 0, 1)
	local p = seatPos + dir.Unit * math.min(2.4, dir.Magnitude)
	p = Vector3.new(p.X, top.Position.Y + top.Size.Y / 2 + 0.46, p.Z)
	bowl = self.placeOnTable(bowl, CFrame.new(p)); t.bowl = bowl
	c.tableBowl = bowl
	local tag = bowl.PrimaryPart:FindFirstChild("Tag"); if tag then tag:Destroy() end   -- no number tag on the table
	self.tickets:setState(t, "done")
	self.releaseCarry(plr, t.id)
	self.refreshBoard()
	c.waitStage = nil
	if c.servePrompt then c.servePrompt:Destroy(); c.servePrompt = nil end
	return true
end

function Serving:storeTakeout(t, takeoutStore)
	local bowl = t.bowl
	if not bowl or not bowl.Parent then return false end
	self.kitchen:release(t)
	local pick = bowl.PrimaryPart:FindFirstChild("Pickup"); if pick then pick:Destroy() end
	local tag = bowl.PrimaryPart:FindFirstChild("Tag"); if tag then tag:Destroy() end
	bowl = self.placeOnTable(bowl, CFrame.new(0, -400, 0))
	bowl.Parent = takeoutStore
	t.bowl = nil
	self.tickets:setState(t, "done")
	return bowl
end

function Serving:placePlayerMeal(t, seat, top)
	local bowl = t.bowl
	if not bowl or not bowl.Parent then return false end
	self.kitchen:release(t)
	local pick = bowl.PrimaryPart:FindFirstChild("Pickup"); if pick then pick:Destroy() end
	local dir = (top.Position - seat.Position) * Vector3.new(1, 0, 1)
	local p = seat.Position + (dir.Magnitude > 0.1 and dir.Unit * math.min(2.4, dir.Magnitude) or Vector3.zero)
	do -- 테이블 위를 벗어나지 않게 (가장자리에서 0.7 안쪽)
		local lp = top.CFrame:PointToObjectSpace(p)
		local hx, hz = math.max(0, top.Size.X / 2 - 0.6), math.max(0, top.Size.Z / 2 - 0.4)
		p = top.CFrame:PointToWorldSpace(Vector3.new(math.clamp(lp.X, -hx, hx), 0, math.clamp(lp.Z, -hz, hz)))
	end
	p = Vector3.new(p.X, top.Position.Y + top.Size.Y / 2 + 0.46, p.Z)
	bowl = self.placeOnTable(bowl, CFrame.new(p)); t.bowl = bowl
	local tag = bowl.PrimaryPart:FindFirstChild("Tag"); if tag then tag:Destroy() end
	self.tickets:setState(t, "done")
	return bowl
end

function Serving:finishPlayerDelivery(t, carrier, message)
	if carrier then
		self.releaseCarry(carrier, t.id)
		if carrier ~= t.playerCustomer then self.reward(carrier, "Serve", t.share or 0, "서빙") end
		self.notify(carrier, string.format(message, t.playerCustomer.DisplayName))
	end
	self.refreshBoard()
end

return Serving
