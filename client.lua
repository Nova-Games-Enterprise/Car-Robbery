local PlayerJob = nil
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

CreateThread(function()
    if not NGEClient.WaitReady() then
        print('[nge_carrobbery] framework client unavailable')
        return
    end
    while true do
        PlayerJob = NGEClient.Job()
        Wait(2000)
    end
end)

local function SpawnVehicle(modelName, coords, heading, cb)
    local hash = type(modelName) == 'number' and modelName or GetHashKey(modelName)
    RequestModel(hash)
    local timeout = GetGameTimer() + 10000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(0) end
    if not HasModelLoaded(hash) then
        NGEClient.Notify('Impossibile caricare il veicolo.', 'error')
        return
    end
    local vehicle = CreateVehicle(hash, coords.x, coords.y, coords.z, heading or 0.0, true, true)
    SetEntityAsMissionEntity(vehicle, true, true)
    SetModelAsNoLongerNeeded(hash)
    if cb then cb(vehicle) end
end

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
                NGEClient.Help('Premi ~INPUT_CONTEXT~ per parlare con il contatto')
                
                if IsControlJustReleased(0, 38) then
                    OpenNPCMenu()
                end
            end
        end

        Citizen.Wait(sleep)
    end
end)

function OpenNPCMenu()
    local options = {
        {
            title = 'Inizia Furto Veicolo',
            onSelect = StartVehicleTheft
        }
    }

    if Config.GPSJammerEnabled then
        options[#options + 1] = {
            title = hasGPSJammer and 'GPS Jammer (Posseduto)' or ('Compra GPS Jammer ($%s)'):format(Config.GPSJammerPrice),
            disabled = hasGPSJammer,
            onSelect = function()
                if not hasGPSJammer then BuyGPSJammer() end
            end
        }
    end

    lib.registerContext({
        id = 'nge_carrobbery_contact',
        title = 'Contatto Furto Veicoli',
        options = options
    })
    lib.showContext('nge_carrobbery_contact')
end

function BuyGPSJammer()
    NGEClient.Callback('nge_carrobbery:buyJammer', function(success)
        if success then
            hasGPSJammer = true
            NGEClient.Notify('~g~Hai acquistato un GPS Jammer! Usalo con ~b~/usejammer')
        else
            NGEClient.Notify('~r~Non hai abbastanza soldi! Serve $' .. Config.GPSJammerPrice)
        end
    end)
end

RegisterCommand('usejammer', function()
    if not hasGPSJammer then
        NGEClient.Notify('~r~Non hai un GPS Jammer!')
        return
    end
    
    if not missionActive then
        NGEClient.Notify('~r~Devi essere in una missione per usare il GPS Jammer!')
        return
    end
    
    if gpsJammerActive then
        NGEClient.Notify('~o~Il GPS Jammer è già attivo!')
        return
    end
    
    hasGPSJammer = false
    gpsJammerActive = true
    gpsJammerEndTime = GetGameTimer() + (Config.GPSJammerDuration * 1000)
    
    TriggerServerEvent('nge_carrobbery:activateJammer', VehToNet(currentVehicle))
    NGEClient.Notify('~g~GPS Jammer attivato! Tracking disabilitato per ' .. Config.GPSJammerDuration .. ' secondi!')
    
    Citizen.CreateThread(function()
        while gpsJammerActive do
            Citizen.Wait(1000)
            local remainingTime = math.ceil((gpsJammerEndTime - GetGameTimer()) / 1000)
            
            if remainingTime <= 0 then
                gpsJammerActive = false
                TriggerServerEvent('nge_carrobbery:deactivateJammer', VehToNet(currentVehicle))
                NGEClient.Notify('~o~GPS Jammer esaurito! Tracking riattivato!')
                break
            end
        end
    end)
end)

