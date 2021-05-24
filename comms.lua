local GuidWarden = LibStub("AceAddon-3.0"):GetAddon('GuidWarden')

function GuidWarden:XorEncrypt(message, key)
	local encrypted = {}
	for i = 1, #message do
		local j = (i % #key) + 1
		local c = nil
		local k = nil
		
		if type(message) == 'string' then
			c = string.byte(message:sub(i, i))
		else
			c = message[i]
		end
		
		if type(key) == 'string' then
			k = string.byte(key:sub(j, j))
		else
			k = key[j]
		end
		encrypted[i] = bit.bxor(c, k)
	end
	
	self:Debug('XorEncrypt #message=%d, #encrypted=%d', #message, #encrypted)
	return encrypted
end

function GuidWarden:Test()
	local original = [[["0x0C00000000029452"] = {
				{
					["race"] = "Tauren",
					["name"] = "Demoniksis",
					["date"] = "05/09/21 16:53:46",
					["class"] = "Death Knight",
					["gender"] = "Male",
					["realm"] = "Frostmourne",
				}, -- [1]
			},]]
			
	local serialized = self:Serialize(original)
	local encrypted = self:XorEncrypt(original, self.api_key)
	self:Debug('original=%s', original)
	self:Debug('serialized=%s', serialized)
	dump('TestEncrypted', encrypted)
	self:Debug('#original=%d, #serialized=%d, #encrypted=%d', #original, #serialized, #encrypted)
end

function GuidWarden:Encrypt(message, key)
	return self:Serialize(self:XorEncrypt(message, key))
end

function GuidWarden:Decrypt(message, key)
	decrypted = self:XorEncrypt(message, key)
	
	local result = ''
	for i = 1, #decrypted do
		result = result .. string.char(decrypted[i])
	end
	
	return result
end

function GuidWarden:SendData(data)
	local serialized = self:Encrypt(data, self.api_key)
	self:Debug(serialized)
	
	GuidWarden:SendCommMessage('GuidWardenComm', serialized, 'GUILD')
end

function GuidWarden:OnCommReceived(prefix, message, distribution, sender)
	self:Debug('Comm received from %s: message=%s', sender, message)
    local success, deserialized = self:Deserialize(message)
	
    if success then
		decrypted = self:Decrypt(deserialized, self.api_key)
		self:Debug('Decrypted message: %s', decrypted)
    end
end
