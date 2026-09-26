local activeMissions = {}
local trackedVehicles = {}
local jammedVehicles = {}

CreateThread(function()
    if not NGEFramework.WaitReady() then error('[nge_carrobbery] framework unavailable') end
end)

-- Callback controllo polizia online
NGEFramework.RegisterCallback('nge_carrobbery:checkPolice', function(source, cb)
    local policeCount = 0
    local xPlayers = NGEFramework.Sources()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = NGEFramework.Get(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if NGEFramework.Job(xPlayer) == job then
                    policeCount = policeCount + 1
                    break
                end
            end
        end
    end
    
    cb(policeCount >= Config.MinPoliceOnline)
end)

-- Callback inizio missione
NGEFramework.RegisterCallback('nge_carrobbery:canStartMission', function(source, cb)
    local xPlayer = NGEFramework.Get(source)
    
    if activeMissions[NGEFramework.Identifier(xPlayer)] then
        cb(false)
    else
        activeMissions[NGEFramework.Identifier(xPlayer)] = {
            source = source,
            stage = 1,
            stageStartedAt = os.time(),
            netId = nil
        }
        cb(true)
    end
end)

-- Callback acquisto GPS Jammer
NGEFramework.RegisterCallback('nge_carrobbery:buyJammer', function(source, cb)
    local xPlayer = NGEFramework.Get(source)
    
    if not xPlayer then 
        cb(false)
        return
    end
    
    if NGEFramework.RemoveMoney(xPlayer, Config.MoneyAccount or 'money', Config.GPSJammerPrice, 'gps-jammer') then
        cb(true)
    else
        cb(false)
    end
end)

-- Ricompensa player
RegisterNetEvent('nge_carrobbery:rewardPlayer')
AddEventHandler('nge_carrobbery:rewardPlayer', function(_clientDeliveryNumber, _clientSpeedBonus)
    local src = source
    local xPlayer = NGEFramework.Get(src)
    if not xPlayer then return end

    local mission = activeMissions[NGEFramework.Identifier(xPlayer)]
    if not mission or mission.source ~= src then
        print(('[CAR ROBBERY] Rejected reward without active mission from %s'):format(src))
        return
    end

    local stage = tonumber(mission.stage) or 1
    local reward
    if stage == 1 then
        reward = Config.FirstDeliveryReward
    elseif stage == 2 then
        reward = Config.SecondDeliveryReward
    elseif stage == 3 then
        reward = Config.ThirdDeliveryReward
    else
        print(('[CAR ROBBERY] Invalid mission stage %s for %s'):format(stage, src))
        return
    end

    local speedBonus = 0
    if Config.EnableSpeedBonus and (os.time() - (mission.stageStartedAt or os.time())) <= (Config.SpeedBonusTime or 0) then
        speedBonus = math.max(0, tonumber(Config.SpeedBonusAmount) or 0)
    end

    local totalReward = math.max(0, (tonumber(reward) or 0) + speedBonus)
    if totalReward <= 0 then return end

    if not NGEFramework.AddMoney(xPlayer, Config.MoneyAccount or 'money', totalReward, 'car-robbery-reward') then
        print(('[CAR ROBBERY] payout failed for %s'):format(tostring(Config.MoneyAccount)))
        return
    end

    if stage >= 3 then
        activeMissions[NGEFramework.Identifier(xPlayer)] = nil
    else
        mission.stage = stage + 1
        mission.stageStartedAt = os.time()
    end
end)

-- Alert polizia
RegisterNetEvent('nge_carrobbery:alertPolice')
AddEventHandler('nge_carrobbery:alertPolice', function()
    local src = source
    local player = NGEFramework.Get(src)
    if not player then return end
    local mission = activeMissions[NGEFramework.Identifier(player)]
    if not mission or not mission.netId then return end

    local vehicle = NetworkGetEntityFromNetworkId(mission.netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    local coords = GetEntityCoords(vehicle)
    local model = tostring(GetEntityModel(vehicle))

    for _, playerId in ipairs(NGEFramework.Sources()) do
        local target = NGEFramework.Get(playerId)
        local job = target and NGEFramework.Job(target)
        for _, allowed in ipairs(Config.PoliceJobs or {}) do
            if job == allowed then
                TriggerClientEvent('nge_carrobbery:policeAlert', playerId, coords, model)
                break
            end
        end
    end
end)

-- Tracking veicolo
RegisterNetEvent('nge_carrobbery:startTracking')
AddEventHandler('nge_carrobbery:startTracking', function(netId)
    local src = source
    local xPlayer = NGEFramework.Get(src)
    if not xPlayer then return end

    local mission = activeMissions[NGEFramework.Identifier(xPlayer)]
    if not mission then return end

    local vehicle = NetworkGetEntityFromNetworkId(netId)
    if not vehicle or vehicle == 0 or not DoesEntityExist(vehicle) then return end
    if NetworkGetEntityOwner(vehicle) ~= src then
        print(('[CAR ROBBERY] Rejected tracking bind for unowned entity from %s'):format(src))
        return
    end

    mission.netId = netId

    if not trackedVehicles[netId] then
        trackedVehicles[netId] = {
            active = true,
            source = src
        }
        
        Citizen.CreateThread(function()
            while trackedVehicles[netId] and trackedVehicles[netId].active do
                local vehicle = NetworkGetEntityFromNetworkId(netId)
                
                if DoesEntityExist(vehicle) then
                    if not jammedVehicles[netId] then
                        local coords = GetEntityCoords(vehicle)
                        
                        local xPlayers = NGEFramework.Sources()
                        for i=1, #xPlayers, 1 do
                            local xPlayer = NGEFramework.Get(xPlayers[i])
                            
                            if xPlayer then
                                for _, job in pairs(Config.PoliceJobs) do
                                    if NGEFramework.Job(xPlayer) == job then
                                        TriggerClientEvent('nge_carrobbery:updateTracking', xPlayers[i], netId, coords)
                                    end
                                end
                            end
                        end
                    end
                else
                    trackedVehicles[netId] = nil
                    break
                end
                
                Citizen.Wait(Config.BlipUpdateInterval)
            end
        end)
    end
end)

RegisterNetEvent('nge_carrobbery:stopTracking')
AddEventHandler('nge_carrobbery:stopTracking', function(netId)
    local src = source
    local player = NGEFramework.Get(src)
    if not player then return end
    local mission = activeMissions[NGEFramework.Identifier(player)]
    if not mission or mission.netId ~= netId then return end
    trackedVehicles[netId] = nil
    jammedVehicles[netId] = nil
    TriggerClientEvent('nge_carrobbery:removeTracking', -1, netId)
end)

-- GPS Jammer
RegisterNetEvent('nge_carrobbery:activateJammer')
AddEventHandler('nge_carrobbery:activateJammer', function(netId)
    local src = source
    local xPlayer = NGEFramework.Get(src)
    if not xPlayer then return end

    local mission = activeMissions[NGEFramework.Identifier(xPlayer)]
    if not mission or mission.netId ~= netId then
        print(('[CAR ROBBERY] Rejected jammer activation from %s'):format(src))
        return
    end

    jammedVehicles[netId] = true
    
    local xPlayers = NGEFramework.Sources()
    for i=1, #xPlayers, 1 do
        local xPlayer = NGEFramework.Get(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if NGEFramework.Job(xPlayer) == job then
                    TriggerClientEvent('nge_carrobbery:jammerActivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

RegisterNetEvent('nge_carrobbery:deactivateJammer')
AddEventHandler('nge_carrobbery:deactivateJammer', function(netId)
    local src = source
    local player = NGEFramework.Get(src)
    if not player then return end
    local mission = activeMissions[NGEFramework.Identifier(player)]
    if not mission or mission.netId ~= netId then return end
    jammedVehicles[netId] = nil
    
    local xPlayers = NGEFramework.Sources()
    for i=1, #xPlayers, 1 do
        local xPlayer = NGEFramework.Get(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if NGEFramework.Job(xPlayer) == job then
                    TriggerClientEvent('nge_carrobbery:jammerDeactivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

-- Pulizia disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = NGEFramework.Get(src)
    
    if xPlayer then
        activeMissions[NGEFramework.Identifier(xPlayer)] = nil
    end
    
    for netId, data in pairs(trackedVehicles) do
        if data.source == src then
            trackedVehicles[netId] = nil
            TriggerClientEvent('nge_carrobbery:removeTracking', -1, netId)
        end
    end
end)

RegisterNetEvent('nge_carrobbery:endMission', function()
    local src = source
    local xPlayer = NGEFramework.Get(src)
    if not xPlayer then return end

    local mission = activeMissions[NGEFramework.Identifier(xPlayer)]
    if mission and mission.netId then
        trackedVehicles[mission.netId] = nil
        jammedVehicles[mission.netId] = nil
        TriggerClientEvent('nge_carrobbery:removeTracking', -1, mission.netId)
    end

    activeMissions[NGEFramework.Identifier(xPlayer)] = nil
end)
