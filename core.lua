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

function GuidWarden:Debug(format, ...)
	if db.debug then
		self:Print(string.format(format, ...))
	end
end

function GuidWarden:AddEncounter(guid, name, realm, class, race, gender)
	if name == nil or realm == nil or class == nil or race == nil or gender == nil then
		class, _, race, _, gender, name, realm = GetPlayerInfoByGUID(guid)
	end
	
  if realm == '' then
	realm = GetRealmName()
  end
	
	self:Debug('[GuidWarden:AddEncounter] %s (%s)', name or 'nil', guid)
	
	if self:InBG() or name == nil or realm == nil or class == nil or race == nil or gender == nil then
		self:Debug('Failed to add ' .. guid .. ' to database')
		self:Debug(string.format(
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
      
		self:Debug('[GuidWarden:AddEncounter] new')
      return 'new'
   end
   
   for _, encounter in ipairs(encounters) do
	  -- We are unable to tell whether our faction or our target's faction
	  -- has changed as a consequene of mercenary battlegrounds
	  if encounter['name'] == name 
	  and encounter['realm'] == realm 
	  and encounter['class'] == class 
	  and encounter['race'] == race 
	  and encounter['gender'] == genderTable[gender] then 
		 encounter['date'] = date()
		self:Debug('[GuidWarden:AddEncounter] updated')
		 return 'updated'
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
   
	self:Debug('[GuidWarden:AddEncounter] conflict')
   return 'conflict'
end

function GuidWarden:AddBlacklist(guid)
	self:Debug('[GuidWarden:AddBlacklist] ' .. guid)
   db.blacklist[guid] = db.previous_players_encountered[guid]
end

function GuidWarden:UNIT_TARGET()
  if not UnitIsPlayer('target') or self:InBG() then 
	 return
  end
  
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
	if not UnitIsPlayer('target') or self:InBG() then return end
	self:Debug('[GuidWarden:BlacklistTarget] ')
	
	local guid = UnitGUID('target')
	if guid == nil then return end
	local _, _, _, _, _, name = GetPlayerInfoByGUID(guid)
	
	self:AddEncounter(guid)
	self:AddBlacklist(guid)
	self:Print(string.format('Player %s (%s) added', name, guid))
end

function GuidWarden:Lookup(name)
	self:Debug('[GuidWarden:Lookup] looking for' .. name)
	local lowered_name = string.lower(name)
	for guid, encounters in pairs(db.previous_players_encountered) do
		for i, data in ipairs(encounters) do
			if data and data['name'] and string.lower(data['name']) == lowered_name then
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
	if not self:InBG() and #substrings == 1 and msg == 'add' then
		self:BlacklistTarget()
		
	elseif #substrings >= 1 and command == 'lookup' then
		local name
		if #substrings >= 2 then
			name = substrings[2]
		else
			name = UnitName('target')
		end
		
		self:Debug(name)
		
		local guid, encounters = self:Lookup(name)
		
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
			blacklist = {},
			previous_players_encountered = {},
		},		
	}
	
	self.db = LibStub('AceDB-3.0'):New('GuidWardenDB', defaults, true)
	db = self.db.global
	
	self:RegisterEvent('UNIT_TARGET')
	self:Print('loaded')
end