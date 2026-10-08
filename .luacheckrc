-- luacheck configuration. Run `luacheck .` from the repo root.

std = "luajit"

-- Engine and DMF globals the mod reads but never assigns.
read_globals = {
	"Application",
	"CLASS",
	"Managers",
	"Mods",
	"Wwise",
	"get_mod",
}

-- Hook handlers and engine callbacks must accept arguments they do not use.
unused_args = false

-- Comment lines follow the 140 character limit. Code and string lines have none.
max_code_line_length = false
max_string_line_length = false
max_comment_line_length = 140

local spec_globals = { "assert_deep_equal", "assert_equal", "describe", "it" }

files["tests/run.lua"] = { globals = spec_globals }
files["tests/spec"] = { read_globals = spec_globals }

exclude_files = { "dist" }
