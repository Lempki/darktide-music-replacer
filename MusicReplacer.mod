return {
	run = function ()
		fassert(rawget(_G, "new_mod"), "`MusicReplacer` encountered an error loading the Darktide Mod Framework.")

		new_mod("MusicReplacer", {
			mod_script       = "MusicReplacer/scripts/mods/MusicReplacer/MusicReplacer",
			mod_data         = "MusicReplacer/scripts/mods/MusicReplacer/MusicReplacer_data",
			mod_localization = "MusicReplacer/scripts/mods/MusicReplacer/MusicReplacer_localization",
		})
	end,
	packages = {},
}
