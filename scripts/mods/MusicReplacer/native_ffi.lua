-- Shared plumbing for calling Windows APIs through LuaJIT's ffi: GUIDs, COM vtable calls, COM setup, and UTF-16 strings.
-- It also covers memory on the Windows heap and the file functions audio_folders.lua uses.
-- The mod loader exposes ffi as Mods.lua.ffi. Outside the game, plain LuaJIT's own ffi is used, so these modules can be tried standalone.

local NativeFfi = {}

local ffi = (Mods and Mods.lua and Mods.lua.ffi) or (not Mods and require("ffi")) or nil
NativeFfi.ffi = ffi

-- Every mod shares one LuaJIT state, and ffi.cdef rejects redefining a name that another mod may also declare, as DMF does.
-- So every name is prefixed, and the functions are redirected to their real symbols.
local CDEF = [[
typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } MusicReplacer_GUID;

typedef struct { void **lpVtbl; } MusicReplacer_ComObject;

/* Audio formats are tightly packed, as in Windows' own headers. */
#pragma pack(push, 1)
typedef struct {
	uint16_t wFormatTag;
	uint16_t nChannels;
	uint32_t nSamplesPerSec;
	uint32_t nAvgBytesPerSec;
	uint16_t nBlockAlign;
	uint16_t wBitsPerSample;
	uint16_t cbSize;
} MusicReplacer_WAVEFORMATEX;
#pragma pack(pop)

int32_t MusicReplacer_CoGetApartmentType(int32_t *type, int32_t *qualifier) __asm__("CoGetApartmentType");
int32_t MusicReplacer_CoIncrementMTAUsage(void **cookie) __asm__("CoIncrementMTAUsage");
void MusicReplacer_CoTaskMemFree(void *memory) __asm__("CoTaskMemFree");

int32_t MusicReplacer_MultiByteToWideChar(uint32_t code_page, uint32_t flags, const char *source, int32_t source_length, uint16_t *target, int32_t target_length) __asm__("MultiByteToWideChar");
void *MusicReplacer_GetProcessHeap(void) __asm__("GetProcessHeap");
void *MusicReplacer_HeapAlloc(void *heap, uint32_t flags, size_t bytes) __asm__("HeapAlloc");
int32_t MusicReplacer_HeapFree(void *heap, uint32_t flags, void *memory) __asm__("HeapFree");
uint32_t MusicReplacer_GetFullPathNameW(const uint16_t *name, uint32_t length, uint16_t *buffer, uint16_t **file_part) __asm__("GetFullPathNameW");
int32_t MusicReplacer_WideCharToMultiByte(uint32_t code_page, uint32_t flags, const uint16_t *source, int32_t source_length, char *target, int32_t target_length, const char *default_char, int32_t *used_default) __asm__("WideCharToMultiByte");

typedef struct { uint32_t low; uint32_t high; } MusicReplacer_FILETIME;
typedef struct {
	uint32_t dwFileAttributes;
	MusicReplacer_FILETIME ftCreationTime;
	MusicReplacer_FILETIME ftLastAccessTime;
	MusicReplacer_FILETIME ftLastWriteTime;
	uint32_t nFileSizeHigh;
	uint32_t nFileSizeLow;
	uint32_t dwReserved0;
	uint32_t dwReserved1;
	uint16_t cFileName[260];
	uint16_t cAlternateFileName[14];
} MusicReplacer_WIN32_FIND_DATAW;

void *MusicReplacer_FindFirstFileW(const uint16_t *pattern, MusicReplacer_WIN32_FIND_DATAW *data) __asm__("FindFirstFileW");
int32_t MusicReplacer_FindNextFileW(void *find, MusicReplacer_WIN32_FIND_DATAW *data) __asm__("FindNextFileW");
int32_t MusicReplacer_FindClose(void *find) __asm__("FindClose");
uint32_t MusicReplacer_GetFileAttributesW(const uint16_t *path) __asm__("GetFileAttributesW");
int32_t MusicReplacer_CreateDirectoryW(const uint16_t *path, void *security) __asm__("CreateDirectoryW");
int32_t MusicReplacer_CreateDirectoryA(const char *path, void *security) __asm__("CreateDirectoryA");
void *MusicReplacer_FindFirstChangeNotificationW(const uint16_t *path, int32_t watch_subtree, uint32_t filter) __asm__("FindFirstChangeNotificationW");
int32_t MusicReplacer_FindNextChangeNotification(void *handle) __asm__("FindNextChangeNotification");
int32_t MusicReplacer_FindCloseChangeNotification(void *handle) __asm__("FindCloseChangeNotification");
uint32_t MusicReplacer_WaitForSingleObject(void *handle, uint32_t milliseconds) __asm__("WaitForSingleObject");
]]

local CO_E_NOTINITIALIZED = -2147221008 -- 0x800401F0
local CP_UTF8 = 65001

local ole32 = nil
local kernel32 = nil
local method_types = {}
local com_ready = false
local load_error = nil

