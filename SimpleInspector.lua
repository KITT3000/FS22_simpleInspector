--
-- Mod: FS22_SimpleInspector
--
-- Author: JTSage
-- source: https://github.com/jtsage/FS22_Simple_Inspector

--[[
CHANGELOG
	v1.0.0.0
		- First version.  not compatible with EnhancedVehicle.
]]--
SimpleInspector= {}

local SimpleInspector_mt = Class(SimpleInspector)

function SimpleInspector:new(mission, i18n, modDirectory, modName)
	local self = {}

	setmetatable(self, SimpleInspector_mt)

	self.isServer          = mission:getIsServer()
	self.isClient          = mission:getIsClient()
	self.mission           = mission
	self.i18n              = i18n
	self.modDirectory      = modDirectory
	self.modName           = modName
	self.gameInfoDisplay   = mission.hud.gameInfoDisplay
	self.speedMeterDisplay = mission.hud.speedMeter

	self.settingsDirectory = getUserProfileAppPath() .. "modSettings/"
	self.confDirectory     = self.settingsDirectory .."FS22_SimpleInspector/"
	self.confFile          = self.confDirectory .. "FS22_SimpleInspectorSettings.xml"

	self.settings = {
		debugMode      = false,
		showAll        = false,
		maxDepth       = 5,
		timerFrequency = 15,
		textMarginX    = 15,
		textMarginY    = 10,
		textSize       = 12,
		colorNormal    = "1, 1, 1, 1",
		colorFillFull  = "1, 0, 0, 1",
		colorFillHalf  = "1, 1, 0, 1",
		colorFillLow   = "0, 1, 0, 1",
		colorUser      = "0, 1, 0, 1",
		colorAI        = "0, 0.77, 1, 1",
		colorAIMark    = "0, .5, 1, 1"
	}

	self.debugTimerRuns = 0
	self.inspectText    = {}
	self.boxBGColor     = { 544, 20, 200, 44 }
	self.uiFilename     = Utils.getFilename("resources/HUD.dds", modDirectory)

	local modDesc       = loadXMLFile("modDesc", modDirectory .. "modDesc.xml");
	self.version        = getXMLString(modDesc, "modDesc.version");

	self.display_data = { }

	return self
end

function SimpleInspector:getColor(name)
	local settings = self.settings
	local colorString = Utils.getNoNil(settings[name], "1,1,1,1")

	local t={}
	for str in string.gmatch(colorString, "([^,]+)") do
		table.insert(t, tonumber(str))
	end
	return t
end

function SimpleInspector:createSettingsFile()
	createFolder(self.settingsDirectory)
	createFolder(self.confDirectory)

	local defaults = self.settings
	local xml = createXMLFile("FS22_SimpleInspector", self.confFile, "FS22_SimpleInspector")

	for idx, value in pairs(defaults) do
		local groupNameTag = string.format("%s.%s(%d)", "FS22_SimpleInspector", idx, 0)
		if type(value) == "boolean" then
			setXMLBool(xml, groupNameTag .. "#boolean", value)
		elseif type(value) == "number" then
			setXMLInt(xml, groupNameTag .. "#int", value)
		else
			setXMLString(xml, groupNameTag .. "#string", value)
		end
	end

	local groupNameTag = string.format("%s.%s(%d)", "FS22_SimpleInspector", "version", 0)
	setXMLString(xml, groupNameTag .. "#string", self.version)

	saveXMLFile(xml)
	print("~~simpleInspector :: saved config file")
end

function SimpleInspector:readSettingsFile()
	local settings = self.settings
	local defaults = {}

	for idx, value in pairs(settings) do
		defaults[idx] = value
	end

	local xml = loadXMLFile("FS22_SimpleInspector", self.confFile, "FS22_SimpleInspector")

	for idx, value in pairs(defaults) do
		local groupNameTag = string.format("%s.%s(%d)", "FS22_SimpleInspector", idx, 0)
		if type(value) == "boolean" then
			settings[idx] = Utils.getNoNil(getXMLBool(xml, groupNameTag .. "#boolean"), value)
		elseif type(value) == "number" then
			settings[idx] = Utils.getNoNil(getXMLInt(xml, groupNameTag .. "#int"), value)
		else
			settings[idx] = Utils.getNoNil(getXMLString(xml, groupNameTag .. "#string"), value)
		end
	end

	print("~~simpleInspector :: read config file")

	local groupNameTag = string.format("%s.%s(%d)", "FS22_SimpleInspector", "version", 0)
	confVersion  = Utils.getNoNil(getXMLString(xml, groupNameTag .. "#string"), "unknown")

	if ( confVersion ~= self.version ) then
		print("~~simpleInspector :: old config file, updating")
		self:createSettingsFile()
	end
	
