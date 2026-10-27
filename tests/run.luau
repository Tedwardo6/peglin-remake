--!nocheck
-- Headless test runner. From the repo root:
--   lune run tests/run.luau            (all suites)
--   lune run tests/run.luau sim        (one suite)
local fs = require("@lune/fs")
local process = require("@lune/process")
local Loader = require("./loader")

Loader.init(".")

local T = {}
T.passed = 0
T.failed = 0
T.current = ""
T.notes = {}

function T.check(cond: any, msg: string)
	if cond then
		T.passed += 1
	else
		T.failed += 1
		print(`  FAIL [{T.current}] {msg}`)
	end
end

function T.eq(a: any, b: any, msg: string)
	if a == b then
		T.passed += 1
	else
		T.failed += 1
		print(`  FAIL [{T.current}] {msg}: expected {tostring(b)}, got {tostring(a)}`)
	end
end

function T.note(msg: string)
	table.insert(T.notes, msg)
	print(`  note: {msg}`)
end

T.Loader = Loader

local only = process.args[1]
local files = {}
for _, name in fs.readDir("tests/suites") do
	if string.sub(name, -5) == ".luau" then
		table.insert(files, name)
	end
end
table.sort(files)

for _, name in files do
	local suite = string.sub(name, 1, -6)
	if only == nil or only == suite then
		print(`suite {suite}`)
		local mod = require(`./suites/{suite}`)
		for _, case in mod do
			T.current = `{suite}: {case.name}`
			local ok, err = pcall(case.run, T)
			if not ok then
				T.failed += 1
				print(`  ERROR [{T.current}] {err}`)
			end
		end
	end
end

print(`\n{T.passed} checks passed, {T.failed} failed`)
if T.failed > 0 then
	process.exit(1)
end
