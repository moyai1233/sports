local Players = game:GetService("Players")
local PFS = game:GetService("PathfindingService")
local Customers = {}

----------------------------------------------------------------- movement
local AGENT = { AgentRadius = 1.4, AgentHeight = 5, AgentCanJump = false, WaypointSpacing = 4 }
local function walkTo(c, target)
	local hum, root = c.hum, c.root
	for attempt = 1, 3 do
		if not c.alive then return false end
		local path = PFS:CreatePath(AGENT)
		local ok = pcall(function() path:ComputeAsync(root.Position, target) end)
		if ok and path.Status == Enum.PathStatus.Success then
			local wps = path:GetWaypoints()
			local stuck = false
			for i = 2, #wps do
				if not c.alive then return false end
				-- (11/19) 웨이포인트에 거의 닿으면 멈추기 전에 바로 다음 점으로 → 걷다 서다 반복(뚝뚝 끊김) 없음
				local wp = wps[i].Position
				local last = (i == #wps)
				hum:MoveTo(wp)
				local done = false
				local conn = hum.MoveToFinished:Connect(function(ok) if ok and ((root.Position - wp) * Vector3.new(1, 0, 1)).Magnitude < 4 then done = true end end)
				local t0 = os.clock()
				while not done and os.clock() - t0 < 3 and c.alive do
					if not last and math.abs(wp.Y - root.Position.Y) < 4 and ((root.Position - wp) * Vector3.new(1, 0, 1)).Magnitude < 2.2 then done = true; break end
					task.wait()
				end
				conn:Disconnect()
				if not done then stuck = true; break end
			end
			if not stuck then return true end
		else
			task.wait(0.5)
		end
	end
	-- last resort: walk straight (same floor only; across floors that means walking off a balcony/window)
	if math.abs(target.Y - root.Position.Y) > 6 then return false end
	hum:MoveTo(target)
	local t0 = os.clock()
	while c.alive and (root.Position - target).Magnitude > 3 and os.clock() - t0 < 6 do task.wait(0.2) end
	return (root.Position - target).Magnitude <= 4
end
-- 2F -> 1F: top landing, down flight 2, half landing, down flight 1, out at the bottom
local STAIRS_DOWN = {
	Vector3.new(-25.2, 20.6, 19.7),   -- arrival platform (2F)
	Vector3.new(-22.9, 20.6, 22.6),   -- top of flight 2
	Vector3.new(-22.9, 12.4, 33.4),   -- bottom of flight 2
	Vector3.new(-25.2, 12.1, 35.6),   -- half landing
	Vector3.new(-27.6, 12.1, 33.4),   -- top of flight 1
	Vector3.new(-27.6, 4.0, 22.6),    -- bottom of flight 1
	Vector3.new(-27.6, 3.0, 19.0),    -- off the stairs (1F)
}
local function stepTo(c, p, timeout)
	local hum, root = c.hum, c.root
	hum:MoveTo(p)
	local t0 = os.clock()
	while c.alive and os.clock() - t0 < (timeout or 4) do
		if ((root.Position - p) * Vector3.new(1, 0, 1)).Magnitude < 1.6 then return true end
		task.wait()
	end
	return false
end
-- 걸어서 못 들어가는 좁은 틈(소파↔테이블)을 걸음 속도로 미끄러지듯 이동 (순간이동 대신)
local function glideTo(c, p, faceDir)
	local root = c.root
	if not c.alive or not root then return end
	local from = Vector3.new(root.Position.X, p.Y, root.Position.Z)   -- 높이는 목표 높이로 고정 (일어날 때 튀어오른 채로 떠 있지 않게)
	local flat = (p - from) * Vector3.new(1, 0, 1)
	local dist = flat.Magnitude
	if dist < 0.2 then return end
	local look = faceDir or flat.Unit
	local speed = math.max(c.hum.WalkSpeed, 6)
	local dur = dist / speed
	root.Anchored = true
	local rot0 = root.CFrame.Rotation
	local rot1 = CFrame.lookAt(Vector3.zero, look)
	local t0 = os.clock()
	while c.alive and root.Parent do
		local a = math.min((os.clock() - t0) / dur, 1)
		local pos = from:Lerp(p, a)
		root.CFrame = CFrame.new(pos) * rot0:Lerp(rot1, math.min((os.clock() - t0) / 0.25, 1))
		if a >= 1 then break end
		task.wait()
	end
	if root.Parent then root.Anchored = false end
end
-- (11/19) 앵커한 채로 목표 CFrame까지 부드럽게 (앉기 · 일어서기: 순간이동처럼 툭 붙지 않게)
local function smoothMove(c, root, toCF, dur)
	local from = root.CFrame
	local t0 = os.clock()
	while c.alive and root.Parent do
		local a = math.min((os.clock() - t0) / dur, 1)
		local e = a * a * (3 - 2 * a)
		root.CFrame = from:Lerp(toCF, e)
		if a >= 1 then break end
		task.wait()
	end
end
local function seatedCF(rec, root)
	local seat = rec.seat
	return seat.CFrame * CFrame.new(0, seat.Size.Y / 2 + root.Size.Y * 0.743, 0)
end
local function smoothSit(c, rec)
	local root, seat = c.root, rec.seat
	if not (root and seat and c.alive) then return end
	c.standY = root.Position.Y
	local to = seatedCF(rec, root)
	local d = (to.Position - root.Position).Magnitude
	if d > 6 or d < 0.15 then return end
	root.Anchored = true
	smoothMove(c, root, to, math.clamp(d / 7, 0.25, 0.55))
	if root.Parent then root.Anchored = false end
end
local function smoothStand(c, rec)
	local root, seat = c.root, rec.seat
	if not (root and seat) then return false end
	local away = rec.top and ((seat.Position - rec.top.Position) * Vector3.new(1, 0, 1)) or (-seat.CFrame.LookVector * Vector3.new(1, 0, 1))
	if away.Magnitude < 0.1 then return false end
	away = away.Unit
	root.Anchored = true
	local sw = seat:FindFirstChild("SeatWeld"); if sw then sw:Destroy() end
	c.hum.Sit = false
	local y = c.standY or root.Position.Y
	local dest = Vector3.new(root.Position.X, y, root.Position.Z) + away * 2.5
	smoothMove(c, root, CFrame.lookAt(dest, dest + away), 0.5)
	if root.Parent then
		c.hum:ChangeState(Enum.HumanoidStateType.Running)
		root.Anchored = false
	end
	return true
end
-- 좁은 자리(VIP 소파 등)의 입구: 소파↔테이블 틈의 끝점 (한 번 계산해 좌석에 저장)
local function slotEntry(rec)
	if rec.slot ~= nil then return rec.slot or nil end
	local seatPos = rec.seat.Position
	local toTable = ((rec.top.Position - seatPos) * Vector3.new(1, 0, 1))
	if toTable.Magnitude < 0.1 then rec.slot = false; return nil end
	toTable = toTable.Unit
	local fwd = toTable
	do local lv = rec.seat.CFrame.LookVector * Vector3.new(1, 0, 1); if lv.Magnitude > 0.5 and lv.Unit:Dot(toTable) > 0.3 then fwd = lv.Unit end end
	local gap = math.clamp((rec.top.Position - seatPos):Dot(fwd) * 0.55, 1.2, 2.4)
	local front = Vector3.new(seatPos.X, seatPos.Y + 1.5, seatPos.Z) + fwd * gap
	local along = Vector3.new(-fwd.Z, 0, fwd.X)
	local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
	local cf = workspace:FindFirstChild("Customers"); if cf then table.insert(ex, cf) end
	rp.FilterDescendantsInstances = ex
	local from = STAIRS_DOWN[1]
	for _, d in ipairs({ 3, -3, 4, -4, 5, -5, 6, -6, 7, -7, 8, -8, 9, -9 }) do
		local entry = front + along * d
		local clear = true
		for _, h in ipairs({ 0.3, 2.2 }) do
			local o = entry + Vector3.new(0, h, 0)
			if workspace:Raycast(o, (front + Vector3.new(0, h, 0)) - o, rp) then clear = false; break end
		end
		if clear then
			for _ = 1, 3 do   -- 요청이 몰려 실패하면 잠깐 쉬었다 다시
				local path = PFS:CreatePath(AGENT)
				local ok = pcall(function() path:ComputeAsync(from, entry) end)
				if ok then
					local wps = path.Status == Enum.PathStatus.Success and path:GetWaypoints()
					if wps and #wps > 0 and ((wps[#wps].Position - entry) * Vector3.new(1, 0, 1)).Magnitude < 2 then
						rec.slot = { entry = entry, front = front }
						return rec.slot
					end
					break
				end
				task.wait(0.3)
			end
		end
	end
	rec.slot = false
	return nil
end

-- 서버 시작 때 VIP 좌석 입구를 미리 계산 (스폰 중 길찾기 요청이 몰려도 순간이동하지 않게)
function Customers.prepareVIPSeats(vipSeats)
	task.delay(3, function()
		local n = 0
		for _, rec in ipairs(vipSeats) do
			if slotEntry(rec) then n += 1 end
			task.wait(0.1)
		end
		print("[CustomerService] VIP 입구 계산", n, "/", #vipSeats)
		-- (11/18) 서버 시작 직후(집 부지 건설 등)와 겹쳐 일시적으로 실패한 좌석만 10초 간격으로 최대 3번 다시 계산
		--   임시 기록으로 계산하고 성공했을 때만 반영 (계산 중에도 좌석은 기존 '실패' 상태 그대로)
		for round = 1, 3 do
			if n >= #vipSeats then break end
			task.wait(10)
			local fixed = 0
			for _, rec in ipairs(vipSeats) do
				if rec.slot == false and rec.seat and rec.seat.Parent and rec.top and rec.top.Parent then
					local tmp = { seat = rec.seat, top = rec.top }
					local ok, sl = pcall(slotEntry, tmp)
					if ok and sl then rec.slot = sl; n += 1; fixed += 1 end
					task.wait(0.1)
				end
			end
			print("[CustomerService] VIP 입구 재계산", round, "회차: +" .. fixed, "→", n, "/", #vipSeats)
		end
	end)
end

local function goDownstairs(c)
	if not c.alive or c.root.Position.Y < 12 then return end
	-- get to the top of the stairs on the 2F floor first (pathfinding works fine on one floor)
	walkTo(c, STAIRS_DOWN[1])
	for i = 2, #STAIRS_DOWN do
		if not c.alive then return end
		stepTo(c, STAIRS_DOWN[i], 5)
	end
end
local function face(c, dir)
	c.root.CFrame = CFrame.lookAt(c.root.Position, c.root.Position + Vector3.new(dir.X, 0, dir.Z))
end

function Customers.new(context)
	local C = context.config
	local DOOR_IN = context.doorIn
	local DOOR_OUT = context.doorOut
	local SPAWNS = context.spawnPoints
	local BOWL_SPOT = context.bowlSpot
	local BAR_SPOTS = context.barSpots
	local REGISTERS = context.registers
	local seats = context.seats
	local vipSeats = context.vipSeats
	local pick = context.pick
	local weighted = context.weighted
	local sfx = context.sfx
	local say = context.say
	local doorPart = context.doorPart
	local announceRE = context.announce
	local rushOn = context.rushOn
	local tickets = context.tickets
	local refreshBoard = context.refreshBoard
	local makeDirty = context.makeDirty
	local holdBowl = context.holdBowl
	local fillBowl = context.fillBowl
	local npc = { lineWaiting = 0, richEventUntil = 0 }

	----------------------------------------------------------------- groups (2 or 4 friends at one table)
	local CHAT_BAR = { "뭐 먹지?", "나 이거 담을래", "맵기 몇 단계 할 거야?", "푸주 꼭 넣어", "많이 담지 마~", "오늘은 내가 쏜다!" }
	local CHAT_WAIT = { "여기 맛집이래", "배고파~", "언제 나오지?", "냄새 좋다", "다음엔 마라샹궈 먹자", "오늘 진짜 힘들었어" }

	local function freeGroupLeftovers(g)
		if not g or not g.seats then return end
		for _, m in ipairs(g.members) do
			if m.alive and not m.leaving and not m.seatRec then return end   -- someone is still coming to sit
		end
		for _, s in ipairs(g.seats) do
			if s.reservedBy == g then
				s.reservedBy = nil; s.seat:SetAttribute("Reserved", nil)
				local pp = s.seat:FindFirstChild("SitPrompt"); if pp then pp.Enabled = s.seat.Occupant == nil end
			end
		end
	end

	local customers = {}
	local function countActive() local n = 0; for _ in pairs(customers) do n += 1 end; return n end

	local function releaseSeat(c)
		local rec = c.seatRec
		c.seatRec = nil
		if not rec or rec.reservedBy ~= c then return end
		local seat = rec.seat
		if not seat.Occupant or seat.Occupant == c.hum then
			local weld = seat:FindFirstChild("SeatWeld")
			if weld then weld:Destroy() end
		end
		rec.reservedBy = nil
		seat:SetAttribute("Reserved", nil)
		local prompt = seat:FindFirstChild("SitPrompt")
		if prompt then prompt.Enabled = seat.Occupant == nil end
	end

	local function leaveQueue(c)
		local reg = c.queueReg
		if not reg then return end
		local index = table.find(reg.line, c)
		if index then table.remove(reg.line, index) end
		c.queueReg = nil
	end
	local function despawn(c)
		if not c.alive then return end
		c.alive = false
		if c.ticket and c.ticket.state ~= "done" then tickets:setState(c.ticket, "done"); tickets:cancel(c.ticket) end
		releaseSeat(c)
		leaveQueue(c)
		if c.servePrompt then c.servePrompt:Destroy() end
		if c.group then task.defer(freeGroupLeftovers, c.group) end
		if c.tableBowl then c.tableBowl:Destroy() end
		customers[c] = nil
		if c.model then c.model:Destroy() end
	end

	local function leave(c, angry)
		if not c.alive or c.leaving then return end
		c.leaving = true
		if c.ticket and c.ticket.state ~= "done" then tickets:setState(c.ticket, "done"); tickets:cancel(c.ticket); refreshBoard() end
		if c.servePrompt then c.servePrompt:Destroy(); c.servePrompt = nil end
		if c.skullRun then say(c, pick({ "으아아아악!!! 💀", "살려줘!!! 🔥🔥", "입에서 불이 나!!!", "물!!! 물 주세요!!!", "으아아 엄마아아!!!" }), false) else say(c, angry and (c.superRich and "이 가게, 실망이군." or "너무 늦어요...") or (c.superRich and "훌륭했소. 다음에 또 오겠네!" or "잘 먹었습니다!"), false) end
		if angry then sfx("Wrong", c.root, 0.3, 40) end
		local messRec, messBowl
		if not angry and c.seatRec and c.tableBowl and c.tableBowl.Parent then
			messRec, messBowl = c.seatRec, c.tableBowl
			c.tableBowl = nil
		end
		local wasSeat = c.seatRec
		-- VIP 소파에서 나갈 때는 항상 틈을 따라 입구로 (들어올 때 어떻게 왔든)
		if wasSeat and wasSeat.vip and type(wasSeat.slot) == "table" and c.hum.Sit then
			local e = wasSeat.slot.entry
			c.approachPt = Vector3.new(e.X, wasSeat.seat.Position.Y + 2.1, e.Z)
		end
		if c.seatRec then
			if c.approachPt and c.root then
				-- 좁은 자리: 일어날 때 점프로 튀어오르지 않게 자리에서 곧게 일어섬
				local r = c.root
				c.hum.Sit = false
				local seat = c.seatRec.seat
				if seat.Occupant == c.hum then
					local weld = seat:FindFirstChild("SeatWeld")
					if weld then weld:Destroy() end
				end
				r.Anchored = true
				r.CFrame = CFrame.new(Vector3.new(r.Position.X, c.approachPt.Y, r.Position.Z)) * r.CFrame.Rotation
				task.wait(0.3)
				releaseSeat(c)
			else
				if c.hum.Sit and c.root and smoothStand(c, c.seatRec) then c.stoodSmooth = true; releaseSeat(c)
				else c.hum.Sit = false; task.wait(0.3); releaseSeat(c) end
			end
		end
		if messRec then makeDirty(messRec, messBowl) end
		-- step out from between the chair and the table first, so pathfinding has a clear start
		if wasSeat and c.approachPt and c.alive then
			local y = c.approachPt.Y
			if type(wasSeat.slot) == "table" then glideTo(c, Vector3.new(wasSeat.slot.front.X, y, wasSeat.slot.front.Z)) end
			glideTo(c, c.approachPt)   -- 좁은 자리(VIP 소파): 들어온 길로 미끄러져 나감
			if c.root and c.root.Parent then c.root.Anchored = false end
			c.approachPt = nil
		elseif wasSeat and wasSeat.top and c.alive and not c.stoodSmooth then
			local away = (wasSeat.seat.Position - wasSeat.top.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then stepTo(c, c.root.Position + away.Unit * 2.5, 1.5) end
		end
		if c.group then freeGroupLeftovers(c.group) end
		leaveQueue(c)
		task.delay(2.5, function() if c.alive then say(c, nil) end end)
		goDownstairs(c)
		walkTo(c, DOOR_IN); walkTo(c, DOOR_OUT); walkTo(c, pick(SPAWNS))
		despawn(c)
	end

	-- patience bar: counts down while waiting for 'stage'
	local function patience(c, seconds, stage, onFail)
		if c.tutReg then seconds = seconds * 3 end   -- (11/19) 튜토리얼 손님은 넉넉히
		c.waitStage = stage
		local t0 = os.clock()
		task.spawn(function()
			local fill = c.bubble.Bar.Fill
			while c.alive and c.waitStage == stage do
				local left = 1 - (os.clock() - t0) / seconds
				fill.Size = UDim2.fromScale(math.clamp(left, 0, 1), 1)
				fill.BackgroundColor3 = left > 0.5 and Color3.fromRGB(120, 220, 100) or (left > 0.25 and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(240, 80, 64))
				if left <= 0 then onFail(); return end
				task.wait(0.25)
			end
		end)
		return t0
	end

	local function findSeat()
		local down, up = {}, {}
		for _, s in ipairs(seats) do
			if not s.reservedBy and not s.seat.Occupant then table.insert(s.upstairs and up or down, s) end
		end
		local wantUp = math.random() < (C.UpstairsChance or 0.3)
		if (wantUp and #up > 0) or #down == 0 then return #up > 0 and pick(up) or nil end
		return pick(down)
	end

	-- 👑 SUPER RICH MAN: VIP 라운지 빈 소파 (없으면 2층 일반석, 그것도 없으면 아무 자리)
	local function findVIPSeat()
		local free = {}
		for _, s in ipairs(vipSeats) do
			if not s.reservedBy and not s.seat.Occupant and s.seat.Parent then table.insert(free, s) end
		end
		if #free > 0 then return pick(free) end
		local up = {}
		for _, s in ipairs(seats) do if s.upstairs and not s.reservedBy and not s.seat.Occupant then table.insert(up, s) end end
		if #up > 0 then return pick(up) end
		return findSeat()
	end
	local function takeSeat(c)
		if c.superRich then return findVIPSeat() end
		local g = c.group
		if not g then return findSeat() end
		if not g.seats then
			g.seats = {}
			local need = 0
			for _, m in ipairs(g.members) do if m.alive and not m.leaving then need += 1 end end
			local byTop, order = {}, {}
			for _, s in ipairs(seats) do
				if not s.reservedBy and not s.seat.Occupant then
					if not byTop[s.top] then byTop[s.top] = {}; table.insert(order, s.top) end
					table.insert(byTop[s.top], s)
				end
			end
			local fits = {}
			for _, top in ipairs(order) do if #byTop[top] >= need then table.insert(fits, top) end end
			if #fits == 0 then
				-- no table has room for everyone: take the emptiest one, the rest sit as close to it as possible
				local best
				for _, top in ipairs(order) do if not best or #byTop[top] > #byTop[best] then best = top end end
				if best and #byTop[best] >= 2 then fits = { best }; need = #byTop[best] end
			end
			if #fits > 0 then
				local chosenTop = pick(fits)
				g.anchorTop = chosenTop
				local list = byTop[chosenTop]
				local chosen = {}
				if need == 2 then
					-- two friends sit across from each other
					local best, bd
					for a = 1, #list do for b = a + 1, #list do
						local fa = (list[a].top.Position - list[a].seat.Position) * Vector3.new(1, 0, 1)
						local fb = (list[b].top.Position - list[b].seat.Position) * Vector3.new(1, 0, 1)
						if fa.Unit:Dot(fb.Unit) < -0.5 then
							local d = (list[a].seat.Position - list[b].seat.Position).Magnitude
							if not bd or d < bd then best, bd = { list[a], list[b] }, d end
						end
					end end
					chosen = best or { list[1], list[2] }
				else
					for i = 1, need do chosen[i] = list[i] end
				end
				for _, s in ipairs(chosen) do
					s.reservedBy = g; s.seat:SetAttribute("Reserved", true)
					local pp = s.seat:FindFirstChild("SitPrompt"); if pp then pp.Enabled = false end
					table.insert(g.seats, s)
				end
			end
		end
		for _, s in ipairs(g.seats) do if s.reservedBy == g then return s end end
		-- overflow: nearest free chair to the group's table
		local anchor = g.anchorTop or (g.seats[1] and g.seats[1].top)
		if anchor then
			local best, bd
			for _, s in ipairs(seats) do
				if not s.reservedBy and not s.seat.Occupant then
					local d = (s.seat.Position - anchor.Position).Magnitude
					if not bd or d < bd then best, bd = s, d end
				end
			end
			if best then return best end
		end
		return findSeat()
	end

	-- chatter for groups (short line, then back to whatever the bubble showed)
	local function chat(c, lines, keepBar)
		if not c.group or not c.alive or c.leaving then return end
		say(c, pick(lines), keepBar)
		task.delay(2.6, function()
			if not c.alive or c.leaving then return end
			if keepBar and c.waitStage == "food" then say(c, "", true) elseif not keepBar then say(c, nil) end
		end)
	end

	local function runCustomer(c)
		local menu, side
		if c.tutReg then
			-- (11/19) 튜토리얼 손님: 계산대 바로 앞에 나타나서 그릇 채운 채로 바로 줄 서기
			menu = weighted(C.Menus, C.MenuWeights)
			side = C.SideMenus and C.SideMenus[menu] == true
			if not side then holdBowl(c); fillBowl(c) end
			task.wait(0.3)
		else
		-- 1) walk in and pick ingredients at the bar
		walkTo(c, DOOR_OUT)
		-- door bell: at most once every 5 s, however many customers walk in together
		local nowT = os.clock()
		if doorPart and nowT - (doorPart:GetAttribute("LastChime") or -99) >= 5 then
			doorPart:SetAttribute("LastChime", nowT)
			sfx("DoorChime", doorPart, 0.55, 70)
		end
		if c.superRich and announceRE then
			announceRE:FireAllClients({ kind = "rich", rarity = "divine", icon = "👑", title = "SUPER RICH MAN 등장!", text = string.format("VIP 라운지로 모셔요! 보상 %d배 + 룰렛 1회!", C.SuperRichMult or 15) })
		elseif c.rich and announceRE and os.clock() > npc.richEventUntil and not (rushOn() and workspace:GetAttribute("RushRich") == true) then   -- (리치맨 러시아워 중엔 배너 도배 방지)   -- (during the event one banner covers everyone)
			announceRE:FireAllClients({ kind = "rich", title = "RICH MAN이 왔어요!", text = "Rich Man을 잘 응대하면 엄청난 보상이 있어요!" })
		end
		if c.headless and announceRE then
			announceRE:FireAllClients({ kind = "rich", icon = "🎃", title = "헤드리스맨이 왔어요!", text = "헤드리스맨을 응대하면 호박을 받을 수 있어요!" })
		end
		walkTo(c, DOOR_IN)
		if not c.alive then return end
		menu = weighted(C.Menus, C.MenuWeights)
		side = C.SideMenus and C.SideMenus[menu] == true
		if not side then
			walkTo(c, BOWL_SPOT + Vector3.new(math.random(-12, 12) / 10, 0, 0)); face(c, Vector3.new(0, 0, 1))
			task.wait(0.6)
			if not c.alive then return end
			holdBowl(c)
			task.wait(0.4)
			local spot = pick(BAR_SPOTS) + Vector3.new(0, 0, math.random(-10, 10) / 10)
			walkTo(c, spot); face(c, Vector3.new(1, 0, 0))
			say(c, nil)
			if c.group and math.random() < 0.6 then task.delay(math.random() * 2, function() chat(c, CHAT_BAR, false) end) end
			task.wait(4 + math.random() * 3)
			if not c.alive then return end
			fillBowl(c)
		else
			-- looks at the menu board for a moment, then goes to order
			if c.group and math.random() < 0.6 then chat(c, { "난 " .. menu .. "!", menu .. " 맛있겠다", "오늘은 " .. menu }, false) end
			task.wait(1 + math.random() * 1.5)
		end
		end   -- (11/19) 튜토리얼 손님 분기 끝
		-- 2) queue at the shorter register line
		-- 가장 짧은 줄 (비어 있는 칸이 많은 줄)
		local reg = REGISTERS[1]
		for _, r in ipairs(REGISTERS) do
			if (#r.queue - #r.line) > (#reg.queue - #reg.line) then reg = r end
		end
		if c.tutReg then reg = c.tutReg end   -- (11/19) 플레이어가 서 있는 계산대로
		if c.group then
			if c.group.reg and #c.group.reg.line < #c.group.reg.queue then reg = c.group.reg else c.group.reg = reg end
		end
		-- 줄이 꽉 찼으면 바로 나가지 말고 자리 날 때까지 조금 기다림 (러시아워 40초 / 평소 15초) (11/14)
		if #reg.line >= #reg.queue then
			npc.lineWaiting += 1
			say(c, "줄 서려고 기다리는 중...", false)
			local t0 = os.clock()
			local limit = rushOn() and 40 or 15
			while c.alive and os.clock() - t0 < limit do
				task.wait(1)
				local found
				for _, r in ipairs(REGISTERS) do if #r.line < #r.queue then found = r; break end end
				if found then reg = found; break end
				if c.group and c.group.reg and #c.group.reg.line < #c.group.reg.queue then reg = c.group.reg; break end
			end
			npc.lineWaiting -= 1
			if not c.alive then return end
			if #reg.line >= #reg.queue then say(c, "줄이 너무 길어요..."); task.wait(1.5); leave(c, true); return end
			say(c, nil)
		end
		if not c.alive or c.leaving then return end
		table.insert(reg.line, c); c.queueReg = reg
		c.ticket = tickets:queue({
			npc = c, menu = menu, side = side, spice = side and 0 or math.random(0, 4), rich = c.rich, superRich = c.superRich, headless = c.headless,
			weight = math.random(30, 90) * 10, correct = true,
		})
		say(c, nil)
		-- (11/18) 포스기가 읽는 주문 정보 (말풍선·저울 표시용. 정답 확인은 서버가 함)
		pcall(function()
			c.model:SetAttribute("OrderMenu", c.ticket.menu)
			c.model:SetAttribute("OrderSpice", c.ticket.spice)
			c.model:SetAttribute("OrderWeight", c.ticket.weight)
			c.model:SetAttribute("OrderSide", c.ticket.side == true)
			c.model:SetAttribute("OrderRich", (c.superRich and 2) or (c.rich and 1) or 0)
		end)
		-- move up the line as it shortens
		local myIndex
		while c.alive and c.ticket.state == "queue" do
			local idx = table.find(reg.line, c) or #reg.line
			if idx ~= myIndex then
				myIndex = idx
				walkTo(c, reg.queue[math.min(idx, #reg.queue)]); face(c, Vector3.new(0, 0, 1))
				if idx == 1 and not c.forcedFront then   -- (줄 감시가 이미 앞으로 당겨서 주문 받게 했으면 건너뜀)
					if c.ticket.side then
						say(c, string.format("%s 하나 주세요!", c.ticket.menu), true)
					else
						say(c, string.format("%s · %s\n%dg 주문할게요!", c.ticket.menu, C.SpiceShort[c.ticket.spice], c.ticket.weight), true)
					end
					patience(c, C.PatienceOrder, "order", function() leave(c, true) end)
				end
			end
			task.wait(0.3)
		end
	end

	local function seatAfterOrder(c, t, onSeated)
		local s = takeSeat(c)
		if not s then say(c, "자리가 없네요..."); task.wait(1.5); leave(c, true); return end
		s.reservedBy = c; c.seatRec = s; s.seat:SetAttribute("Reserved", true)
		freeGroupLeftovers(c.group)
		local pp2 = s.seat:FindFirstChild("SitPrompt"); if pp2 then pp2.Enabled = false end
		say(c, nil)
		c.model:SetAttribute("TicketId", t.id)      -- ServeGuide (client) points the carrier here
		task.spawn(function()
			local function goTo(rec)
				c.approachPt = nil
				local seatPos = rec.seat.Position
				local toTable = ((rec.top.Position - seatPos) * Vector3.new(1, 0, 1)).Unit
				-- VIP 소파: 미리 계산해둔 입구로 걸어가서 틈을 따라 미끄러져 들어감
				if rec.vip then
					local sl = slotEntry(rec)
					if sl then
						local ok = walkTo(c, sl.entry) or (c.alive and not c.leaving and walkTo(c, sl.entry))
						if ok and c.alive and not c.leaving then
							c.approachPt = c.root.Position
							glideTo(c, Vector3.new(sl.front.X, c.root.Position.Y, sl.front.Z), (sl.front - sl.entry) * Vector3.new(1, 0, 1))
							return
						end
						if not c.alive or c.leaving then return end
					end
				end
				if walkTo(c, Vector3.new(seatPos.X, seatPos.Y + 1.5, seatPos.Z) - toTable * 1.5) then return end
				if not c.alive or c.leaving then return end
				-- 자리가 좁아 길찾기가 안 닿는 경우(VIP 라운지 소파 등): 근처 닿는 곳까지 걸어간 뒤 직선으로 들어감 (순간이동 방지)
				local root = c.root
				local seatY = seatPos.Y + 1.5
				-- 좌석이 바라보는 방향(테이블 쪽) 기준으로 틈을 잡음 (테이블이 비스듬히 있어도 소파열과 나란히)
				local fwd = toTable
				do local lv = rec.seat.CFrame.LookVector * Vector3.new(1, 0, 1); if lv.Magnitude > 0.5 and lv.Unit:Dot(toTable) > 0.3 then fwd = lv.Unit end end
				local gap = math.clamp((rec.top.Position - seatPos):Dot(fwd) * 0.55, 1.2, 2.4)   -- 소파 앞면과 테이블 사이 틈의 가운데
				local front = Vector3.new(seatPos.X, seatY, seatPos.Z) + fwd * gap
				-- 1) 소파열 끝(테이블과 소파 사이 틈의 입구)까지 걸어간 뒤 옆으로 미끄러져 들어감
				do
					local along = Vector3.new(-fwd.Z, 0, fwd.X)
					local rp = RaycastParams.new(); rp.FilterType = Enum.RaycastFilterType.Exclude
					local ex = { c.model }
					for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
					local cf = workspace:FindFirstChild("Customers"); if cf then table.insert(ex, cf) end
					rp.FilterDescendantsInstances = ex
					local cands = {}
					for d = 3, 9 do table.insert(cands, d); table.insert(cands, -d) end
					for _, d in ipairs(cands) do
						local entry = front + along * d
						local clear = true
						for _, h in ipairs({ 0.3, 2.2 }) do
							local o = entry + Vector3.new(0, h, 0)
							if workspace:Raycast(o, (front + Vector3.new(0, h, 0)) - o, rp) then clear = false; break end
						end
						if clear then
							local path = PFS:CreatePath(AGENT)
							local ok = pcall(function() path:ComputeAsync(root.Position, entry) end)
							local wps = ok and path.Status == Enum.PathStatus.Success and path:GetWaypoints()
							if wps and #wps > 0 and ((wps[#wps].Position - entry) * Vector3.new(1, 0, 1)).Magnitude < 2 then
								if walkTo(c, entry) and c.alive and not c.leaving then
									c.approachPt = root.Position
									glideTo(c, Vector3.new(front.X, root.Position.Y, front.Z), (front - entry) * Vector3.new(1, 0, 1))
								end
								return
							end
						end
						if not c.alive then return end
					end
				end
				-- 2) 그래도 안 되면 주변에서 닿는 가장 가까운 곳까지
				for _, r in ipairs({ 3, 4.5, 6, 7.5 }) do
					local found
					for k = 0, 11 do
						local a = k / 12 * math.pi * 2
						local p = Vector3.new(seatPos.X + math.cos(a) * r, seatPos.Y + 1.5, seatPos.Z + math.sin(a) * r)
						local path = PFS:CreatePath(AGENT)
						local ok = pcall(function() path:ComputeAsync(root.Position, p) end)
						if ok and path.Status == Enum.PathStatus.Success then found = p; break end
					end
					if found then
						c.approachPt = found   -- 나갈 때 여기로 되돌아 나옴
						if walkTo(c, found) and c.alive then
							stepTo(c, Vector3.new(seatPos.X, seatPos.Y + 1.5, seatPos.Z) + toTable * 0.8, 4)
						end
						return
					end
					if not c.alive then return end
				end
			end
			goTo(s)
			if not c.alive or c.leaving then return end
			-- somebody (a player) is already in my chair: find another one instead of storming out
			local tries = 0
			while s.seat.Occupant and s.seat.Occupant ~= c.hum and tries < 3 do
				tries += 1
				say(c, "어, 누가 앉아있네...", false)
				releaseSeat(c)
				local ns = takeSeat(c)
				if not ns then break end
				ns.reservedBy = c; c.seatRec = ns; ns.seat:SetAttribute("Reserved", true)
				local pp3 = ns.seat:FindFirstChild("SitPrompt"); if pp3 then pp3.Enabled = false end
				s = ns
				task.wait(0.8)
				say(c, nil)
				goTo(s)
				if not c.alive or c.leaving then return end
			end
			if s.seat.Occupant and s.seat.Occupant ~= c.hum or not c.seatRec then
				say(c, "앉을 데가 없네요...", false); task.wait(1.5); leave(c, true); return
			end
			smoothSit(c, s)
			if not c.alive or c.leaving or c.seatRec ~= s then return end
			s.seat:Sit(c.hum)
			if c.superRich then say(c, pick({ "VIP석은 역시 편하군", "오늘 팀은 두뚩하게 줌시", "여기 음식이 그렇게 맛있다며?" }), false); task.delay(2.5, function() if c.alive and c.waitStage == "food" then say(c, "", true) end end) end
			c.foodWaitStart = patience(c, C.PatienceFood + (s.upstairs and 40 or 0) + (c.superRich and 40 or 0), "food", function() leave(c, true) end)
			say(c, "", true)
			if c.group then
				task.spawn(function()
					while c.alive and c.waitStage == "food" do
						task.wait(7 + math.random() * 9)
						if c.waitStage == "food" and math.random() < 0.55 then chat(c, CHAT_WAIT, true) end
					end
				end)
			end
			onSeated()
		end)
	end

	npc.active = customers
	npc.count = countActive
	npc.run = runCustomer
	npc.seatAfterOrder = seatAfterOrder
	npc.leave = leave
	npc.despawn = despawn
	npc.patience = patience
	npc.chat = chat
	npc.walkTo = walkTo
	return npc
end

return Customers
