local GuidWarden = LibStub("AceAddon-3.0"):NewAddon(
	'GuidWarden', 
	'AceConsole-3.0', 'AceComm-3.0', 'AceEvent-3.0'
)

local db
--local LibDeflate = LibStub:GetLibrary("LibDeflate")
local genderTable = { "Unknown", "Male", "Female" }

local options = {
	name = 'GuidWarden',
	handler = GuidWarden,
	type = 'group',
	args = {
		monitorAll = {
			type = 'toggle',
			name = 'Monitor All',
			desc = 'Toggles whether all targetted players are monitored, or only those added by the command "/guid add"',
			get = 'IsMonitoringAll',
			set = 'ToggleMonitorAll',
		},
		
		debug = {
			type = 'toggle',
			name = 'Debug',
			desc = 'Enables debug messages to be displayed',
			get = 'IsDebug',
			set = 'ToggleDebug',
		},
		
		quiet = {
			type = 'toggle',
			name = 'Quiet Mode',
			desc = 'When disabled, notifies the user of any conflicts even after first encounter',
			get = 'IsQuiet',
			set = 'ToggleQuiet',
		},
		
		logging = {
			type = 'toggle',
			name = 'Log',
			desc = 'Enables addon information to be logged for further analysis',
			get = 'IsLogging',
			set = 'ToggleLogging',
		},
	}
}

function GuidWarden:InBG()
	return UnitInBattleground('player') ~= nil
end

function GuidWarden:IsMonitoringAll(info)
	return db.monitorAll
end

function GuidWarden:ToggleMonitorAll(info, value)
	db.monitorAll = value
end

function GuidWarden:IsDebug(info)
	return db.debug
end

function GuidWarden:ToggleDebug(info, value)
	db.debug = value
end

function GuidWarden:IsQuiet(info)
	return db.quiet
end

function GuidWarden:ToggleQuiet(info, value)
	db.quiet = value
end

function GuidWarden:ToggleLogging(info, value)
	db.logging = value
end

function GuidWarden:IsLogging(info)
	return db.logging
end

function GuidWarden:Debug(format, ...)
	if format == nil then return end
	if db.debug then
		self:Print(string.format(format, ...))
	end
end

function GuidWarden:Log(format, ...)
	if format == nil then return end
	if not db.logging then return end
	
	local message = string.format(format, ...)
	local logged_message = string.format('[%s] %s', date(), message)
	table.insert(db.log, logged_message)
end

local function searchEncounters(encounters, name, realm, class, race, gender, exclude_guid)
	for i, encounter in ipairs(encounters) do
		-- We are unable to tell whether our faction or our target's faction
		-- has changed as a consequene of being in a mercenary battleground
		if encounter['name'] == name 
		and encounter['realm'] == realm 
		and encounter['class'] == class 
		and encounter['race'] == race 
		and encounter['gender'] == genderTable[gender] then 
			return encounter
	  end
   end
   
   return nil
end

