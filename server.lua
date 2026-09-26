ESX = nil
local activeMissions = {}
local trackedVehicles = {}
local jammedVehicles = {}

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)

-- Callback controllo polizia online
ESX.RegisterServerCallback('esx_vehicle_theft:checkPolice', function(source, cb)
    local policeCount = 0
    local xPlayers = ESX.GetPlayers()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    policeCount = policeCount + 1
                    break
                end
            end
        end
    end
    
    cb(policeCount >= Config.MinPoliceOnline)
end)

-- Callback inizio missione
ESX.RegisterServerCallback('esx_vehicle_theft:canStartMission', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if activeMissions[xPlayer.identifier] then
        cb(false)
    else
        activeMissions[xPlayer.identifier] = {
            source = source,
            stage = 1,
            stageStartedAt = os.time(),
            netId = nil
        }
        cb(true)
    end
end)

-- Callback acquisto GPS Jammer
ESX.RegisterServerCallback('esx_vehicle_theft:buyJammer', function(source, cb)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then 
        cb(false)
        return
    end
    
    local playerMoney = 0
    
    if Config.MoneyAccount == 'money' then
        playerMoney = xPlayer.getMoney()
    elseif Config.MoneyAccount == 'black_money' then
        playerMoney = xPlayer.getAccount('black_money').money
    elseif Config.MoneyAccount == 'bank' then
        playerMoney = xPlayer.getAccount('bank').money
    end
    
    if playerMoney >= Config.GPSJammerPrice then
        if Config.MoneyAccount == 'money' then
            xPlayer.removeMoney(Config.GPSJammerPrice)
        elseif Config.MoneyAccount == 'black_money' then
            xPlayer.removeAccountMoney('black_money', Config.GPSJammerPrice)
        elseif Config.MoneyAccount == 'bank' then
            xPlayer.removeAccountMoney('bank', Config.GPSJammerPrice)
        end
        
        cb(true)
    else
        cb(false)
    end
end)

-- Ricompensa player
RegisterNetEvent('esx_vehicle_theft:rewardPlayer')
AddEventHandler('esx_vehicle_theft:rewardPlayer', function(_clientDeliveryNumber, _clientSpeedBonus)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local mission = activeMissions[xPlayer.identifier]
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

    if Config.MoneyAccount == 'money' then
        xPlayer.addMoney(totalReward)
        xPlayer.showNotification(('~g~Ricompensa: %s'):format(totalReward))
    elseif Config.MoneyAccount == 'black_money' then
        xPlayer.addAccountMoney('black_money', totalReward)
        xPlayer.showNotification(('~g~Ricompensa sporca: %s'):format(totalReward))
    elseif Config.MoneyAccount == 'bank' then
        xPlayer.addAccountMoney('bank', totalReward)
        xPlayer.showNotification(('~g~Ricompensa banca: %s'):format(totalReward))
    end

    if stage >= 3 then
        activeMissions[xPlayer.identifier] = nil
    else
        mission.stage = stage + 1
        mission.stageStartedAt = os.time()
    end
end)

-- Alert polizia
RegisterNetEvent('esx_vehicle_theft:alertPolice')
AddEventHandler('esx_vehicle_theft:alertPolice', function(coords, vehicleModel)
    local xPlayers = ESX.GetPlayers()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:policeAlert', xPlayers[i], coords, vehicleModel)
                end
            end
        end
    end
end)

