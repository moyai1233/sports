local Kitchen = {}
Kitchen.__index = Kitchen

-- 패스대(계산대 쪽 진열대) 5칸 (PassSill x -14.2 ~ 3.8)
local PASS_SLOTS = { Vector3.new(-12, 5.72, 36), Vector3.new(-8.6, 5.72, 36), Vector3.new(-5.2, 5.72, 36), Vector3.new(-1.8, 5.72, 36), Vector3.new(1.6, 5.72, 36) }

function Kitchen.new(fxFolder, tickets)
	return setmetatable({
		ranges = {},
		passSlots = PASS_SLOTS,
		occupied = {},
		folder = fxFolder,
		tickets = tickets,
	}, Kitchen)
end

function Kitchen:setupRanges(kitchen)
	local fxFolder = self.folder
	for _, m in ipairs(kitchen:GetChildren()) do
		if m.Name == "Range" and m:IsA("Model") then
			local cf, size = m:GetBoundingBox()
			-- works for any facing: "front" is the side the cook stands on, the pot goes on the left burner
			local look, right = cf.LookVector, cf.RightVector
			local top = Vector3.new(cf.X, cf.Y + size.Y / 2, cf.Z) + look * 0.3
			-- front-left burner of the range model (measured on the mesh: 1.45 left of centre, 0.9 toward the cook)
			local seatPos = Vector3.new(cf.X, cf.Y + size.Y / 2, cf.Z) - right * 1.45 + look * 0.9 + Vector3.new(0, 0.02, 0)
			local anchor = Instance.new("Part")
			anchor.Name = "RangeAnchor"; anchor.Anchored = true; anchor.CanCollide = false; anchor.CanQuery = false; anchor.CanTouch = false
			anchor.Transparency = 1; anchor.Size = Vector3.new(1, 1, 1); anchor.Position = top + Vector3.new(0, 1, 0) + look * 0.8; anchor.Parent = fxFolder
			local pp = Instance.new("ProximityPrompt")
			pp.Name = "Cook"; pp.ActionText = "조리하기"; pp.ObjectText = "화구"
			pp.KeyboardKeyCode = Enum.KeyCode.E; pp.HoldDuration = 0.5; pp.MaxActivationDistance = 7; pp.RequiresLineOfSight = false
			pp.Parent = anchor
			-- (11/19 퀄업) 화구 머리 위 상태 표시: 금테 + 빨간 판(스터드·광택) + 🔥 배지 + 반짝이는 게이지
			local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(230, 66); bb.StudsOffset = Vector3.new(0, 2.8, 0); bb.LightInfluence = 0; bb.MaxDistance = 40; bb.Enabled = false; bb.Parent = anchor
			local function rc(o, r) local c = Instance.new("UICorner"); c.CornerRadius = r; c.Parent = o end
			local function gr(o, a1, a2) local g = Instance.new("UIGradient"); g.Rotation = 90; g.Color = ColorSequence.new(a1, a2); g.Parent = o; return g end
			local rim = Instance.new("Frame"); rim.Name = "Rim"; rim.AnchorPoint = Vector2.new(1, 0.5); rim.Position = UDim2.fromScale(1, 0.5); rim.Size = UDim2.fromScale(0.86, 0.9)
			rim.BackgroundColor3 = Color3.new(1, 1, 1); rim.Parent = bb; rc(rim, UDim.new(0.3, 0)); gr(rim, Color3.fromRGB(255, 236, 150), Color3.fromRGB(205, 140, 36))
			do local s1 = Instance.new("UIStroke"); s1.Color = Color3.fromRGB(60, 14, 10); s1.Thickness = 2; s1.Parent = rim end
			local bgf = Instance.new("Frame"); bgf.Name = "Inner"; bgf.AnchorPoint = Vector2.new(0.5, 0.5); bgf.Position = UDim2.fromScale(0.5, 0.5); bgf.Size = UDim2.new(1, -6, 1, -6)
			bgf.BackgroundColor3 = Color3.new(1, 1, 1); bgf.Parent = rim; rc(bgf, UDim.new(0.3, 0)); gr(bgf, Color3.fromRGB(255, 138, 118), Color3.fromRGB(226, 72, 62))
			do local stud = Instance.new("ImageLabel"); stud.BackgroundTransparency = 1; stud.Size = UDim2.fromScale(1, 1); stud.Image = "rbxassetid://79018637165895"; stud.ScaleType = Enum.ScaleType.Tile
				stud.TileSize = UDim2.fromOffset(60, 60); stud.ImageTransparency = 0.55; stud.Parent = bgf; rc(stud, UDim.new(0.3, 0)); gr(stud, Color3.fromRGB(255, 138, 118), Color3.fromRGB(226, 72, 62))
				local gl = Instance.new("Frame"); gl.BackgroundColor3 = Color3.new(1, 1, 1); gl.Position = UDim2.fromScale(0.03, 0.04); gl.Size = UDim2.fromScale(0.94, 0.34); gl.Parent = bgf; rc(gl, UDim.new(0.5, 0))
				local t0 = Instance.new("UIGradient"); t0.Rotation = 90; t0.Transparency = NumberSequence.new(0.7, 1); t0.Parent = gl end
			-- 게이지 (어두운 홈 + 주황→노랑 채움 + 윗광)
			local track = Instance.new("Frame"); track.Name = "Track"; track.AnchorPoint = Vector2.new(0.5, 1); track.Position = UDim2.new(0.5, 17, 1, -6); track.Size = UDim2.new(1, -52, 0.3, 0)
			track.BackgroundColor3 = Color3.fromRGB(70, 14, 12); track.ZIndex = 2; track.Parent = bgf; rc(track, UDim.new(0.5, 0))
			local fill = Instance.new("Frame"); fill.Size = UDim2.fromScale(0, 1); fill.BackgroundColor3 = Color3.new(1, 1, 1); fill.BorderSizePixel = 0; fill.ZIndex = 3; fill.Parent = track; rc(fill, UDim.new(0.5, 0))
			do local fg = Instance.new("UIGradient"); fg.Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 225, 90)); fg.Parent = fill
				local fs = Instance.new("Frame"); fs.BackgroundColor3 = Color3.new(1, 1, 1); fs.BackgroundTransparency = 0.55; fs.Position = UDim2.fromScale(0, 0.12); fs.Size = UDim2.fromScale(1, 0.32); fs.ZIndex = 4; fs.Parent = fill; rc(fs, UDim.new(0.5, 0)) end
			local txt = Instance.new("TextLabel"); txt.Name = "Status"; txt.BackgroundTransparency = 1; txt.Position = UDim2.new(0, 36, 0, 3); txt.Size = UDim2.new(1, -46, 0.54, 0)
			txt.Font = Enum.Font.FredokaOne; txt.TextScaled = true; txt.TextColor3 = Color3.new(1, 1, 1); txt.Text = ""; txt.ZIndex = 3; txt.Parent = bgf
			do local ts = Instance.new("UIStroke"); ts.Thickness = 2; ts.Color = Color3.fromRGB(90, 14, 10); ts.Parent = txt end
			-- 🔥 동그란 배지 (왼쪽)
			local badge = Instance.new("Frame"); badge.Name = "Badge"; badge.AnchorPoint = Vector2.new(0, 0.5); badge.Position = UDim2.fromScale(0, 0.5); badge.Size = UDim2.fromScale(0.27, 0.95)
			badge.BackgroundColor3 = Color3.new(1, 1, 1); badge.ZIndex = 5; badge.Parent = bb; rc(badge, UDim.new(1, 0)); gr(badge, Color3.fromRGB(255, 240, 170), Color3.fromRGB(240, 160, 40))
			do local ar = Instance.new("UIAspectRatioConstraint"); ar.AspectRatio = 1; ar.Parent = badge
				local bs = Instance.new("UIStroke"); bs.Thickness = 2; bs.Color = Color3.fromRGB(60, 14, 10); bs.Parent = badge
				local ic = Instance.new("TextLabel"); ic.BackgroundTransparency = 1; ic.Size = UDim2.fromScale(0.8, 0.8); ic.AnchorPoint = Vector2.new(0.5, 0.5); ic.Position = UDim2.fromScale(0.5, 0.52)
				ic.Text = "🔥"; ic.TextScaled = true; ic.ZIndex = 6; ic.Parent = badge end
			table.insert(self.ranges, { model = m, top = top, seatPos = seatPos, anchor = anchor, prompt = pp, bb = bb, fill = fill, txt = txt, state = "idle" })
		end
	end
