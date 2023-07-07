-- AutoIcons: Automatically generates/renders weapon select icons and killicons for SWEPs not containing them.
-- Made by Joker Gaming (STEAM_0:0:38422842)
-- https://steamcommunity.com/sharedfiles/filedetails/?id=2495300496

module("autoicon", package.seeall)
ReplaceAllConvar = CreateClientConVar("autoicons_replaceall", "1", true, false, "Replace all select/kill icons (otherwise, only create icons for SWEPS/Ents that would use the default)", 0, 1)

-- API to override the convar
function OverrideReplaceAll(state)
    ReplaceAllOverrideState = state
    UpdateReplaceAll()
end

local replace_all

function UpdateReplaceAll()
    replace_all = ReplaceAllOverrideState or ReplaceAllConvar:GetBool()
end

cvars.AddChangeCallback("autoicons_replaceall", UpdateReplaceAll)
UpdateReplaceAll()
local placeholder_model = "models/maxofs2d/logo_gmod_b.mdl"
local error_model = "models/error.mdl"

local model_angle_override = {
    ["models/weapons/w_toolgun.mdl"] = Angle(0, 0, 0),
    ["models/MaxOfS2D/camera.mdl"] = Angle(0, 90, 0),
    [placeholder_model] = Angle(0, 90, 0),
    [error_model] = Angle(0, 90, 0),
}

local weaponselectcolor = Vector(1, 0.93, 0.05)
local killiconsize = 96
local killiconcolor = Vector(1, 80 / 255, 0)
MODE_HL2WEAPONSELECT = 1
MODE_HL2KILLICON = 2

-- cache[mode][cachekey] = Material
local cache = {{}, {}}

local name_prefix = "autoicon" .. tostring(ReloadIndex or "") .. "_"
ReloadIndex = (ReloadIndex or 0) + 1
local unique_name_index = 0

local function unique_name()
    unique_name_index = unique_name_index + 1

    return name_prefix .. tostring(unique_name_index)
end

local function make_rt(name_func, xs, ys, depth, alpha)
    return GetRenderTargetEx(name_func(), xs, ys, depth and RT_SIZE_DEFAULT or RT_SIZE_NO_CHANGE, depth and MATERIAL_RT_DEPTH_SEPARATE or MATERIAL_RT_DEPTH_NONE, 12 + 2, 0, alpha and IMAGE_FORMAT_RGBA8888 or IMAGE_FORMAT_RGB888)
end

MAT_MODELCOLOR = CreateMaterial(unique_name(), "VertexLitGeneric", {
    ["$basetexture"] = "lights/white",
})

MAT_TEXTURE = CreateMaterial(unique_name(), "UnlitGeneric", {
    ["$basetexture"] = "lights/white",
    ["$vertexcolor"] = "1",
})

MAT_DESATURATE = CreateMaterial(unique_name(), "g_colourmodify", {
    ["$fbtexture"] = "lights/white",
    ["$pp_colour_addr"] = 0,
    ["$pp_colour_addg"] = 0,
    ["$pp_colour_addb"] = 0,
    ["$pp_colour_brightness"] = -0.25,
    ["$pp_colour_contrast"] = 3,
    ["$pp_colour_colour"] = 0,
    ["$pp_colour_mulr"] = 0,
    ["$pp_colour_mulg"] = 0,
    ["$pp_colour_mulb"] = 0,
})

local function render_context(params, callback)
    if params.rt then
        render.PushRenderTarget(params.rt)
    end

    if params.clear then
        render.Clear(unpack(params.clear))
    end

    if params.cam then
        if params.cam == "2D" then
            cam.Start2D()
        else
            cam.Start(params.cam)
        end
    end

    if params.material then
        render.MaterialOverride(params.material)
    end

    if callback then
        ProtectedCall(callback)
    end

    if params.material then
        render.MaterialOverride()
    end

    if params.cam then
        if params.cam == "2D" then
            cam.End2D()
        else
            cam.End3D()
        end
    end

    if params.rt then
        render.PopRenderTarget()
    end
end

local read_pixel = render.ReadPixel
-- The game likes to black out our textures sometimes (eg. when changing screen res).
-- Make a little 1x1 square that is white when the textures still exist, so if the game blacks it out we'll know, without having to capture an entire large texture.
-- Still takes about 0.5ms to check it though.
INDICATOR_TEXTURE = GetRenderTargetEx(unique_name(), 1, 1, 0, 2, 1, 0, IMAGE_FORMAT_RGB888)

