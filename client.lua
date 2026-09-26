ESX = nil
local PlayerData = {}
local missionActive = false
local currentVehicle = nil
local deliveryBlip = nil
local deliveryMarker = nil
local currentDeliveryNumber = 1
local trackedVehicles = {}
local outOfVehicleTimer = 0
local isOutOfVehicle = false
local missionStartTime = 0
local hasGPSJammer = false
local gpsJammerActive = false
local gpsJammerEndTime = 0
local currentEvent = nil
local eventActive = false

Citizen.CreateThread(function()
    while ESX == nil do
        TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)
        Citizen.Wait(0)
    end
    
    while ESX.GetPlayerData().job == nil do
        Citizen.Wait(10)
    end
    
    PlayerData = ESX.GetPlayerData()
end)

RegisterNetEvent('esx:playerLoaded')
AddEventHandler('esx:playerLoaded', function(xPlayer)
    PlayerData = xPlayer
end)

RegisterNetEvent('esx:setJob')
AddEventHandler('esx:setJob', function(job)
    PlayerData.job = job
end)

-- Crea il NPC
Citizen.CreateThread(function()
    RequestModel(GetHashKey(Config.NPCLocation.model))
    while not HasModelLoaded(GetHashKey(Config.NPCLocation.model)) do
        Wait(1)
    end

    local npc = CreatePed(4, GetHashKey(Config.NPCLocation.model), Config.NPCLocation.coords.x, Config.NPCLocation.coords.y, Config.NPCLocation.coords.z, Config.NPCLocation.heading, false, true)
    SetEntityHeading(npc, Config.NPCLocation.heading)
    FreezeEntityPosition(npc, true)
    SetEntityInvincible(npc, true)
    SetBlockingOfNonTemporaryEvents(npc, true)
end)

