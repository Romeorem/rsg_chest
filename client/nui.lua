-- Interface du code : cryptex à molettes (NUI) ou fenêtre ox_lib en secours.
local T = Config.Text
local pending, handler

local function CloseNui()
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
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

    pending = promise.new()
    handler = opts.onSubmit
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        title = opts.title,
        steps = opts.steps,
        length = Config.Code.Length,
        text = {
            validate = T.nui_validate, next = T.nui_next, reset = T.nui_reset,
            cancel = T.nui_cancel, help = T.nui_help, step = T.nui_step,
        },
    })
    local result = Citizen.Await(pending)
    pending, handler = nil, nil
    return result
end

RegisterNUICallback('submit', function(data, cb)
    if not pending then return cb({ ok = false }) end
    local values = data.values or {}
    for i, v in ipairs(values) do values[i] = tostring(v) end

    local ok, msg = true, nil
    if handler then ok, msg = handler(values) end
    cb({ ok = ok and true or false, msg = msg })

    if ok then
        CloseNui()
        if msg then lib.notify({ description = msg, type = 'success' }) end
        pending:resolve(values)
    end
end)

RegisterNUICallback('cancel', function(_, cb)
    cb({})
    CloseNui()
    if pending then pending:resolve(nil) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and pending then
        SetNuiFocus(false, false)
    end
end)
