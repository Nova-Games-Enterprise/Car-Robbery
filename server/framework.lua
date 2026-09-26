NGEFramework=NGEFramework or {}
local F=NGEFramework
local kind,ESX,QB
local function started(n) return GetResourceState(n)=='started' end

function F.Init()
    if kind then return true end
    local wanted=string.lower(tostring(Config.Framework or 'auto'))
    if wanted=='qb' then wanted='qbcore' end
    if wanted=='qbx' then wanted='qbox' end
    if wanted=='auto' then
        if started('qbx_core') then wanted='qbox'
        elseif started('qb-core') then wanted='qbcore'
        elseif started('es_extended') then wanted='esx'
        else return false end
    end
    if wanted=='qbox' then kind='qbox'
    elseif wanted=='qbcore' then QB=exports['qb-core']:GetCoreObject(); kind=QB and 'qbcore' or nil
    elseif wanted=='esx' then ESX=exports['es_extended']:getSharedObject(); kind=ESX and 'esx' or nil end
    if kind then print(('[nge_carrobbery] framework: %s'):format(kind)); return true end
    return false
end
function F.WaitReady()
    for _=1,120 do if F.Init() then return true end Wait(250) end
    return false
end
function F.Get(src)
    if kind=='qbox' then return exports.qbx_core:GetPlayer(src)
    elseif kind=='qbcore' then return QB.Functions.GetPlayer(src)
    elseif kind=='esx' then return ESX.GetPlayerFromId(src) end
end
function F.Source(p) return kind=='esx' and p.source or p.PlayerData.source end
function F.Identifier(p)
    if kind=='esx' then return p.identifier end
    return p.PlayerData.citizenid or p.PlayerData.license
end
function F.Job(p)
    if kind=='esx' then return p.job and p.job.name end
    return p.PlayerData.job and p.PlayerData.job.name
end
function F.Sources()
    local out={}
    for _,src in ipairs(GetPlayers()) do out[#out+1]=tonumber(src) end
    return out
end
function F.RegisterCallback(name,handler)
    lib.callback.register(name,function(source,...)
        local p=promise.new()
        handler(source,function(result) p:resolve(result) end,...)
        return Citizen.Await(p)
    end)
end
local function accountName(account)
    return account=='money' and 'cash' or account
end
function F.GetMoney(p,account)
    account=accountName(account)
    if kind=='esx' then
        if account=='cash' then return p.getMoney() end
        local a=p.getAccount(account); return a and (a.money or 0) or 0
    elseif account=='black_money' then
        return 0
    elseif kind=='qbox' then
        return tonumber(exports.qbx_core:GetMoney(F.Source(p),account)) or 0
    else
        return tonumber(p.PlayerData.money and p.PlayerData.money[account]) or 0
    end
end
function F.RemoveMoney(p,account,amount,reason)
    account=accountName(account); amount=math.max(0,math.floor(tonumber(amount) or 0))
    if F.GetMoney(p,account)<amount then return false end
    if kind=='esx' then
        if account=='cash' then p.removeMoney(amount) else p.removeAccountMoney(account,amount) end
        return true
    elseif account=='black_money' then return false
    elseif kind=='qbox' then return exports.qbx_core:RemoveMoney(F.Source(p),account,amount,reason or 'nge-carrobbery')==true
    else return p.Functions.RemoveMoney(account,amount,reason or 'nge-carrobbery')==true end
end
function F.AddMoney(p,account,amount,reason)
    account=accountName(account); amount=math.max(0,math.floor(tonumber(amount) or 0)); if amount<=0 then return false end
    if kind=='esx' then
        if account=='cash' then p.addMoney(amount) else p.addAccountMoney(account,amount) end
        return true
    elseif account=='black_money' then return false
    elseif kind=='qbox' then return exports.qbx_core:AddMoney(F.Source(p),account,amount,reason or 'nge-carrobbery')==true
    else return p.Functions.AddMoney(account,amount,reason or 'nge-carrobbery')==true end
end
