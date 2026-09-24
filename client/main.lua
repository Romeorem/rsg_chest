local RSGCore = exports['rsg-core']:GetCoreObject()
local T = Config.Text

local Chests = {}      -- [id] = { id, type, model, coords, rot, owner, label, entity }
local PlayerData = {}
local Loaded = false

function GetLoadedChests() return Chests end

---------------------------------------------------------------------
-- Utilitaires
---------------------------------------------------------------------
local function toVec(t) return vector3(t.x + 0.0, t.y + 0.0, t.z + 0.0) end

local function PlayScenario(scenario)
    TaskStartScenarioInPlace(PlayerPedId(), GetHashKey(scenario), -1, true, false, false, false)
end

local function Mismatch(a, b)
    if a ~= b then return false, T.code_mismatch end
    return true
end

---------------------------------------------------------------------
-- Spawn des props
---------------------------------------------------------------------
local function AddTarget(chest)
    if Config.Interaction ~= 'target' then return end
    if Config.TargetResource == 'ox_target' then
        exports.ox_target:addLocalEntity(chest.entity, {
            { name = 'rsg_chest_' .. chest.id, icon = 'fas fa-box', label = T.prompt_interact,
              distance = Config.InteractDistance, onSelect = function() OpenChestMenu(chest.id) end },
        })
    else
        exports['rsg-target']:AddTargetEntity(chest.entity, {
            options = {
                { icon = 'fas fa-box', label = T.prompt_interact, action = function() OpenChestMenu(chest.id) end },
            },
            distance = Config.InteractDistance,
        })
    end
end

local function SpawnChest(chest)
    local hash = GetHashKey(chest.model)
    if not IsModelInCdimage(hash) then
        print(('[rsg_chest] ^1Modèle introuvable : %s (coffre #%d)^7'):format(chest.model, chest.id))
        return
    end
    lib.requestModel(hash, 5000)
    local obj = CreateObject(hash, chest.coords.x, chest.coords.y, chest.coords.z, false, false, false)
    SetEntityCoordsNoOffset(obj, chest.coords.x, chest.coords.y, chest.coords.z, false, false, false)
    SetEntityRotation(obj, chest.rot.x, chest.rot.y, chest.rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    SetModelAsNoLongerNeeded(hash)
    chest.entity = obj
    AddTarget(chest)
end

local function DespawnChest(chest)
    if chest.entity and DoesEntityExist(chest.entity) then
        DeleteEntity(chest.entity)
    end
    chest.entity = nil
end

local function RegisterChest(data)
    local chest = {
        id = data.id, type = data.type, model = data.model, owner = data.owner,
        coords = toVec(data.coords), rot = toVec(data.rot),
        label = (Config.Chests[data.type] and Config.Chests[data.type].label or 'Coffre') .. ' #' .. data.id,
    }
    if Chests[chest.id] then DespawnChest(Chests[chest.id]) end
    Chests[chest.id] = chest
end

local function LoadChests()
    for _, c in pairs(Chests) do DespawnChest(c) end
    Chests = {}
    local list = lib.callback.await('rsg_chest:server:getChests', false) or {}
    for _, data in ipairs(list) do RegisterChest(data) end
    Loaded = true
end

CreateThread(function()
    while true do
        if Loaded then
            local pos = GetEntityCoords(PlayerPedId())
            for _, chest in pairs(Chests) do
                local dist = #(pos - chest.coords)
                if dist < Config.SpawnDistance and not chest.entity then
                    SpawnChest(chest)
                elseif dist >= Config.SpawnDistance and chest.entity then
                    DespawnChest(chest)
                end
            end
        end
        Wait(1000)
    end
end)

RegisterNetEvent('rsg_chest:client:addChest', function(data) RegisterChest(data) end)

RegisterNetEvent('rsg_chest:client:removeChest', function(id)
    if Chests[id] then
        DespawnChest(Chests[id])
        Chests[id] = nil
    end
end)

---------------------------------------------------------------------
-- Données joueur
---------------------------------------------------------------------
RegisterNetEvent('RSGCore:Client:OnPlayerLoaded', function()
    PlayerData = RSGCore.Functions.GetPlayerData()
    LoadChests()
end)

RegisterNetEvent('RSGCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)

RegisterNetEvent('RSGCore:Client:OnJobUpdate', function(job)
    PlayerData.job = job
end)

RegisterNetEvent('RSGCore:Player:SetPlayerData', function(data)
    PlayerData = data
end)

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    if LocalPlayer.state.isLoggedIn then
        PlayerData = RSGCore.Functions.GetPlayerData()
        LoadChests()
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, c in pairs(Chests) do DespawnChest(c) end
end)

---------------------------------------------------------------------
-- Placement d'un coffre (depuis l'item)
---------------------------------------------------------------------
RegisterNetEvent('rsg_chest:client:startPlacement', function(chestType)
    local cfg = Config.Chests[chestType]
    if not cfg then return end

    local coords, rot = StartPlacement(cfg.model)
    if not coords then
        lib.notify({ description = T.cancelled, type = 'inform' })
        return
    end

    local input = RequestCode({
        title = T.title_new,
        steps = { T.input_code, T.input_confirm },
        onSubmit = function(v) return Mismatch(v[1], v[2]) end,
    })
    if not input then return end

    PlayScenario('WORLD_HUMAN_CROUCH_INSPECT')
    local done = lib.progressBar({
        duration = Config.Placement.PlaceDuration, label = T.placing,
        useWhileDead = false, canCancel = true, disable = { move = true, combat = true },
    })
    ClearPedTasks(PlayerPedId())
    if not done then
        lib.notify({ description = T.cancelled, type = 'inform' })
        return
    end

    local ok, msg = lib.callback.await('rsg_chest:server:place', false, chestType,
        { x = coords.x, y = coords.y, z = coords.z }, { x = rot.x, y = rot.y, z = rot.z }, input[1])
    lib.notify({ description = msg, type = ok and 'success' or 'error' })
end)

