local Tickets = {}
Tickets.__index = Tickets

function Tickets.new()
	return setmetatable({ nextId = 1, byId = {} }, Tickets)
end

-- 줄을 서는 동안에는 주문 번호가 없고, POS 접수 때 같은 티켓을 등록한다.
function Tickets:queue(ticket)
	ticket.id = 0
	ticket.state = "queue"
	return ticket
end

function Tickets:register(ticket, state, testId)
	local id = testId or self.nextId
	if not testId then self.nextId += 1 end
	ticket.id = id
	ticket.state = state
	self.byId[id] = ticket
	return ticket
end

function Tickets:get(id)
	return self.byId[id]
end

function Tickets:entries()
	return pairs(self.byId)
end

function Tickets:firstOrdered()
	local first
	for _, ticket in self:entries() do
		if ticket.state == "ordered" and (not first or ticket.id < first.id) then
			first = ticket
		end
	end
	return first
end

function Tickets:setState(ticket, state)
	ticket.state = state
end

-- 취소된 주문의 그릇·화구 정리는 서버의 기존 정리 루프에서 처리한다.
function Tickets:cancel(ticket)
	ticket.cancelled = true
end

function Tickets:remove(id)
	self.byId[id] = nil
end

return Tickets
