Config = {}

Config.Framework = 'auto' -- auto | esx | qbcore | qbox

Config.Locale = 'it'

-- ============================================
-- COORDINATE E POSIZIONI
-- ============================================
-- Per trovare le coordinate:
-- 1. Vai nel punto desiderato in gioco
-- 2. Scrivi /getcoords (se hai un comando simile)
-- 3. Oppure usa /save o /savecoords
-- 4. Copia e incolla le coordinate qui sotto nel formato vector3(x, y, z)
-- ============================================

-- Posizione del NPC che assegna i furti
Config.NPCLocation = {
    coords = vector3(1075.5522, -2330.5234, 30.2925), -- Cambia con la tua posizione
    heading = 180.0,
    model = 'g_m_m_chigoon_01' -- Modello del NPC
}

-- Lavori delle forze dell'ordine che riceveranno l'alert
Config.PoliceJobs = {
    'police',
    'carabinieri',
    'finanza',
    'poliziaromacapitale'
}

-- Numero minimo di FDO online per iniziare una missione
Config.MinPoliceOnline = 1

-- Veicoli che possono essere assegnati per il furto
Config.Vehicles = {
    'adder',
    'zentorno',
    't20',
    'banshee',
    'carbonizzare',
    'coquette',
    'feltzer2',
    'surano',
    'baller',
    'dubsta2',
    'schafter3'
}

-- Punti di consegna casuali
-- PUOI MODIFICARE QUESTE COORDINATE E AGGIUNGERNE ALTRE!
-- Usa /getcoords in gioco per trovare le tue coordinate preferite
Config.DeliveryLocations = {
    vector3(1391.4, 3612.0, 34.9),      -- Sandy Shores
    vector3(-1076.7, -2876.5, 13.9),    -- Aeroporto
    vector3(-56.9, -2516.5, 7.4),       -- Docks
    vector3(2549.5, 383.0, 108.6),      -- Paleto Bay
    vector3(1737.5, 3709.5, 34.1),      -- Sandy Shores 2
    vector3(-3038.5, 584.5, 7.9),       -- Porto
    vector3(-1106.5, 2708.5, 19.1),     -- Deserto
    vector3(2451.5, 4063.5, 38.1),      -- Grapeseed
    vector3(1695.5, 4786.5, 42.0),      -- Nord mappa
    vector3(-448.5, 6260.5, 30.0)       -- Paleto Forest
    -- Aggiungi tutte le coordinate che vuoi qui!
}

-- Pagamenti (totale massimo 5000€ se completa tutte e 3 le consegne)
Config.FirstDeliveryReward = 1500   -- Pagamento per la prima consegna
Config.SecondDeliveryReward = 1500  -- Pagamento per la seconda consegna
Config.ThirdDeliveryReward = 2000   -- Pagamento per la terza consegna (finale)

-- Probabilità di ricevere un'altra missione dopo ogni consegna (0-100)
Config.SecondMissionChance = 70  -- Probabilità di avere una seconda consegna dopo la prima
Config.ThirdMissionChance = 60   -- Probabilità di avere una terza consegna dopo la seconda

-- Timeout: secondi massimi fuori dal veicolo prima che la missione fallisca
Config.OutOfVehicleTimeout = 60

-- Distanza minima per considerare la consegna completata
Config.DeliveryDistance = 15.0

-- Tempo di aggiornamento tracker per le FDO (in millisecondi)
Config.BlipUpdateInterval = 5000

-- Account ESX dove verranno accreditati i soldi
Config.MoneyAccount = 'black_money' -- 'money', 'black_money', 'bank'

-- ============================================
-- BONUS VELOCITÀ
-- ============================================
Config.EnableSpeedBonus = true
Config.SpeedBonusTime = 180 -- Secondi per ottenere il bonus (3 minuti)
Config.SpeedBonusAmount = 500 -- Bonus in € per consegna veloce

-- ============================================
-- GPS JAMMER
-- ============================================
Config.GPSJammerEnabled = true
Config.GPSJammerPrice = 2000 -- Prezzo del GPS Jammer
Config.GPSJammerDuration = 120 -- Durata in secondi (2 minuti)

-- ============================================
-- EVENTI CASUALI
-- ============================================
Config.RandomEventsEnabled = true
Config.RandomEventChance = 5 -- Probabilità massima (5%)

-- Tipi di eventi casuali possibili
Config.RandomEvents = {
    {
        name = 'flat_tire',
        chance = 3, -- 3% di probabilità
        message = '~r~PNEUMATICO FORATO! Ripara il veicolo velocemente!',
        duration = 30 -- Tempo per riparare (secondi)
    },
    {
        name = 'fuel_leak',
        chance = 2, -- 2% di probabilità
        message = '~r~PERDITA CARBURANTE! Hai 60 secondi per consegnare!',
        duration = 60 -- Tempo prima del "blocco motore"
    }
}