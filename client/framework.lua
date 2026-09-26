NGEClient=NGEClient or {}
local F=NGEClient
local kind,ESX,QB
local function started(n) return GetResourceState(n)=='started' end
function F.Init()
    if kind then return true end
    local wanted=string.lower(tostring(Config.Framework or 'auto'))
    if wanted=='auto' then
        if started('qbx_core') then wanted='qbox'
        elseif started('qb-core') then wanted='qbcore'
        elseif started('es_extended') then wanted='esx'
        else return false end
    end
    if wanted=='qbox' then kind='qbox'
    elseif wanted=='qbcore' then QB=exports['qb-core']:GetCoreObject(); kind='qbcore'
    elseif wanted=='esx' then ESX=exports['es_extended']:getSharedObject(); kind='esx'
    else return false end
    return true
end
function F.WaitReady()
    for _=1,120 do if F.Init() then return true end Wait(250) end
    return false
end
function F.Job()
    if kind=='qbox' then local d=exports.qbx_core:GetPlayerData(); return d.job and d.job.name
    elseif kind=='qbcore' then local d=QB.Functions.GetPlayerData(); return d.job and d.job.name
    else local d=ESX.GetPlayerData(); return d.job and d.job.name end
end
function F.Notify(msg,typ)
    lib.notify({description=msg,type=typ or 'inform'})
end
function F.Help(msg)
    BeginTextCommandDisplayHelp('STRING'); AddTextComponentSubstringPlayerName(msg); EndTextCommandDisplayHelp(0,false,true,-1)
end
function F.Callback(name,cb,...)
    lib.callback(name,false,cb,...)
end
