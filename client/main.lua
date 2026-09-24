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

local function IsLaw()
    local job = PlayerData.job
    if not job then return false end
    local P = Config.Perquisition
    if P.RequireOnDuty and not job.onduty then return false end
    local minGrade = P.Jobs[job.name]
    local grade = job.grade and job.grade.level or 0
    if minGrade and grade >= minGrade then return true end
    return P.AllowJobTypeLeo and job.type == 'leo'
end

local function JobGrade()
    return PlayerData.job and PlayerData.job.grade and PlayerData.job.grade.level or 0
end

local function IsOwner(chest)
    return PlayerData.citizenid and chest.owner == PlayerData.citizenid
end

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

    PlayScenario('WORLD_HUMAN_CROUCH_INSPECT')
    local done = lib.progressBar({
        duration = Config.Perquisition.Duration, label = T.searching,
        useWhileDead = false, canCancel = true, disable = { move = true, combat = true },
    })
    ClearPedTasks(PlayerPedId())
    if not done then return Notify(false, T.cancelled) end

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
            title = ('%s — %s'):format(log.action, log.name or '?'),
            description = ('%s%s%s'):format(log.date or '', log.job and (' | ' .. log.job) or '',
                log.details and (' | ' .. log.details) or ''),
            readOnly = true,
        }
    end
    if #options == 0 then options[1] = { title = T.no_logs, readOnly = true } end
    lib.registerContext({ id = 'rsg_chest_logs', title = T.menu_logs, menu = 'rsg_chest_menu', options = options })
    lib.showContext('rsg_chest_logs')
end

function OpenChestMenu(id)
    local chest = Chests[id]
    if not chest then return end

    local options = {
        { title = T.menu_open, description = T.menu_open_desc, icon = 'lock', onSelect = function() OpenWithCode(id) end },
    }
    if IsOwner(chest) then
        options[#options + 1] = { title = T.menu_change, icon = 'key', onSelect = function() ChangeCode(id) end }
        options[#options + 1] = { title = T.menu_pickup, icon = 'hand', onSelect = function() Pickup(id) end }
        options[#options + 1] = { title = T.menu_logs, icon = 'list', onSelect = function() ShowLogs(id) end }
    end
    if IsLaw() then
        options[#options + 1] = { title = T.menu_search, description = T.menu_search_desc, icon = 'magnifying-glass',
            onSelect = function() Search(id) end }
        if Config.Perquisition.CanSeize and JobGrade() >= Config.Perquisition.SeizeMinGrade then
            options[#options + 1] = { title = T.menu_seize, icon = 'gavel', onSelect = function() Seize(id) end }
        end
        if not IsOwner(chest) then
            options[#options + 1] = { title = T.menu_logs, icon = 'list', onSelect = function() ShowLogs(id) end }
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