end


function SimpleInspector:onStartMission(mission)
	-- Load the mod, make the box that info lives in.
	print("~~simpleInspector :: version " .. self.version .. " loaded.")

	if fileExists(self.confFile) then
		self:readSettingsFile()
	else
		self:createSettingsFile()
	end

	if ( self.settings.debugMode ) then
		print("~~simpleInspector :: onStartMission")
	end

	if not self.isClient then
		return
	end

	self:createTextBox()
end

function SimpleInspector:getVehSpeed(vehicle)
	-- Get the current speed of the vehicle
	local speed = Utils.getNoNil(vehicle.lastSpeed, 0) * 3600
	if g_gameSettings:getValue('useMiles') then
		speed = speed * 0.621371
	end
	return string.format("%1.0f", "".. Utils.getNoNil(speed, 0))
end

function SimpleInspector:getSingleFill(vehicle, theseFills)
	-- This is the single run at the fill type, for the current vehicle only.
	-- Borrowed heavily from older versions of similar plugins, ignores unknonw fill types
	local spec_fillUnit = vehicle.spec_fillUnit

	if spec_fillUnit ~= nil and spec_fillUnit.fillUnits ~= nil then
		for i = 1, #spec_fillUnit.fillUnits do
			local goodFillType = false
			local fillUnit = spec_fillUnit.fillUnits[i]
			if fillUnit.capacity > 0 and fillUnit.showOnHud then
				local fillType = fillUnit.fillType;
				if fillType == FillType.UNKNOWN and table.size(fillUnit.supportedFillTypes) == 1 then
					fillType = next(fillUnit.supportedFillTypes)
				end
				if fillUnit.fillTypeToDisplay ~= FillType.UNKNOWN then
					fillType = fillUnit.fillTypeToDisplay
				end

				local fillLevel = fillUnit.fillLevel;
				if fillUnit.fillLevelToDisplay ~= nil then
					fillLevel = fillUnit.fillLevelToDisplay
				end

				fillLevel = math.ceil(fillLevel)

				local capacity = fillUnit.capacity
				if fillUnit.parentUnitOnHud ~= nil then
					if fillType == FillType.UNKNOWN then
						fillType = spec_fillUnit.fillUnits[fillUnit.parentUnitOnHud].fillType;
					end
					capacity = 0
				elseif fillUnit.childUnitOnHud ~= nil and fillType == FillType.UNKNOWN then
					fillType = spec_fillUnit.fillUnits[fillUnit.childUnitOnHud].fillType
				end

				local maxReached = not fillUnit.ignoreFillLimit and g_currentMission.missionInfo.trailerFillLimit and vehicle.getMaxComponentMassReached ~= nil and vehicle:getMaxComponentMassReached();

				if maxReached then
					capacity = fillLevel
				end
				
				if fillLevel > 0 then
					if ( theseFills[fillType] ~= nil ) then
						theseFills[fillType][1] = theseFills[fillType][1] + fillLevel
						theseFills[fillType][2] = theseFills[fillType][2] + capacity
					else
						theseFills[fillType] = { fillLevel, capacity }
					end
				end
			end
		end
	end
	return theseFills
end

function SimpleInspector:getAllFills(vehicle, fillLevels, depth)
	-- This is the recursive function, to a max depth of `maxDepth` (default 5)
	-- That's 5 levels of attachments, so 5 trailers, #6 gets ignored.
	self:getSingleFill(vehicle, fillLevels)

	if vehicle.getAttachedImplements ~= nil and depth < self.settings.maxDepth then
		local attachedImplements = vehicle:getAttachedImplements();
		for _, implement in pairs(attachedImplements) do
			if implement.object ~= nil then
				local newDepth = depth + 1
				self:getAllFills(implement.object, fillLevels, newDepth)
			end
		end
	end
end