---------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------
local function Notify(ok, msg)
    if msg then lib.notify({ description = msg, type = ok and 'success' or 'error' }) end
end

local function Progress(duration, label)
    PlayScenario('WORLD_HUMAN_CROUCH_INSPECT')
    local done = lib.progressBar({
        duration = duration, label = label,
        useWhileDead = false, canCancel = true, disable = { move = true, combat = true },
    })
    ClearPedTasks(PlayerPedId())
    if not done then Notify(false, T.cancelled) end
    return done
end

local function OpenWithCode(id)
    RequestCode({
        title = Chests[id] and Chests[id].label or T.menu_open,
        steps = { T.input_code },
        onSubmit = function(v)
            return lib.callback.await('rsg_chest:server:openWithCode', false, id, v[1])
        end,
    })
end

local function ChangeCode(id)
    RequestCode({
        title = T.menu_change,
        steps = { T.input_old, T.input_new, T.input_confirm },
        onSubmit = function(v)
            local ok, msg = Mismatch(v[2], v[3])
            if not ok then return ok, msg end
            return lib.callback.await('rsg_chest:server:changeCode', false, id, v[1], v[2])
        end,
    })
end

local function Pickup(id)
    RequestCode({
        title = T.menu_pickup,
        steps = { T.input_code },
        onSubmit = function(v)
            return lib.callback.await('rsg_chest:server:pickup', false, id, v[1])
        end,
    })
end

local function Search(id)
    local ok, msg = lib.callback.await('rsg_chest:server:searchStart', false, id)
    if not ok then return Notify(false, msg) end
    if not Progress(Config.Perquisition.Duration, T.searching) then return end
    ok, msg = lib.callback.await('rsg_chest:server:searchFinish', false, id)
    if not ok then Notify(false, msg) end
end

local function Seize(id)
    local answer = lib.alertDialog({
        header = T.seize_confirm, content = T.seize_confirm_d, centered = true, cancel = true,
    })
    if answer ~= 'confirm' then return end
    Notify(lib.callback.await('rsg_chest:server:seize', false, id))
end

