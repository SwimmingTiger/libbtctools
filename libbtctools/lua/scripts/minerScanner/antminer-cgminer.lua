local scanner = {}

local json = require ("lua.scripts.dkjson")
local utils = require ("lua.scripts.utils")


local regularTypeStr = function(fullTypeStr)
    local typeStr = 'unknown'
    local typeLowerStr = string.lower(fullTypeStr)
    
    if (string.match(typeLowerStr, 'antminer')) then
        typeStr = 'antminer'
        
        if (string.match(typeLowerStr, 's3') or string.match(typeLowerStr, 's1')) then
            typeStr = typeStr .. '-openwrt'
        else
            typeStr = typeStr .. '-cgi-sh'
        end
    end
    
    return typeStr
end

local parseMinerStats = function(jsonStr, miner, stat)

    local typeStr = 'unknown'
    local fullTypeStr = 'Unknown'
    
    if (stat == "success") then
        local obj, pos, err = utils.jsonDecode (jsonStr)
        
        if not err then
            local stat = obj.STATS
            
            if (type(stat) == "table" and type(stat[1]) == "table" and type(stat[1].Type) == "string") then
                fullTypeStr = stat[1].Type
            end
            
            typeStr = regularTypeStr(fullTypeStr)
            
            -- find more infos
            if (type(stat) == "table" and type(stat[2]) == "table") then
                local opts = stat[2]
                
                if (opts['GHS 5s'] ~= nil) then
                    miner:setOpt('hashrate_5s', opts['GHS 5s']..' GH/s')
                end
                
                if (opts['GHS av'] ~= nil) then
                    miner:setOpt('hashrate_avg', opts['GHS av']..' GH/s')
                end
                
                if (opts['temp1'] ~= nil) then
                    local temp = {}
                    local i = 1
                    
                    while (opts['temp'..i] ~= nil) do
                        if (opts['temp'..i] > 0) then
                            table.insert(temp, opts['temp'..i])
                        end
                        
                        i = i + 1
                    end
                    
                    miner:setOpt('temperature', table.concat(temp, ' / '))
                end
                
                if (opts['fan1'] ~= nil) then
                    local fan = {}
                    local i = 1
                    
                    while (opts['fan'..i] ~= nil) do
                        if (opts['fan'..i] > 0) then
                            table.insert(fan, opts['fan'..i])
                        end
                        
                        i = i + 1
                    end
                    
                    miner:setOpt('fan_speed', table.concat(fan, ' / '))
                end
                
                if (opts['Elapsed'] ~= nil) then
                    miner:setOpt('elapsed', utils.formatTime(opts['Elapsed'], 'd :h :m :s '))
                end
            end
        end
    else
        fullTypeStr = ''
    end
    
    miner:setTypeStr(typeStr)
    miner:setFullTypeStr(fullTypeStr)
    
    return true
end

local parseMinerPools = function(jsonStr, miner, stat)

    local pool1 = miner:pool1()
    local pool2 = miner:pool2()
    local pool3 = miner:pool3()
    
    local findSuccess = false
    
    if (stat == "success") then
        jsonStr = utils.trimJsonStr(jsonStr)
        local obj, pos, err = json.decode (jsonStr)
        
        if not err then
            local pools = obj.POOLS
            
            if (type(pools) == "table") then
                if (type(pools[1]) == "table") then
                    pool1:setUrl(pools[1].URL)
                    pool1:setWorker(pools[1].User)
                end
                
                if (type(pools[2]) == "table") then
                    pool2:setUrl(pools[2].URL)
                    pool2:setWorker(pools[2].User)
                end
                
                if (type(pools[3]) == "table") then
                    pool3:setUrl(pools[3].URL)
                    pool3:setWorker(pools[3].User)
                end
                
                findSuccess = true
            end
        end
    end
    
    return findSuccess
end

function scanner.doMakeRequest(context)
    local step = context:stepName()
    local miner = context:miner()
    local ip = miner:ip()
    
    context:setCanYield(true)
    
    if (step == "begin") then
        local port = "4028"
        local content = '{"command":"stats"}'
        
        context:setStepName("doFindStats")
        miner:setStat('get status...')
        context:setRequestHost(ip)
        context:setRequestPort(port)
        context:setRequestContent(content)
        
    elseif (step == "findPools") then
        local content = '{"command":"pools"}'
        
        context:setStepName("doFindPools")
        miner:setStat('find pools...')
        context:setRequestContent(content)
		
	else
		context:setStepName("end")
		context:miner():setStat("inner error: unknown step name: " .. step)
    end
    
end

function scanner.doMakeResult(context, response, stat)
    local step = context:stepName()
    local miner = context:miner()
    
    context:setCanYield(true)
    miner:setStat(stat)
    
    if (step == "doFindStats") then
        if (stat == "success") then
            step = "findPools"
        else
            step = "end"
        end
        
        context:setStepName(step)
        parseMinerStats(response, context:miner(), stat)
        
    elseif (step == "doFindPools") then
        context:setStepName("end")
        parseMinerPools(response, context:miner(), stat)
		
	else
		context:setStepName("end")
		context:miner():setStat("inner error: unknown step name: " .. step)
    end
end


return scanner
