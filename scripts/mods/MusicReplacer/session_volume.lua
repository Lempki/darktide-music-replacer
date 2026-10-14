-- Reads and sets the Windows audio session volume of one process, such as a running ffplay, through Core Audio COM calls over LuaJIT's ffi.
-- ffplay bakes its volume in at launch and has no control channel, so its session volume is the only way to change a running track's level.
-- Only the session whose process id matches is touched, never the system volume or another program.
-- Windows remembers a program's session volume across launches, so every new ffplay starts at the last value set for ffplay_dt.exe.
-- Every call walks the active output devices and their sessions afresh, so an ended session or a changed device is never used stale.
-- Docs: https://learn.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-isimpleaudiovolume

local SessionVolume = {}

local ffi = (Mods and Mods.lua and Mods.lua.ffi) or (not Mods and require("ffi")) or nil

-- Every mod shares one LuaJIT state, and ffi.cdef rejects redefining a name that another mod may also declare, as DMF does.
-- So every name is prefixed, and the functions are redirected to their real symbols.
-- A mod reload finds the names already defined and skips the block.
local CDEF = [[
typedef struct { uint32_t Data1; uint16_t Data2; uint16_t Data3; uint8_t Data4[8]; } MusicReplacer_GUID;

typedef struct { void **lpVtbl; } MusicReplacer_ComObject;

int32_t MusicReplacer_CoIncrementMTAUsage(void **cookie) __asm__("CoIncrementMTAUsage");
int32_t MusicReplacer_CoCreateInstance(const MusicReplacer_GUID *clsid, void *outer, uint32_t cls_context,
	const MusicReplacer_GUID *iid, void **object) __asm__("CoCreateInstance");

void *MusicReplacer_OpenProcess(uint32_t access, int32_t inherit, uint32_t pid) __asm__("OpenProcess");
int32_t MusicReplacer_GetExitCodeProcess(void *process, uint32_t *exit_code) __asm__("GetExitCodeProcess");
int32_t MusicReplacer_CloseHandle(void *handle) __asm__("CloseHandle");
]]

local PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
local STILL_ACTIVE = 259

-- Each signature is the method's own, with the object pointer first. Indexes are vtable slots, counting IUnknown's three.
local METHODS = {
	add_ref = { 1, "uint32_t (*)(void *)" },
	release = { 2, "uint32_t (*)(void *)" },
	enum_audio_endpoints = { 3, "int32_t (*)(void *, int32_t, uint32_t, void **)" }, -- IMMDeviceEnumerator
	activate = { 3, "int32_t (*)(void *, const MusicReplacer_GUID *, uint32_t, void *, void **)" }, -- IMMDevice
	collection_get_count = { 3, "int32_t (*)(void *, uint32_t *)" }, -- IMMDeviceCollection
	collection_item = { 4, "int32_t (*)(void *, uint32_t, void **)" },
	get_session_enumerator = { 5, "int32_t (*)(void *, void **)" }, -- IAudioSessionManager2
	session_get_count = { 3, "int32_t (*)(void *, int32_t *)" }, -- IAudioSessionEnumerator
	get_session = { 4, "int32_t (*)(void *, int32_t, void **)" },
	query_interface = { 0, "int32_t (*)(void *, const MusicReplacer_GUID *, void **)" },
	get_process_id = { 14, "int32_t (*)(void *, uint32_t *)" }, -- IAudioSessionControl2, after IAudioSessionControl's nine
	set_master_volume = { 3, "int32_t (*)(void *, float, const MusicReplacer_GUID *)" }, -- ISimpleAudioVolume
	get_master_volume = { 4, "int32_t (*)(void *, float *)" },
}

local CO_E_NOTINITIALIZED = -2147221008 -- 0x800401F0
local CLSCTX_ALL = 23
local E_RENDER = 0
local DEVICE_STATE_ACTIVE = 1

local ole32 = nil
local kernel32 = nil
local method_types = {}
local guids = {}
local device_enumerator = nil
local init_error = nil

local function guid(data1, data2, data3, d4)
	local value = ffi.new("MusicReplacer_GUID")
	value.Data1, value.Data2, value.Data3 = data1, data2, data3
	for index = 1, 8 do
		value.Data4[index - 1] = d4[index]
	end
	return value