function SimpleInspector:updateVehicles()
	local new_data_table = {}
	if g_currentMission ~= nil and g_currentMission.vehicles ~= nil then
		for v=1, #g_currentMission.vehicles do
			local thisVeh = g_currentMission.vehicles[v]
			if thisVeh ~= nil and thisVeh.getIsControlled ~= nil then
				local typeName = Utils.getNoNil(thisVeh.typeName, "unknown")
				local isTrain = typeName == "locomotive"
				local isRidable = SpecializationUtil.hasSpecialization(Rideable, thisVeh.specializations)
				if ( not isTrain and not isRidable) then
					local isRunning = thisVeh.getIsMotorStarted ~= nil and thisVeh:getIsMotorStarted()
					local isOnAI    = thisVeh.getIsAIActive ~= nil and thisVeh:getIsAIActive()
					local isConned  = thisVeh.getIsControlled ~= nil and thisVeh:getIsControlled()
					
					if ( self.settings.showAll or isConned or isRunning or isOnAI) then
						local thisName  = thisVeh:getName()
						local thisBrand = g_brandManager:getBrandByIndex(thisVeh:getBrand())
						local speed     = self:getVehSpeed(thisVeh)
						local fills     = {}
						local status    = 0
						local isAI      = false

						if isOnAI then
							status = 1
							isAI = true
						end
						if thisVeh:getIsControlled() then
							status = 2
						end

						self:getAllFills(thisVeh, fills, 0)
						table.insert(new_data_table, {
							status,
							isAI,
							thisBrand.title .. " " .. thisName,
							tostring(speed),
							fills
						})
					end
				end
			end
		end
	end

	self.display_data = {unpack(new_data_table)}
end

function SimpleInspector:update(dt)
	if not self.isClient then
		return
	end

	if self:shouldNotBeShown() then
		self.inspectBox:setVisible(false)
		return
	end

	if g_updateLoopIndex % self.settings.timerFrequency == 0 then
		-- Lets not be rediculous, only update the vehicles "infrequently"
		self:updateVehicles()
		if ( self.settings.debugMode ) then
			self.debugTimerRuns = self.debugTimerRuns + 1
			print("~~simpleInspector :: update (" .. self.debugTimerRuns .. ")")
		end
	end

	if self.inspectBox ~= nil then
		local info_text = self.display_data
		local deltaY = 0

		if g_currentMission.hud.sideNotifications ~= nil then
			if #g_currentMission.hud.sideNotifications.notificationQueue > 0 then
				deltaY = g_currentMission.hud.sideNotifications:getHeight()
			end
		end

		setTextAlignment(RenderText.ALIGN_RIGHT)
		setTextBold(false)
		setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_TOP)

		local x = self.inspectText.posX - self.inspectText.marginHeight
		local y = self.inspectText.posY - self.inspectText.marginHeight - deltaY
		local _w, _h = 0, self.inspectText.marginHeight * 2

		local hideBox = true


		for _, txt in pairs(info_text) do
			-- Data structure for each vehicle is:
			-- (new_data_table, {
			-- 	status, (0 no special status, 1 = AI, 2 = user controlled)
			-- 	isAI, (true / false - if status is 1 & 2)
			-- 	thisBrand.title .. " " .. thisName,
			-- 	tostring(speed), (in the users units)
			-- 	fills (table - index is fillType, contents are 1:level, 2:capacity)
			-- })
			hideBox = false

			setTextBold(true)
			local fullTextSoFar = ""

			for idx, thisFill in pairs(txt[5]) do
				local thisFillType = g_fillTypeManager:getFillTypeByIndex(idx)
				local thisString = thisFillType.title:lower() .. ":" .. thisFill[1]
				local thisPerc = math.ceil((thisFill[1] / thisFill[2]) * 100 )

				if idx == 16 then thisPerc = 100 - thisPerc
				elseif idx > 72 and idx < 79 then thisPerc = 100 - thisPerc
				elseif idx > 79 and idx < 84 then thisPerc = 100 - thisPerc
				end

				if thisPerc < 50     then setTextColor(unpack(self:getColor("colorFillLow")))
				elseif thisPerc < 85 then setTextColor(unpack(self:getColor("colorFillHalf")))
				else                      setTextColor(unpack(self:getColor("colorFillFulll")))
				end

				renderText(x - getTextWidth(self.inspectText.size, fullTextSoFar), y, self.inspectText.size, thisString)
				fullTextSoFar = thisString .. fullTextSoFar
				setTextColor(unpack(self:getColor("colorNormal")))
				renderText(x - getTextWidth(self.inspectText.size, fullTextSoFar), y, self.inspectText.size, "|")
				fullTextSoFar = "|" .. fullTextSoFar
			end

			local speedString = "|" .. txt[4]

			if g_gameSettings:getValue('useMiles') then
				speedString = speedString .. "mph"
			else
				speedString = speedString .. "kph"
			end

			setTextColor(unpack(self:getColor("colorNormal")))
			renderText(x - getTextWidth(self.inspectText.size, fullTextSoFar), y, self.inspectText.size, speedString)
			fullTextSoFar = speedString .. fullTextSoFar

			if txt[1] == 0     then setTextColor(unpack(self:getColor("colorNormal")))
			elseif txt[1] == 1 then setTextColor(unpack(self:getColor("colorAI")))
			else                    setTextColor(unpack(self:getColor("colorUser")))
			end

			renderText(x - getTextWidth(self.inspectText.size, fullTextSoFar), y, self.inspectText.size, txt[3])
			fullTextSoFar = txt[3] .. fullTextSoFar

			if txt[2] then
				setTextColor(unpack(self:getColor("colorAIMark")))
				renderText(x - getTextWidth(self.inspectText.size, fullTextSoFar), y, self.inspectText.size, "_AI_ ")
				fullTextSoFar = "_AI_ " .. fullTextSoFar
			end

			y = y - self.inspectText.size
			_h = _h + self.inspectText.size
			local tmp = getTextWidth(self.inspectText.size, fullTextSoFar)

			if tmp > _w then _w = tmp end
		end

		if hideBox then
			self.inspectBox:setVisible(false)
		else
			self.inspectBox:setVisible(true)
		end

		-- update overlay background
		self.inspectBox.overlay:setPosition(x - _w - self.inspectText.marginWidth, y - self.inspectText.marginHeight)
		self.inspectBox.overlay:setDimension(_w + self.inspectText.marginHeight + self.inspectText.marginWidth, _h)

		setTextColor(1,1,1,1)
		setTextAlignment(RenderText.ALIGN_LEFT)
		setTextVerticalAlignment(RenderText.VERTICAL_ALIGN_BASELINE)
		setTextBold(false)
	end
