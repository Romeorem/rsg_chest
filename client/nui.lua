-- Interface cryptex : saisie du code et mini-jeu de crochetage.
-- Fenêtre ox_lib / skillCheck en secours si Config.Code.UseNui = false.
local T = Config.Text
local pending, handlers

local function CloseNui()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

local function Finish(result)
    CloseNui()
    local p = pending
    pending, handlers = nil, nil
    if p then p:resolve(result) end
end

local function OpenNui(payload, h)
    if pending then return nil end
    pending = promise.new()
    handlers = h
    SetNuiFocus(true, true)
    SendNUIMessage(payload)
    return Citizen.Await(pending)
end

local function NuiText()
    return {
        validate = T.nui_validate, next = T.nui_next, reset = T.nui_reset,
        cancel = T.nui_cancel, help = T.nui_help, step = T.nui_step,
        lock = T.lockpick_lock, lockHelp = T.lockpick_help,
    }
end

--- Demande un ou plusieurs codes au joueur.
--- @param opts { title: string, steps: string[], onSubmit: fun(values: string[]): boolean, string|nil }
--- `onSubmit` est appelé à la validation. S'il renvoie false, l'interface reste
--- ouverte et affiche le message (mauvais code, codes différents...).
--- @return string[]|nil values
function RequestCode(opts)
    if pending then return nil end

    if not Config.Code.UseNui then
        local fields = {}
        for i, label in ipairs(opts.steps) do
            fields[i] = {
                type = 'input', label = label, password = true, required = true,
                min = Config.Code.Length, max = Config.Code.Length,
            }
        end
        local input = lib.inputDialog(opts.title, fields)
        if not input then return nil end
        local ok, msg = opts.onSubmit(input)
        if msg then lib.notify({ description = msg, type = ok and 'success' or 'error' }) end
        return ok and input or nil
    end

    return OpenNui({
        action = 'open', mode = 'code',
        title = opts.title, steps = opts.steps, length = Config.Code.Length, text = NuiText(),
    }, { onSubmit = opts.onSubmit })
end

--- Mini-jeu de crochetage.
--- @param opts { title: string, digits: integer[], time: integer, onFail: fun(): { broken: boolean, msg: string } }
--- @return 'success'|'broken'|'timeout'|nil
function RequestLockpick(opts)
    if pending then return nil end

    if not Config.Code.UseNui then
        local diff = {}
        for i = 1, #opts.digits do diff[i] = i <= 2 and 'medium' or 'hard' end
        while true do
            if lib.skillCheck(diff) then return 'success' end
            local r = opts.onFail() or {}
            if r.broken then return 'broken' end
            lib.notify({ description = r.msg, type = 'error' })
        end
    end

    return OpenNui({
        action = 'open', mode = 'lockpick',
        title = opts.title, digits = opts.digits, time = opts.time, text = NuiText(),
    }, { onFail = opts.onFail })
end

RegisterNUICallback('submit', function(data, cb)
    if not pending or not handlers or not handlers.onSubmit then return cb({ ok = false }) end
    local values = data.values or {}
    for i, v in ipairs(values) do values[i] = tostring(v) end

    local ok, msg = handlers.onSubmit(values)
    cb({ ok = ok and true or false, msg = msg })

    if ok then
        if msg then lib.notify({ description = msg, type = 'success' }) end
        Finish(values)
    end
end)

RegisterNUICallback('lockpickFail', function(_, cb)
    if not pending or not handlers or not handlers.onFail then return cb({ broken = true }) end
    local r = handlers.onFail() or { broken = true }
    cb(r)
    if r.broken then
        SetTimeout(900, function() Finish('broken') end)
    end
end)

RegisterNUICallback('lockpickSuccess', function(_, cb)
    cb({})
    SetTimeout(500, function() Finish('success') end)
end)

RegisterNUICallback('lockpickTimeout', function(_, cb)
    cb({})
    Finish('timeout')
end)

RegisterNUICallback('cancel', function(_, cb)
    cb({})
    Finish(nil)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and pending then
        SetNuiFocus(false, false)
    end
end)