INDICATOR_MATERIAL = CreateMaterial(unique_name(), "VertexLitGeneric", {
    ["$basetexture"] = "lights/white",
})

local textures_valid_check_time = 0

local function check_textures_valid()
    if SysTime() - textures_valid_check_time < 5 then return end
    textures_valid_check_time = SysTime()
    local r

    render_context({
        rt = INDICATOR_TEXTURE
    }, function()
        render.CapturePixels()
        r = read_pixel(0, 0)
    end)

    local curtex = INDICATOR_MATERIAL:GetTexture("$basetexture")

    if r == 0 or not curtex or curtex:GetName() == "lights/white" then
        render_context({
            rt = INDICATOR_TEXTURE,
            clear = {255, 255, 255, 255}
        })

        INDICATOR_MATERIAL:SetTexture("$basetexture", INDICATOR_TEXTURE)

        for mode, subcache in pairs(cache) do
            table.Empty(subcache)
        end
    end
end

local function get_bitmap()
    render.CapturePixels()
    local xs, ys = ScrW(), ScrH()
    local bitmask, bitcount = {}, 0

    for x = 0, xs - 1 do
        bitmask[x] = {}

        for y = 0, ys - 1 do
            -- Only checks red
            if read_pixel(x, y) > 0 then
                bitcount = bitcount + 1
                bitmask[x][y] = true
            end
        end
    end

    return bitmask, bitcount
end

-- Find the bounds of nonzero pixels
local function get_bbox(bitmask)
    local xs, ys = ScrW(), ScrH()
    local px1, py1, px2, py2 = 0, 0, 1, 1

    for x = 0, xs - 1 do
        for y = 0, ys - 1 do
            if bitmask[x][y] then
                px1 = x / xs
                goto found_px1
            end
        end
    end

    ::found_px1::

    for y = 0, ys - 1 do
        for x = 0, xs - 1 do
            if bitmask[x][y] then
                py1 = y / ys
                goto found_py1
            end
        end
    end

    ::found_py1::

    for x = xs - 1, 0, -1 do
        for y = 0, ys - 1 do
            if bitmask[x][y] then
                px2 = (x + 1) / xs
                goto found_px2
            end
        end
    end

    ::found_px2::

    for y = ys - 1, 0, -1 do
        for x = 0, xs - 1 do
            if bitmask[x][y] then
                py2 = (y + 1) / ys
                goto found_py2
            end
        end
    end

    ::found_py2::

    return px1, py1, px2, py2
end

local function estimate_bitmask_angle(bitmask, x1, x2)
    local px1, py1, px2, py2 = get_bbox(bitmask)
    -- Taller than long, probably a knife
    if py2 - py1 > px2 - px1 then return 0 end
    local xs, ys = ScrW(), ScrH()
    local linesused = {}
    local slopeweight = {}

    for x = 0, xs - 1 do
        linesused[x] = {}
    end

    for x = math.floor(xs * Lerp(x1, px1, px2)), math.ceil(xs * Lerp(x2, px1, px2)) - 1 do
        for y = math.floor(ys * py1), math.ceil(ys * py2) - 1 do
            if bitmask[x][y] and not linesused[x][y] then
                local passed = 0
                local sx = x

                while (bitmask[sx] or {})[y] do
                    linesused[sx][y] = true
                    passed = passed + 1
                    sx = sx + 1
                end

                local slope = 0

                if (bitmask[sx] or {})[y + 1] then
                    slope = passed
                elseif (bitmask[sx] or {})[y - 1] then
                    slope = -passed
                end

                if math.abs(slope) > 40 then
                    slope = 0
                end

                if slope == 0 and passed < 3 then
                    passed = 0
                end

                slopeweight[slope] = (slopeweight[slope] or 0) + passed
            end
        end
    end

    local highestsl = 0
    local highestslw = slopeweight[0] or 1
    local highestsla = 0

    for k, v in pairs(slopeweight) do
        if math.abs(k) > 2 then
            local uw = slopeweight[k - 1] or 0
            local dw = slopeweight[k + 1] or 0
            local slw = v + math.max(uw, dw)

            if slw > highestslw then
                highestsl = k
                highestslw = slw
                local isl

                if uw > dw then
                    isl = (v * k + uw * (k - 1)) / (v + uw)
                else
                    isl = (v * k + dw * (k + 1)) / (v + dw)
                end

                highestsla = math.deg(math.atan(1 / isl))
            end
        end
    end

    return highestsla
