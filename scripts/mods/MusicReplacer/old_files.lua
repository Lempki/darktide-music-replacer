-- Moves the mod's files that belong to the songs from the folder the mod kept them in before, %APPDATA%, into the audio folder.
-- There they travel with the songs they describe, and their path does not depend on the Windows username.
-- A file already in the audio folder stays as it is, and the old one is left alone, so nothing is ever overwritten.

local OldFiles = {}

local _io = Mods and Mods.lua and Mods.lua.io
local _os = Mods and Mods.lua and Mods.lua.os

local function read(path)
	local file = _io.open(path, "rb")
	if not file then
		return nil
	end
	local text = file:read("*a")
	file:close()
	return text
end

local function write(path, text)
	local file = _io.open(path, "wb")
	if not file then
		return false
	end
	local ok = file:write(text)
	file:close()
	return ok ~= nil and ok ~= false
end

-- Moves each file of `names` from `from_folder` into `to_folder`, unless `to_folder` already has one by that name.
-- The file is copied and then deleted, since the two folders can be on different drives, which a rename cannot cross.
-- `log` receives a line for each file moved, or kept because it could not be.
function OldFiles.move(names, from_folder, to_folder, log)
	if not (_io and _os and from_folder and to_folder) then
		return
	end

	for _, name in ipairs(names) do
		local from = from_folder .. "/" .. name
		local to = to_folder .. "/" .. name
		local text = read(from)
		if text and not read(to) then
			if write(to, text) then
				_os.remove(from)
				log(string.format("[files] moved %s from %%APPDATA%% into the audio folder", name))
			else
				log(string.format("[files] could not move %s into the audio folder, so it stays in %%APPDATA%% and is not used", name))
			end
		end
	end
end

return OldFiles
