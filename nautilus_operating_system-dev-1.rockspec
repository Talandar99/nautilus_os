package = "nautilus_operating_system"
version = "dev-1"
source = {
   url = "git+ssh://git@github.com/Talandar99/nautilus_operating_system.git"
}
description = {
   summary = "### Requirements- Internet connection- Linux based OS- gcc - docker",
   detailed = [[
### Requirements
- Internet connection
- Linux based OS
- gcc 
- docker]],
   homepage = "*** please enter a project homepage ***",
   license = "*** please specify a license ***"
}
build = {
   type = "builtin",
   modules = {
      dependancies = "src/dependancies.lua",
      filesystem = "src/filesystem.lua",
      lua = "src/lua.lua"
   }
}