local function ShowLogs(id)
    local logs = lib.callback.await('rsg_chest:server:getLogs', false, id)
    if not logs then return Notify(false, T.not_allowed) end
    local options = {}
    for _, log in ipairs(logs) do
        options[#options + 1] = {
            title = ('%s — %s'):format(log.action, log.name or 'Système'),
            description = ('%s%s%s'):format(log.date or '', log.job and (' | ' .. log.job) or '',
                log.details and (' | ' .. log.details) or ''),
            readOnly = true,
        }
    end
    if #options == 0 then options[1] = { title = T.no_logs, readOnly = true } end
    lib.registerContext({ id = 'rsg_chest_logs', title = T.menu_logs, menu = 'rsg_chest_menu', options = options })
    lib.showContext('rsg_chest_logs')
end

---------------------------------------------------------------------
-- Partage
---------------------------------------------------------------------
local ShowAccess

local function AddNearbyPlayer(id)
    local ids = {}
    for _, p in ipairs(lib.getNearbyPlayers(GetEntityCoords(PlayerPedId()), Config.Sharing.NearbyDistance, false)) do
        ids[#ids + 1] = GetPlayerServerId(p.id)
    end
    local names = #ids > 0 and lib.callback.await('rsg_chest:server:getNearbyNames', false, ids) or {}
    if #names == 0 then return Notify(false, T.access_none_near) end

    local options = {}
    for _, p in ipairs(names) do
        options[#options + 1] = {
            title = p.name, description = ('ID %d'):format(p.id), icon = 'user-plus',
            onSelect = function()
                Notify(lib.callback.await('rsg_chest:server:shareAddPlayer', false, id, p.id))
                ShowAccess(id)
            end,
        }
    end
    lib.registerContext({ id = 'rsg_chest_access_add', title = T.access_add_player, menu = 'rsg_chest_access', options = options })
    lib.showContext('rsg_chest_access_add')
end

ShowAccess = function(id)
    local info = lib.callback.await('rsg_chest:server:getChestInfo', false, id)
    if not info or not info.isOwner then return end
    local kinds = { citizen = T.access_player, gang = T.access_gang, job = T.access_job }
    local icons = { citizen = 'user', gang = 'users', job = 'briefcase' }

    local options = {
        { title = T.access_add_player, icon = 'user-plus', onSelect = function() AddNearbyPlayer(id) end },
    }
    if info.gang then
        options[#options + 1] = { title = T.access_add_gang:format(info.gangLabel or info.gang), icon = 'users',
            onSelect = function()
                Notify(lib.callback.await('rsg_chest:server:shareAddGroup', false, id, 'gang'))
                ShowAccess(id)
            end }
    end
    if info.job then
        options[#options + 1] = { title = T.access_add_job:format(info.jobLabel or info.job), icon = 'briefcase',
            onSelect = function()
                Notify(lib.callback.await('rsg_chest:server:shareAddGroup', false, id, 'job'))
                ShowAccess(id)
            end }
    end
    for i, a in ipairs(info.shared or {}) do
        options[#options + 1] = {
            title = a.label, description = ('%s · %s'):format(kinds[a.type] or a.type, T.access_remove),
            icon = icons[a.type] or 'user',
            onSelect = function()
                Notify(lib.callback.await('rsg_chest:server:shareRemove', false, id, i))
                ShowAccess(id)
            end,
        }
    end
    lib.registerContext({ id = 'rsg_chest_access', title = T.access_title, menu = 'rsg_chest_menu', options = options })
    lib.showContext('rsg_chest_access')
end

---------------------------------------------------------------------
-- Mandats
---------------------------------------------------------------------
local function IssueWarrant(chestId)
    local targets = {}
    if chestId then
        targets[#targets + 1] = { value = 'chest', label = T.warrant_t_chest:format(chestId) }
        targets[#targets + 1] = { value = 'owner', label = T.warrant_t_owner }
    end
    targets[#targets + 1] = { value = 'citizen', label = T.warrant_t_citizen }

    local input = lib.inputDialog(T.warrant_title, {
        { type = 'select', label = T.warrant_target, options = targets, default = targets[1].value, required = true },
        { type = 'input', label = T.warrant_citizen },
        { type = 'input', label = T.warrant_reason, required = true, max = 250 },
        { type = 'number', label = T.warrant_hours, default = Config.Warrant.DefaultHours,
          min = 1, max = Config.Warrant.MaxHours, required = true },
    })
    if not input then return end
    Notify(lib.callback.await('rsg_chest:server:issueWarrant', false, {
        kind = input[1], chest = chestId, citizen = input[2], reason = input[3], hours = input[4],
    }))
end

local function ShowWarrants()
    local list, canRevoke = lib.callback.await('rsg_chest:server:getWarrants', false)
    if not list then return Notify(false, T.not_allowed) end
    local options = {}
    for _, w in ipairs(list) do
        local hours = math.floor(w.minutes / 60)
        options[#options + 1] = {
            title = ('#%d — %s'):format(w.id, w.target_name or '?'),
            description = ('%s | %s | %dh%02d restantes | %d fouille(s)'):format(
                w.reason or '', w.issued_name or '', hours, w.minutes % 60, w.uses or 0),
            icon = 'file-signature',
            readOnly = not canRevoke,
            onSelect = canRevoke and function()
                local answer = lib.alertDialog({ header = T.warrant_revoke .. (' #%d ?'):format(w.id), centered = true, cancel = true })
                if answer == 'confirm' then
                    Notify(lib.callback.await('rsg_chest:server:revokeWarrant', false, w.id))
                end
            end or nil,
        }
    end
    if #options == 0 then options[1] = { title = T.warrant_empty, readOnly = true } end
    lib.registerContext({ id = 'rsg_chest_warrants', title = T.warrant_list, options = options })
    lib.showContext('rsg_chest_warrants')
end

RegisterCommand('mandat', function() IssueWarrant(nil) end, false)
RegisterCommand('mandats', function() ShowWarrants() end, false)

---------------------------------------------------------------------
-- Crochetage & dynamite
---------------------------------------------------------------------
local function Lockpick(id)
    local ok, data = lib.callback.await('rsg_chest:server:lockpickStart', false, id)
    if not ok then return Notify(false, data) end

    PlayScenario('WORLD_HUMAN_CROUCH_INSPECT')
    local result = RequestLockpick({
        title = T.lockpick_title,
        digits = data.digits,
        time = data.time,
        onFail = function()
            return lib.callback.await('rsg_chest:server:lockpickFail', false)
        end,
    })
    ClearPedTasks(PlayerPedId())

    if result == 'success' then
        Notify(lib.callback.await('rsg_chest:server:lockpickSuccess', false))
    elseif result == 'broken' then
        Notify(false, T.lockpick_broken)
    else
        lib.callback.await('rsg_chest:server:lockpickCancel', false)
        Notify(false, result == 'timeout' and T.lockpick_timeout or T.cancelled)
    end
end

local function Dynamite(id)
    if not Progress(Config.Dynamite.PlantDuration, T.dynamite_plant) then return end
    local ok, msg = lib.callback.await('rsg_chest:server:dynamitePlant', false, id)
    Notify(ok, msg)
    if not ok then return end

    CreateThread(function()
        for left = Config.Dynamite.Fuse, 1, -1 do
            lib.showTextUI(T.dynamite_countdown:format(left))
            Wait(1000)
        end
        lib.hideTextUI()
    end)
end

local function OpenBroken(id)
    local ok, msg = lib.callback.await('rsg_chest:server:openBroken', false, id)
    if not ok then Notify(false, msg) end
end

RegisterNetEvent('rsg_chest:client:explode', function(c)
    AddExplosion(c.x + 0.0, c.y + 0.0, c.z + 0.2, Config.Dynamite.ExplosionType, 1.0, true, false, 1.0)
end)

---------------------------------------------------------------------
-- Alertes (forces de l'ordre)
---------------------------------------------------------------------
RegisterNetEvent('rsg_chest:client:lawAlert', function(c, message)
    lib.notify({ title = T.alert_blip, description = message, type = 'warning', duration = 10000 })
    -- zone approximative, pas la position exacte
    local r = Config.Alerts.BlipRadius
    local x = c.x + (math.random() - 0.5) * r
    local y = c.y + (math.random() - 0.5) * r
    local blip = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, x, y, c.z, r) -- BlipAddForRadius
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, T.alert_blip)                   -- SetBlipName
    SetTimeout(Config.Alerts.BlipTime * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end)
end)

---------------------------------------------------------------------
-- Menu du coffre
---------------------------------------------------------------------
function OpenChestMenu(id)
    local chest = Chests[id]
    if not chest then return end
    local info = lib.callback.await('rsg_chest:server:getChestInfo', false, id)
    if not info then return Notify(false, T.too_far) end

    local options = {}
    local function add(opt) options[#options + 1] = opt end

    if info.broken then
        add({ title = T.menu_loot, description = T.menu_loot_d, icon = 'box-open', onSelect = function() OpenBroken(id) end })
    else
        if info.hasAccess then
            add({ title = T.menu_open_shared, description = T.menu_open_shared_d, icon = 'lock-open',
                onSelect = function()
                    local ok, msg = lib.callback.await('rsg_chest:server:openShared', false, id)
                    if not ok then Notify(false, msg) end
                end })
        end
        add({ title = T.menu_open, description = T.menu_open_desc, icon = 'lock', onSelect = function() OpenWithCode(id) end })
    end

    if info.isOwner then
        add({ title = T.menu_change, icon = 'key', onSelect = function() ChangeCode(id) end })
        if info.shared then
            add({ title = T.menu_access, description = ('%d / %d'):format(#info.shared, Config.Sharing.Max),
                icon = 'users', onSelect = function() ShowAccess(id) end })
        end
        add({ title = T.menu_pickup, icon = 'hand', onSelect = function() Pickup(id) end })
        add({ title = T.menu_logs, icon = 'list', onSelect = function() ShowLogs(id) end })
    end

    if not info.broken and not info.armed then
        if info.canLockpick then
            add({ title = T.menu_lockpick, description = T.menu_lockpick_d, icon = 'unlock-keyhole', onSelect = function() Lockpick(id) end })
        end
        if info.canDynamite then
            add({ title = T.menu_dynamite, description = T.menu_dynamite_d, icon = 'bomb', onSelect = function() Dynamite(id) end })
        end
    end

    if info.isLaw then
        local warrantText = info.warrant and T.warrant_valid:format(info.warrant) or T.warrant_none
        add({ title = T.menu_search, description = ('%s · %s'):format(warrantText, info.ownerName or ''),
            icon = 'magnifying-glass', onSelect = function() Search(id) end })
        if info.canIssue then
            add({ title = T.menu_warrant, icon = 'file-signature', onSelect = function() IssueWarrant(id) end })
        end
        if info.canSeize then
            add({ title = T.menu_seize, icon = 'gavel', onSelect = function() Seize(id) end })
        end
        if not info.isOwner then
            add({ title = T.menu_logs, icon = 'list', onSelect = function() ShowLogs(id) end })
        end
    end

    lib.registerContext({ id = 'rsg_chest_menu', title = chest.label, options = options })
    lib.showContext('rsg_chest_menu')
end

---------------------------------------------------------------------
-- Prompt natif RedM
---------------------------------------------------------------------
if Config.Interaction == 'prompt' then
    CreateThread(function()
        local group = GetRandomIntInRange(0, 0xffffff)
        local prompt = PromptRegisterBegin()
        PromptSetControlAction(prompt, Config.PromptKey)
        PromptSetText(prompt, CreateVarString(10, 'LITERAL_STRING', T.prompt_interact))
        PromptSetEnabled(prompt, true)
        PromptSetVisible(prompt, true)
        PromptSetHoldMode(prompt, true)
        PromptSetGroup(prompt, group, 0)
        PromptRegisterEnd(prompt)

        while true do
            local sleep = 750
            if Loaded then
                local pos = GetEntityCoords(PlayerPedId())
                local nearest, nearestDist
                for _, chest in pairs(Chests) do
                    if chest.entity then
                        local d = #(pos - chest.coords)
                        if d <= Config.InteractDistance and (not nearestDist or d < nearestDist) then
                            nearest, nearestDist = chest, d
                        end
                    end
                end
                if nearest then
                    sleep = 0
                    PromptSetActiveGroupThisFrame(group, CreateVarString(10, 'LITERAL_STRING', nearest.label))
                    if PromptHasHoldModeCompleted(prompt) then
                        OpenChestMenu(nearest.id)
                        Wait(1000)
                    end
                end
            end
            Wait(sleep)
        end
    end)
end
