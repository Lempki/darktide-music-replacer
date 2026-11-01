-- Keeps one of the mod's elements in the game's constant UI, which is drawn on every screen, loading screens included.
-- A HUD element would only exist in the hub and in missions, and miss the loading and mission preparation contexts.
-- The constant UI has no API for mods, so the element is added and removed the way the game sets up its own constant elements.

local ConstantElementSlot = {}
ConstantElementSlot.__index = ConstantElementSlot

-- Every group the game's own always-visible elements use, so the element shows on every screen but the disabled ones.
local VISIBILITY_GROUPS = {
	"tactical_overlay",
	"cutscene",
	"mission_lobby",
	"end_of_round",
	"in_view",
	"in_hub_view",
	"in_hub",
	"in_loading",
	"skippable_cinematic",
	"in_mission",
	"default",
}

-- `class_name` is the element's class, and the name it is kept under in the constant UI.
function ConstantElementSlot.new(class_name, draw_layer)
	local slot = {
		_class_name = class_name,
		_draw_layer = draw_layer,
		_installed_into = nil, -- The constant UI the element was added to, or nil.
		_install_failed = false,
	}
	return setmetatable(slot, ConstantElementSlot)
end

-- The element in the constant UI it was added to, or nil.
function ConstantElementSlot:element()
	local elements = self._installed_into and self._installed_into._elements
	return elements and elements[self._class_name]
end

function ConstantElementSlot:remove()
	local class_name = self._class_name
	local constant_elements = self._installed_into
	self._installed_into = nil

	-- The game destroys every element of a constant UI it tears down, ours included, and then drops its element list.
	-- So a torn-down UI has nothing left to remove, and destroying the element again would act on a dead object.
	if not constant_elements or not constant_elements._elements_array then
		return
	end

	local elements = constant_elements._elements
	local element = elements and elements[class_name]
	if element then
		elements[class_name] = nil

		local elements_array = constant_elements._elements_array
		for index = #elements_array, 1, -1 do
			if elements_array[index] == element then
				table.remove(elements_array, index)
			end
		end

		if element.destroy then
			element:destroy(constant_elements:ui_renderer())
		end
	end

	for _, group in ipairs(constant_elements._visibility_groups or {}) do
		if group.visible_elements then
			group.visible_elements[class_name] = nil
		end
	end
	for _, parameters in pairs(constant_elements._visibility_group_parameters or {}) do
		parameters[class_name] = nil
	end
end

function ConstantElementSlot:_install(constant_elements, create_element)
	-- Set first, so a failure below still has its partial setup removed.
	self._installed_into = constant_elements

	-- Fills in the visibility groups the same way the game does for its own elements. The misspelled name is the game's own.
	constant_elements:_setup_visiblity_groups({ { class_name = self._class_name, visibility_groups = VISIBILITY_GROUPS } })

	local element = create_element(constant_elements, self._draw_layer)
	constant_elements._elements[self._class_name] = element
	constant_elements._elements_array[#constant_elements._elements_array + 1] = element

	-- The next update works out the element's visibility again, as after the game adds an element.
	constant_elements._current_group_name = nil
end

local function constant_elements_now()
	local ui = Managers and Managers.ui
	return ui and ui.ui_constant_elements and ui:ui_constant_elements()
end

-- Call every update while the element should show. Adds it once the game's UI exists, and adds it again if the UI was rebuilt.
-- `create_element(constant_elements, draw_layer)` makes the element.
-- Returns the error when adding the element failed. The slot then stops trying, so the error comes back only once.
function ConstantElementSlot:update(create_element)
	if self._install_failed then
		return nil
	end

	local constant_elements = constant_elements_now()
	if not constant_elements or constant_elements == self._installed_into then
		return nil
	end

	self:remove()

	local ok, err = pcall(self._install, self, constant_elements, create_element)
	if not ok then
		self._install_failed = true
		self:remove()
		return tostring(err)
	end
	return nil
end

return ConstantElementSlot
