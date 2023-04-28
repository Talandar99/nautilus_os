#!/usr/bin/lua
require("lua.dependancies")
require("lua.filesystem")

print("---------------------------------------")
print("Checking dependencies")
print("---------------------------------------")
local dependencies = {
	"docker",
	"make",
	"curl",
	"tar",
	"gcc",
}
checkForDependencies(dependencies)

print("---------------------------------------")
print("Creating main directory")
print("and root file system")
print("---------------------------------------")
local filesystem = {
	"nautilus" == {
		"rootfs" == {
			"dev",
			"proc",
			"sys",
			"bin",
			"tmp",
			"root",
			"nix", -- VIP
			"etc" == {
				"nix",
				"ssl" == {
					"certs",
				},
			},
		},
	},
}
createDirectories(filesystem)

print("---------------------------------------")
print("Getting kernel")
print("---------------------------------------")

--os.execute("wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.2.tar.xz -P nautilus")
--os.execute("tar -C nautilus -xf nautilus/linux-6.2.tar.xz")
--os.execute("rm nautilus/linux-6.2.tar.xz")

print("---------------------------------------")
print("creating configuration")
print("---------------------------------------")

--os.execute("make -C nautilus/linux-6.2 defconfig")

print("---------------------------------------")
print("compiling kernel")
print("---------------------------------------")

--os.execute("make -C nautilus/linux-6.2 -j" .. tostring(os.execute("nproc")))

print("---------------------------------------")
print("installing kernel")
print("---------------------------------------")

--os.execute("mkdir nautilus/kernel-bin")
--os.execute("make -C nautilus/linux-6.2 INSTALL_PATH=/path/to/nautilus/kernel-bin install")
