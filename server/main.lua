local RSGCore = exports['rsg-core']:GetCoreObject()
local T = Config.Text

local Chests = {}        -- [id] = row (coords / rot en vector3, shared en table)
local Warrants = {}      -- [id] = mandat actif
local Attempts = {}      -- ["citizenid:id"] = { count, lockUntil }
local Searches = {}      -- [src] = { id, started, warrant }
local Lockpicks = {}     -- [src] = { id, started, fails, wheels }
local LockpickCooldown = {} -- [chestId] = os.time() de fin
local Dynamites = {}     -- [chestId] = true pendant la mèche
local ChestFails = {}    -- [chestId] = { count, first, lockUntil } (tous joueurs confondus)

---------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------
local function toVec(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

--- Sel aléatoire propre à chaque coffre.
local function NewSalt()
    local t = {}
    for i = 1, 16 do t[i] = ('%x'):format(math.random(0, 15)) end
    return table.concat(t)
end

--- SHA-256 calculé par MySQL/MariaDB : sel du coffre + sel du serveur + code.
local function HashCode(code, salt)
    return MySQL.scalar.await('SELECT SHA2(?, 256)', { ('%s:%s:%s'):format(salt, Config.Code.Salt, tostring(code)) })
end

--- Ancien format (avant la version 1.2), converti au premier bon code.
local function LegacyHash(code)
    return tostring(GetHashKey(Config.Code.Salt .. ':' .. tostring(code)))
end

local function ValidCode(code)
    if type(code) ~= 'string' then return false end
    return #code == Config.Code.Length and code:match('^%d+$') ~= nil
end

local function InvalidCodeMsg()
    return T.code_invalid:format(Config.Code.Length)
end

local function StashId(id) return 'rsgchest_' .. id end

local function CharName(Player)
    local c = Player.PlayerData.charinfo or {}
    return ('%s %s'):format(c.firstname or '?', c.lastname or '')
end

local function Grade(Player)
    local job = Player.PlayerData.job
    return job and job.grade and job.grade.level or 0
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

local function PedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

local function IsNear(src, coords, dist)
    local pos = PedCoords(src)
    return pos ~= nil and #(pos - coords) <= dist
end

local function IsLaw(Player)
    local job = Player.PlayerData.job
    if not job then return false end
    local P = Config.Perquisition
    if P.RequireOnDuty and not job.onduty then return false end
    local minGrade = P.Jobs[job.name]
    if minGrade and Grade(Player) >= minGrade then return true end
    return P.AllowJobTypeLeo and job.type == 'leo'
end

local function IsAdmin(src)
    return RSGCore.Functions.HasPermission(src, Config.Admin.Permission) or IsPlayerAceAllowed(src, 'command')
end

local function IsInBlacklistZone(coords)
    for _, zone in ipairs(Config.BlacklistZones) do
        if #(coords - zone.coords) <= zone.radius then return true end
    end
    return false
end

local function HasItem(Player, item)
    return Player.Functions.GetItemByName(item) ~= nil
end

local function ItemLabel(item)
    local it = RSGCore.Shared.Items[item]
    return it and it.label or item
end

local function RemoveItem(src, Player, item)
    if Player.Functions.RemoveItem(item, 1) then
        TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'remove', 1)
        return true
    end
    return false
end

local function AddItem(src, Player, item)
    Player.Functions.AddItem(item, 1)
    TriggerClientEvent('rsg-inventory:client:ItemBox', src, RSGCore.Shared.Items[item], 'add', 1)
end

local function ForEachPlayer(cb)
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local Player = RSGCore.Functions.GetPlayer(src)
        if Player then cb(src, Player) end
    end
end

--- Contenu d'un stash : la version en mémoire de rsg-inventory si elle existe
--- (la plus récente), sinon la base de données.
--- @return table items, boolean isOpen
local function GetStashItems(identifier)
    local ok, inv = pcall(function() return exports['rsg-inventory']:GetInventory(identifier) end)
    if ok and type(inv) == 'table' and type(inv.items) == 'table' then
        return inv.items, inv.isOpen and true or false
    end
    local row = MySQL.single.await('SELECT items FROM inventories WHERE identifier = ?', { identifier })
    local items = row and row.items and json.decode(row.items) or {}
    return type(items) == 'table' and items or {}, false
end

local function CountItems(items)
    local n = 0
    for _, it in pairs(items) do
        if type(it) == 'table' and it.name and (tonumber(it.amount) or 1) > 0 then n = n + 1 end
    end
    return n
end

local function IsStashEmpty(id)
    local items = GetStashItems(StashId(id))
    return CountItems(items) == 0
end

local function IsStashOpen(id)
    local _, open = GetStashItems(StashId(id))
    return open
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
        ('**%s** (%s) [%s]\n%s'):format(name or 'Système', citizenid or '-', job or '-', details or ''))
end

local function NotifyOwner(c, msg)
    local Owner = RSGCore.Functions.GetPlayerByCitizenId(c.owner)
    if Owner then Notify(Owner.PlayerData.source, msg, 'warning') end
end

local function RemoveChest(id)
    Chests[id] = nil
    Dynamites[id] = nil
    LockpickCooldown[id] = nil
    MySQL.query.await('DELETE FROM rsg_chests WHERE id = ?', { id })
    DeleteStash(id)
    TriggerClientEvent('rsg_chest:client:removeChest', -1, id)
end

local function SaveShared(c)
    MySQL.update('UPDATE rsg_chests SET shared = ? WHERE id = ?', { json.encode(c.shared), c.id })
end