end

function Kitchen:freePassSlot()
	for slot in ipairs(self.passSlots) do
		if not self.occupied[slot] then return slot end
	end
	return nil
end

function Kitchen:placeOnPass(t, buildDish, bagify)
	local slot = self:freePassSlot()
	if not slot then return nil end
	self.occupied[slot] = t
	local bowl = buildDish(t)
	if t.takeout then pcall(bagify, bowl) end
	bowl:PivotTo(CFrame.new(self.passSlots[slot]))
	bowl.PrimaryPart.Anchored = true
	bowl.Parent = self.folder
	t.bowl = bowl
	t.slot = slot
	self.tickets:setState(t, "ready")
	return bowl
end

function Kitchen:returnBowl(t, slot, placeOnTable)
	t.bowl = placeOnTable(t.bowl, CFrame.new(self.passSlots[slot]))
	self.occupied[slot] = t
	t.slot = slot
	t.carrier = nil
	self.tickets:setState(t, "ready")
end

function Kitchen:release(t)
	if t.slot then
		self:clearPassSlot(t.slot)
		t.slot = nil
	end
end

function Kitchen:clearPassSlot(slot)
	self.occupied[slot] = nil
end

function Kitchen:beginRange(r, t, plr)
	self.tickets:setState(t, "cooking")
	r.state = "cooking"
	r.ticket = t
	r.cook = plr
end

function Kitchen.setFlame(r, on)
	if not r.pot then return end
	local fl = r.pot:FindFirstChild("Flame")
	if fl then
		for _, p in ipairs(fl:GetDescendants()) do
			if p:IsA("ParticleEmitter") then p.Enabled = on elseif p:IsA("BasePart") then p.Transparency = 1 end
		end
	end
	local l = r.pot.PrimaryPart:FindFirstChild("FlameLight"); if l then l.Brightness = on and 1.4 or 0 end
end

function Kitchen.finishRange(r, cookRE)
	if r.pot then
		local body = r.pot.PrimaryPart
		local boil = body and body:FindFirstChild("Boil"); if boil then boil:Stop() end
		Kitchen.setFlame(r, false)
		r.pot:Destroy(); r.pot = nil
	end
	r.pieces = nil
	local ia = r.ia; r.ia = nil
	if ia and not ia.resulted and not ia.auto and ia.plr.Parent then cookRE:FireClient(ia.plr, "cancel", {}) end
	r.state = "idle"; r.ticket = nil; r.spiceUser = nil
	r.bb.Enabled = false
	r.prompt.ActionText = "조리하기"; r.prompt.ObjectText = "화구"; r.prompt.Enabled = true
end

return Kitchen
