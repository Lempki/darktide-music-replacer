-- Shared plumbing for calling Windows APIs through LuaJIT's ffi: GUIDs, COM vtable calls, COM setup, and UTF-16 strings.
-- The mod loader exposes ffi as Mods.lua.ffi. Outside the game, plain LuaJIT's own ffi is used, so these modules can be tried standalone.

local NativeFfi = {}

local ffi = (Mods and Mods.lua and Mods.lua.ffi) or (not Mods and require("ffi")) or nil
NativeFfi.ffi = ffi

-- Every mod shares one LuaJIT state, and ffi.cdef rejects redefining a name that another mod may also declare, as DMF does.
-- So every name is prefixed, and the functions are redirected to their real symbols.
-- A mod reload finds the names already defined and skips the block.
local CDEF = [[
typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } MusicReplacer_GUID;

typedef struct { void **lpVtbl; } MusicReplacer_ComObject;

int32_t MusicReplacer_CoGetApartmentType(int32_t *type, int32_t *qualifier) __asm__("CoGetApartmentType");
int32_t MusicReplacer_CoIncrementMTAUsage(void **cookie) __asm__("CoIncrementMTAUsage");
int32_t MusicReplacer_CoCreateInstance(const MusicReplacer_GUID *clsid, void *outer, uint32_t cls_context,
	const MusicReplacer_GUID *iid, void **object) __asm__("CoCreateInstance");
void MusicReplacer_CoTaskMemFree(void *memory) __asm__("CoTaskMemFree");

int32_t MusicReplacer_MultiByteToWideChar(uint32_t code_page, uint32_t flags, const char *source, int32_t source_length,
	uint16_t *target, int32_t target_length) __asm__("MultiByteToWideChar");
void *MusicReplacer_OpenProcess(uint32_t access, int32_t inherit, uint32_t pid) __asm__("OpenProcess");
int32_t MusicReplacer_GetExitCodeProcess(void *process, uint32_t *exit_code) __asm__("GetExitCodeProcess");
int32_t MusicReplacer_CloseHandle(void *handle) __asm__("CloseHandle");
]]

local CO_E_NOTINITIALIZED = -2147221008 -- 0x800401F0
local CP_UTF8 = 65001

local ole32 = nil
local kernel32 = nil
local method_types = {}
local com_ready = false
local load_error = nil

-- Loads the declarations and libraries once. Returns false, with NativeFfi.error() saying why, when anything is missing.
function NativeFfi.load()
	if ole32 then
		return true
	end

	if load_error then
		return false
	end

	if not ffi or ffi.os ~= "Windows" then
		load_error = "ffi is not available"
		return false
	end

	local ok, err = pcall(function()
		if not pcall(ffi.typeof, "MusicReplacer_GUID") then
			ffi.cdef(CDEF)
		end

		ole32 = ffi.load("ole32")
		kernel32 = ffi.load("kernel32")
	end)

	if not ok then
		ole32 = nil
		load_error = "ffi setup failed: " .. tostring(err)
		return false
	end

	return true
end

function NativeFfi.error()
	return load_error
end

function NativeFfi.ole32()
	return ole32
end

function NativeFfi.kernel32()
	return kernel32
end

-- CoInitializeEx would change how the calling thread runs COM for the whole game, so it is never called.
-- If this thread has no COM yet, CoIncrementMTAUsage lets it use the process-wide multithreaded apartment without joining it.
function NativeFfi.ensure_com()
	if com_ready then
		return
	end

	local apartment_type = ffi.new("int32_t[1]")
	local qualifier = ffi.new("int32_t[1]")
	if ole32.MusicReplacer_CoGetApartmentType(apartment_type, qualifier) == CO_E_NOTINITIALIZED then
		ole32.MusicReplacer_CoIncrementMTAUsage(ffi.new("void *[1]"))
	end

	com_ready = true
end

function NativeFfi.guid(data1, data2, data3, d4)
	local value = ffi.new("MusicReplacer_GUID")
	value.Data1, value.Data2, value.Data3 = data1, data2, data3
	for index = 1, 8 do
		value.Data4[index - 1] = d4[index]
	end
	return value
end

function NativeFfi.succeeded(hresult)
	return hresult >= 0
end

function NativeFfi.hex(hresult)
	return string.format("0x%08X", hresult < 0 and hresult + 2 ^ 32 or hresult)
end

-- Calls the method in vtable slot `index` of `object`. `signature` is the method's C type with the object pointer first.
function NativeFfi.call(object, index, signature, ...)
	local method_type = method_types[signature]
	if not method_type then
		method_type = ffi.typeof(signature)
		method_types[signature] = method_type
	end

	local vtable = ffi.cast("MusicReplacer_ComObject *", object).lpVtbl
	return ffi.cast(method_type, vtable[index])(object, ...)
end

function NativeFfi.add_ref(object)
	if object ~= nil then
		NativeFfi.call(object, 1, "uint32_t (*)(void *)")
	end
end

function NativeFfi.release(object)
	if object ~= nil then
		NativeFfi.call(object, 2, "uint32_t (*)(void *)")
	end
end

-- A NUL-terminated UTF-16 copy of a UTF-8 string, for the wide-character APIs.
function NativeFfi.wide(text)
	local length = kernel32.MusicReplacer_MultiByteToWideChar(CP_UTF8, 0, text, -1, nil, 0)
	local buffer = ffi.new("uint16_t[?]", math.max(length, 1))
	kernel32.MusicReplacer_MultiByteToWideChar(CP_UTF8, 0, text, -1, buffer, length)
	return buffer
end

return NativeFfi