function GuidWarden:AddEncounter(guid, name, realm, class, race, gender)
	if name == nil or realm == nil or class == nil or race == nil or gender == nil then
		class, _, race, _, gender, name, realm = GetPlayerInfoByGUID(guid)
	end
	
	if realm == '' then
		realm = GetRealmName()
	end
	
	self:Debug('[GuidWarden:AddEncounter] %s (%s)', name or 'nil', guid)
	
	-- We are unable to tell whether our faction or our target's faction
	-- has changed as a consequene of being in a mercenary battleground
	if name == nil or realm == nil or class == nil or race == nil or gender == nil then
		self:Debug('Failed to add ' .. guid .. ' to database')
		self:Debug(
			'name: %s, realm: %s, guid: %s, gender: %s, race: %s, class: %s',
			name or 'nil', realm or 'nil', guid or 'nil', gender or 'nil', race or 'nil', class or 'nil'
		)
		return
	end
	
	self:Log("[GuidWarden:AddEncounter] %s (%s) %s, InBG(): %s, UnitIsVisible(\'target\'): %s, debugstack: %s", name, guid, race, tostring(self:InBG()), tostring(UnitIsVisible('target')), debugstack())
	
	local encounters = db.previous_players_encountered[guid]
	if encounters == nil then 
		db.previous_players_encountered[guid] = {[1] = {
			name = name,
			realm = realm,
			class = class,
			race = race,
			gender = genderTable[gender],
			date = date()
		}}
		self:Debug('[GuidWarden:AddEncounter] new')
		return 'new'
	end
	
	local start_db_search = GetTime()
	local num_entries = 0
	
	-- Search through entire list of players to see if any have had the same name in the past.
	for new_guid, encounters in pairs(db.previous_players_encountered) do
		num_entries = num_entries + 1
		if new_guid ~= guid then 
			local encounter = searchEncounters(encounters, name, realm, class, race, gender)
			if encounter ~= nil then
				self:Debug('[GuidWarden:AddEncounter] Long search conflict')
				self:Debug('Time to search guid database: %s', GetTime() - start_db_search)
				return 'conflict'
			end
		end
	end
	self:Debug('Time to search guid database: %s', GetTime() - start_db_search)
	if GetTime() - start_db_search >= 0.1 then
		self:Print(string.format(
			'Warning: guid encounter database size is becoming too large: %d entries',
			num_entries
		))
	end
   
	local start_update = GetTime()
	local encounter = searchEncounters(encounters, name, realm, class, race, gender)
	if encounter ~= nil then   
		self:Debug('Number of encounters: %d', #encounters)
		if not self:IsQuiet() and #encounters > 1 then
			return 'conflict'
		end
		
		self:Debug('[GuidWarden:AddEncounter] %s updated', encounter['name'])
		encounter['date'] = date()
		self:Debug('Time to update: %s', GetTime() - start_update)
		return 'updated'
	end
	self:Debug('Time to update: %s', GetTime() - start_update)
   
   -- New distinct encounter of known player
	table.insert(encounters, {
		name = name,
		realm = realm,
		class = class,
		race = race,
		gender = genderTable[gender],
		date = date()
	})
   
	self:Debug('[GuidWarden:AddEncounter] conflict')
	return 'conflict'
end

function GuidWarden:AddBlacklist(guid)
	self:Debug('[GuidWarden:AddBlacklist] ' .. guid)
	db.blacklist[guid] = db.previous_players_encountered[guid]
end

local last_scan = GetTime()

function GuidWarden:UNIT_TARGET()
	local current_time = GetTime()
	if (current_time - last_scan < 0.1) or self:InBG() 
	  or not UnitIsVisible('target') or not UnitIsPlayer('target') then 
		return
	end
  
	last_scan = current_time
	local guid = UnitGUID('target')
	local class, _, race, _, gender, name, realm = GetPlayerInfoByGUID(guid)
	if realm == '' then
		realm = GetRealmName()
	end

	self:Debug('[GuidWarden:UNIT_TARGET] ')
	if (not self:IsMonitoringAll() and db.blacklist[guid] ~= nil) or self:IsMonitoringAll() then
		local result = self:AddEncounter(guid, name, realm, class, race, UnitSexgender)
		if result == 'conflict' then
			self:Print(string.format('Player %s seen with conflicting player data', name))
			self:Print('Perform a "/guid lookup <name>" for more details')
		end
	end
end

function GuidWarden:BlacklistTarget()
	if not UnitIsPlayer('target') then return end
	self:Debug('[GuidWarden:BlacklistTarget] ')
	
	local guid = UnitGUID('target')
	if guid == nil then return end
	local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
	
	self:AddEncounter(guid)
	self:AddBlacklist(guid)
	self:Print(string.format('Player %s (%s) added', name, guid))
end

function GuidWarden:Lookup(name)
	if name == nil or #name == 0 then return nil end
	
	local encountered_guids = {}
	
	self:Debug('[GuidWarden:Lookup] looking for ' .. name)
	local lowered_name = string.lower(name)
	for guid, encounters in pairs(db.previous_players_encountered) do
		for i, data in ipairs(encounters) do
			if data and data['name'] and string.lower(data['name']) == lowered_name then
				table.insert(encountered_guids, {guid=guid, encounters=encounters})
			end
		end
	end
	
	return encountered_guids
end

function GuidWarden:HandleLookup(name)
	self:Debug(name)
	
	local encountered_guids = self:Lookup(name)
	
	if #encountered_guids == 0 then
		self:Print(string.format(
			'Unable to find player %s in previous encounters',
			name
		))
		
	else
		for _, encountered_guid in ipairs(encountered_guids) do
			local guid = encountered_guid.guid
			local encounters = encountered_guid.encounters
			
			self:Print(string.format(
				'Player with guid %s found with the following data:',
				guid
			))
			for _, data in ipairs(encounters) do
				self:Print(string.format(
					'[%s] %s (%s) - %s, %s %s %s', 
					data['date'], data['name'], guid, data['realm'], data['gender'], data['race'], data['class']
				))
			end
		end
	end
end

function GuidWarden:Collisions()
	local names = {}
	for guid, encounters in pairs(db.previous_players_encountered) do
		if #encounters > 1 then
			table.insert(names, encounters[1]['name'])
		end
	end
	return names
end

function GuidWarden:ChatHandler(msg)
	local substrings = {strsplit(' ', msg)}
	if #substrings == 0 then 
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	end
	
	local command = string.lower(substrings[1])
	if #substrings == 1 and (command == 'add' or command == 'scan') then
		self:BlacklistTarget()
		
	elseif #substrings == 1 and command == 'collisions' then
		local collisions = self:Collisions()
		for _, name in ipairs(collisions) do
			self:HandleLookup(name)
		end
	
	elseif #substrings >= 1 and command == 'lookup' then
		local name
		if #substrings >= 2 then
			name = substrings[2]
		else
			name = UnitName('target')
		end
		
		self:HandleLookup(name)
	end
end

function GuidWarden:OnCommReceived(prefix, message, distribution, sender)
	self:Debug('Comm received: [%s] [%s] [%s]: %s', prefix, distribution, sender, message)
end

function GuidWarden:OnInitialize()
	LibStub("AceConfig-3.0"):RegisterOptionsTable('GuidWarden', options)
	
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions('GuidWarden', 'GuidWarden')
	self:RegisterChatCommand('gw', 'ChatHandler')
	self:RegisterChatCommand('guid', 'ChatHandler')
	self:RegisterComm('GuidWardenComm', 'OnCommReceived')
end

function GuidWarden:OnEnable()
	local defaults = {
		global = {
			monitorAll = false,
			debug = false,
			logging = false,
			log = {},
			blacklist = {},
			previous_players_encountered = {},
		},		
	}
	
	self.db = LibStub('AceDB-3.0'):New('GuidWardenDB', defaults, true)
	db = self.db.global
	
	self:RegisterEvent('UNIT_TARGET')
	self:Print('loaded')
end