end

local function succeeded(hresult)
	return hresult >= 0
end

local function call(object, method_name, ...)
	local method = METHODS[method_name]
	local vtable = ffi.cast("MusicReplacer_ComObject *", object).lpVtbl
	return ffi.cast(method_types[method_name], vtable[method[1]])(object, ...)
end

local function release(object)
	if object ~= nil then
		call(object, "release")
	end
end

-- Sets up ffi and COM once. Returns false, with SessionVolume.error() saying why, when anything is missing.
local function ensure_initialized()
	if device_enumerator ~= nil then
		return true
	end

	if init_error then
		return false
	end

	if not ffi or ffi.os ~= "Windows" then
		init_error = "ffi is not available"
		return false
	end

	local ok, err = pcall(function()
		if not pcall(ffi.typeof, "MusicReplacer_GUID") then
			ffi.cdef(CDEF)
		end

		for name, method in pairs(METHODS) do
			method_types[name] = ffi.typeof(method[2])
		end

		guids.clsid_device_enumerator = guid(0xBCDE0395, 0xE52F, 0x467C, { 0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E })
		guids.iid_device_enumerator = guid(0xA95664D2, 0x9614, 0x4F35, { 0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6 })
		guids.iid_session_manager2 = guid(0x77AA99A0, 0x1BD6, 0x484F, { 0x8B, 0xC7, 0x2C, 0x65, 0x4C, 0x9A, 0x9B, 0x6F })
		guids.iid_session_control2 = guid(0xBFB7FF88, 0x7239, 0x4FC9, { 0x8F, 0xA2, 0x07, 0xC9, 0x50, 0xBE, 0x9C, 0x6D })
		guids.iid_simple_audio_volume = guid(0x87CE5498, 0x68D6, 0x44E5, { 0x92, 0x15, 0x6D, 0xA4, 0x7E, 0xF8, 0x83, 0xD8 })

		ole32 = ffi.load("ole32")
		kernel32 = ffi.load("kernel32")
	end)

	if not ok then
		init_error = "ffi setup failed: " .. tostring(err)
		return false
	end

	local out = ffi.new("void *[1]")
	local function create_enumerator()
		return ole32.MusicReplacer_CoCreateInstance(guids.clsid_device_enumerator, nil, CLSCTX_ALL, guids.iid_device_enumerator, out)
	end

	-- CoInitializeEx would change how the calling thread runs COM for the whole game, so it is never called.
	-- If this thread has no COM yet, CoIncrementMTAUsage lets it use the process-wide multithreaded apartment without joining it.
	local hresult = create_enumerator()
	if hresult == CO_E_NOTINITIALIZED then
		ole32.MusicReplacer_CoIncrementMTAUsage(ffi.new("void *[1]"))
		hresult = create_enumerator()
	end

	if not succeeded(hresult) then
		init_error = string.format("creating the device enumerator failed with 0x%08X", hresult < 0 and hresult + 2 ^ 32 or hresult)
		return false
	end

	device_enumerator = out[0]
	return true
end

-- Calls visit(simple_audio_volume) if `control` is the session of `pid`, and returns visit's result.
local function visit_if_session_of(control, pid, visit)
	local out = ffi.new("void *[1]")
	local session_pid = ffi.new("uint32_t[1]")

	if not succeeded(call(control, "query_interface", guids.iid_session_control2, out)) then
		return nil
	end
	local control2 = out[0]
	local result = nil

	-- A session shared by several processes reports a success code with no single pid, which never matches.
	if succeeded(call(control2, "get_process_id", session_pid)) and session_pid[0] == pid
		and succeeded(call(control2, "query_interface", guids.iid_simple_audio_volume, out)) then
		local simple_volume = out[0]
		result = visit(simple_volume)
		release(simple_volume)
	end

	release(control2)
	return result
end