--- Alerte toutes les forces de l'ordre en service.
local function AlertLaw(coords, message)
    ForEachPlayer(function(src, Player)
        if IsLaw(Player) then
            TriggerClientEvent('rsg_chest:client:lawAlert', src, { x = coords.x, y = coords.y, z = coords.z }, message)
        end
    end)
    if Config.Alerts.ServerEvent then
        TriggerEvent(Config.Alerts.ServerEvent, coords, message)
    end
end

local function IsBroken(c)
    return c.broken_until and c.broken_until > os.time()
end

---------------------------------------------------------------------
-- Base de données (création / mise à jour automatique)
---------------------------------------------------------------------
local function Migrate()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rsg_chests` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `owner` VARCHAR(50) NOT NULL,
            `owner_name` VARCHAR(100) DEFAULT NULL,
            `type` VARCHAR(50) NOT NULL,
            `model` VARCHAR(100) NOT NULL,
            `coords` LONGTEXT NOT NULL,
            `rotation` LONGTEXT NOT NULL,
            `code` VARCHAR(64) NOT NULL,
            `slots` INT(11) NOT NULL DEFAULT 20,
            `weight` INT(11) NOT NULL DEFAULT 100000,
            `shared` LONGTEXT DEFAULT NULL,
            `last_search` INT(11) NOT NULL DEFAULT 0,
            `broken_until` INT(11) NOT NULL DEFAULT 0,
            `salt` VARCHAR(32) DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `owner` (`owner`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    -- anciennes installations (MariaDB)
    for _, col in ipairs({
        '`shared` LONGTEXT DEFAULT NULL',
        '`last_search` INT(11) NOT NULL DEFAULT 0',
        '`broken_until` INT(11) NOT NULL DEFAULT 0',
        '`salt` VARCHAR(32) DEFAULT NULL',
    }) do
        pcall(function() MySQL.query.await('ALTER TABLE `rsg_chests` ADD COLUMN IF NOT EXISTS ' .. col) end)
    end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rsg_chests_logs` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `chest_id` INT(11) NOT NULL,
            `citizenid` VARCHAR(50) DEFAULT NULL,
            `name` VARCHAR(100) DEFAULT NULL,
            `job` VARCHAR(50) DEFAULT NULL,
            `action` VARCHAR(32) NOT NULL,
            `details` VARCHAR(255) DEFAULT NULL,
            `date` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `chest_id` (`chest_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rsg_chests_evidence` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `chest_id` INT(11) NOT NULL,
            `owner` VARCHAR(50) DEFAULT NULL,
            `owner_name` VARCHAR(100) DEFAULT NULL,
            `warrant_id` INT(11) DEFAULT NULL,
            `seized_by` VARCHAR(50) DEFAULT NULL,
            `seized_name` VARCHAR(100) DEFAULT NULL,
            `job` VARCHAR(50) DEFAULT NULL,
            `items` INT(11) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `chest_id` (`chest_id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `rsg_chests_warrants` (
            `id` INT(11) NOT NULL AUTO_INCREMENT,
            `target_type` VARCHAR(10) NOT NULL,
            `target` VARCHAR(50) NOT NULL,
            `target_name` VARCHAR(100) DEFAULT NULL,
            `reason` VARCHAR(255) DEFAULT NULL,
            `issued_by` VARCHAR(50) DEFAULT NULL,
            `issued_name` VARCHAR(100) DEFAULT NULL,
            `job` VARCHAR(50) DEFAULT NULL,
            `expires_at` INT(11) NOT NULL,
            `revoked` TINYINT(1) NOT NULL DEFAULT 0,
            `uses` INT(11) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`), KEY `target` (`target_type`, `target`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    ]])
end

