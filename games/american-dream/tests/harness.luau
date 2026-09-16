-- Mini framework de test : describe / it / expect, résultats agrégés par run.luau.
local Harness = {}

local results = { passed = 0, failed = 0, failures = {} }
local currentSuite = ""

function Harness.describe(name, body)
	local previous = currentSuite
	currentSuite = previous == "" and name or (previous .. " > " .. name)
	local ok, err = pcall(body)
	if not ok then
		results.failed += 1
		table.insert(results.failures, currentSuite .. " (suite) : " .. tostring(err))
	end
	currentSuite = previous
end

function Harness.it(name, body)
	local ok, err = pcall(body)
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, currentSuite .. " > " .. name .. " : " .. tostring(err))
	end
end

local function fmt(v)
	if type(v) == "table" then
		local parts = {}
		for k, val in v do
			table.insert(parts, tostring(k) .. "=" .. tostring(val))
			if #parts > 8 then
				table.insert(parts, "...")
				break
			end
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(v)
end

function Harness.expect(value)
	local e = {}
	function e.toBe(expected)
		if value ~= expected then
			error(string.format("attendu %s, obtenu %s", fmt(expected), fmt(value)), 2)
		end
	end
	function e.toEqual(expected)
		local function deepEqual(a, b)
			if type(a) ~= type(b) then
				return false
			end
			if type(a) ~= "table" then
				return a == b
			end
			for k, v in a do
				if not deepEqual(v, b[k]) then
					return false
				end
			end
			for k in b do
				if a[k] == nil then
					return false
				end
			end
			return true
		end
		if not deepEqual(value, expected) then
			error(string.format("attendu %s, obtenu %s", fmt(expected), fmt(value)), 2)
		end
	end
	function e.toBeTruthy()
		if not value then
			error("attendu une valeur vraie, obtenu " .. fmt(value), 2)
		end
	end
	function e.toBeFalsy()
		if value then
			error("attendu une valeur fausse, obtenu " .. fmt(value), 2)
		end
	end
	function e.toBeNil()
		if value ~= nil then
			error("attendu nil, obtenu " .. fmt(value), 2)
		end
	end
	function e.toBeCloseTo(expected, tolerance)
		tolerance = tolerance or 1e-6
		if type(value) ~= "number" or math.abs(value - expected) > tolerance then
			error(string.format("attendu %s ± %s, obtenu %s", tostring(expected), tostring(tolerance), fmt(value)), 2)
		end
	end
	function e.toBeGreaterThan(expected)
		if not (type(value) == "number" and value > expected) then
			error(string.format("attendu > %s, obtenu %s", tostring(expected), fmt(value)), 2)
		end
	end
	function e.toBeGreaterThanOrEqual(expected)
		if not (type(value) == "number" and value >= expected) then
			error(string.format("attendu >= %s, obtenu %s", tostring(expected), fmt(value)), 2)
		end
	end
	function e.toBeLessThan(expected)
		if not (type(value) == "number" and value < expected) then
			error(string.format("attendu < %s, obtenu %s", tostring(expected), fmt(value)), 2)
		end
	end
	function e.toBeLessThanOrEqual(expected)
		if not (type(value) == "number" and value <= expected) then
			error(string.format("attendu <= %s, obtenu %s", tostring(expected), fmt(value)), 2)
		end
	end
	function e.toBeBetween(low, high)
		if not (type(value) == "number" and value >= low and value <= high) then
			error(string.format("attendu dans [%s, %s], obtenu %s", tostring(low), tostring(high), fmt(value)), 2)
		end
	end
	function e.toThrow()
		if type(value) ~= "function" then
			error("toThrow attend une fonction", 2)
		end
		local ok = pcall(value)
		if ok then
			error("attendu une erreur, aucune levée", 2)
		end
	end
	return e
end

function Harness.results()
	return results
end

return Harness