end

local function get_stored(classname)
    return weapons.GetStored(classname) or (scripted_ents.GetStored(classname) or {}).t
end

local function translate_string(class_or_model)
    return string.EndsWith(class_or_model, ".mdl") and class_or_model or get_stored(class_or_model)
end

local function translate_model(mdl)
    return (mdl or "") == "" and placeholder_model or (util.IsValidModel(mdl) and mdl or "models/error.mdl")
end

-- This won't work for entities outside of PVS, but it's the best we can do without server code
-- This won't override models for non-SENTs (prop_physics etc)
local classname_default_model = {}

hook.Add("NetworkEntityCreated", "AutoIconsNetworkEntityCreated", function(ent)
    if not classname_default_model[ent:GetClass()] and (ent:GetModel() or "") ~= "" then
        classname_default_model[ent:GetClass()] = ent:GetModel()
    end
end)

local function class_default_model(data)
    return (data.IronSightStruct and data.ViewModel or data.WorldModel) or data.Model or classname_default_model[data.ClassName]
end

-- IronSightStruct indicates ARCCW. data.Model is an attempt to get something from an ENT table
local function autoicon_params(data)
    local p = {}

    if isstring(data) and not data:EndsWith(".mdl") then
        data = get_stored(data) or placeholder_model
    end

    if isentity(data) then
        local mdl = translate_model(data:GetModel())
        -- If the current model is not the default model, or it isn't a SWEP/SENT, draw that instead
        data = (mdl == class_default_model(data)) and get_stored(data:GetClass()) or mdl
    end

    if isstring(data) then
        p.mainmodel = data
        p.cachekey = data
        p.force_angle = model_angle_override[data]
    elseif istable(data) then
        p.mainmodel = translate_model(class_default_model(data))
        p.cachekey = data.ClassName

        -- TFA
        if data.Offset and data.Offset.Ang then
            local a = data.Offset.Ang
            p.force_angle = Angle(8, 0, 180)
            p.force_angle:RotateAroundAxis(p.force_angle:Up(), a.Up)
            p.force_angle:RotateAroundAxis(p.force_angle:Right(), a.Right)
            p.force_angle:RotateAroundAxis(p.force_angle:Forward(), a.Forward)
            p.force_sense_angle = true
        end

        -- SCK, scifi sweps
        if data.ShowWorldModel == false or data.SciFiWorld == "dev/hide" or data.SciFiWorld == "vgui/white" then
            p.hide_mainmodel = true
        end

        -- SCK
        p.welements = data.WElements
        p.force_angle = data.AutoIconAngle or model_angle_override[p.mainmodel] or p.force_angle
    else
        error(type(data))
    end

    assert(isstring(p.mainmodel) and p.mainmodel ~= "")
    assert(isstring(p.cachekey) and p.cachekey ~= "")
    p.legit = p.mainmodel ~= placeholder_model and p.mainmodel ~= error_model

    return p
end

local function sck_local_to_world(ipos, iang, pos, ang)
    pos = pos + ipos.x * ang:Forward() + ipos.y * ang:Right() + ipos.z * ang:Up()
    ang = Angle(ang)
    ang:RotateAroundAxis(ang:Up(), iang.y)
    ang:RotateAroundAxis(ang:Right(), iang.p)
    ang:RotateAroundAxis(ang:Forward(), iang.r)

    return pos, ang
end

