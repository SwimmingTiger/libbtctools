local configurator = {}

local utils = require ("utils")
local http = require ("http")

function configurator.doMakeRequest(context)
    local step = context:stepName()
    local ip = context:miner():ip()
    local miner = context:miner()
	local typeStr = miner:typeStr()
    
    context:setCanYield(true)
    
    if (step == "begin") then
        local request = {
			method = 'GET',
			host = ip,
			path = '/cgi-bin/minerConfiguration.cgi',
		}
		
		context:setRequestHost(ip)
		context:setRequestPort("80")
		context:setRequestContent(http.makeRequest(request))
		context:setStepName("auth")
        miner:setStat('login...')
	elseif (step == "getMinerConf") then
		context:setStepName("parseMinerConf")
        miner:setStat('read config...')
    elseif (step == "setMinerConf") then
		context:setStepName("parseResult")
        miner:setStat('update config...')
	else
		context:setStepName("end")
		context:miner():setStat("inner error: unknown step name: " .. step)
    end
end

function configurator.doMakeResult(context, response, stat)
    local step = context:stepName()
    local miner = context:miner()
    
    context:setCanYield(true)
    miner:setStat(stat)
    
	response = http.parseResponse(response)
    
    if (step == "auth") then
		if (response.statCode == "401") then
			local request = http.parseRequest(context:requestContent())
			local requestContent, err = http.makeAuthRequest(request, response, 'root', 'root')
			
			if (err) then
				context:setStepName("end")
				context:miner():setStat('failed: ' .. err)
			else
				context:setStepName("getMinerConf")
				context:setRequestContent(requestContent)
			end
		else
			context:setStepName("end")
			context:miner():setStat("read config failed")
		end
	elseif (step == "parseMinerConf") then
		if (response.statCode == "401") then
			context:setStepName("end")
			context:miner():setStat("login failed")
		else
            local request = http.parseRequest(context:requestContent())
            local miner = context:miner()
            local pool1, pool2, pool3 = miner:pool1(), miner:pool2(), miner:pool3()
            
            -- the default failed order of keys
            local formKeys = {
                "_ant_pool1url",
                "_ant_pool1user",
                "_ant_pool1pw",
                "_ant_pool2url",
                "_ant_pool2user",
                "_ant_pool2pw",
                "_ant_pool3url",
                "_ant_pool3user",
                "_ant_pool3pw"
            }
            
            -- Auto detecting the order of keys.
            -- It's so important because the miner's cgi script hardcoded the orders when parse params.

            local formKeysJsonStr = string.match(response.body, "data%s*:%s*{(.-)}%s*,%s*[\r\n]")
            formKeysJsonStr = '[' .. string.gsub(formKeysJsonStr, "([a-zA-Z0-9_-]+):[a-zA-Z0-9_-]+", '"%1"') .. ']'
            local newFormKeys, pos, err = utils.jsonDecode (formKeysJsonStr)
            
            if (not err) and (type(newFormKeys) == "table") and (#newFormKeys >= #formKeys) then
                formKeys = newFormKeys
            else
                print("inexpectant newFormKeys:")
                utils.print(formKeys)
            end
            
            -- All known form params from Antminer S4 to S9
            
            local formParams = {
                _ant_pool1url = pool1:url(),
                _ant_pool1user = pool1:worker(),
                _ant_pool1pw = pool1:passwd(),
                _ant_pool2url = pool2:url(),
                _ant_pool2user = pool2:worker(),
                _ant_pool2pw = pool2:passwd(),
                _ant_pool3url = pool3:url(),
                _ant_pool3user = pool3:worker(),
                _ant_pool3pw = pool3:passwd(),
                _ant_nobeeper = "false",
                _ant_notempoverctrl = "false",
                _ant_fan_customize_switch = "false",
                _ant_fan_customize_value = "",
                _ant_freq = "",
                _ant_voltage = ""
            }
            
            local bmconfJsonStr = string.match(response.body, "ant_data%s*=%s*({.-})%s*;%s*[\r\n]")
            local bmconf, pos, err = utils.jsonDecode (bmconfJsonStr)
            
            if not (err) then
                if (bmconf['bitmain-nobeeper']) then
                    formParams._ant_nobeeper = bmconf['bitmain-nobeeper']
                end
                
                if (bmconf['bitmain-notempoverctrl']) then
                    formParams._ant_notempoverctrl = bmconf['bitmain-notempoverctrl']
                end
                
                if (bmconf['bitmain-fan-ctrl']) then
                    formParams._ant_fan_customize_switch = bmconf['bitmain-fan-ctrl']
                    formParams._ant_fan_customize_value = bmconf['bitmain-fan-pwm']
                end
                
                if (bmconf['bitmain-freq']) then
                    formParams._ant_freq = bmconf['bitmain-freq']
                end
                
                if (bmconf['bitmain-voltage']) then
                    formParams._ant_voltage = bmconf['bitmain-voltage']
                end
            end
            
            request.method = 'POST';
            request.path = '/cgi-bin/set_miner_conf.cgi';
            request.headers['Content-Type'] = 'application/x-www-form-urlencoded'
            request.body = utils.makeUrlQueryString(formParams, formKeys)
            
            loginPassword = utils.getMinerLoginPassword(miner:fullTypeStr())
            
            if (loginPassword == nil) then
                context:setStepName("end")
                context:miner():setStat("require password")
            else
                local requestContent, err = http.makeAuthRequest(request, response, loginPassword.userName, loginPassword.password)
        
			    if (err) then
			    	context:setStepName("end")
			    	context:miner():setStat('failed: ' .. err)
			    else
			    	context:setStepName("setMinerConf")
			    	context:setRequestContent(requestContent)
                end
            end
		end
    elseif (step == "parseResult") then
        if (response.statCode == "401") then
			context:setStepName("end")
			context:miner():setStat("login failed")
		else
            context:setStepName("end")
			context:miner():setStat(utils.trimAll(response.body))
        end
	else
		context:setStepName("end")
		context:miner():setStat("inner error: unknown step name: " .. step)
    end
end

return configurator