-- Marker e interazione con NPC
Citizen.CreateThread(function()
    while true do
        local sleep = 1000
        local playerPed = PlayerPedId()
        local playerCoords = GetEntityCoords(playerPed)
        local distance = #(playerCoords - Config.NPCLocation.coords)

        if distance < 20.0 then
            sleep = 0
            DrawMarker(27, Config.NPCLocation.coords.x, Config.NPCLocation.coords.y, Config.NPCLocation.coords.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.5, 1.5, 1.0, 255, 0, 0, 200, false, true, 2, false, nil, nil, false)

            if distance < 2.0 and not missionActive then
                ESX.ShowHelpNotification('Premi ~INPUT_CONTEXT~ per parlare con il contatto')
                
                if IsControlJustReleased(0, 38) then
                    OpenNPCMenu()
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

function OpenNPCMenu()
    local elements = {
        {label = '🚗 Inizia Furto Veicolo', value = 'start_mission'},
    }
    
    if Config.GPSJammerEnabled then
        local jammerLabel = hasGPSJammer and '📡 GPS Jammer (Posseduto)' or '📡 Compra GPS Jammer ($' .. Config.GPSJammerPrice .. ')'
        table.insert(elements, {label = jammerLabel, value = 'buy_jammer'})
    end
    
    table.insert(elements, {label = '❌ Chiudi', value = 'close'})

    ESX.UI.Menu.CloseAll()
    ESX.UI.Menu.Open('default', GetCurrentResourceName(), 'npc_menu', {
        title    = 'Contatto Furto Veicoli',
        align    = 'top-left',
        elements = elements
    }, function(data, menu)
        if data.current.value == 'start_mission' then
            menu.close()
            StartVehicleTheft()
        elseif data.current.value == 'buy_jammer' then
            if hasGPSJammer then
                ESX.ShowNotification('~o~Hai già un GPS Jammer!')
            else
                menu.close()
                BuyGPSJammer()
            end
        elseif data.current.value == 'close' then
            menu.close()
        end
    end, function(data, menu)
        menu.close()
    end)
end

function BuyGPSJammer()
    ESX.TriggerServerCallback('esx_vehicle_theft:buyJammer', function(success)
        if success then
            hasGPSJammer = true
            ESX.ShowNotification('~g~Hai acquistato un GPS Jammer! Usalo con ~b~/usejammer')
        else
            ESX.ShowNotification('~r~Non hai abbastanza soldi! Serve $' .. Config.GPSJammerPrice)
        end
    end)
end

RegisterCommand('usejammer', function()
    if not hasGPSJammer then
        ESX.ShowNotification('~r~Non hai un GPS Jammer!')
        return
    end
    
    if not missionActive then
        ESX.ShowNotification('~r~Devi essere in una missione per usare il GPS Jammer!')
        return
    end
    
    if gpsJammerActive then
        ESX.ShowNotification('~o~Il GPS Jammer è già attivo!')
        return
    end
    
    hasGPSJammer = false
    gpsJammerActive = true
    gpsJammerEndTime = GetGameTimer() + (Config.GPSJammerDuration * 1000)
    
    TriggerServerEvent('esx_vehicle_theft:activateJammer', VehToNet(currentVehicle))
    ESX.ShowNotification('~g~GPS Jammer attivato! Tracking disabilitato per ' .. Config.GPSJammerDuration .. ' secondi!')
    
    Citizen.CreateThread(function()
        while gpsJammerActive do
            Citizen.Wait(1000)
            local remainingTime = math.ceil((gpsJammerEndTime - GetGameTimer()) / 1000)
            
            if remainingTime <= 0 then
                gpsJammerActive = false
                TriggerServerEvent('esx_vehicle_theft:deactivateJammer', VehToNet(currentVehicle))
                ESX.ShowNotification('~o~GPS Jammer esaurito! Tracking riattivato!')
                break
            end
        end
    end)
end)

function StartVehicleTheft()
    ESX.TriggerServerCallback('esx_vehicle_theft:checkPolice', function(enoughPolice)
        if not enoughPolice then
            ESX.ShowNotification('~r~Non ci sono forze dell\'ordine in servizio!')
            return
        end
        
        ESX.TriggerServerCallback('esx_vehicle_theft:canStartMission', function(canStart)
            if canStart then
                local vehicleModel = Config.Vehicles[math.random(1, #Config.Vehicles)]
                local deliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
                SpawnVehicleForTheft(vehicleModel, deliveryLocation)
            else
                ESX.ShowNotification('~r~Hai già una missione attiva!')
            end
        end)
    end)
end

function SpawnVehicleForTheft(vehicleModel, deliveryLocation)
    local spawnCoords = Config.NPCLocation.coords + vector3(5.0, 5.0, 0.0)
    
    ESX.Game.SpawnVehicle(vehicleModel, spawnCoords, Config.NPCLocation.heading, function(vehicle)
        currentVehicle = vehicle
        missionActive = true
        currentDeliveryNumber = 1
        deliveryMarker = deliveryLocation
        outOfVehicleTimer = 0
        isOutOfVehicle = false
        missionStartTime = GetGameTimer()
        
        SetVehicleNumberPlateText(vehicle, "STOLEN")
        TaskWarpPedIntoVehicle(PlayerPedId(), vehicle, -1)
        CreateDeliveryBlip(deliveryLocation)
        
        if Config.EnableSpeedBonus then
            ESX.ShowNotification('~g~Porta il veicolo al punto di consegna! (1/3)~n~~y~Bonus velocità: ' .. Config.SpeedBonusTime .. ' sec per +$' .. Config.SpeedBonusAmount)
        else
            ESX.ShowNotification('~g~Porta il veicolo al punto di consegna! (1/3)')
        end
        
        TriggerServerEvent('esx_vehicle_theft:alertPolice', GetEntityCoords(vehicle), vehicleModel)
        TriggerServerEvent('esx_vehicle_theft:startTracking', VehToNet(vehicle))
        
        if Config.RandomEventsEnabled then
            TriggerRandomEvent()
        end
    end)
end

function CreateDeliveryBlip(coords)
    if deliveryBlip then
        RemoveBlip(deliveryBlip)
    end
    
    deliveryBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(deliveryBlip, 1)
    SetBlipDisplay(deliveryBlip, 4)
    SetBlipScale(deliveryBlip, 1.0)
    SetBlipColour(deliveryBlip, 5)
    SetBlipAsShortRange(deliveryBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Punto di Consegna")
    EndTextCommandSetBlipName(deliveryBlip)
    SetBlipRoute(deliveryBlip, true)
end

-- Check consegna veicolo
Citizen.CreateThread(function()
    while true do
        local sleep = 1000

        if missionActive and deliveryMarker then
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local distance = #(playerCoords - deliveryMarker)

            if distance < 50.0 then
                sleep = 0
                DrawMarker(1, deliveryMarker.x, deliveryMarker.y, deliveryMarker.z - 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 8.0, 8.0, 1.0, 0, 255, 0, 100, false, true, 2, false, nil, nil, false)

                if distance < Config.DeliveryDistance then
                    if IsPedInVehicle(playerPed, currentVehicle, false) then
                        ESX.ShowHelpNotification('Premi ~INPUT_CONTEXT~ per consegnare il veicolo')
                        
                        if IsControlJustReleased(0, 38) then
                            DeliverVehicle()
                        end
                    end
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

function DeliverVehicle()
    TaskLeaveVehicle(PlayerPedId(), currentVehicle, 0)
    Citizen.Wait(2000)
    
    local speedBonus = 0
    if Config.EnableSpeedBonus then
        local elapsedTime = (GetGameTimer() - missionStartTime) / 1000
        if elapsedTime <= Config.SpeedBonusTime then
            speedBonus = Config.SpeedBonusAmount
            ESX.ShowNotification('~g~BONUS VELOCITÀ! +$' .. speedBonus)
        end
    end
    
    if currentDeliveryNumber == 1 then
        local chance = math.random(1, 100)
        
        if chance <= Config.SecondMissionChance then
            TriggerServerEvent('esx_vehicle_theft:rewardPlayer', 1, speedBonus)
            local newDeliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
            deliveryMarker = newDeliveryLocation
            currentDeliveryNumber = 2
            missionStartTime = GetGameTimer()
            eventActive = false
            
            CreateDeliveryBlip(newDeliveryLocation)
            
            if Config.EnableSpeedBonus then
                ESX.ShowNotification('~b~Ottimo! Secondo punto! (2/3)~n~~y~' .. Config.SpeedBonusTime .. ' sec per bonus!')
            else
                ESX.ShowNotification('~b~Ottimo! Secondo punto! (2/3)')
            end
            
            if Config.RandomEventsEnabled then
                TriggerRandomEvent()
            end
        else
            TriggerServerEvent('esx_vehicle_theft:rewardPlayer', 1, speedBonus)
            ESX.ShowNotification('~g~Missione completata! $' .. (1500 + speedBonus))
            EndMission()
        end
    elseif currentDeliveryNumber == 2 then
        local chance = math.random(1, 100)
        
        if chance <= Config.ThirdMissionChance then
            TriggerServerEvent('esx_vehicle_theft:rewardPlayer', 2, speedBonus)
            local newDeliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
            deliveryMarker = newDeliveryLocation
            currentDeliveryNumber = 3
            missionStartTime = GetGameTimer()
            eventActive = false
            
            CreateDeliveryBlip(newDeliveryLocation)
            
            if Config.EnableSpeedBonus then
                ESX.ShowNotification('~b~Ultimo giro! Jackpot! (3/3)~n~~y~' .. Config.SpeedBonusTime .. ' sec per bonus!')
            else
                ESX.ShowNotification('~b~Ultimo giro! Jackpot! (3/3)')
            end
            
            if Config.RandomEventsEnabled then
                TriggerRandomEvent()
            end
        else
            TriggerServerEvent('esx_vehicle_theft:rewardPlayer', 2, speedBonus)
            ESX.ShowNotification('~g~Missione completata! $3000 totali')
            EndMission()
        end
    else
        TriggerServerEvent('esx_vehicle_theft:rewardPlayer', 3, speedBonus)
        ESX.ShowNotification('~g~JACKPOT! $5000 totali!')
        EndMission()
    end
end

function EndMission()
    TriggerServerEvent('nge_carrobbery:endMission')
    if deliveryBlip then
        RemoveBlip(deliveryBlip)
        deliveryBlip = nil
    end
    
    if currentVehicle then
        TriggerServerEvent('esx_vehicle_theft:stopTracking', VehToNet(currentVehicle))
        ESX.Game.DeleteVehicle(currentVehicle)
        currentVehicle = nil
    end
    
    missionActive = false
    deliveryMarker = nil
    currentDeliveryNumber = 1
    outOfVehicleTimer = 0
    isOutOfVehicle = false
    missionStartTime = 0
    gpsJammerActive = false
    gpsJammerEndTime = 0
    currentEvent = nil
    eventActive = false
end

-- Timer fuori veicolo
Citizen.CreateThread(function()
    while true do
        local sleep = 1000

        if missionActive and currentVehicle then
            local playerPed = PlayerPedId()
            
            if IsPedInVehicle(playerPed, currentVehicle, false) then
                outOfVehicleTimer = 0
                isOutOfVehicle = false
            else
                if not isOutOfVehicle then
                    isOutOfVehicle = true
                    outOfVehicleTimer = GetGameTimer()
                    ESX.ShowNotification('~o~Risali sul veicolo entro 60 secondi!')
                else
                    local elapsedTime = (GetGameTimer() - outOfVehicleTimer) / 1000
                    local remainingTime = Config.OutOfVehicleTimeout - elapsedTime
                    
                    if remainingTime <= 30 and remainingTime > 25 then
                        ESX.ShowNotification('~o~' .. math.floor(remainingTime) .. ' secondi!')
                    elseif remainingTime <= 10 and remainingTime > 9 then
                        ESX.ShowNotification('~r~10 secondi!')
                    end
                    
                    if elapsedTime >= Config.OutOfVehicleTimeout then
                        ESX.ShowNotification('~r~Missione fallita! Troppo tempo fuori dal veicolo!')
                        EndMission()
                    end
                end
            end
        else
            outOfVehicleTimer = 0
            isOutOfVehicle = false
        end

        Citizen.Wait(sleep)
    end
end)

-- Eventi casuali
function TriggerRandomEvent()
    if not Config.RandomEventsEnabled then return end
    
    Citizen.CreateThread(function()
        Citizen.Wait(math.random(30000, 90000))
        
        if not missionActive or eventActive then return end
        
        local roll = math.random(1, 100)
        
        for _, event in pairs(Config.RandomEvents) do
            if roll <= event.chance then
                currentEvent = event
                eventActive = true
                
                ESX.ShowNotification(event.message)
                PlaySoundFrontend(-1, "CHECKPOINT_MISSED", "HUD_MINI_GAME_SOUNDSET", 1)
                
                if event.name == 'flat_tire' then
                    HandleFlatTire(event.duration)
                elseif event.name == 'fuel_leak' then
                    HandleFuelLeak(event.duration)
                end
                
                break
            end
        end
    end)
end

function HandleFlatTire(duration)
    if not currentVehicle then return end
    
    local tireIndex = math.random(0, 3)
    SetVehicleTyreBurst(currentVehicle, tireIndex, true, 1000.0)
    
    local repairTime = GetGameTimer() + (duration * 1000)
    
    Citizen.CreateThread(function()
        while eventActive and missionActive do
            Citizen.Wait(1000)
            
            local remainingTime = math.ceil((repairTime - GetGameTimer()) / 1000)
            
            if GetVehicleEngineHealth(currentVehicle) > 900 and not IsVehicleTyreBurst(currentVehicle, tireIndex, false) then
                ESX.ShowNotification('~g~Riparato! Continua!')
                eventActive = false
                break
            end
            
            if remainingTime <= 0 then
                ESX.ShowNotification('~r~Tempo scaduto! Missione fallita!')
                EndMission()
                break
            elseif remainingTime <= 10 and remainingTime % 5 == 0 then
                ESX.ShowNotification('~o~Ripara in ' .. remainingTime .. ' sec!')
            end
        end
    end)
end

function HandleFuelLeak(duration)
    if not currentVehicle then return end
    
    local deadlineTime = GetGameTimer() + (duration * 1000)
    ESX.ShowNotification('~y~Corri alla consegna!')
    
    Citizen.CreateThread(function()
        while eventActive and missionActive do
            Citizen.Wait(1000)
            
            local remainingTime = math.ceil((deadlineTime - GetGameTimer()) / 1000)
            
            if remainingTime <= 0 then
                SetVehicleEngineHealth(currentVehicle, 0.0)
                SetVehicleUndriveable(currentVehicle, true)
                ESX.ShowNotification('~r~Motore bloccato! Missione fallita!')
                EndMission()
                break
            elseif remainingTime <= 30 and remainingTime % 10 == 0 then
                ESX.ShowNotification('~r~' .. remainingTime .. ' secondi!')
            end
        end
    end)
end

-- Sistema tracking per FDO
RegisterNetEvent('esx_vehicle_theft:updateTracking')
AddEventHandler('esx_vehicle_theft:updateTracking', function(netId, coords)
    if not trackedVehicles[netId] then
        trackedVehicles[netId] = {blip = nil, coords = coords}
    end
    
    trackedVehicles[netId].coords = coords
    
    if PlayerData.job and isPoliceJob(PlayerData.job.name) then
        if not trackedVehicles[netId].blip then
            local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
            SetBlipSprite(blip, 225)
            SetBlipDisplay(blip, 4)
            SetBlipScale(blip, 1.0)
            SetBlipColour(blip, 1)
            SetBlipAsShortRange(blip, false)
            BeginTextCommandSetBlipName("STRING")
            AddTextComponentString("Veicolo Rubato")
            EndTextCommandSetBlipName(blip)
            
            trackedVehicles[netId].blip = blip
        else
            SetBlipCoords(trackedVehicles[netId].blip, coords.x, coords.y, coords.z)
        end
    end
end)

RegisterNetEvent('esx_vehicle_theft:removeTracking')
AddEventHandler('esx_vehicle_theft:removeTracking', function(netId)
    if trackedVehicles[netId] then
        if trackedVehicles[netId].blip then
            RemoveBlip(trackedVehicles[netId].blip)
        end
        trackedVehicles[netId] = nil
    end
end)

RegisterNetEvent('esx_vehicle_theft:policeAlert')
AddEventHandler('esx_vehicle_theft:policeAlert', function(coords, vehicleModel)
    if PlayerData.job and isPoliceJob(PlayerData.job.name) then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 161)
        SetBlipScale(blip, 1.5)
        SetBlipColour(blip, 1)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Furto Veicolo")
        EndTextCommandSetBlipName(blip)
        
        Citizen.SetTimeout(30000, function()
            RemoveBlip(blip)
        end)
        
        PlaySoundFrontend(-1, "CONFIRM_BEEP", "HUD_MINI_GAME_SOUNDSET", 1)
        ESX.ShowAdvancedNotification('Centrale', '~r~Allarme', 'Furto ' .. vehicleModel .. '!', 'CHAR_CALL911', 1)
    end
end)

RegisterNetEvent('esx_vehicle_theft:jammerActivated')
AddEventHandler('esx_vehicle_theft:jammerActivated', function(netId)
    if PlayerData.job and isPoliceJob(PlayerData.job.name) then
        if trackedVehicles[netId] and trackedVehicles[netId].blip then
            SetBlipColour(trackedVehicles[netId].blip, 8)
            SetBlipAlpha(trackedVehicles[netId].blip, 128)
        end
        
        ESX.ShowNotification('~o~GPS Jammer rilevato!')
        PlaySoundFrontend(-1, "CHECKPOINT_MISSED", "HUD_MINI_GAME_SOUNDSET", 1)
    end
end)

RegisterNetEvent('esx_vehicle_theft:jammerDeactivated')
AddEventHandler('esx_vehicle_theft:jammerDeactivated', function(netId)
    if PlayerData.job and isPoliceJob(PlayerData.job.name) then
        if trackedVehicles[netId] and trackedVehicles[netId].blip then
            SetBlipColour(trackedVehicles[netId].blip, 1)
            SetBlipAlpha(trackedVehicles[netId].blip, 255)
        end
        
        ESX.ShowNotification('~g~Tracking ripristinato!')
    end
end)

function isPoliceJob(jobName)
    for _, job in pairs(Config.PoliceJobs) do
        if job == jobName then
            return true
        end
    end
    return false
end