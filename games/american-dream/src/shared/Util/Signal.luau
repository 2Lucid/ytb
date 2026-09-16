--!strict
-- Signal minimal et typé. Pas de dépendance Roblox : utilisable dans les tests Lune.
-- Les connexions sont appelées dans l'ordre d'inscription, sur un thread séparé via task.spawn
-- si disponible (Roblox), sinon en direct (Lune).

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Fire: (self: Signal<T...>, T...) -> (),
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

type Handler = (...any) -> ()
type Entry = { handler: Handler, once: boolean, connected: boolean }
type Impl = { _entries: { Entry } }

local Signal = {}
Signal.__index = Signal

local function spawnHandler(handler: Handler, ...: any)
	if task ~= nil and task.spawn ~= nil then
		task.spawn(handler, ...)
	else
		handler(...)
	end
end

function Signal.new<T...>(): Signal<T...>
	local self = setmetatable({ _entries = {} :: { Entry } }, Signal)
	return (self :: any) :: Signal<T...>
end

function Signal.Connect(self: Impl, handler: Handler): Connection
	local entry: Entry = { handler = handler, once = false, connected = true }
	table.insert(self._entries, entry)
	local connection = {
		Connected = true,
		Disconnect = function(conn: Connection)
			if not entry.connected then
				return
			end
			entry.connected = false
			conn.Connected = false
			local index = table.find(self._entries, entry)
			if index then
				table.remove(self._entries, index)
			end
		end,
	}
	return connection
end

function Signal.Once(self: Impl, handler: Handler): Connection
	local connection: Connection
	connection = Signal.Connect(self, function(...)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal.Fire(self: Impl, ...: any)
	-- copie pour tolérer les déconnexions pendant l'itération
	local snapshot = table.clone(self._entries)
	for _, entry in snapshot do
		if entry.connected then
			spawnHandler(entry.handler, ...)
		end
	end
end

function Signal.Wait(self: Impl): ...any
	local thread = coroutine.running()
	Signal.Once(self, function(...)
		if task ~= nil and task.spawn ~= nil then
			task.spawn(thread, ...)
		else
			coroutine.resume(thread, ...)
		end
	end)
	return coroutine.yield()
end

function Signal.DisconnectAll(self: Impl)
	for _, entry in self._entries do
		entry.connected = false
	end
	table.clear(self._entries)
end

return Signal
