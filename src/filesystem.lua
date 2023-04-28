function createDirectories(node, path)
	path = path or ""
	for k, v in pairs(node) do
		local new_path = path .. "/" .. k
		os.execute("mkdir " .. new_path)
		if type(v) == "table" then
			createDirectories(v, new_path)
		end
	end
end