function GetIcon(p, mode)
    check_textures_valid()
    if cache[mode][p.cachekey] then return cache[mode][p.cachekey] end
    local mainent = ClientsideModel(p.mainmodel)
    assert(IsValid(mainent))
    local extraents = {}
    mainent:SetPos(Vector(0, 0, 0))
    mainent:SetAngles(Angle(0, 0, 0))
    mainent:SetupBones()

    for k, v in pairs(p.welements or {}) do
        if not v.model then continue end
        if v.color and v.color.a == 0 then continue end
        local mat

        if (v.material or "") ~= "" then
            mat = Material(v.material)
            if mat:GetShader() ~= "VertexLitGeneric" and mat:GetShader() ~= "UnlitGeneric" then continue end
            -- nodraw, vertexalpha, additive, -- translucent 2097152
            if bit.band(mat:GetInt("$flags"), 4 + 32 + 128) ~= 0 then continue end
        end

        -- Compute position relative to mainent position
        local lpos, lang = Vector(0, 0, 0), Angle(0, 0, 0) -- sck_local_to_world(Vector(0,0,0), Angle(0,0,0), v.pos or Vector(0,0,0), v.angle or Angle(0,0,0))
        local bn = v.bone
        local parent = v

        for i = 1, 10 do
            if (parent.rel or "") == "" then break end
            parent = p.welements[parent.rel]
            if not parent then break end
            lpos, lang = sck_local_to_world(lpos, lang, parent.pos or Vector(0, 0, 0), parent.angle or Angle(0, 0, 0))
            bn = parent.bone
        end

        --"ValveBiped.Bip01_R_Hand"?
        if bn == "Base" then
            bn = nil
        end

        if bn then
            bn = mainent:LookupBone(bn)
            if not bn then continue end
            local p, a = mainent:GetBonePosition(bn)
            -- a.r = -a.r
            lpos, lang = sck_local_to_world(lpos, lang, p, a)
        end

        lpos, lang = sck_local_to_world(v.pos or Vector(0, 0, 0), v.angle or Angle(0, 0, 0), lpos, lang)
        local e = ClientsideModel(v.model)

        if mat then
            e:SetMaterial(v.material)
        end

        e.lpos = lpos
        e.lang = lang
        mat = Matrix()
        mat:Scale(v.size or Vector(1, 1, 1))
        e:EnableMatrix("RenderMultiply", mat)
        table.insert(extraents, e)
    end

    -- If we have an error, we'll still delete the entities
    local ok, ret = pcall(function()
        local function drawmodel()
            if not p.hide_mainmodel then
                mainent:DrawModel()
            end

            for i, v in ipairs(extraents) do
                local p, a = LocalToWorld(v.lpos, v.lang, mainent:GetPos(), mainent:GetAngles())
                v:SetPos(p)
                v:SetAngles(a)
                v:SetupBones()
                v:DrawModel()
            end
        end

        local min, max = mainent:GetRenderBounds()
        local center, rad = (min + max) / 2, min:Distance(max) / 2
        local ang
        local b

        if p.force_angle then
            ang = p.force_angle
        else
            local muzzleatt = mainent:LookupAttachment("muzzle")

            if muzzleatt < 1 then
                muzzleatt = mainent:LookupAttachment("muzzle_flash")
            end

            b = mainent:LookupBone("ValveBiped.Bip01_R_Hand")

            if muzzleatt > 0 or b then
                mainent:SetAngles(Angle(0, 0, 0))
                mainent:SetupBones()

                local v = muzzleatt > 0 and mainent:GetAttachment(muzzleatt).Ang:Forward() or ({mainent:GetBonePosition(b)})[2]:Forward()

                -- Despite various attachments and bones existing, this is the best I could do.
                -- Pretty pathetic huh? Half the SWEPs on workshop have totally wrong attachment/bone angles and anything more than this completely messes them up.
                -- There is a second pass below where it tries to fix the angle by looking at the drawn mask itself
                ang = Angle(0, -math.deg(math.atan2(v.y, v.x)), 0)
            else
                -- One of these is usually correct
                ang = Angle(0, (max.x - min.x >= max.y - min.y) and 0 or 90, 0)
                ang:RotateAroundAxis(Vector(1, 0, 0), -11)
            end
        end

        -- Flip weaponselect icons the other way
        if mode == MODE_HL2WEAPONSELECT then
            ang:RotateAroundAxis(Vector(0, 0, 1), 180)
        end

        mainent:SetAngles(ang)
        mainent:SetupBones()
        local zpd = math.min(max.x - min.x, max.y - min.y)
        local viewdist = 5 * rad + 1
        local znear = viewdist - zpd / 2
        local zfar = znear + zpd
        local hw, hh, cx, cy = 0.5, 0.5, 0.5, 0.5
        local rtx, rty = 512, 512

        if mode == MODE_HL2KILLICON then
            rtx, rty = 256, 256
        end

        local crtx, crty = 512, 512
        local fov = 30

        local function ortho_cam()
            -- local function unclampedlerp(t, x, y)
            --     return (1 - t) * x + t * y
            -- end
            return {
                x = 0,
                y = 0,
                w = ScrW(),
                h = ScrH(),
                type = "3D",
                origin = mainent:LocalToWorld(center) + Vector(0, -viewdist, 0),
                angles = Vector(0, 90, 0),
                aspect = 1,
                fov = fov,
                -- znear = znear, -- zfar = zfar, -- ortho = {left=unclampedlerp(cx-hw,-rad,rad),bottom=unclampedlerp(cy-hh,rad,-rad),right=unclampedlerp(cx+hw,-rad,rad),top=unclampedlerp(cy+hh,rad,-rad)},
                offcenter = {
                    left = (cx - hw) * ScrW(),
                    top = ((1 - cy) - hh) * ScrH(),
                    bottom = ((1 - cy) + hh) * ScrH(),
                    right = (cx + hw) * ScrW()
                },
            }
        end

        local function drawtexture(tex, col, bf, x, y)
            if isfunction(col) then
                col, bf, x, y = nil, col, bf, x
            end

            if isnumber(col) then
                col, bf, x, y = nil, nil, col, bf
            end

            col, x, y = col or Vector(1, 1, 1), x or 0, y or 0
            MAT_TEXTURE:SetTexture("$basetexture", tex)
            MAT_TEXTURE:SetVector("$color2", col)

            if bf then
                bf()
            else
                render.OverrideBlend(false)
            end

            MAT_TEXTURE:SetMatrix("$basetexturetransform", Matrix({
                {1, 0, 0, x / tex:Width()},
                {0, 1, 0, y / tex:Height()},
                {0, 0, 1, 0},
                {0, 0, 0, 1}
            }))

            render.SetMaterial(MAT_TEXTURE)
            render.DrawScreenQuad()
            render.OverrideBlend(false)
        end

        render.SuppressEngineLighting(true)
        render.SetColorModulation(1, 1, 1)
        local lnameidx = 0

        local function reusable_name()
            lnameidx = lnameidx + 1

            return name_prefix .. tostring(mode) .. "_" .. tostring(lnameidx)
        end

        local function bf_sub()
            render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_REVERSE_SUBTRACT, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        end

        local function bf_add()
            render.OverrideBlend(true, BLEND_ONE, BLEND_ONE, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        end

        local function bf_mul()
            render.OverrideBlend(true, BLEND_DST_COLOR, BLEND_ZERO, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
        end

        -- Figure out the model bounds then make a mask (white on black, no grays)
        local cmaskrt = make_rt(reusable_name, crtx, crty)
        local cbmaskrt = make_rt(reusable_name, crtx, crty)
        local canglert = make_rt(reusable_name, crtx, crty)

        -- DRAW THE MODEL (WHITE MASK)
        render_context({
            rt = cmaskrt
        }, function()
            render_context({
                clear = {0, 0, 0, 0},
                cam = ortho_cam(),
                material = MAT_MODELCOLOR
            }, drawmodel)

            -- If it's bonemerged to the player (and no angle override), assume it's a gun, and try to fix the angle by looking at the mask
            if b or p.force_sense_angle then
                -- Make a version of the mask essentially blurred horizontally to remove noise from attachment rails
                render_context({
                    rt = cbmaskrt,
                    clear = {0, 0, 0, 0},
                    cam = "2D"
                }, function()
                    for blur = -3, 3 do
                        drawtexture(cmaskrt, bf_add, blur, 0)
                    end
                end)

                -- A mask of just the top edge of the gun
                local fixang

                render_context({
                    rt = canglert,
                    clear = {0, 0, 0, 0}
                }, function()
                    render_context({
                        cam = "2D"
                    }, function()
                        drawtexture(cbmaskrt, bf_add)
                        drawtexture(cbmaskrt, bf_sub, 0, -1)
                    end)

                    local bitmask, bitcount = get_bitmap()
                    local x0, x1 = 0.33, 1

                    if mode == MODE_HL2WEAPONSELECT then
                        x0, x1 = 0, 0.67
                    end

                    fixang = estimate_bitmask_angle(bitmask, x0, x1)
                end)

                -- Render again with the angle visually corrected
                if fixang ~= 0 then
                    ang = mainent:GetAngles()
                    ang:RotateAroundAxis(Vector(0, -1, 0), fixang)
                    mainent:SetAngles(ang)
                    mainent:SetupBones()

                    render_context({
                        clear = {0, 0, 0, 0},
                        cam = ortho_cam(),
                        material = MAT_MODELCOLOR
                    }, drawmodel)
                end
            end

            local bitmask, bitcount = get_bitmap()
            local px1, py1, px2, py2 = get_bbox(bitmask)

            -- Zoom out until the whole actual model is in view (needed by some SCK weapons)
            while px1 == 0 or py1 == 0 or px2 == 1 or py2 == 1 do
                fov = fov + 10
                if fov > 150 then break end

                render_context({
                    clear = {0, 0, 0, 0},
                    cam = ortho_cam(),
                    material = MAT_MODELCOLOR
                }, drawmodel)

                local bitmask, bitcount = get_bitmap()
                px1, py1, px2, py2 = get_bbox(bitmask)
            end

            -- Adjust the ortho bounds to match the model (GetRenderBounds ARE RARELY TIGHT)
            local area = bitcount / (rtx * rty)
            local pad = 0.01
            local icon_max_height = 0.5

            if mode == MODE_HL2WEAPONSELECT then
                pad = 0.04
                icon_max_height = 0.5
                px1, px2 = px1 - pad, px2 + pad
            else
                px1, py1, px2, py2 = px1 - pad, py1 - pad, px2 + pad, py2 + pad
            end

            hw, hh = (px2 - px1) / 2, (py2 - py1) / 2
            cx, cy = (px2 + px1) / 2, (py2 + py1) / 2
            local realhh = hh
            hw, hh = math.max(hw, hh), math.max(hw, hh)

            if realhh / hh > icon_max_height then
                hw = hw * (realhh / hh) / icon_max_height
                hh = hh * (realhh / hh) / icon_max_height
            end

            local icon_max_area = (mode == MODE_HL2WEAPONSELECT) and 0.15 or 0.5
            area = area / (hw * hh * 4)
            local scale = math.sqrt(math.max(area / icon_max_area, 1))
            hw, hh = scale * hw, scale * hh
        end)

        -- code to supersample the mask, doesn't make much difference as image is already 4x
        -- local mask2 = make_rt(reusable_name,rtx*2,rty*2,false,false)
        -- Render the mask
        local maskrt = make_rt(reusable_name, rtx, rty)

        render_context({
            rt = maskrt,
            clear = {0, 0, 0, 0},
            cam = ortho_cam(),
            material = MAT_MODELCOLOR
        }, drawmodel)

        -- Render the model fullbright
        local colorrt = make_rt(reusable_name, rtx, rty, true)

        render_context({
            rt = colorrt,
            clear = {0, 0, 0, 0, true, true}
        }, function()
            render_context({
                cam = ortho_cam()
            }, drawmodel)

            render.BlurRenderTarget(colorrt, 1 / rtx, 1 / rty, 1) --make it less noisy
        end)

        -- Render the model normals
        local normalrt = make_rt(reusable_name, rtx, rty, true)

        render_context({
            rt = normalrt,
            clear = {0, 0, 0, 0, true, true}
        }, function()
            render_context({
                cam = ortho_cam(),
                material = MAT_MODELCOLOR
            }, function()
                render.SetModelLighting(0, 1, 0.5, 0.5)
                render.SetModelLighting(1, 0, 0.5, 0.5)
                render.SetModelLighting(2, 0.5, 1, 0.5)
                render.SetModelLighting(3, 0.5, 0, 0.5)
                render.SetModelLighting(4, 0.5, 0.5, 1)
                render.SetModelLighting(5, 0.5, 0.5, 0)
                drawmodel()
            end)

            render.ResetModelLighting(1, 1, 1)
            render.BlurRenderTarget(normalrt, 1 / rtx, 1 / rty, 1) --this was colorrt, i think that was a mistake
        end)

        -- Do edge detection convolution
        local coloredgert = make_rt(reusable_name, rtx, rty)

        render_context({
            rt = coloredgert,
            clear = {0, 0, 0, 0},
            cam = "2D"
        }, function()
            -- Dialation (makes edges thicker)
            local d = mode == MODE_HL2WEAPONSELECT and 3 or 1
            -- g_sharpen seems to be a convolution of [[-a 0] [0 a+1]]
            -- sobel seems to run a proper sobel/laplacian but then thresholds the result and adds it back
            -- Note: We can't just increase mul 8* and add the unshifted image one time
            -- Nor can we use mul/8 for the shifted images and then mul the result
            -- (the bytes don't accumulate correctly)
            local mul = Vector(1, 1, 1) * 0.7

            -- edge detection from normals
            for x = -1, 1 do
                for y = -1, 1 do
                    if x ~= 0 or y ~= 0 then
                        drawtexture(normalrt, mul, bf_add)
                        drawtexture(normalrt, mul, bf_sub, x * d, y * d)
                    end
                end
            end

            if mode == MODE_HL2WEAPONSELECT then
                mul = Vector(1, 1, 1) * 0.7

                -- edge detection from color
                for x = -1, 1 do
                    for y = -1, 1 do
                        if x ~= 0 or y ~= 0 then
                            drawtexture(colorrt, mul, bf_add)
                            drawtexture(colorrt, mul, bf_sub, x * d, y * d)
                        end
                    end
                end

                d = 3
                mul = Vector(1, 1, 1) * 0.5

                -- edge detection from mask
                -- maybe replace the mask with the depth buffer version? render.FogMode(MATERIAL_FOG_LINEAR) (NOTE: fog seems to only work with non-orthographic 3D that also doesn't have custom near/far z planes)
                for x = -1, 1 do
                    for y = -1, 1 do
                        if x ~= 0 or y ~= 0 then
                            drawtexture(maskrt, mul, bf_add)
                            drawtexture(maskrt, mul, bf_sub, x * d, y * d)
                        end
                    end
                end
            end
        end)

        -- Desaturate the edge detect image and adjust the min/max a little
        local edgert = make_rt(reusable_name, rtx, rty)
        local bluredgert

        render_context({
            rt = edgert,
            clear = {0, 0, 0, 0}
        }, function()
            render_context({
                cam = "2D"
            }, function()
                MAT_DESATURATE:SetTexture("$fbtexture", coloredgert)
                render.SetMaterial(MAT_DESATURATE)
                render.DrawScreenQuad()
            end)

            if mode == MODE_HL2WEAPONSELECT then
                -- Blurred version of edges
                bluredgert = make_rt(reusable_name, rtx, rty)
                render.CopyRenderTargetToTexture(bluredgert)
                render.BlurRenderTarget(bluredgert, 14, 14, 8)
            end
        end)

        local finalrt = make_rt(unique_name, rtx, rty)

        if mode == MODE_HL2WEAPONSELECT then
            -- Blurred version of mask
            local blurmaskrt = make_rt(reusable_name, rtx, rty)

            render_context({
                rt = blurmaskrt,
                clear = {0, 0, 0, 0},
                cam = "2D"
            }, function()
                drawtexture(maskrt)
                render.BlurRenderTarget(blurmaskrt, 8, 8, 3)
            end)

            -- Final composition
            render_context({
                rt = finalrt,
                clear = {0, 0, 0, 0},
                cam = "2D"
            }, function()
                -- Create "glow"
                drawtexture(maskrt, Vector(1, 1, 1) * 0.2)
                render.BlurRenderTarget(finalrt, 20, 20, 2)
                drawtexture(bluredgert, Vector(1, 1, 1) * 16, bf_add)
                -- Multiply = masks the glow
                drawtexture(blurmaskrt, Vector(1, 1, 1) * 128, bf_mul)
                -- Mask out lines
                local stp = 10

                for y = 0, rty, stp do
                    surface.SetDrawColor(0, 0, 0, 180)
                    surface.DrawRect(0, y, rtx, stp - 1)
                end

                -- Add edges
                drawtexture(edgert, bf_add)
            end)
        else
            render_context({
                rt = finalrt,
                clear = {0, 0, 0, 0},
                cam = "2D"
            }, function()
                for x = -1, 1 do
                    for y = -1, 1 do
                        drawtexture(maskrt, bf_add, x, y)
                    end
                end

                -- Subtract edges * 10 to make the image more thresholded looking
                drawtexture(edgert, Vector(1, 1, 1) * 10, bf_sub)
            end)
        end

        -- color2 gets overridden by killicons
        local m = CreateMaterial(unique_name(), "UnlitGeneric", {
            ["$basetexture"] = finalrt:GetName(),
        })

        cache[mode][p.cachekey] = m
        render.SuppressEngineLighting(false)
        render.OverrideBlend(false)

        return m
    end)

    mainent:Remove()

    for i, v in ipairs(extraents) do
        v:Remove()
    end

    if not ok then
        error(ret)
    end

    return ret
end

function DrawWeaponSelection(self, x, y, wide, tall, alpha)
    -- This might not work totally right with subclassing
    if not replace_all and (self.BasedDrawWeaponSelection or self.WepSelectIcon ~= BASED_WEPSELECTICON or self.WorldModel == "") then return (self.BasedDrawWeaponSelection or BASED_DRAWWEAPONSELECTION)(self, x, y, wide, tall, alpha) end
    local shift = math.floor(tall / 4)
    local y2 = y + shift
    local tall2 = tall - shift
    local weaponselect = GetIcon(autoicon_params(self), MODE_HL2WEAPONSELECT)
    render.SetMaterial(weaponselect)
    weaponselect:SetVector("$color2", weaponselectcolor * alpha / 255)
    -- Looks best at 256 (2:1 sampling) - at lower sizes (when below 1680x1050 game res) an interference pattern is visible on the lines
    -- I could draw the icons themselves smaller, but they might have some kind of custom weapon selector that changes the wide/tall dynamically which would make the icons redraw every frame
    local sz = wide < 245 and wide or 256
    cam.Start2D()
    render.OverrideBlend(true, BLEND_ONE_MINUS_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
    render.DrawScreenQuadEx(x + (wide - sz) * 0.5, y2 + (tall2 - sz) * 0.5, sz, sz)
    render.OverrideBlend(false)
    cam.End2D()

    -- Draw weapon info box
    if self.PrintWeaponInfo then
        self:PrintWeaponInfo(x + wide + 20, y + tall * 0.95, alpha)
    end
end

hook.Add("PreRegisterSWEP", "AutoIconsOverrideDrawWeaponSelection", function(swep, cls)
    if cls == "weapon_base" then
        BASED_DRAWWEAPONSELECTION = swep.DrawWeaponSelection
        BASED_WEPSELECTICON = swep.WepSelectIcon
        swep.BasedDrawWeaponSelection = false
    else
        swep.BasedDrawWeaponSelection = swep.DrawWeaponSelection
    end

    swep.DrawWeaponSelection = function(a, b, c, d, e, f)
        DrawWeaponSelection(a, b, c, d, e, f)
    end
end)

-- Killicons
-- Search for the "Icons" table declared locally in killicons.lua. Check all functions to maximize compatibility.
if not KilliconTable then
    for k, v in pairs(killicon) do
        if isfunction(v) then
            local info = debug.getinfo(v, "Su")

            if info.short_src == "lua/includes/modules/killicon.lua" then
                for i = 1, info.nups do
                    local name, value = debug.getupvalue(v, i) -- Should be name == "Icons", but don't check in case of minification

                    if istable(value) and istable(value.default) then
                        KilliconTable = value
                        goto killicon_table_found
                    end
                end
            end
        end
    end

    error("Could not find killicon table")
    ::killicon_table_found::
    BasedKilliconExists, BasedKilliconGetSize, BasedKilliconDraw = killicon.Exists, killicon.GetSize, killicon.Draw
end

local killicon_table = KilliconTable
local default_killicon = KilliconTable.default

local function killicon_params(name)
    local icon = killicon_table[name]

    if replace_all or (icon or default_killicon) == default_killicon then
        local params = autoicon_params(name)

        if params.legit then
            if not icon then
                killicon_table[name] = default_killicon
            end

            return params
        end
    end
end

local function override_killicon_functions()
    function killicon.Exists(name)
        killicon_params(name)

        return BasedKilliconExists(name)
    end

    function killicon.GetSize(name)
        local params = killicon_params(name)
        local w, h = BasedKilliconGetSize(name) -- This will make sure the size is set on the stored killicon to address a weird bug people are reporting
        if params then return killiconsize, killiconsize / 2 end

        return w, h
    end

    -- It might be cool to override GM:PlayerDeath and have it actually send the inflictor entity as well as classname...
    function killicon.Draw(x, y, name, alpha)
        local params = killicon_params(name)

        if params then
            local w, h = killiconsize, killiconsize
            x = x - w * 0.5
            y = y - h * 0.35
            cam.Start2D()
            local icon = GetIcon(params, MODE_HL2KILLICON)
            render.SetMaterial(icon)
            icon:SetVector("$color2", killiconcolor * alpha / 255)
            render.OverrideBlend(true, BLEND_ONE_MINUS_DST_COLOR, BLEND_ONE, BLENDFUNC_ADD, BLEND_ZERO, BLEND_ONE, BLENDFUNC_ADD)
            render.OverrideDepthEnable(true, false)
            render.DrawScreenQuadEx(x, y, w, h)
            render.OverrideDepthEnable(false, false)
            render.OverrideBlend(false)
            cam.End2D()
        else
            return BasedKilliconDraw(x, y, name, alpha)
        end
    end
end

override_killicon_functions()
timer.Simple(1, override_killicon_functions) -- addon conflict?