-- Declares each top-level C declaration in `text` on its own.
-- A mod reload declares everything again, which LuaJIT may reject as a redefinition, so that error alone is skipped.
-- Any other error, such as a typo in a declaration, stops the load, since it would otherwise surface later as a missing name.
-- The first load's layouts stay until the game restarts, as LuaJIT keeps every declaration for the life of its state.
-- A packed region between #pragma pack(push) and #pragma pack(pop) stays one declaration.
function NativeFfi.define(text)
	local chunk = {}
	local depth = 0
	local packed = false

	for line in text:gmatch("[^\n]+") do
		chunk[#chunk + 1] = line

		if line:find("^#pragma pack%(push") then
			packed = true
		elseif line:find("^#pragma pack%(pop") then
			packed = false
		end

		local _, opened = line:gsub("{", "")
		local _, closed = line:gsub("}", "")
		depth = depth + opened - closed

		if not packed and depth == 0 and (line:find(";%s*$") or line:find("^#pragma pack%(pop")) then
			local ok, err = pcall(ffi.cdef, table.concat(chunk, "\n"))
			if not ok and not tostring(err):find("attempt to redefine", 1, true) then
				error(err, 2)
			end
			chunk = {}
		end
	end
end

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
		NativeFfi.define(CDEF)

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

-- CoInitializeEx would change how the game's thread runs COM, so it is never called.
-- If the thread has no COM yet, CoIncrementMTAUsage keeps the process-wide multithreaded apartment alive for it to run in implicitly.
-- The cookie is never released, so the apartment outlives every COM object the mod creates, and ends with the game's process.
-- A reloaded mod finds the thread in the apartment already, so it adds no second count.
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

-- The method in vtable slot `index` of `object`, as a function that takes the object pointer first, as `signature` declares.
-- A method called every frame is fetched once with this, since each fetch makes a new cdata object on the Lua heap.
function NativeFfi.method(object, index, signature)
	local method_type = method_types[signature]
	if not method_type then
		method_type = ffi.typeof(signature)
		method_types[signature] = method_type
	end

	local vtable = ffi.cast("MusicReplacer_ComObject *", object).lpVtbl
	return ffi.cast(method_type, vtable[index])
end

-- Calls the method in vtable slot `index` of `object`. `signature` is the method's C type with the object pointer first.
function NativeFfi.call(object, index, signature, ...)
	return NativeFfi.method(object, index, signature)(object, ...)
end

-- Calls IUnknown::Release, which is slot 2 of every COM object's vtable.
function NativeFfi.release(object)
	if object ~= nil then
		NativeFfi.call(object, 2, "uint32_t (*)(void *)")
	end
end

-- Allocates `bytes` from the Windows process heap, outside the Lua heap, which the game's own memory use already strains.
-- Returns a uint8_t pointer, or nil. Free it with NativeFfi.free(), since the garbage collector never will.
function NativeFfi.alloc(bytes)
	local memory = kernel32.MusicReplacer_HeapAlloc(kernel32.MusicReplacer_GetProcessHeap(), 0, bytes)
	if memory == nil then
		return nil
	end
	return ffi.cast("uint8_t *", memory)
end

function NativeFfi.free(memory)
	if memory ~= nil then
		kernel32.MusicReplacer_HeapFree(kernel32.MusicReplacer_GetProcessHeap(), 0, memory)
	end
end

-- The loudest of `count` 16-bit samples at `memory`, as a share of full scale.
function NativeFfi.peak_int16(memory, count)
	local samples = ffi.cast("const int16_t *", memory)
	local peak = 0
	for index = 0, count - 1 do
		local sample = samples[index]
		if sample < 0 then
			sample = -sample
		end
		if sample > peak then
			peak = sample
		end
	end
	return peak / 32768
end

-- A NUL-terminated UTF-16 copy of a UTF-8 string, for the wide-character APIs.
function NativeFfi.wide(text)
	local length = kernel32.MusicReplacer_MultiByteToWideChar(CP_UTF8, 0, text, -1, nil, 0)
	local buffer = ffi.new("uint16_t[?]", math.max(length, 1))
	kernel32.MusicReplacer_MultiByteToWideChar(CP_UTF8, 0, text, -1, buffer, length)
	return buffer
end

-- A NUL-terminated UTF-16 full path for a UTF-8 path, which may be relative to the game's working directory.
function NativeFfi.wide_full_path(text)
	local relative = NativeFfi.wide(text)
	local length = kernel32.MusicReplacer_GetFullPathNameW(relative, 0, nil, nil)
	if length == 0 then
		return relative
	end

	local buffer = ffi.new("uint16_t[?]", length)
	kernel32.MusicReplacer_GetFullPathNameW(relative, length, buffer, nil)
	return buffer
end

-- A UTF-8 Lua string from a NUL-terminated UTF-16 buffer, as the wide-character APIs return.
function NativeFfi.utf8(wide)
	local length = kernel32.MusicReplacer_WideCharToMultiByte(CP_UTF8, 0, wide, -1, nil, 0, nil, nil)
	if length <= 1 then
		return ""
	end

	local buffer = ffi.new("char[?]", length)
	kernel32.MusicReplacer_WideCharToMultiByte(CP_UTF8, 0, wide, -1, buffer, length, nil, nil)
	return ffi.string(buffer, length - 1)
end

-- Creates the folder `path` and any missing folders above it, without starting cmd.exe as os.execute("mkdir") would.
-- `path` is in Windows' legacy code page, the one os.getenv returns and Lua's io library opens, so both agree on the folder.
-- A folder that already exists fails to be created, which is fine, since opening a file in it is the real check.
function NativeFfi.create_directories(path)
	local prefix = nil
	for part in path:gsub("/", "\\"):gmatch("[^\\]+") do
		prefix = prefix and (prefix .. "\\" .. part) or part
		-- A drive such as C: is a root, not a folder to create.
		if not prefix:find(":$") then
			kernel32.MusicReplacer_CreateDirectoryA(prefix, nil)
		end
	end
end

return NativeFfi
