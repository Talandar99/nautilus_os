function checkForDependencies(dependencies)
	for i = 1, #dependencies do
		local handle = io.popen("which " .. dependencies[i])
		local result = handle:read("*a")
		handle:close()

		if string.len(result) == 0 then
			print()
			print(dependencies[i] .. " is missing.")
			os.exit(1)
		else
			print(dependencies[i] .. " is installed.")
		end
	end
end
