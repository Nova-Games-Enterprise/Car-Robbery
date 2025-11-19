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
        activeMissions[xPlayer.identifier] = true
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
AddEventHandler('esx_vehicle_theft:rewardPlayer', function(deliveryNumber, speedBonus)
    local xPlayer = ESX.GetPlayerFromId(source)
    
    if not xPlayer then return end
    
    speedBonus = speedBonus or 0
    
    local reward
    if deliveryNumber == 1 then
        reward = Config.FirstDeliveryReward
    elseif deliveryNumber == 2 then
        reward = Config.SecondDeliveryReward
    else
        reward = Config.ThirdDeliveryReward
    end
    
    local totalReward = reward + speedBonus
    
    if Config.MoneyAccount == 'money' then
        xPlayer.addMoney(totalReward)
        xPlayer.showNotification('~g~+$' .. totalReward)
    elseif Config.MoneyAccount == 'black_money' then
        xPlayer.addAccountMoney('black_money', totalReward)
        xPlayer.showNotification('~g~+$' .. totalReward .. ' (sporchi)')
    elseif Config.MoneyAccount == 'bank' then
        xPlayer.addAccountMoney('bank', totalReward)
        xPlayer.showNotification('~g~+$' .. totalReward .. ' (banca)')
    end
    
    if deliveryNumber == 3 or deliveryNumber == 0 then
        activeMissions[xPlayer.identifier] = nil
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