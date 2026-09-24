local RSGCore = exports['rsg-core']:GetCoreObject()
local T = Config.Text

local Chests = {}        -- [id] = row (coords / rot en vector3)
local Attempts = {}      -- ["citizenid:id"] = { count, lockUntil }
local Searches = {}      -- [src] = { id, started }

---------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------
local function toVec(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function HashCode(code)
    return tostring(GetHashKey(Config.Code.Salt .. ':' .. tostring(code)))
end

local function ValidCode(code)
    if type(code) ~= 'string' then return false end
    local len = #code
    if len < Config.Code.MinLength or len > Config.Code.MaxLength then return false end
    if Config.Code.OnlyDigits and not code:match('^%d+$') then return false end
    return true
end

local function InvalidCodeMsg()
    return T.code_invalid:format(Config.Code.MinLength, Config.Code.MaxLength, Config.Code.OnlyDigits and T.only_digits or '')
end

local function StashId(id) return 'rsgchest_' .. id end

local function CharName(Player)
    local c = Player.PlayerData.charinfo or {}
    return ('%s %s'):format(c.firstname or '?', c.lastname or '')
end

local function Notify(src, msg, typ)
    TriggerClientEvent('ox_lib:notify', src, { description = msg, type = typ or 'inform' })
end

local function ToClient(c)
    return {
        id = c.id, type = c.type, model = c.model, owner = c.owner,
        coords = { x = c.coords.x, y = c.coords.y, z = c.coords.z },
        rot = { x = c.rot.x, y = c.rot.y, z = c.rot.z },
    }
end

local function IsNear(src, coords, dist)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end
    return #(GetEntityCoords(ped) - coords) <= dist
end

local function IsLaw(Player)
    local job = Player.PlayerData.job
    if not job then return false end
    local P = Config.Perquisition
    if P.RequireOnDuty and not job.onduty then return false end
    local minGrade = P.Jobs[job.name]
    local grade = job.grade and job.grade.level or 0
    if minGrade and grade >= minGrade then return true end
    return P.AllowJobTypeLeo and job.type == 'leo'
end

local function IsInBlacklistZone(coords)
    for _, zone in ipairs(Config.BlacklistZones) do
        if #(coords - zone.coords) <= zone.radius then return true end
    end
    return false
end

local function IsStashEmpty(id)
    local stash = StashId(id)
    local ok, inv = pcall(function() return exports['rsg-inventory']:GetInventory(stash) end)
    if ok and type(inv) == 'table' and inv.items then
        return next(inv.items) == nil
    end
    local row = MySQL.single.await('SELECT items FROM inventories WHERE identifier = ?', { stash })
    if not row or not row.items then return true end
    local items = json.decode(row.items) or {}
    return next(items) == nil
end

local function DeleteStash(id)
    local stash = StashId(id)
    pcall(function() exports['rsg-inventory']:ClearStash(stash) end)
    MySQL.query.await('DELETE FROM inventories WHERE identifier = ?', { stash })
end

local function OpenStash(src, c)
    local cfg = Config.Chests[c.type]
    exports['rsg-inventory']:OpenInventory(src, StashId(c.id), {
        label = ('%s #%d'):format(cfg and cfg.label or 'Coffre', c.id),
        maxweight = c.weight,
        slots = c.slots,
    })
end

local function SendWebhook(title, message)
    if not Config.Webhook or Config.Webhook == '' then return end
    PerformHttpRequest(Config.Webhook, function() end, 'POST', json.encode({
        username = 'rsg_chest',
        embeds = { { title = title, description = message, color = 9127187 } },
    }), { ['Content-Type'] = 'application/json' })
end

local function Log(chestId, Player, action, details)
    local citizenid, name, job
    if Player then
        citizenid = Player.PlayerData.citizenid
        name = CharName(Player)
        job = Player.PlayerData.job and Player.PlayerData.job.name
    end
    MySQL.insert('INSERT INTO rsg_chests_logs (chest_id, citizenid, name, job, action, details) VALUES (?, ?, ?, ?, ?, ?)',
        { chestId, citizenid, name, job, action, details })
    SendWebhook(('Coffre #%d — %s'):format(chestId, action),
        ('**%s** (%s) [%s]\n%s'):format(name or 'Console', citizenid or '-', job or '-', details or ''))
end

local function NotifyOwner(c, msg)
    local Owner = RSGCore.Functions.GetPlayerByCitizenId(c.owner)
    if Owner then Notify(Owner.PlayerData.source, msg, 'warning') end
end

local function RemoveChest(id)
    Chests[id] = nil
    MySQL.query.await('DELETE FROM rsg_chests WHERE id = ?', { id })
    DeleteStash(id)
    TriggerClientEvent('rsg_chest:client:removeChest', -1, id)
end

---------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------
MySQL.ready(function()
    local rows = MySQL.query.await('SELECT * FROM rsg_chests') or {}
    for _, row in ipairs(rows) do
        row.coords = toVec(json.decode(row.coords))
        row.rot = toVec(json.decode(row.rotation))
        Chests[row.id] = row
    end
    print(('[rsg_chest] %d coffre(s) chargé(s)'):format(#rows))
end)

lib.callback.register('rsg_chest:server:getChests', function()
    local list = {}
    for _, c in pairs(Chests) do list[#list + 1] = ToClient(c) end
    return list
end)

---------------------------------------------------------------------
-- Items utilisables
---------------------------------------------------------------------
for chestType, cfg in pairs(Config.Chests) do
    RSGCore.Functions.CreateUseableItem(cfg.item, function(source)
        TriggerClientEvent('rsg_chest:client:startPlacement', source, chestType)
    end)
end

---------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------
lib.callback.register('rsg_chest:server:place', function(src, chestType, coords, rot, code)
    local Player = RSGCore.Functions.GetPlayer(src)
    local cfg = Config.Chests[chestType]
    if not Player or not cfg or type(coords) ~= 'table' or type(rot) ~= 'table' then return false, T.not_allowed end
    if not ValidCode(code) then return false, InvalidCodeMsg() end

    local pos = toVec(coords)
    local rotation = toVec(rot)
    if not IsNear(src, pos, Config.Placement.MaxDistance + 2.0) then return false, T.too_far end
    if IsInBlacklistZone(pos) then return false, T.blacklisted end
    for _, c in pairs(Chests) do
        if #(c.coords - pos) < Config.MinDistanceBetween then return false, T.too_close end
    end

    local citizenid = Player.PlayerData.citizenid
    if Config.MaxChestsPerPlayer > 0 then
        local count = 0
        for _, c in pairs(Chests) do if c.owner == citizenid then count = count + 1 end end
        if count >= Config.MaxChestsPerPlayer then return false, T.max_reached:format(Config.MaxChestsPerPlayer) end
    end

    if not Player.Functions.GetItemByName(cfg.item) or not Player.Functions.RemoveItem(cfg.item, 1) then
        return false, T.no_item
    end
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[cfg.item], 'remove', 1)

    local id = MySQL.insert.await([[
        INSERT INTO rsg_chests (owner, owner_name, type, model, coords, rotation, code, slots, weight)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        citizenid, CharName(Player), chestType, cfg.model,
        json.encode({ x = pos.x, y = pos.y, z = pos.z }),
        json.encode({ x = rotation.x, y = rotation.y, z = rotation.z }),
        HashCode(code), cfg.slots, cfg.weight,
    })
    if not id then
        Player.Functions.AddItem(cfg.item, 1)
        return false, 'Erreur SQL'
    end

    local chest = {
        id = id, owner = citizenid, owner_name = CharName(Player), type = chestType, model = cfg.model,
        coords = pos, rot = rotation, code = HashCode(code), slots = cfg.slots, weight = cfg.weight,
    }
    Chests[id] = chest
    TriggerClientEvent('rsg_chest:client:addChest', -1, ToClient(chest))
    Log(id, Player, 'place', ('%s @ %.2f, %.2f, %.2f'):format(chestType, pos.x, pos.y, pos.z))
    return true, T.placed
end)

---------------------------------------------------------------------
-- Code
---------------------------------------------------------------------
local function CheckCode(src, Player, c, code)
    local key = Player.PlayerData.citizenid .. ':' .. c.id
    local att = Attempts[key]
    local now = os.time()
    if att and att.lockUntil and att.lockUntil > now then
        return false, T.locked:format(att.lockUntil - now)
    end

    if type(code) == 'string' and HashCode(code) == c.code then
        Attempts[key] = nil
        return true
    end

    att = att or { count = 0 }
    if att.lockUntil and att.lockUntil <= now then att = { count = 0 } end
    att.count = att.count + 1
    Log(c.id, Player, 'failed_code', ('essai %d/%d'):format(att.count, Config.Code.MaxAttempts))
    if Config.Code.NotifyOwnerOnFail and c.owner ~= Player.PlayerData.citizenid then
        NotifyOwner(c, T.fail_owner:format(c.id))
    end
    if att.count >= Config.Code.MaxAttempts then
        att.lockUntil = now + Config.Code.LockTime
        Attempts[key] = att
        return false, T.locked:format(Config.Code.LockTime)
    end
    Attempts[key] = att
    return false, T.wrong_code:format(Config.Code.MaxAttempts - att.count)
end

local function GetContext(src, id)
    local Player = RSGCore.Functions.GetPlayer(src)
    local c = Chests[tonumber(id)]
    if not Player or not c then return nil, nil, T.not_allowed end
    if not IsNear(src, c.coords, Config.InteractDistance + 1.5) then return nil, nil, T.too_far end
    return Player, c
end

lib.callback.register('rsg_chest:server:openWithCode', function(src, id, code)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local ok, msg = CheckCode(src, Player, c, code)
    if not ok then return false, msg end
    Log(c.id, Player, 'open')
    OpenStash(src, c)
    return true
end)

lib.callback.register('rsg_chest:server:changeCode', function(src, id, oldCode, newCode)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    if not ValidCode(newCode) then return false, InvalidCodeMsg() end
    local ok, msg = CheckCode(src, Player, c, oldCode)
    if not ok then return false, msg end
    c.code = HashCode(newCode)
    MySQL.update.await('UPDATE rsg_chests SET code = ? WHERE id = ?', { c.code, c.id })
    Log(c.id, Player, 'change_code')
    return true, T.code_changed
end)

lib.callback.register('rsg_chest:server:pickup', function(src, id, code)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    local ok, msg = CheckCode(src, Player, c, code)
    if not ok then return false, msg end
    if Config.PickupRequireEmpty and not IsStashEmpty(c.id) then return false, T.not_empty end

    local cfg = Config.Chests[c.type]
    RemoveChest(c.id)
    if cfg then
        Player.Functions.AddItem(cfg.item, 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[cfg.item], 'add', 1)
    end
    Log(c.id, Player, 'pickup')
    return true, T.picked_up
end)

---------------------------------------------------------------------
-- Perquisition
---------------------------------------------------------------------
lib.callback.register('rsg_chest:server:searchStart', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not IsLaw(Player) then return false, T.not_allowed end
    Searches[src] = { id = c.id, started = GetGameTimer() }
    if Config.Perquisition.NotifyOwner then NotifyOwner(c, T.searched_owner:format(c.id)) end
    return true
end)

lib.callback.register('rsg_chest:server:searchFinish', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not IsLaw(Player) then return false, T.not_allowed end
    local s = Searches[src]
    Searches[src] = nil
    -- la fouille doit avoir réellement duré (anti-trigger)
    if not s or s.id ~= c.id or GetGameTimer() - s.started < Config.Perquisition.Duration * 0.9 then
        return false, T.not_allowed
    end
    Log(c.id, Player, 'search', ('propriétaire : %s'):format(c.owner_name or c.owner))
    OpenStash(src, c)
    return true
end)

lib.callback.register('rsg_chest:server:seize', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local P = Config.Perquisition
    local grade = Player.PlayerData.job.grade and Player.PlayerData.job.grade.level or 0
    if not P.CanSeize or not IsLaw(Player) or grade < P.SeizeMinGrade then return false, T.not_allowed end
    local empty = IsStashEmpty(c.id)
    if P.SeizeRequireEmpty and not empty then return false, T.not_empty end

    local cfg = Config.Chests[c.type]
    Log(c.id, Player, 'seize', ('propriétaire : %s | contenu %s'):format(c.owner_name or c.owner, empty and 'vide' or 'détruit'))
    NotifyOwner(c, T.searched_owner:format(c.id))
    RemoveChest(c.id)
    if P.SeizeGiveItem and cfg then
        Player.Functions.AddItem(cfg.item, 1)
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[cfg.item], 'add', 1)
    end
    return true, T.seized
end)

lib.callback.register('rsg_chest:server:getLogs', function(src, id)
    local Player = RSGCore.Functions.GetPlayer(src)
    local c = Chests[tonumber(id)]
    if not Player or not c then return nil end
    if c.owner ~= Player.PlayerData.citizenid and not IsLaw(Player) then return nil end
    return MySQL.query.await([[
        SELECT action, name, job, details, DATE_FORMAT(date, '%d/%m/%Y %H:%i') AS date
        FROM rsg_chests_logs WHERE chest_id = ? ORDER BY id DESC LIMIT ?
    ]], { c.id, Config.LogsLimit }) or {}
end)

AddEventHandler('playerDropped', function()
    Searches[source] = nil
end)

---------------------------------------------------------------------
-- Commandes admin
---------------------------------------------------------------------
RSGCore.Commands.Add('chestdelete', 'Supprimer un coffre (rsg_chest)', { { name = 'id', help = 'ID du coffre' } }, true,
    function(source, args)
        local id = tonumber(args[1])
        if not id or not Chests[id] then return Notify(source, 'Coffre introuvable', 'error') end
        RemoveChest(id)
        Log(id, RSGCore.Functions.GetPlayer(source), 'admin_delete')
        Notify(source, ('Coffre #%d supprimé'):format(id), 'success')
    end, 'admin')

RSGCore.Commands.Add('chestnearest', 'Afficher l\'ID du coffre le plus proche', {}, false, function(source)
    local ped = GetPlayerPed(source)
    local pos = GetEntityCoords(ped)
    local best, bestDist
    for _, c in pairs(Chests) do
        local d = #(c.coords - pos)
        if not bestDist or d < bestDist then best, bestDist = c, d end
    end
    if not best then return Notify(source, 'Aucun coffre', 'error') end
    Notify(source, ('Coffre #%d (%s) — propriétaire %s — %.1fm'):format(best.id, best.type, best.owner_name or best.owner, bestDist))
end, 'admin')
