-- Système de placement type "gizmo" pour RedM
-- Le prop fantôme suit la caméra (raycast), puis peut être ajusté finement
-- sur les 3 axes + rotation. Un gizmo externe peut prendre le relais (optionnel).

local Placement = Config.Placement
local Keys = Placement.Keys
local IsPlacing = false

local function DrawLine3D(a, b, r, g, bl, alpha)
    Citizen.InvokeNative(0x6B7256074AE34680, a.x, a.y, a.z, b.x, b.y, b.z, r, g, bl, alpha) -- DRAW_LINE
end

local function RotationToDirection(rot)
    local z = math.rad(rot.z)
    local x = math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local function RaycastFromCamera(distance, ignore)
    local camCoords = GetGameplayCamCoord()
    local dir = RotationToDirection(GetGameplayCamRot(2))
    local dest = camCoords + dir * distance
    local ray = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, dest.x, dest.y, dest.z, 1 | 16, ignore, 0)
    local _, hit, endCoords = GetShapeTestResult(ray)
    return hit == 1, endCoords
end

function IsInBlacklistZone(coords)
    for _, zone in ipairs(Config.BlacklistZones) do
        if #(coords - zone.coords) <= zone.radius then return true end
    end
    return false
end

local function IsTooCloseToChest(coords)
    for _, chest in pairs(GetLoadedChests()) do
        if #(coords - chest.coords) < Config.MinDistanceBetween then return true end
    end
    return false
end

local function DisablePlacementControls()
    for _, key in pairs(Keys) do
        DisableControlAction(0, key, true)
    end
    DisableControlAction(0, 0x07CE1E61, true) -- attaque
    DisableControlAction(0, 0xF84FA74F, true) -- visée
end

local function Pressed(key) return IsDisabledControlPressed(0, key) end
local function JustPressed(key) return IsDisabledControlJustPressed(0, key) end

local function DrawAxes(pos, heading, valid)
    local h = math.rad(heading)
    local fwd = vector3(-math.sin(h), math.cos(h), 0.0)
    local right = vector3(math.cos(h), math.sin(h), 0.0)
    local up = vector3(0.0, 0.0, 1.0)
    DrawLine3D(pos, pos + right * 0.8, 255, 40, 40, 255)   -- X rouge
    DrawLine3D(pos, pos + fwd * 0.8, 40, 255, 40, 255)     -- Y vert
    DrawLine3D(pos, pos + up * 0.8, 40, 120, 255, 255)     -- Z bleu
    if not valid then
        DrawLine3D(pos - right * 0.5, pos + right * 0.5 + up * 0.5, 255, 0, 0, 255)
        DrawLine3D(pos + right * 0.5, pos - right * 0.5 + up * 0.5, 255, 0, 0, 255)
    end
end

local function UseExternalGizmo(obj)
    local gizmo = Placement.ExternalGizmo
    if not gizmo.enabled or GetResourceState(gizmo.resource) ~= 'started' then return nil end
    SetEntityCollision(obj, true, true)
    local ok, data = pcall(function()
        return exports[gizmo.resource][gizmo.export](nil, obj)
    end)
    if not ok or type(data) ~= 'table' or not data.position then
        if Config.Debug then print('[rsg_chest] gizmo externe indisponible : ' .. tostring(data)) end
        return nil
    end
    return data
end

--- Lance le placement d'un modèle.
--- @return vector3|nil coords, vector3|nil rotation
function StartPlacement(model)
    if IsPlacing then
        lib.notify({ description = Config.Text.already_placing, type = 'error' })
        return nil
    end

    local hash = GetHashKey(model)
    if not IsModelInCdimage(hash) then
        print(('[rsg_chest] ^1Modèle introuvable : %s^7 (vérifiez sur redm.info/props ou spooni.pages.dev/props)'):format(model))
        lib.notify({ description = Config.Text.invalid_model, type = 'error' })
        return nil
    end

    IsPlacing = true
    lib.requestModel(hash, 5000)

    local ped = PlayerPedId()
    local start = GetOffsetFromEntityInWorldCoords(ped, 0.0, 1.5, 0.0)
    local obj = CreateObject(hash, start.x, start.y, start.z, false, false, false)
    SetEntityAlpha(obj, 170, false)
    SetEntityCollision(obj, false, false)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)

    local heading = GetEntityHeading(ped)
    local base = start
    local offset = vector3(0.0, 0.0, 0.0)
    local locked = false
    local result, rotation = nil, nil

    lib.showTextUI(Config.Text.placement_help)

    while true do
        Wait(0)
        DisablePlacementControls()

        local mult = Pressed(Keys.Fast) and Placement.FastMultiplier or 1.0
        local step = Placement.MoveStep * mult

        if not locked then
            local hit, coords = RaycastFromCamera(Placement.MaxDistance + 4.0, ped)
            if hit then base = coords end
        end

        -- rotation
        if Pressed(Keys.RotLeft) then heading = heading + Placement.RotateStep * mult end
        if Pressed(Keys.RotRight) then heading = heading - Placement.RotateStep * mult end
        heading = heading % 360.0

        -- déplacement relatif à la caméra
        local camH = math.rad(GetGameplayCamRot(2).z)
        local camFwd = vector3(-math.sin(camH), math.cos(camH), 0.0)
        local camRight = vector3(math.cos(camH), math.sin(camH), 0.0)
        if Pressed(Keys.Forward) then offset = offset + camFwd * step end
        if Pressed(Keys.Backward) then offset = offset - camFwd * step end
        if Pressed(Keys.Right) then offset = offset + camRight * step end
        if Pressed(Keys.Left) then offset = offset - camRight * step end
        if Pressed(Keys.Up) then offset = offset + vector3(0.0, 0.0, step) end
        if Pressed(Keys.Down) then offset = offset - vector3(0.0, 0.0, step) end

        if JustPressed(Keys.Lock) then locked = not locked end

        local pos = base + offset
        SetEntityCoordsNoOffset(obj, pos.x, pos.y, pos.z, false, false, false)
        SetEntityRotation(obj, 0.0, 0.0, heading, 2, true)

        if JustPressed(Keys.Ground) then
            PlaceObjectOnGroundProperly(obj)
            local g = GetEntityCoords(obj)
            base, offset = g, vector3(0.0, 0.0, 0.0)
            locked = true
            pos = g
        end

        local valid = #(GetEntityCoords(ped) - pos) <= Placement.MaxDistance
            and not IsInBlacklistZone(pos)
            and not IsTooCloseToChest(pos)

        DrawAxes(pos, heading, valid)

        if JustPressed(Keys.Cancel) then break end

        if JustPressed(Keys.Confirm) then
            if not valid then
                local msg = IsInBlacklistZone(pos) and Config.Text.blacklisted
                    or IsTooCloseToChest(pos) and Config.Text.too_close
                    or Config.Text.too_far
                lib.notify({ description = msg, type = 'error' })
            else
                result = pos
                rotation = vector3(0.0, 0.0, heading)
                break
            end
        end
    end

    lib.hideTextUI()

    if result then
        local gizmo = UseExternalGizmo(obj)
        if gizmo then
            result = vector3(gizmo.position.x, gizmo.position.y, gizmo.position.z)
            rotation = vector3(gizmo.rotation.x, gizmo.rotation.y, gizmo.rotation.z)
            if #(GetEntityCoords(ped) - result) > Placement.MaxDistance or IsInBlacklistZone(result) then
                lib.notify({ description = Config.Text.too_far, type = 'error' })
                result = nil
            end
        end
    end

    DeleteEntity(obj)
    IsPlacing = false
    return result, rotation
end