end

function SimpleInspector:delete()
	if self.inspectBox ~= nil then
		self.inspectBox:delete()
	end
end

function SimpleInspector:createTextBox()
	if ( self.settings.debugMode ) then
		print("~~simpleInspector :: createTextBox")
	end

	local baseX, baseY = self.gameInfoDisplay:getPosition()
	self.marginWidth, self.marginHeight = self.gameInfoDisplay:scalePixelToScreenVector({ 8, 8 })

	local boxOverlay = Overlay.new(self.uiFilename, 1, baseY - self.marginHeight, 1, 1)
	local boxElement = HUDElement.new(boxOverlay)
	self.inspectBox = boxElement
	self.inspectBox:setUVs(GuiUtils.getUVs(self.boxBGColor))
	self.inspectBox:setColor(unpack(SpeedMeterDisplay.COLOR.GEARS_BG))
	self.inspectBox:setVisible(false)
	self.gameInfoDisplay:addChild(boxElement)

	self.inspectText.posX = 1
	self.inspectText.posY = baseY - self.marginHeight
	self.inspectText.marginWidth, self.inspectText.marginHeight = self.gameInfoDisplay:scalePixelToScreenVector({self.settings.textMarginX, self.settings.textMarginY})
	self.inspectText.size = self.gameInfoDisplay:scalePixelToScreenHeight(self.settings.textSize)
end

function SimpleInspector:shouldNotBeShown()
	if g_currentMission.paused or
		g_gui:getIsGuiVisible() or
		g_currentMission.inGameMenu.paused or
		g_currentMission.inGameMenu.isOpen or
		g_currentMission.physicsPaused or
		not g_currentMission.hud.isVisible then

			if g_currentMission.missionDynamicInfo.isMultiplayer and g_currentMission.manualPaused then return false end

			return true
		end
		return false
end


local modDirectory = g_currentModDirectory or ""
local modName = g_currentModName or "unknown"
local modEnvironment

---Fix for registering the savegame schema (perhaps this can be better).
-- g_simpleInspectorModName = modName

local function load(mission)
	assert(g_simpleInspector == nil)

	modEnvironment = SimpleInspector:new(mission, g_i18n, modDirectory, modName)

	getfenv(0)["g_simpleInspector"] = modEnvironment

	addModEventListener(modEnvironment)
end

local function unload()
	removeModEventListener(modEnvironment)
	modEnvironment:delete()
	modEnvironment = nil -- Allows garbage collecting
	getfenv(0)["g_simpleInspector"] = nil
end

local function startMission(mission)
	modEnvironment:onStartMission(mission)
end


local function init()
	FSBaseMission.delete = Utils.appendedFunction(FSBaseMission.delete, unload)

	Mission00.load = Utils.prependedFunction(Mission00.load, load)
	Mission00.onStartMission = Utils.appendedFunction(Mission00.onStartMission, startMission)
end

init()