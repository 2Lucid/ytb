--!strict
-- Journal de progression du lot, sauvegardé dans les réglages du plugin : une génération interrompue
-- (plantage de Studio, fermeture, coupure réseau) reprend exactement où elle s'était arrêtée.

export type Record = { status: string, assetId: number, reason: string, triangles: number, textured: boolean, at: number }

export type Store = {
	get: (self: Store, id: string) -> Record?,
	set: (self: Store, id: string, record: Record) -> (),
	clear: (self: Store) -> (),
	all: (self: Store) -> { [string]: Record },
	counts: (self: Store) -> { done: number, failed: number },
}

local State = {}
State.__index = State

local KEY = "AssetForge_Progress_v1"

-- Le backend est `plugin` en Studio ; un faux objet suffit dans les tests.
export type Backend = Plugin | { GetSetting: (self: any, key: string) -> any, SetSetting: (self: any, key: string, value: any) -> () }

function State.new(rawBackend: Backend): Store
	local backend = rawBackend :: any
	local raw = backend:GetSetting(KEY)
	local records: { [string]: Record } = {}
	if type(raw) == "table" then
		for id, record in raw :: { [string]: any } do
			if type(id) == "string" and type(record) == "table" then
				records[id] = {
					status = tostring(record.status or "pending"),
					assetId = tonumber(record.assetId) or 0,
					reason = tostring(record.reason or ""),
					triangles = tonumber(record.triangles) or 0,
					textured = record.textured == true,
					at = tonumber(record.at) or 0,
				}
			end
		end
	end
	local self = setmetatable({ _backend = backend, _records = records }, State)
	return (self :: any) :: Store
end

function State.get(self: any, id: string): Record?
	local record: Record? = self._records[id]
	return record
end

function State.set(self: any, id: string, record: Record)
	self._records[id] = record
	self._backend:SetSetting(KEY, self._records)
end

function State.clear(self: any)
	self._records = {}
	self._backend:SetSetting(KEY, nil)
end

function State.all(self: any): { [string]: Record }
	return self._records
end

function State.counts(self: any): { done: number, failed: number }
	local done, failed = 0, 0
	for _, record in self._records do
		if record.status == "done" then
			done += 1
		elseif record.status == "failed" then
			failed += 1
		end
	end
	return { done = done, failed = failed }
end

return State