function StartVehicleTheft()
    NGEClient.Callback('nge_carrobbery:checkPolice', function(enoughPolice)
        if not enoughPolice then
            NGEClient.Notify('~r~Non ci sono forze dell\'ordine in servizio!')
            return
        end
        
        NGEClient.Callback('nge_carrobbery:canStartMission', function(canStart)
            if canStart then
                local vehicleModel = Config.Vehicles[math.random(1, #Config.Vehicles)]
                local deliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
                SpawnVehicleForTheft(vehicleModel, deliveryLocation)
            else
                NGEClient.Notify('~r~Hai già una missione attiva!')
            end
        end)
    end)
end

function SpawnVehicleForTheft(vehicleModel, deliveryLocation)
    local spawnCoords = Config.NPCLocation.coords + vector3(5.0, 5.0, 0.0)
    
    SpawnVehicle(vehicleModel, spawnCoords, Config.NPCLocation.heading, function(vehicle)
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
            NGEClient.Notify('~g~Porta il veicolo al punto di consegna! (1/3)~n~~y~Bonus velocità: ' .. Config.SpeedBonusTime .. ' sec per +$' .. Config.SpeedBonusAmount)
        else
            NGEClient.Notify('~g~Porta il veicolo al punto di consegna! (1/3)')
        end
        
        TriggerServerEvent('nge_carrobbery:startTracking', VehToNet(vehicle))
        Wait(100)
        TriggerServerEvent('nge_carrobbery:alertPolice')
        
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
                        NGEClient.Help('Premi ~INPUT_CONTEXT~ per consegnare il veicolo')
                        
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
            NGEClient.Notify('~g~BONUS VELOCITÀ! +$' .. speedBonus)
        end
    end
    
    if currentDeliveryNumber == 1 then
        local chance = math.random(1, 100)
        
        if chance <= Config.SecondMissionChance then
            TriggerServerEvent('nge_carrobbery:rewardPlayer', 1, speedBonus)
            local newDeliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
            deliveryMarker = newDeliveryLocation
            currentDeliveryNumber = 2
            missionStartTime = GetGameTimer()
            eventActive = false
            
            CreateDeliveryBlip(newDeliveryLocation)
            
            if Config.EnableSpeedBonus then
                NGEClient.Notify('~b~Ottimo! Secondo punto! (2/3)~n~~y~' .. Config.SpeedBonusTime .. ' sec per bonus!')
            else
                NGEClient.Notify('~b~Ottimo! Secondo punto! (2/3)')
            end
            
            if Config.RandomEventsEnabled then
                TriggerRandomEvent()
            end
        else
            TriggerServerEvent('nge_carrobbery:rewardPlayer', 1, speedBonus)
            NGEClient.Notify('~g~Missione completata! $' .. (1500 + speedBonus))
            EndMission()
        end
    elseif currentDeliveryNumber == 2 then
        local chance = math.random(1, 100)
        
        if chance <= Config.ThirdMissionChance then
            TriggerServerEvent('nge_carrobbery:rewardPlayer', 2, speedBonus)
            local newDeliveryLocation = Config.DeliveryLocations[math.random(1, #Config.DeliveryLocations)]
            deliveryMarker = newDeliveryLocation
            currentDeliveryNumber = 3
            missionStartTime = GetGameTimer()
            eventActive = false
            
            CreateDeliveryBlip(newDeliveryLocation)
            
            if Config.EnableSpeedBonus then
                NGEClient.Notify('~b~Ultimo giro! Jackpot! (3/3)~n~~y~' .. Config.SpeedBonusTime .. ' sec per bonus!')
            else
                NGEClient.Notify('~b~Ultimo giro! Jackpot! (3/3)')
            end
            
            if Config.RandomEventsEnabled then
                TriggerRandomEvent()
            end
        else
            TriggerServerEvent('nge_carrobbery:rewardPlayer', 2, speedBonus)
            NGEClient.Notify('~g~Missione completata! $3000 totali')
            EndMission()
        end
    else
        TriggerServerEvent('nge_carrobbery:rewardPlayer', 3, speedBonus)
        NGEClient.Notify('~g~JACKPOT! $5000 totali!')
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
        TriggerServerEvent('nge_carrobbery:stopTracking', VehToNet(currentVehicle))
        DeleteEntity(currentVehicle)
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
                    NGEClient.Notify('~o~Risali sul veicolo entro 60 secondi!')
                else
                    local elapsedTime = (GetGameTimer() - outOfVehicleTimer) / 1000
                    local remainingTime = Config.OutOfVehicleTimeout - elapsedTime
                    
                    if remainingTime <= 30 and remainingTime > 25 then
                        NGEClient.Notify('~o~' .. math.floor(remainingTime) .. ' secondi!')
                    elseif remainingTime <= 10 and remainingTime > 9 then
                        NGEClient.Notify('~r~10 secondi!')
                    end
                    
                    if elapsedTime >= Config.OutOfVehicleTimeout then
                        NGEClient.Notify('~r~Missione fallita! Troppo tempo fuori dal veicolo!')
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
                
                NGEClient.Notify(event.message)
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
                NGEClient.Notify('~g~Riparato! Continua!')
                eventActive = false
                break
            end
            
            if remainingTime <= 0 then
                NGEClient.Notify('~r~Tempo scaduto! Missione fallita!')
                EndMission()
                break
            elseif remainingTime <= 10 and remainingTime % 5 == 0 then
                NGEClient.Notify('~o~Ripara in ' .. remainingTime .. ' sec!')
            end
        end
    end)
end

function HandleFuelLeak(duration)
    if not currentVehicle then return end
    
    local deadlineTime = GetGameTimer() + (duration * 1000)
    NGEClient.Notify('~y~Corri alla consegna!')
    
    Citizen.CreateThread(function()
        while eventActive and missionActive do
            Citizen.Wait(1000)
            
            local remainingTime = math.ceil((deadlineTime - GetGameTimer()) / 1000)
            
            if remainingTime <= 0 then
                SetVehicleEngineHealth(currentVehicle, 0.0)
                SetVehicleUndriveable(currentVehicle, true)
                NGEClient.Notify('~r~Motore bloccato! Missione fallita!')
                EndMission()
                break
            elseif remainingTime <= 30 and remainingTime % 10 == 0 then
                NGEClient.Notify('~r~' .. remainingTime .. ' secondi!')
            end
        end
    end)
end

-- Sistema tracking per FDO
RegisterNetEvent('nge_carrobbery:updateTracking')
AddEventHandler('nge_carrobbery:updateTracking', function(netId, coords)
    if not trackedVehicles[netId] then
        trackedVehicles[netId] = {blip = nil, coords = coords}
    end
    
    trackedVehicles[netId].coords = coords
    
    if PlayerJob and isPoliceJob(PlayerJob) then
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

RegisterNetEvent('nge_carrobbery:removeTracking')
AddEventHandler('nge_carrobbery:removeTracking', function(netId)
    if trackedVehicles[netId] then
        if trackedVehicles[netId].blip then
            RemoveBlip(trackedVehicles[netId].blip)
        end
        trackedVehicles[netId] = nil
    end
end)

RegisterNetEvent('nge_carrobbery:policeAlert')
AddEventHandler('nge_carrobbery:policeAlert', function(coords, vehicleModel)
    if PlayerJob and isPoliceJob(PlayerJob) then
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
        NGEClient.Notify(('Allarme furto veicolo %s'):format(vehicleModel), 'error')
    end
end)

RegisterNetEvent('nge_carrobbery:jammerActivated')
AddEventHandler('nge_carrobbery:jammerActivated', function(netId)
    if PlayerJob and isPoliceJob(PlayerJob) then
        if trackedVehicles[netId] and trackedVehicles[netId].blip then
            SetBlipColour(trackedVehicles[netId].blip, 8)
            SetBlipAlpha(trackedVehicles[netId].blip, 128)
        end
        
        NGEClient.Notify('~o~GPS Jammer rilevato!')
        PlaySoundFrontend(-1, "CHECKPOINT_MISSED", "HUD_MINI_GAME_SOUNDSET", 1)
    end
end)

RegisterNetEvent('nge_carrobbery:jammerDeactivated')
AddEventHandler('nge_carrobbery:jammerDeactivated', function(netId)
    if PlayerJob and isPoliceJob(PlayerJob) then
        if trackedVehicles[netId] and trackedVehicles[netId].blip then
            SetBlipColour(trackedVehicles[netId].blip, 1)
            SetBlipAlpha(trackedVehicles[netId].blip, 255)
        end
        
        NGEClient.Notify('~g~Tracking ripristinato!')
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