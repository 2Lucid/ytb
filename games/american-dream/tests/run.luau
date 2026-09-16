-- Lance tous les tests/*.spec.luau. Usage : lune run tests/run.luau [filtre]
local fs = require("@lune/fs")
local process = require("@lune/process")
local harness = require("./harness")
local loader = require("./loader")

loader.setup(".")

local filter = process.args[1]
local specs = {}
for _, entry in fs.readDir("tests") do
	if entry:match("%.spec%.luau$") and (filter == nil or entry:find(filter, 1, true)) then
		table.insert(specs, entry)
	end
end
table.sort(specs)

local started = os.clock()
for _, spec in specs do
	local ok, err = pcall(function()
		local fn = require("./" .. spec:gsub("%.luau$", ""))
		if type(fn) == "function" then
			fn(harness, loader)
		end
	end)
	if not ok then
		local results = harness.results()
		results.failed += 1
		table.insert(results.failures, spec .. " (chargement) : " .. tostring(err))
	end
end

local results = harness.results()
print(string.format("\n%d spec(s), %d réussi(s), %d échec(s) en %.2fs", #specs, results.passed, results.failed, os.clock() - started))
for _, failure in results.failures do
	print("  ÉCHEC : " .. failure)
end
if results.failed > 0 then
	process.exit(1)
end