-- Tracking veicolo
RegisterNetEvent('esx_vehicle_theft:startTracking')
AddEventHandler('esx_vehicle_theft:startTracking', function(netId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local mission = activeMissions[xPlayer.identifier]
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
                        
                        local xPlayers = ESX.GetPlayers()
                        for i=1, #xPlayers, 1 do
                            local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
                            
                            if xPlayer then
                                for _, job in pairs(Config.PoliceJobs) do
                                    if xPlayer.job.name == job then
                                        TriggerClientEvent('esx_vehicle_theft:updateTracking', xPlayers[i], netId, coords)
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

RegisterNetEvent('esx_vehicle_theft:stopTracking')
AddEventHandler('esx_vehicle_theft:stopTracking', function(netId)
    if trackedVehicles[netId] then
        trackedVehicles[netId].active = false
        trackedVehicles[netId] = nil
        
        TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
    end
end)

-- GPS Jammer
RegisterNetEvent('esx_vehicle_theft:activateJammer')
AddEventHandler('esx_vehicle_theft:activateJammer', function(netId)
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end
    local mission = activeMissions[xPlayer.identifier]
    if not mission or mission.netId ~= netId then
        print(('[CAR ROBBERY] Rejected jammer activation from %s'):format(src))
        return
    end
    jammedVehicles[netId] = true
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerActivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

RegisterNetEvent('esx_vehicle_theft:deactivateJammer')
AddEventHandler('esx_vehicle_theft:deactivateJammer', function(netId)
    jammedVehicles[netId] = nil
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerDeactivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

-- Pulizia disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if xPlayer then
        activeMissions[xPlayer.identifier] = nil
    end
    
    for netId, data in pairs(trackedVehicles) do
        if data.source == src then
            trackedVehicles[netId] = nil
            TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
        end
    end
end) .. totalReward)
    elseif Config.MoneyAccount == 'black_money' then
        xPlayer.addAccountMoney('black_money', totalReward)
        xPlayer.showNotification('~g~+

-- Alert polizia
RegisterNetEvent('esx_vehicle_theft:alertPolice')
AddEventHandler('esx_vehicle_theft:alertPolice', function(coords, vehicleModel)
    local xPlayers = ESX.GetPlayers()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:policeAlert', xPlayers[i], coords, vehicleModel)
                end
            end
        end
    end
end)

-- Tracking veicolo
RegisterNetEvent('esx_vehicle_theft:startTracking')
AddEventHandler('esx_vehicle_theft:startTracking', function(netId)
    local src = source
    
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
                        
                        local xPlayers = ESX.GetPlayers()
                        for i=1, #xPlayers, 1 do
                            local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
                            
                            if xPlayer then
                                for _, job in pairs(Config.PoliceJobs) do
                                    if xPlayer.job.name == job then
                                        TriggerClientEvent('esx_vehicle_theft:updateTracking', xPlayers[i], netId, coords)
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

RegisterNetEvent('esx_vehicle_theft:stopTracking')
AddEventHandler('esx_vehicle_theft:stopTracking', function(netId)
    if trackedVehicles[netId] then
        trackedVehicles[netId].active = false
        trackedVehicles[netId] = nil
        
        TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
    end
end)

-- GPS Jammer
RegisterNetEvent('esx_vehicle_theft:activateJammer')
AddEventHandler('esx_vehicle_theft:activateJammer', function(netId)
    jammedVehicles[netId] = true
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerActivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

RegisterNetEvent('esx_vehicle_theft:deactivateJammer')
AddEventHandler('esx_vehicle_theft:deactivateJammer', function(netId)
    jammedVehicles[netId] = nil
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerDeactivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

-- Pulizia disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if xPlayer then
        activeMissions[xPlayer.identifier] = nil
    end
    
    for netId, data in pairs(trackedVehicles) do
        if data.source == src then
            trackedVehicles[netId] = nil
            TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
        end
    end
end) .. totalReward .. ' (sporchi)')
    elseif Config.MoneyAccount == 'bank' then
        xPlayer.addAccountMoney('bank', totalReward)
        xPlayer.showNotification('~g~+

-- Alert polizia
RegisterNetEvent('esx_vehicle_theft:alertPolice')
AddEventHandler('esx_vehicle_theft:alertPolice', function(coords, vehicleModel)
    local xPlayers = ESX.GetPlayers()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:policeAlert', xPlayers[i], coords, vehicleModel)
                end
            end
        end
    end
end)

-- Tracking veicolo
RegisterNetEvent('esx_vehicle_theft:startTracking')
AddEventHandler('esx_vehicle_theft:startTracking', function(netId)
    local src = source
    
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
                        
                        local xPlayers = ESX.GetPlayers()
                        for i=1, #xPlayers, 1 do
                            local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
                            
                            if xPlayer then
                                for _, job in pairs(Config.PoliceJobs) do
                                    if xPlayer.job.name == job then
                                        TriggerClientEvent('esx_vehicle_theft:updateTracking', xPlayers[i], netId, coords)
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

RegisterNetEvent('esx_vehicle_theft:stopTracking')
AddEventHandler('esx_vehicle_theft:stopTracking', function(netId)
    if trackedVehicles[netId] then
        trackedVehicles[netId].active = false
        trackedVehicles[netId] = nil
        
        TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
    end
end)

-- GPS Jammer
RegisterNetEvent('esx_vehicle_theft:activateJammer')
AddEventHandler('esx_vehicle_theft:activateJammer', function(netId)
    jammedVehicles[netId] = true
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerActivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

RegisterNetEvent('esx_vehicle_theft:deactivateJammer')
AddEventHandler('esx_vehicle_theft:deactivateJammer', function(netId)
    jammedVehicles[netId] = nil
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerDeactivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

-- Pulizia disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if xPlayer then
        activeMissions[xPlayer.identifier] = nil
    end
    
    for netId, data in pairs(trackedVehicles) do
        if data.source == src then
            trackedVehicles[netId] = nil
            TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
        end
    end
end) .. totalReward .. ' (banca)')
    end

    if stage >= 3 then
        activeMissions[xPlayer.identifier] = nil
    else
        mission.stage = stage + 1
        mission.stageStartedAt = os.time()
    end
end)

-- Alert polizia
RegisterNetEvent('esx_vehicle_theft:alertPolice')
AddEventHandler('esx_vehicle_theft:alertPolice', function(coords, vehicleModel)
    local xPlayers = ESX.GetPlayers()
    
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:policeAlert', xPlayers[i], coords, vehicleModel)
                end
            end
        end
    end
end)

-- Tracking veicolo
RegisterNetEvent('esx_vehicle_theft:startTracking')
AddEventHandler('esx_vehicle_theft:startTracking', function(netId)
    local src = source
    
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
                        
                        local xPlayers = ESX.GetPlayers()
                        for i=1, #xPlayers, 1 do
                            local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
                            
                            if xPlayer then
                                for _, job in pairs(Config.PoliceJobs) do
                                    if xPlayer.job.name == job then
                                        TriggerClientEvent('esx_vehicle_theft:updateTracking', xPlayers[i], netId, coords)
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

RegisterNetEvent('esx_vehicle_theft:stopTracking')
AddEventHandler('esx_vehicle_theft:stopTracking', function(netId)
    if trackedVehicles[netId] then
        trackedVehicles[netId].active = false
        trackedVehicles[netId] = nil
        
        TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
    end
end)

-- GPS Jammer
RegisterNetEvent('esx_vehicle_theft:activateJammer')
AddEventHandler('esx_vehicle_theft:activateJammer', function(netId)
    jammedVehicles[netId] = true
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerActivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

RegisterNetEvent('esx_vehicle_theft:deactivateJammer')
AddEventHandler('esx_vehicle_theft:deactivateJammer', function(netId)
    jammedVehicles[netId] = nil
    
    local xPlayers = ESX.GetPlayers()
    for i=1, #xPlayers, 1 do
        local xPlayer = ESX.GetPlayerFromId(xPlayers[i])
        
        if xPlayer then
            for _, job in pairs(Config.PoliceJobs) do
                if xPlayer.job.name == job then
                    TriggerClientEvent('esx_vehicle_theft:jammerDeactivated', xPlayers[i], netId)
                end
            end
        end
    end
end)

-- Pulizia disconnect
AddEventHandler('playerDropped', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    
    if xPlayer then
        activeMissions[xPlayer.identifier] = nil
    end
    
    for netId, data in pairs(trackedVehicles) do
        if data.source == src then
            trackedVehicles[netId] = nil
            TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, netId)
        end
    end
end)

RegisterNetEvent('nge_carrobbery:endMission', function()
    local src = source
    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then return end

    local mission = activeMissions[xPlayer.identifier]
    if mission and mission.netId then
        trackedVehicles[mission.netId] = nil
        jammedVehicles[mission.netId] = nil
        TriggerClientEvent('esx_vehicle_theft:removeTracking', -1, mission.netId)
    end

    activeMissions[xPlayer.identifier] = nil
end)