---------------------------------------------------------------------
-- Chargement
---------------------------------------------------------------------
MySQL.ready(function()
    Migrate()

    local rows = MySQL.query.await('SELECT * FROM rsg_chests') or {}
    for _, row in ipairs(rows) do
        row.coords = toVec(json.decode(row.coords))
        row.rot = toVec(json.decode(row.rotation))
        row.shared = row.shared and json.decode(row.shared) or {}
        row.last_search = row.last_search or 0
        row.broken_until = row.broken_until or 0
        Chests[row.id] = row
    end

    local warrants = MySQL.query.await('SELECT * FROM rsg_chests_warrants WHERE revoked = 0 AND expires_at > ?', { os.time() }) or {}
    for _, w in ipairs(warrants) do Warrants[w.id] = w end

    print(('[rsg_chest] %d coffre(s), %d mandat(s) actif(s)'):format(#rows, #warrants))
end)

lib.callback.register('rsg_chest:server:getChests', function()
    local list = {}
    for _, c in pairs(Chests) do list[#list + 1] = ToClient(c) end
    return list
end)

---------------------------------------------------------------------
-- Accès / mandats : logique
---------------------------------------------------------------------
local function HasAccess(Player, c)
    local pd = Player.PlayerData
    if c.owner == pd.citizenid then return Config.Sharing.OwnerNoCode end
    if not Config.Sharing.Enabled then return false end
    for _, a in ipairs(c.shared) do
        if a.type == 'citizen' and a.value == pd.citizenid then return true end
        if a.type == 'gang' and pd.gang and pd.gang.name == a.value then return true end
        if a.type == 'job' and pd.job and pd.job.name == a.value then return true end
    end
    return false
end

local function ActiveWarrant(c)
    local now = os.time()
    for id, w in pairs(Warrants) do
        if w.revoked == 0 and w.expires_at > now then
            if (w.target_type == 'chest' and tonumber(w.target) == c.id)
                or (w.target_type == 'citizen' and w.target == c.owner) then
                return w
            end
        elseif w.expires_at <= now then
            Warrants[id] = nil
        end
    end
    return nil
end

local function OfficersNearby(coords)
    local count = 0
    ForEachPlayer(function(src, Player)
        if IsLaw(Player) and IsNear(src, coords, Config.Perquisition.OfficersRadius) then
            count = count + 1
        end
    end)
    return count
end

local function CanSearch(Player, c)
    local P = Config.Perquisition
    if not IsLaw(Player) then return false, T.not_allowed end
    local warrant = ActiveWarrant(c)
    if Config.Warrant.Required and not warrant then return false, T.no_warrant end
    local left = (c.last_search or 0) + P.Cooldown - os.time()
    if left > 0 then return false, T.search_cooldown:format(math.ceil(left / 60)) end
    if OfficersNearby(c.coords) < P.MinOfficersNearby then
        return false, T.not_enough_officers:format(P.MinOfficersNearby)
    end
    return true, nil, warrant
end

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

    local salt = NewSalt()
    local hash = HashCode(code, salt)
    if not hash then return false, T.sql_error end

    if not HasItem(Player, cfg.item) or not RemoveItem(src, Player, cfg.item) then
        return false, T.no_item
    end

    local id = MySQL.insert.await([[
        INSERT INTO rsg_chests (owner, owner_name, type, model, coords, rotation, code, salt, slots, weight, shared)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '[]')
    ]], {
        citizenid, CharName(Player), chestType, cfg.model,
        json.encode({ x = pos.x, y = pos.y, z = pos.z }),
        json.encode({ x = rotation.x, y = rotation.y, z = rotation.z }),
        hash, salt, cfg.slots, cfg.weight,
    })
    if not id then
        AddItem(src, Player, cfg.item)
        return false, T.sql_error
    end

    local chest = {
        id = id, owner = citizenid, owner_name = CharName(Player), type = chestType, model = cfg.model,
        coords = pos, rot = rotation, code = hash, salt = salt, slots = cfg.slots, weight = cfg.weight,
        shared = {}, last_search = 0, broken_until = 0,
    }
    Chests[id] = chest
    TriggerClientEvent('rsg_chest:client:addChest', -1, ToClient(chest))
    Log(id, Player, 'place', ('%s @ %.2f, %.2f, %.2f'):format(chestType, pos.x, pos.y, pos.z))
    return true, T.placed
end)

---------------------------------------------------------------------
-- Infos pour le menu (le client n'affiche que ce que le serveur autorise)
---------------------------------------------------------------------
local function GetContext(src, id)
    local Player = RSGCore.Functions.GetPlayer(src)
    local c = Chests[tonumber(id)]
    if not Player or not c then return nil, nil, T.not_allowed end
    if not IsNear(src, c.coords, Config.InteractDistance + 1.5) then return nil, nil, T.too_far end
    return Player, c
end

lib.callback.register('rsg_chest:server:getChestInfo', function(src, id)
    local Player, c = GetContext(src, id)
    if not Player then return nil end
    local pd = Player.PlayerData
    local law = IsLaw(Player)
    local isOwner = c.owner == pd.citizenid
    local warrant = law and ActiveWarrant(c) or nil

    local info = {
        id = c.id,
        isOwner = isOwner,
        hasAccess = HasAccess(Player, c),
        broken = IsBroken(c),
        armed = Dynamites[c.id] == true,
        isLaw = law,
        warrant = warrant and warrant.id or nil,
        canIssue = law and Grade(Player) >= Config.Warrant.IssueMinGrade,
        canSeize = law and Config.Perquisition.CanSeize and Grade(Player) >= Config.Perquisition.SeizeMinGrade,
        canLockpick = Config.Lockpick.Enabled and (not law or Config.Lockpick.LawCanLockpick) and not isOwner,
        canDynamite = Config.Dynamite.Enabled and (not law or Config.Dynamite.LawCanUse) and not isOwner,
        ownerName = law and (c.owner_name or c.owner) or nil,
        evidence = Config.Evidence.Enabled,
    }
    if isOwner and Config.Sharing.Enabled then
        info.shared = c.shared
        info.gang = Config.Sharing.AllowGang and pd.gang and pd.gang.name ~= 'none' and pd.gang.name or nil
        info.gangLabel = pd.gang and pd.gang.label
        info.job = Config.Sharing.AllowJob and pd.job and pd.job.name ~= 'unemployed' and pd.job.name or nil
        info.jobLabel = pd.job and pd.job.label
    end
    return info
end)

---------------------------------------------------------------------
-- Code
---------------------------------------------------------------------
local function CodeMatches(c, code)
    if type(code) ~= 'string' or code == '' then return false end
    if c.salt and c.salt ~= '' then
        return HashCode(code, c.salt) == c.code
    end
    if LegacyHash(code) ~= c.code then return false end
    -- conversion vers SHA-256 salé
    c.salt = NewSalt()
    c.code = HashCode(code, c.salt)
    MySQL.update('UPDATE rsg_chests SET code = ?, salt = ? WHERE id = ?', { c.code, c.salt, c.id })
    return true
end

local function SetCode(c, code)
    local salt = NewSalt()
    local hash = HashCode(code, salt)
    if not hash then return false end
    c.salt, c.code = salt, hash
    MySQL.update.await('UPDATE rsg_chests SET code = ?, salt = ? WHERE id = ?', { hash, salt, c.id })
    return true
end

--- Blocage du coffre entier après trop d'échecs, tous joueurs confondus
--- (empêche de contourner la limite avec plusieurs personnages).
local function ChestFailed(c)
    local C = Config.Code
    local now = os.time()
    local f = ChestFails[c.id]
    if not f or now - f.first > C.ChestFailWindow then f = { count = 0, first = now } end
    f.count = f.count + 1
    if f.count >= C.ChestMaxFails then
        f.lockUntil = now + C.ChestLockTime
        NotifyOwner(c, T.fail_owner:format(c.id))
    end
    ChestFails[c.id] = f
end

local function CheckCode(Player, c, code)
    local now = os.time()
    local cf = ChestFails[c.id]
    if cf and cf.lockUntil and cf.lockUntil > now then
        return false, T.chest_locked:format(math.ceil((cf.lockUntil - now) / 60))
    end

    local key = Player.PlayerData.citizenid .. ':' .. c.id
    local att = Attempts[key]
    if att and att.lockUntil and att.lockUntil > now then
        return false, T.locked:format(att.lockUntil - now)
    end

    if CodeMatches(c, code) then
        Attempts[key] = nil
        return true
    end

    ChestFailed(c)
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

lib.callback.register('rsg_chest:server:openWithCode', function(src, id, code)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local ok, msg = CheckCode(Player, c, code)
    if not ok then return false, msg end
    Log(c.id, Player, 'open')
    OpenStash(src, c)
    return true
end)

lib.callback.register('rsg_chest:server:openShared', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not HasAccess(Player, c) then return false, T.not_allowed end
    Log(c.id, Player, 'open_access')
    OpenStash(src, c)
    return true
end)

lib.callback.register('rsg_chest:server:changeCode', function(src, id, oldCode, newCode)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    if not ValidCode(newCode) then return false, InvalidCodeMsg() end
    local ok, msg = CheckCode(Player, c, oldCode)
    if not ok then return false, msg end
    if not SetCode(c, newCode) then return false, T.sql_error end
    Log(c.id, Player, 'change_code')
    return true, T.code_changed
end)

lib.callback.register('rsg_chest:server:pickup', function(src, id, code)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    local ok, msg = CheckCode(Player, c, code)
    if not ok then return false, msg end
    if IsStashOpen(c.id) then return false, T.stash_in_use end
    if Config.PickupRequireEmpty and not IsStashEmpty(c.id) then return false, T.not_empty end

    local cfg = Config.Chests[c.type]
    RemoveChest(c.id)
    if cfg then AddItem(src, Player, cfg.item) end
    Log(c.id, Player, 'pickup')
    return true, T.picked_up
end)

---------------------------------------------------------------------
-- Partage
---------------------------------------------------------------------
local function AddAccess(Player, c, entry)
    if not Config.Sharing.Enabled then return false, T.not_allowed end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    for _, a in ipairs(c.shared) do
        if a.type == entry.type and a.value == entry.value then return false, T.access_exists end
    end
    if #c.shared >= Config.Sharing.Max then return false, T.access_max:format(Config.Sharing.Max) end
    c.shared[#c.shared + 1] = entry
    SaveShared(c)
    Log(c.id, Player, 'access_add', ('%s : %s'):format(entry.type, entry.label))
    return true, T.access_added
end

lib.callback.register('rsg_chest:server:getNearbyNames', function(src, ids)
    local names = {}
    local pos = PedCoords(src)
    if type(ids) ~= 'table' or not pos then return names end
    for _, target in ipairs(ids) do
        target = tonumber(target)
        local P = target and RSGCore.Functions.GetPlayer(target)
        if P and target ~= src and IsNear(target, pos, Config.Sharing.NearbyDistance + 2.0) then
            names[#names + 1] = { id = target, name = CharName(P) }
        end
    end
    return names
end)

lib.callback.register('rsg_chest:server:shareAddPlayer', function(src, id, target)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    target = tonumber(target)
    local Target = target and RSGCore.Functions.GetPlayer(target)
    local pos = PedCoords(src)
    if not Target or not pos or not IsNear(target, pos, Config.Sharing.NearbyDistance + 2.0) then
        return false, T.access_none_near
    end
    return AddAccess(Player, c, { type = 'citizen', value = Target.PlayerData.citizenid, label = CharName(Target) })
end)

lib.callback.register('rsg_chest:server:shareAddGroup', function(src, id, kind)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local pd = Player.PlayerData
    if kind == 'gang' and Config.Sharing.AllowGang and pd.gang and pd.gang.name ~= 'none' then
        return AddAccess(Player, c, { type = 'gang', value = pd.gang.name, label = pd.gang.label or pd.gang.name })
    elseif kind == 'job' and Config.Sharing.AllowJob and pd.job and pd.job.name ~= 'unemployed' then
        return AddAccess(Player, c, { type = 'job', value = pd.job.name, label = pd.job.label or pd.job.name })
    end
    return false, T.not_allowed
end)

lib.callback.register('rsg_chest:server:shareRemove', function(src, id, index)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if c.owner ~= Player.PlayerData.citizenid then return false, T.not_owner end
    local entry = c.shared[tonumber(index)]
    if not entry then return false, T.not_allowed end
    table.remove(c.shared, tonumber(index))
    SaveShared(c)
    Log(c.id, Player, 'access_remove', ('%s : %s'):format(entry.type, entry.label))
    return true, T.access_removed
end)

---------------------------------------------------------------------
-- Mandats
---------------------------------------------------------------------
local function ResolveCitizen(input)
    local num = tonumber(input)
    if num then
        local P = RSGCore.Functions.GetPlayer(num)
        if P then return P.PlayerData.citizenid, CharName(P) end
    end
    if type(input) ~= 'string' or input == '' then return nil end
    local P = RSGCore.Functions.GetPlayerByCitizenId(input)
    if P then return input, CharName(P) end
    local row = MySQL.single.await('SELECT charinfo FROM players WHERE citizenid = ?', { input })
    if not row then return nil end
    local ci = json.decode(row.charinfo or '{}') or {}
    return input, ('%s %s'):format(ci.firstname or '?', ci.lastname or '')
end

lib.callback.register('rsg_chest:server:issueWarrant', function(src, data)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not IsLaw(Player) or Grade(Player) < Config.Warrant.IssueMinGrade then return false, T.not_allowed end
    if type(data) ~= 'table' then return false, T.not_allowed end

    local targetType, target, targetName
    if data.kind == 'chest' then
        local c = Chests[tonumber(data.chest)]
        if not c then return false, T.warrant_bad_target end
        targetType, target, targetName = 'chest', tostring(c.id), ('Coffre #%d (%s)'):format(c.id, c.owner_name or c.owner)
    elseif data.kind == 'owner' then
        local c = Chests[tonumber(data.chest)]
        if not c then return false, T.warrant_bad_target end
        targetType, target, targetName = 'citizen', c.owner, c.owner_name or c.owner
    elseif data.kind == 'citizen' then
        targetType = 'citizen'
        target, targetName = ResolveCitizen(data.citizen)
        if not target then return false, T.warrant_bad_target end
    else
        return false, T.not_allowed
    end

    local hours = math.floor(math.min(math.max(tonumber(data.hours) or Config.Warrant.DefaultHours, 1), Config.Warrant.MaxHours))
    local reason = tostring(data.reason or ''):sub(1, 250)
    local expires = os.time() + hours * 3600
    local id = MySQL.insert.await([[
        INSERT INTO rsg_chests_warrants (target_type, target, target_name, reason, issued_by, issued_name, job, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { targetType, target, targetName, reason, Player.PlayerData.citizenid, CharName(Player), Player.PlayerData.job.name, expires })
    if not id then return false, T.sql_error end

    Warrants[id] = {
        id = id, target_type = targetType, target = target, target_name = targetName, reason = reason,
        issued_by = Player.PlayerData.citizenid, issued_name = CharName(Player), job = Player.PlayerData.job.name,
        expires_at = expires, revoked = 0, uses = 0,
    }

    local details = ('mandat #%d (%dh) : %s'):format(id, hours, reason)
    for _, c in pairs(Chests) do
        if (targetType == 'chest' and tostring(c.id) == target) or (targetType == 'citizen' and c.owner == target) then
            Log(c.id, Player, 'warrant_issue', details)
        end
    end
    return true, T.warrant_issued:format(id)
end)

lib.callback.register('rsg_chest:server:getWarrants', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not IsLaw(Player) then return nil end
    local list, now = {}, os.time()
    for _, w in pairs(Warrants) do
        if w.revoked == 0 and w.expires_at > now then
            list[#list + 1] = {
                id = w.id, target_type = w.target_type, target_name = w.target_name, reason = w.reason,
                issued_name = w.issued_name, minutes = math.floor((w.expires_at - now) / 60), uses = w.uses,
            }
        end
    end
    table.sort(list, function(a, b) return a.id > b.id end)
    return list, Grade(Player) >= Config.Warrant.IssueMinGrade
end)

lib.callback.register('rsg_chest:server:revokeWarrant', function(src, id)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not IsLaw(Player) or Grade(Player) < Config.Warrant.IssueMinGrade then return false, T.not_allowed end
    local w = Warrants[tonumber(id)]
    if not w then return false, T.warrant_bad_target end
    w.revoked = 1
    Warrants[w.id] = nil
    MySQL.update.await('UPDATE rsg_chests_warrants SET revoked = 1 WHERE id = ?', { w.id })
    for _, c in pairs(Chests) do
        if (w.target_type == 'chest' and tostring(c.id) == w.target) or (w.target_type == 'citizen' and c.owner == w.target) then
            Log(c.id, Player, 'warrant_revoke', ('mandat #%d'):format(w.id))
        end
    end
    return true, T.warrant_revoked
end)

local function UseWarrant(w)
    w.uses = (w.uses or 0) + 1
    if Config.Warrant.SingleUse then
        w.revoked = 1
        Warrants[w.id] = nil
    end
    MySQL.update('UPDATE rsg_chests_warrants SET uses = ?, revoked = ? WHERE id = ?', { w.uses, w.revoked, w.id })
end

---------------------------------------------------------------------
-- Perquisition
---------------------------------------------------------------------
lib.callback.register('rsg_chest:server:searchStart', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local ok, msg, warrant = CanSearch(Player, c)
    if not ok then return false, msg end
    Searches[src] = { id = c.id, started = GetGameTimer(), warrant = warrant and warrant.id }
    if Config.Perquisition.NotifyOwner then NotifyOwner(c, T.searched_owner:format(c.id)) end
    return true
end)

lib.callback.register('rsg_chest:server:searchFinish', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local s = Searches[src]
    Searches[src] = nil
    -- la fouille doit avoir réellement duré (anti-trigger)
    if not s or s.id ~= c.id or GetGameTimer() - s.started < Config.Perquisition.Duration * 0.9 then
        return false, T.not_allowed
    end
    local ok, msg, warrant = CanSearch(Player, c)
    if not ok then return false, msg end

    c.last_search = os.time()
    MySQL.update('UPDATE rsg_chests SET last_search = ? WHERE id = ?', { c.last_search, c.id })
    if warrant then UseWarrant(warrant) end
    Log(c.id, Player, 'search', ('propriétaire : %s | %s'):format(c.owner_name or c.owner,
        warrant and ('mandat #%d'):format(warrant.id) or 'sans mandat'))
    OpenStash(src, c)
    return true
end)

---------------------------------------------------------------------
-- Scellés : le contenu saisi est déplacé, jamais perdu
---------------------------------------------------------------------
local function EvidenceStash(eid) return 'rsgchest_evidence_' .. eid end

local function MoveToEvidence(c, Player, warrant)
    local items = GetStashItems(StashId(c.id))
    local count = CountItems(items)
    if count == 0 then return nil end

    local eid = MySQL.insert.await([[
        INSERT INTO rsg_chests_evidence (chest_id, owner, owner_name, warrant_id, seized_by, seized_name, job, items)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ]], { c.id, c.owner, c.owner_name, warrant and warrant.id, Player.PlayerData.citizenid, CharName(Player),
        Player.PlayerData.job.name, count })
    if not eid then return false end

    local ok = MySQL.insert.await([[
        INSERT INTO inventories (identifier, items) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE items = VALUES(items)
    ]], { EvidenceStash(eid), json.encode(items) })
    if ok == nil then
        MySQL.query.await('DELETE FROM rsg_chests_evidence WHERE id = ?', { eid })
        return false
    end
    return eid
end

lib.callback.register('rsg_chest:server:seize', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    local P = Config.Perquisition
    if not P.CanSeize or not IsLaw(Player) or Grade(Player) < P.SeizeMinGrade then return false, T.not_allowed end
    local warrant = ActiveWarrant(c)
    if Config.Warrant.SeizeRequiresWarrant and not warrant then return false, T.no_warrant end
    if IsStashOpen(c.id) then return false, T.stash_in_use end
    local empty = IsStashEmpty(c.id)
    if P.SeizeRequireEmpty and not empty then return false, T.not_empty end

    local eid
    if not empty and Config.Evidence.Enabled then
        eid = MoveToEvidence(c, Player, warrant)
        -- en cas d'échec on ne supprime rien : aucun objet ne doit disparaître
        if eid == false then return false, T.sql_error end
    end

    local cfg = Config.Chests[c.type]
    if warrant then UseWarrant(warrant) end
    local contents = empty and 'vide' or (eid and ('scellé #%d'):format(eid) or 'détruit')
    Log(c.id, Player, 'seize', ('propriétaire : %s | contenu %s | %s'):format(c.owner_name or c.owner,
        contents, warrant and ('mandat #%d'):format(warrant.id) or 'sans mandat'))
    NotifyOwner(c, T.searched_owner:format(c.id))
    RemoveChest(c.id)
    if P.SeizeGiveItem and cfg then AddItem(src, Player, cfg.item) end
    return true, eid and T.evidence_saved:format(eid) or T.seized
end)

local function AtEvidenceLocation(src)
    local locs = Config.Evidence.Locations
    if not locs or #locs == 0 then return true end
    for _, l in ipairs(locs) do
        if IsNear(src, l.coords, l.radius or 5.0) then return true end
    end
    return false
end

lib.callback.register('rsg_chest:server:getEvidence', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    if not Player or not IsLaw(Player) or Grade(Player) < Config.Evidence.MinGrade then return nil, T.not_allowed end
    if not AtEvidenceLocation(src) then return nil, T.evidence_not_here end
    return MySQL.query.await([[
        SELECT id, chest_id, owner_name, seized_name, warrant_id, items, DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS date
        FROM rsg_chests_evidence ORDER BY id DESC LIMIT ?
    ]], { Config.Evidence.ListLimit }) or {}
end)

lib.callback.register('rsg_chest:server:openEvidence', function(src, eid)
    local Player = RSGCore.Functions.GetPlayer(src)
    eid = tonumber(eid)
    if not Player or not eid or not IsLaw(Player) or Grade(Player) < Config.Evidence.MinGrade then return false, T.not_allowed end
    if not AtEvidenceLocation(src) then return false, T.evidence_not_here end
    local row = MySQL.single.await('SELECT id, chest_id FROM rsg_chests_evidence WHERE id = ?', { eid })
    if not row then return false, T.evidence_empty end
    Log(row.chest_id, Player, 'evidence_open', ('scellé #%d'):format(eid))
    exports['rsg-inventory']:OpenInventory(src, EvidenceStash(eid), {
        label = T.evidence_label:format(eid),
        maxweight = Config.Evidence.Weight,
        slots = Config.Evidence.Slots,
    })
    return true
end)

lib.callback.register('rsg_chest:server:getLogs', function(src, id)
    local Player = RSGCore.Functions.GetPlayer(src)
    local c = Chests[tonumber(id)]
    if not Player or not c then return nil end
    if c.owner ~= Player.PlayerData.citizenid and not IsLaw(Player) and not IsAdmin(src) then return nil end
    return MySQL.query.await([[
        SELECT action, name, job, details, DATE_FORMAT(date, '%d/%m/%Y %H:%i') AS date
        FROM rsg_chests_logs WHERE chest_id = ? ORDER BY id DESC LIMIT ?
    ]], { c.id, Config.LogsLimit }) or {}
end)

---------------------------------------------------------------------
-- Crochetage
---------------------------------------------------------------------
local LP = Config.Lockpick

lib.callback.register('rsg_chest:server:lockpickStart', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not LP.Enabled or (IsLaw(Player) and not LP.LawCanLockpick) or c.owner == Player.PlayerData.citizenid then
        return false, T.not_allowed
    end
    if not HasItem(Player, LP.Item) then return false, T.need_item:format(ItemLabel(LP.Item)) end
    local left = (LockpickCooldown[c.id] or 0) - os.time()
    if left > 0 then return false, T.lockpick_cooldown:format(left) end

    LockpickCooldown[c.id] = os.time() + LP.ChestCooldown
    local wheels = math.min(math.max(LP.Wheels, 3), 8)
    local digits = {}
    for i = 1, wheels do digits[i] = math.random(0, 9) end
    Lockpicks[src] = { id = c.id, started = GetGameTimer(), fails = 0, wheels = wheels }

    Log(c.id, Player, 'lockpick_start')
    if math.random(100) <= LP.AlertChance then AlertLaw(c.coords, T.alert_lockpick) end
    if LP.NotifyOwner then NotifyOwner(c, T.lockpick_owner:format(c.id)) end
    return true, { digits = digits, time = LP.TimeLimit }
end)

local function BreakPick(src, Player, s, reason)
    RemoveItem(src, Player, LP.Item)
    Lockpicks[src] = nil
    Log(s.id, Player, 'lockpick_broken', reason)
end

lib.callback.register('rsg_chest:server:lockpickFail', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    local s = Lockpicks[src]
    if not Player or not s then return { broken = true, msg = T.not_allowed } end
    s.fails = s.fails + 1
    if s.fails >= LP.MaxFails or math.random(100) <= LP.BreakChance then
        BreakPick(src, Player, s, ('erreur %d'):format(s.fails))
        return { broken = true, msg = T.lockpick_broken }
    end
    return { broken = false, msg = T.lockpick_slip }
end)

lib.callback.register('rsg_chest:server:lockpickSuccess', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    local s = Lockpicks[src]
    Lockpicks[src] = nil
    if not Player or not s then return false, T.not_allowed end
    local c = Chests[s.id]
    if not c or not IsNear(src, c.coords, Config.InteractDistance + 1.5) then return false, T.too_far end

    local elapsed = (GetGameTimer() - s.started) / 1000
    if elapsed < s.wheels * LP.MinSecondsPerWheel or elapsed > LP.TimeLimit + 5 then
        Log(c.id, Player, 'lockpick_fail', 'durée invalide')
        return false, T.lockpick_timeout
    end

    if math.random(100) <= LP.BreakOnSuccessChance then
        BreakPick(src, Player, s, 'cassé en réussite')
        Notify(src, T.lockpick_broken, 'error')
    end
    Log(c.id, Player, 'lockpick_success')
    OpenStash(src, c)
    return true, T.lockpick_success
end)

lib.callback.register('rsg_chest:server:lockpickCancel', function(src)
    local Player = RSGCore.Functions.GetPlayer(src)
    local s = Lockpicks[src]
    Lockpicks[src] = nil
    if Player and s then Log(s.id, Player, 'lockpick_fail', 'abandon / temps écoulé') end
    return true
end)

---------------------------------------------------------------------
-- Dynamite
---------------------------------------------------------------------
local DY = Config.Dynamite

lib.callback.register('rsg_chest:server:dynamitePlant', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not DY.Enabled or (IsLaw(Player) and not DY.LawCanUse) or c.owner == Player.PlayerData.citizenid then
        return false, T.not_allowed
    end
    if Dynamites[c.id] then return false, T.dynamite_armed end
    if IsBroken(c) then return false, T.not_allowed end
    if not HasItem(Player, DY.Item) or not RemoveItem(src, Player, DY.Item) then
        return false, T.need_item:format(ItemLabel(DY.Item))
    end

    Dynamites[c.id] = true
    Log(c.id, Player, 'dynamite', ('mèche %ds'):format(DY.Fuse))
    if DY.AlertOnPlant then AlertLaw(c.coords, T.alert_dynamite) end

    SetTimeout(DY.Fuse * 1000, function()
        if not Chests[c.id] then return end
        Dynamites[c.id] = nil
        -- l'explosion est créée par le poseur (explosion réseau), sinon par le joueur le plus proche
        local shooter = IsNear(src, c.coords, 150.0) and src or nil
        if not shooter then
            ForEachPlayer(function(p) if not shooter and IsNear(p, c.coords, 150.0) then shooter = p end end)
        end
        if shooter then
            TriggerClientEvent('rsg_chest:client:explode', shooter, { x = c.coords.x, y = c.coords.y, z = c.coords.z })
        end
        c.broken_until = os.time() + DY.OpenTime
        MySQL.update('UPDATE rsg_chests SET broken_until = ? WHERE id = ?', { c.broken_until, c.id })
        Log(c.id, nil, 'exploded', ('ouvert à tous pendant %d min'):format(math.floor(DY.OpenTime / 60)))
        if not DY.AlertOnPlant then AlertLaw(c.coords, T.alert_dynamite) end
        NotifyOwner(c, T.alert_dynamite)
    end)
    return true, T.dynamite_lit:format(DY.Fuse)
end)

lib.callback.register('rsg_chest:server:openBroken', function(src, id)
    local Player, c, err = GetContext(src, id)
    if not Player then return false, err end
    if not IsBroken(c) then return false, T.not_allowed end
    Log(c.id, Player, 'loot')
    OpenStash(src, c)
    return true
end)

-- Coffres éventrés : suppression ou fermeture à la fin du délai
CreateThread(function()
    while true do
        Wait(30000)
        local now = os.time()
        for id, c in pairs(Chests) do
            if c.broken_until and c.broken_until > 0 and c.broken_until <= now then
                if DY.RemoveAfter then
                    Log(id, nil, 'destroyed', 'coffre dynamité')
                    NotifyOwner(c, T.chest_destroyed:format(id))
                    RemoveChest(id)
                else
                    c.broken_until = 0
                    MySQL.update('UPDATE rsg_chests SET broken_until = 0 WHERE id = ?', { id })
                end
            end
        end
    end
end)

---------------------------------------------------------------------
-- Coffres abandonnés
---------------------------------------------------------------------
local function CleanAbandoned()
    local AB = Config.Abandon
    if not AB.Enabled then return end
    local rows = MySQL.query.await([[
        SELECT c.id, (p.citizenid IS NULL) AS missing
        FROM rsg_chests c
        LEFT JOIN players p ON p.citizenid = c.owner
        WHERE p.citizenid IS NULL OR p.last_updated < (NOW() - INTERVAL ? DAY)
    ]], { AB.Days }) or {}
    -- sécurité : si la requête renvoie presque tous les coffres, la table `players`
    -- ne correspond probablement pas (autre framework, colonne renommée) -> on n'efface rien
    local total = 0
    for _ in pairs(Chests) do total = total + 1 end
    if #rows > 5 and #rows > total * 0.5 then
        print(('[rsg_chest] ^3Nettoyage annulé : %d coffres sur %d seraient supprimés. Vérifiez la table players (citizenid, last_updated).^7'):format(#rows, total))
        return
    end

    local removed = 0
    for _, row in ipairs(rows) do
        local missing = row.missing == 1 or row.missing == true
        if Chests[row.id] and (not missing or AB.DeleteIfNoCharacter) then
            -- ne jamais supprimer le coffre d'un joueur connecté
            if not RSGCore.Functions.GetPlayerByCitizenId(Chests[row.id].owner) then
                Log(row.id, nil, 'abandoned', missing and 'personnage supprimé' or ('inactif depuis %d jours'):format(AB.Days))
                RemoveChest(row.id)
                removed = removed + 1
            end
        end
    end
    if removed > 0 then print(('[rsg_chest] %d coffre(s) abandonné(s) supprimé(s)'):format(removed)) end
end

CreateThread(function()
    Wait(60000)
    while true do
        local ok, err = pcall(CleanAbandoned)
        if not ok then print('[rsg_chest] ^1nettoyage des coffres abandonnés : ' .. tostring(err) .. '^7') end
        Wait(math.max(Config.Abandon.CheckEveryHours, 1) * 3600 * 1000)
    end
end)

AddEventHandler('playerDropped', function()
    Searches[source] = nil
    Lockpicks[source] = nil
end)

---------------------------------------------------------------------
-- Admin
---------------------------------------------------------------------
lib.callback.register('rsg_chest:server:adminList', function(src)
    if not IsAdmin(src) then return nil end
    local list = {}
    for _, c in pairs(Chests) do
        list[#list + 1] = {
            id = c.id, type = c.type, owner = c.owner_name or c.owner,
            coords = { x = c.coords.x, y = c.coords.y, z = c.coords.z },
            broken = IsBroken(c), shared = #c.shared,
        }
    end
    return list
end)

lib.callback.register('rsg_chest:server:adminOpen', function(src, id)
    if not IsAdmin(src) then return false, T.not_allowed end
    local c = Chests[tonumber(id)]
    if not c then return false, T.admin_not_found end
    Log(c.id, RSGCore.Functions.GetPlayer(src), 'admin_open')
    OpenStash(src, c)
    return true
end)

lib.callback.register('rsg_chest:server:adminDelete', function(src, id)
    if not IsAdmin(src) then return false, T.not_allowed end
    id = tonumber(id)
    if not id or not Chests[id] then return false, T.admin_not_found end
    Log(id, RSGCore.Functions.GetPlayer(src), 'admin_delete')
    RemoveChest(id)
    return true, T.admin_deleted:format(id)
end)

RSGCore.Commands.Add('chestadmin', T.cmd_admin, {}, false, function(source)
    TriggerClientEvent('rsg_chest:client:adminMenu', source)
end, Config.Admin.Permission)

RSGCore.Commands.Add('chestdelete', T.cmd_delete, { { name = 'id', help = T.cmd_delete_arg } }, true,
    function(source, args)
        local id = tonumber(args[1])
        if not id or not Chests[id] then return Notify(source, T.admin_not_found, 'error') end
        Log(id, RSGCore.Functions.GetPlayer(source), 'admin_delete')
        RemoveChest(id)
        Notify(source, T.admin_deleted:format(id), 'success')
    end, Config.Admin.Permission)

RSGCore.Commands.Add('chestnearest', T.cmd_nearest, {}, false, function(source)
    local pos = PedCoords(source)
    if not pos then return end
    local best, bestDist
    for _, c in pairs(Chests) do
        local d = #(c.coords - pos)
        if not bestDist or d < bestDist then best, bestDist = c, d end
    end
    if not best then return Notify(source, T.admin_none, 'error') end
    Notify(source, T.admin_nearest:format(best.id, best.type, best.owner_name or best.owner, bestDist))
end, Config.Admin.Permission)

RSGCore.Commands.Add('chestclean', T.cmd_clean, {}, false, function(source)
    CleanAbandoned()
    Notify(source, T.admin_clean_done, 'success')
end, Config.Admin.Permission)
