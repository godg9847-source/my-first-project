-- Builds a fake instance tree from SRC_ROOT so `require(script.Parent.X)` works.
local cache = {}
local NodeMT = {}

local function newNode(name, parent)
	return setmetatable({ __name = name, __parent = parent, __children = {} }, NodeMT)
end

NodeMT.__index = function(t, k)
	if k == "Parent" then
		return rawget(t, "__parent")
	elseif k == "Name" then
		return rawget(t, "__name")
	elseif k == "FindFirstChild" then
		return function(self, n)
			return rawget(self, "__children")[n]
		end
	elseif k == "WaitForChild" then
		return function(self, n)
			local c = rawget(self, "__children")[n]
			if not c then
				error("WaitForChild: " .. rawget(self, "__name") .. " has no child " .. tostring(n), 2)
			end
			return c
		end
	elseif k == "GetChildren" then
		return function(self)
			local out = {}
			for _, c in rawget(self, "__children") do
				table.insert(out, c)
			end
			table.sort(out, function(a, b)
				return rawget(a, "__name") < rawget(b, "__name")
			end)
			return out
		end
	elseif k == "IsA" then
		return function(self, cls)
			if cls == "ModuleScript" then
				return rawget(self, "__file") ~= nil
			end
			return cls == "Folder" or cls == "Instance"
		end
	end
	local c = rawget(t, "__children")[k]
	if c == nil then
		error("fake instance '" .. rawget(t, "__name") .. "' has no child '" .. tostring(k) .. "'", 2)
	end
	return c
end

local function baseName(n)
	for _, suffix in { "%.server%.luau$", "%.client%.luau$", "%.luau$", "%.lua$" } do
		local b, count = string.gsub(n, suffix, "")
		if count > 0 then
			return b
		end
	end
	return nil
end

local function build(path, name, parent)
	local node = newNode(name, parent)
	for _, e in __listdir(path) do
		if e.dir then
			node.__children[e.name] = build(path .. "/" .. e.name, e.name, node)
		elseif e.name == "init.luau" or e.name == "init.lua" then
			rawset(node, "__file", path .. "/" .. e.name)
		else
			local b = baseName(e.name)
			if b then
				local child = newNode(b, node)
				rawset(child, "__file", path .. "/" .. e.name)
				node.__children[b] = child
			end
		end
	end
	return node
end

local function req(node)
	if type(node) ~= "table" then
		error("require expects a fake instance, got " .. type(node), 2)
	end
	local file = rawget(node, "__file")
	if not file then
		error("require: '" .. tostring(rawget(node, "__name")) .. "' is not a module", 2)
	end
	if cache[file] ~= nil then
		return cache[file]
	end
	local env = setmetatable({ script = node, require = req }, { __index = _G })
	local fn = __load(file, env)
	local result = fn()
	cache[file] = result
	return result
end

_G.require = req
_G.Root = build(SRC_ROOT, "Root", nil)