local function visit_session_on_device(device, pid, visit)
	local out = ffi.new("void *[1]")
	local session_count = ffi.new("int32_t[1]")

	if not succeeded(call(device, "activate", guids.iid_session_manager2, CLSCTX_ALL, nil, out)) then
		return nil
	end
	local manager = out[0]
	local result = nil

	if succeeded(call(manager, "get_session_enumerator", out)) then
		local sessions = out[0]

		if succeeded(call(sessions, "session_get_count", session_count)) then
			for index = 0, session_count[0] - 1 do
				if succeeded(call(sessions, "get_session", index, out)) then
					local control = out[0]
					result = visit_if_session_of(control, pid, visit)
					release(control)
				end

				if result ~= nil then
					break
				end
			end
		end

		release(sessions)
	end

	release(manager)
	return result
end

-- Calls visit(simple_audio_volume) for the first session of `pid` on any active output device.
-- Returns visit's result, or nil when no such session exists.
local function with_session_volume(pid, visit)
	local out = ffi.new("void *[1]")
	local device_count = ffi.new("uint32_t[1]")

	if not succeeded(call(device_enumerator, "enum_audio_endpoints", E_RENDER, DEVICE_STATE_ACTIVE, out)) then
		return nil
	end
	local devices = out[0]
	local result = nil

	if succeeded(call(devices, "collection_get_count", device_count)) then
		for index = 0, device_count[0] - 1 do
			if succeeded(call(devices, "collection_item", index, out)) then
				local device = out[0]
				result = visit_session_on_device(device, pid, visit)
				release(device)
			end

			if result ~= nil then
				break
			end
		end
	end

	release(devices)
	return result
end

-- True when the COM setup works. Safe to call any time, and cheap after the first call.
function SessionVolume.available()
	return ensure_initialized()
end

-- Why SessionVolume.available() is false, or nil.
function SessionVolume.error()
	return init_error
end

-- The session volume of `pid` from 0 to 1, or nil when that process has no audio session yet or COM is unavailable.
function SessionVolume.get(pid)
	if not pid or not ensure_initialized() then
		return nil
	end

	local level = ffi.new("float[1]")

	return with_session_volume(pid, function(simple_volume)
		if succeeded(call(simple_volume, "get_master_volume", level)) then
			return level[0]
		end
		return nil
	end)
end

-- An open session keeps its ISimpleAudioVolume, so each call skips the device and session walk.
-- It still works after its process ends, which the caller can use to reset the volume Windows stores for the program.
local Session = {}
Session.__index = Session

function Session:get()
	if self.pointer == nil then
		return nil
	end

	local level = ffi.new("float[1]")
	if succeeded(call(self.pointer, "get_master_volume", level)) then
		return level[0]
	end
	return nil
end

function Session:set(volume)
	if self.pointer == nil then
		return false
	end

	return succeeded(call(self.pointer, "set_master_volume", math.max(0, math.min(1, volume)), nil))
end

-- True once the session's process has exited, which is when setting the volume can no longer be heard.
function Session:process_ended()
	local process = kernel32.MusicReplacer_OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, self.pid)
	if process == nil then
		return true
	end

	local exit_code = ffi.new("uint32_t[1]")
	local ok = kernel32.MusicReplacer_GetExitCodeProcess(process, exit_code) ~= 0
	kernel32.MusicReplacer_CloseHandle(process)

	return ok and exit_code[0] ~= STILL_ACTIVE
end

function Session:close()
	if self.pointer ~= nil then
		release(ffi.gc(self.pointer, nil))
		self.pointer = nil
	end
end

-- Opens the session of `pid`, or returns nil when that process has no audio session yet or COM is unavailable.
function SessionVolume.open(pid)
	if not pid or not ensure_initialized() then
		return nil
	end

	local pointer = with_session_volume(pid, function(simple_volume)
		call(simple_volume, "add_ref")
		return simple_volume
	end)

	if pointer == nil then
		return nil
	end

	-- Released on close, or by the garbage collector if a caller drops it.
	return setmetatable({ pointer = ffi.gc(pointer, release), pid = pid }, Session)
end

-- Sets the session volume of `pid`, clamped to 0 to 1.
-- Returns true once it is set, or false when that process has no audio session yet or COM is unavailable.
function SessionVolume.set(pid, volume)
	if not pid or not ensure_initialized() then
		return false
	end

	volume = math.max(0, math.min(1, volume))

	return with_session_volume(pid, function(simple_volume)
		return succeeded(call(simple_volume, "set_master_volume", volume, nil))
	end) == true
end

return SessionVolume
