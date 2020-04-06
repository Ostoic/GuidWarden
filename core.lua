local GuidWarden = LibStub("AceAddon-3.0"):NewAddon('GuidWarden', 'AceConsole-3.0', "AceEvent-3.0")
local db

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
			get = 'isMonitoringAll',
			set = 'toggleMonitorAll',
		},
		
		debug = {
			type = 'toggle',
			name = 'Debug',
			desc = 'Enables debug messages to be displayed',
			get = 'isDebug',
			set = 'toggleDebug',
		},
	}
}

function GuidWarden:isMonitoringAll(info)
	return db.monitorAll
end

function GuidWarden:toggleMonitorAll(info, value)
	db.monitorAll = value
end

function GuidWarden:isDebug(info)
	return db.debug
end

function GuidWarden:toggleDebug(info, value)
	db.debug = value
end

function GuidWarden:Debug(format, ...)
	if db.debug then
		self:Print(string.format(format, ...))
	end
end

function GuidWarden:addEncounter(guid, name, realm, class, race, gender)
	if name == nil or realm == nil or class == nil or race == nil or gender == nil then
		class, _, race, _, gender, name, realm = GetPlayerInfoByGUID(guid)
	end
	
  if realm == '' then
	realm = GetRealmName()
  end
	
	self:Debug('[GuidWarden:addEncounter] %s (%s)', name or 'nil', guid)
	
	if name == nil or realm == nil or class == nil or race == nil or gender == nil then
		self:Print('Failed to add ' .. guid .. ' to database')
		self:Print(string.format(
			'name: %s, realm: %s, guid: %s, gender: %s, race: %s, class: %s',
			name or 'nil', realm or 'nil', guid or 'nil', gender or 'nil', race or 'nil', class or 'nil'
		))
		return
	end
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
      
		self:Debug('[GuidWarden:addEncounter] new')
      return 'new'
   end
   
   for _, encounter in ipairs(encounters) do
	  -- We are unable to tell whether our faction or our target's faction
	  -- has changed as a consequene of mercenary battlegrounds
	  if UnitInBattleground('player') then	  
		  if encounter['name'] == name 
		  and encounter['realm'] == realm 
		  and encounter['class'] == class
		  and encounter['gender'] == genderTable[gender] then 
			 encounter['date'] = date()
			self:Debug('[GuidWarden:addEncounter] updated')
			 return 'updated'
		  end
	  else	  
		  if encounter['name'] == name 
		  and encounter['realm'] == realm 
		  and encounter['class'] == class 
		  and encounter['race'] == race 
		  and encounter['gender'] == genderTable[gender] then 
			 encounter['date'] = date()
			self:Debug('[GuidWarden:addEncounter] updated')
			 return 'updated'
		  end
	  end
   end
   
   -- New distince encounter of known player
   table.insert(encounters, {
         name = name,
         realm = realm,
         class = class,
         race = race,
         gender = genderTable[gender],
         date = date()
   })
   
	self:Debug('[GuidWarden:addEncounter] conflict')
   return 'conflict'
end

function GuidWarden:addBlacklist(guid)
	self:Debug('[GuidWarden:addBlacklist] ' .. guid)
   db.blacklist[guid] = db.previous_players_encountered[guid]
end

function GuidWarden:UNIT_TARGET()
  if not UnitIsPlayer('target') then 
	 return
  end
  
  local guid = UnitGUID('target')
  local class, _, race, _, gender, name, realm = GetPlayerInfoByGUID(guid)
  if realm == '' then
	realm = GetRealmName()
  end
  
	self:Debug('[GuidWarden:UNIT_TARGET] ')
  if (not self:isMonitoringAll() and db.blacklist[guid] ~= nil) or self:isMonitoringAll() then
	local result = self:addEncounter(guid, name, realm, class, race, UnitSexgender)
	if result == 'conflict' then
		self:Print(string.format('Player %s seen with conflicting player data', name))
		self:Print('Perform a "/guid lookup <name>" for more details')
	end
  end
end

function GuidWarden:blacklistTarget()
	if not UnitIsPlayer('target') then return end
	self:Debug('[GuidWarden:blacklistTarget] ')
	
	local guid = UnitGUID('target')
	if guid == nil then return end
	local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
	
	self:addEncounter(guid)
	self:addBlacklist(guid)
	self:Print(string.format('Player %s (%s) added', name, guid))
end

function GuidWarden:lookup(name)
	self:Debug('[GuidWarden:lookup] ' .. name)
	local lowered_name = string.lower(name)
	for guid, encounters in pairs(db.previous_players_encountered) do
		for i, data in ipairs(encounters) do
			if string.lower(data['name']) == lowered_name then
				return guid, encounters
			end
		end
	end
	
	return nil
end

function GuidWarden:ChatHandler(msg)
	local substrings = {strsplit(' ', msg)}
	if #substrings == 0 then 
        InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	end
	
	local command = string.lower(substrings[1])
	if #substrings == 1 and msg == 'add' then
		self:blacklistTarget()
		
	elseif #substrings >= 1 and command == 'lookup' then
		local name
		if #substrings >= 2 then
			name = substrings[2]
		else
			name = UnitName('target')
		end
		
		self:Debug(name)
		
		local guid, encounters = self:lookup(name)
		
		if guid == nil then
			self:Print(string.format(
				'Unable to find player %s in player encounters',
				name
			))
			
		else
			self:Print(string.format(
				'Player %s (%s) found with the following data:',
				name, guid
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

function GuidWarden:OnInitialize()
	LibStub("AceConfig-3.0"):RegisterOptionsTable('GuidWarden', options)
	
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions('GuidWarden', 'GuidWarden')
	self:RegisterChatCommand('gw', 'ChatHandler')
	self:RegisterChatCommand('guid', 'ChatHandler')
end

function GuidWarden:OnEnable()
	local defaults = {
		global = {
			monitorAll = false,
			debug = false,
			blacklist = {},
			previous_players_encountered = {},
		},		
	}
	
	self.db = LibStub('AceDB-3.0'):New('GuidWardenDB', defaults, true)
	db = self.db.global
	
	self:RegisterEvent('UNIT_TARGET')
	self:Print('loaded')
end