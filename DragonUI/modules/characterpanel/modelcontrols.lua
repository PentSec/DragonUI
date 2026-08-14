local addon = select(2, ...)
local CP = addon.CharacterPanel

-- Retail's model control strip: rotate, zoom and reset, faded in while the cursor is over it.
local BTN_SIZE = 29
local BTN_OVERLAP = 5
local GLYPH_SIZE = 17
local FADE_SECONDS = 0.15

local PLATE_SHEET = addon._dir .. "CharacterPanel\\commonbuttons"
local ICON_SHEET = addon._dir .. "CharacterPanel\\commonicons"

-- The strip's zoom buttons write the depth axis the native gestures drive. On the Ascension model
-- the native scroll-zoom still moves that same depth (this engine has no camera -- SetCamDistanceScale
-- only arrives in Cataclysm), so the retail buttons read the live position and clamp to the range the
-- XML's SetMinMaxDistance configures; the vanilla and pet models are handled by the core module
-- (core/modelview.lua), which tracks the same depth as an offset and re-bases it on reload.
local ZOOM_STEP = 0.25
-- Fallbacks only: the Ascension clamp is read off the model's own SetMinMaxDistance when available.
local RETAIL_ZOOM_MIN, RETAIL_ZOOM_MAX = -1.4, 1.4
-- Model_OnLoad's own starting rotation, so reset returns to exactly Blizzard's default.
local DEFAULT_ROTATION = 0.61
-- The Ascension model's OnLoad facing (PaperDollPanel.xml), so reset returns to exactly its default.
local DEFAULT_FACING = 0.45
-- One click of a strip rotate button, matching Blizzard's own 0.15-per-press step.
local ROTATE_STEP = 0.15
-- Radians per second while a hold-to-rotate button is held; roughly a full turn in four seconds.
local ROTATE_PER_SECOND = 1.6

-- Draw order of the whole strip; the settings decide which of these actually stand.
local STRIP_ORDER = { "left", "right", "zoomOut", "zoomIn", "reset" }

-- One entry per viewport the strip is built over, keyed by the model itself.
local strips = {}

-- The Ascension model's native gestures write the widget directly, so its strip reads the live
-- position to stay in step (the vanilla model's depth is owned by the core module instead).
local function position(model)
    if not model.GetPosition then return 0, 0, 0 end
    local ok, x, y, z = pcall(model.GetPosition, model)
    if not ok or not x then return 0, 0, 0 end
    return x, y or 0, z or 0
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- The strip's zoom buttons write the same axis the native gestures drive: the model's depth
-- position. The vanilla model's depth is owned by the core module (addon:ZoomModelDepth), which
-- tracks it as an offset re-based on every reload; the Ascension model's native scroll-zoom and
-- drag-move write the widget directly, so its strip reads the position live and clamps to the
-- range its own XML configures.
local function applyZoom(strip, notches)
    local model = strip.model
    if strip.retail then
        local x, y, z = position(model)
        pcall(model.SetPosition, model,
              clamp(x + notches * ZOOM_STEP, strip.zoomMin, strip.zoomMax), y, z)
    else
        addon:ZoomModelDepth(model, notches)
    end
end

local function resetModel(strip)
    local model = strip.model
    if strip.retail then
        if model.SetFacing then pcall(model.SetFacing, model, DEFAULT_FACING) end
        -- Clears the depth (zoom) and the drag-move pan in one go.
        if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
    else
        addon:ResetModelView(model)
        addon:ResetModelRotation(model)
    end
end

-- Steps the strip's own rotate pair. On the Ascension model the native drag-rotate writes the
-- facing too, so reading it live keeps the buttons and the mouse in step; the vanilla model reads
-- the same `rotation` field Model_OnUpdate carries while a Blizzard button is held.
local function rotateModel(strip, delta)
    local model = strip.model
    if strip.retail then
        local facing = 0
        if model.GetFacing then
            local ok, f = pcall(model.GetFacing, model)
            if ok and type(f) == "number" then facing = f end
        end
        if model.SetFacing then pcall(model.SetFacing, model, facing + delta) end
    else
        model.rotation = (model.rotation or DEFAULT_ROTATION) + delta
        if model.SetRotation then pcall(model.SetRotation, model, model.rotation) end
    end
end
-- Square plate, centred glyph, additive glow of that glyph on hover -- how retail lights these.
local function styleButton(btn, glyph)
    if btn._duiGlyph then return end
    btn:SetSize(BTN_SIZE, BTN_SIZE)

    -- A plain Button has no normal or pushed texture, so they must exist before they can be skinned.
    if not btn:GetNormalTexture() then btn:SetNormalTexture(PLATE_SHEET) end
    if not btn:GetPushedTexture() then btn:SetPushedTexture(PLATE_SHEET) end

    -- Pinned below the glyph explicitly rather than trusting the widget's default layer.
    local normal = btn:GetNormalTexture()
    normal:set_atlas("common-button-square-gray-up")
    normal:SetDrawLayer("BORDER")
    normal:ClearAllPoints()
    normal:SetAllPoints(btn)

    local pushed = btn:GetPushedTexture()
    pushed:set_atlas("common-button-square-gray-down")
    pushed:SetDrawLayer("BORDER")
    pushed:ClearAllPoints()
    pushed:SetAllPoints(btn)

    -- OVERLAY, not ARTWORK: a button's normal texture also sits there and creation order decides,
    -- so the plate could end up in front of the glyph.
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:set_atlas(glyph)
    icon:SetSize(GLYPH_SIZE, GLYPH_SIZE)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    btn._duiGlyph = icon

    if not btn:GetHighlightTexture() then btn:SetHighlightTexture(ICON_SHEET) end
    local hl = btn:GetHighlightTexture()
    hl:set_atlas(glyph)
    hl:ClearAllPoints()
    hl:SetAllPoints(icon)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.45)
end

-- Hiding a rotate button between its down and its up swallows the up and leaves it latched PUSHED,
-- drawing the dark plate for good -- and fading the strip under a held button does exactly that.
local function releaseButtons(strip)
    if not strip.controls then return end
    for _, btn in ipairs(strip.controls) do
        if btn:GetButtonState() == "PUSHED" then btn:SetButtonState("NORMAL") end
    end
end

-- Rebuilt rather than toggled button by button: the strip is centred on the model, so dropping one
-- has to re-measure the bar or whatever survives ends up sitting off-centre.
local function layoutControls(strip)
    local bar, buttons = strip.bar, strip.buttons
    if not (bar and buttons) then return end
    local cfg = CP:Config()

    local order = {}
    if not cfg.hide_model_controls then
        for _, key in ipairs(STRIP_ORDER) do order[#order + 1] = buttons[key] end
    elseif cfg.model_controls_reset_only then
        order[1] = buttons.reset
    end

    local standing = {}
    for _, btn in ipairs(order) do standing[btn] = true end

    -- Only the vanilla rotate pair fades on their own: they are the strip's siblings, while the
    -- strip's own children (including the Ascension-made rotate pair) inherit the bar's alpha.
    strip.faded = {}
    if not strip.retail then
        for _, btn in ipairs(order) do
            if btn == buttons.left or btn == buttons.right then strip.faded[#strip.faded + 1] = btn end
        end
    end
    strip.controls = order

    for _, key in ipairs(STRIP_ORDER) do
        local btn = buttons[key]
        -- Unlatched first: hiding a button between its down and its up strands it PUSHED for good.
        if btn:GetButtonState() == "PUSHED" then
            btn:SetButtonState("NORMAL")
        end
    end

    -- The vanilla rotate pair are siblings of the strip and are shown only by the fade, so they
    -- stay down here; the strip's own children each carry their own shown flag through a parent
    -- Show -- the retail-made rotate pair are children too, so they follow the standing flags.
    if strip.retail then
        for _, key in ipairs({ "left", "right", "zoomOut", "zoomIn", "reset" }) do
            local btn = buttons[key]
            if standing[btn] then btn:Show() else btn:Hide() end
        end
    else
        buttons.left:Hide()
        buttons.right:Hide()
        for _, key in ipairs({ "zoomOut", "zoomIn", "reset" }) do
            local btn = buttons[key]
            if standing[btn] then btn:Show() else btn:Hide() end
        end
    end

    local step = BTN_SIZE - BTN_OVERLAP
    bar:SetWidth(math.max(1, step * (#order - 1) + BTN_SIZE))
    for i, btn in ipairs(order) do
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", bar, "LEFT", (i - 1) * step, 0)
    end
end

-- A plain alpha lerp; the rotate buttons are siblings, not children, so they fade alongside it.
-- Re-armed every call: the ticker dies with an ancestor, stranding any "already fading" flag.
local function startFade(strip, target)
    local bar = strip.bar
    if not bar then return end
    bar._duiTarget = target

    if target > 0 then
        releaseButtons(strip)
        bar:Show()
        for _, btn in ipairs(strip.faded) do btn:Show() end
    end

    bar:SetScript("OnUpdate", function(self, elapsed)
        local current = self:GetAlpha()
        local goal = self._duiTarget
        local step = elapsed / FADE_SECONDS
        if current < goal then
            current = math.min(goal, current + step)
        else
            current = math.max(goal, current - step)
        end

        self:SetAlpha(current)
        for _, btn in ipairs(strip.faded) do btn:SetAlpha(current) end

        if current == goal then
            self:SetScript("OnUpdate", nil)
            if goal == 0 then
                self:Hide()
                for _, btn in ipairs(strip.faded) do btn:Hide() end
            end
        end
    end)
end

-- One strip per model viewport: the vanilla CharacterModelFrame (Blizzard's rotate buttons passed
-- in) and the Ascension character/Inspect models (retail = true -- a created rotate pair, and no
-- drag or wheel wiring, since ModelMixin owns those gestures).
local function buildStrip(model, opts)
    if not model or strips[model] then return end
    opts = opts or {}

    local strip = { model = model, retail = opts.retail and true or false }
    strips[model] = strip

    -- The zoom clamp the retail buttons obey: the Ascension model's live SetMinMaxDistance (with
    -- the same fallback the XML configures). Some getters hand back (max, min), so normalize first.
    -- The vanilla model's clamp lives in the core module (DEPTH_MIN/MAX), so none is stored here.
    if strip.retail then
        local min, max = RETAIL_ZOOM_MIN, RETAIL_ZOOM_MAX
        if model.GetMinMaxDistance then
            local ok, lo, hi = pcall(model.GetMinMaxDistance, model)
            if ok and type(lo) == "number" and type(hi) == "number" then
                if lo > hi then lo, hi = hi, lo end
                min, max = lo, hi
            end
        end
        strip.zoomMin, strip.zoomMax = min, max
    end

    local bar = CreateFrame("Frame", opts.name or "DragonUIModelControls", model)
    bar:SetHeight(BTN_SIZE)
    bar:SetPoint("TOP", model, "TOP", 0, -1)
    bar:SetAlpha(0)
    bar:Hide()
    strip.bar = bar

    local prefix = opts.prefix or "DragonUIModel"
    local buttons = {}
    strip.buttons = buttons

    if opts.left and opts.right then
        -- Blizzard's rotate buttons stay parented to the model: their OnClick passes self:GetParent()
        -- to the rotation helper, so reparenting them makes model.rotation come back nil.
        styleButton(opts.left, "common-icon-rotateright")
        styleButton(opts.right, "common-icon-rotateleft")
        buttons.left, buttons.right = opts.left, opts.right
        strip.faded = { opts.left, opts.right }
        for _, btn in ipairs(strip.faded) do
            -- Siblings of the strip, not children, and the strip has mouse enabled over the same area
            -- -- so without an explicit level it swallows their clicks.
            btn:SetFrameLevel(bar:GetFrameLevel() + 1)
            btn:SetAlpha(0)
            btn:Hide()
        end
    else
        -- The Ascension window has no rotate buttons, so the strip makes its own pair; as children
        -- of the bar they inherit its fade instead of needing a sibling alpha of their own.
        local function makeRotate(name, glyph, delta)
            local btn = CreateFrame("Button", name, bar)
            styleButton(btn, glyph)
            btn:SetScript("OnClick", function() rotateModel(strip, delta) end)
            return btn
        end
        -- The glyphs mirror the vanilla pair: the left button shows the right-turn arrow and steps
        -- the facing down, the right shows the left-turn arrow and steps it up.
        buttons.left = makeRotate(prefix .. "RotateLeft", "common-icon-rotateright", -ROTATE_STEP)
        buttons.right = makeRotate(prefix .. "RotateRight", "common-icon-rotateleft", ROTATE_STEP)
        strip.faded = {}
    end

    local function makeButton(name, glyph, onClick)
        local btn = CreateFrame("Button", name, bar)
        styleButton(btn, glyph)
        btn:SetScript("OnClick", onClick)
        return btn
    end

    local zoomIn = makeButton(prefix .. "ZoomIn", "common-icon-zoomin",
                              function() applyZoom(strip, 1) end)
    local zoomOut = makeButton(prefix .. "ZoomOut", "common-icon-zoomout",
                               function() applyZoom(strip, -1) end)
    local reset = makeButton(prefix .. "Reset", "common-icon-undo",
                             function() resetModel(strip) end)

    buttons.zoomOut, buttons.zoomIn, buttons.reset = zoomOut, zoomIn, reset
    layoutControls(strip)

    -- Closing the panel kills the ticker mid-fade, so reset rather than reopen at a frozen alpha.
    bar:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self:SetAlpha(0)
        self._duiTarget = 0
        for _, btn in ipairs(strip.faded) do
            btn:SetAlpha(0)
            btn:Hide()
        end
        releaseButtons(strip)
    end)

    model:EnableMouse(true)
    -- The Ascension model's ModelMixin already owns drag-rotate, drag-move and scroll-zoom, so the
    -- wheel hook and the drag loops below are vanilla-only. Hooked, not set: the model's XML
    -- OnMouseUp is what lets an item be dropped onto it to equip.
    if not strip.retail then
        addon:WireModelView(model, { hook = true })
    end

    -- Revealed over the model OR the strip, so reaching for a button does not fade it out underneath.
    -- Nothing standing means nothing to reveal; drag-rotate and wheel-zoom are not buttons and stay.
    local function show()
        if not strip.controls or #strip.controls == 0 then return end
        startFade(strip, 1)
    end
    local function hide()
        if bar:IsMouseOver() or model:IsMouseOver() then return end
        startFade(strip, 0)
    end
    model:HookScript("OnEnter", show)
    model:HookScript("OnLeave", hide)
    bar:EnableMouse(true)
    bar:SetScript("OnEnter", show)
    bar:SetScript("OnLeave", hide)
end

CP.BuildModelControls = buildStrip

-- Always put every strip away after a re-layout: each bar's own OnHide resets the alphas and
-- unlatches anything left PUSHED, and the next hover brings back whichever buttons survived.
function CP.RefreshModelControls()
    for _, strip in pairs(strips) do
        layoutControls(strip)
        strip.bar:Hide()
    end
end

CP.StyleModelButton = styleButton

-- Scale zoom: an imp and a felguard are framed at distances a depth push cannot serve alike.
function CP.WirePetModelControls(model)
    if not model or model._duiPetControls then return end
    model._duiPetControls = true
    -- Scale zoom: an imp and a felguard are framed at distances a depth push cannot serve alike.
    addon:ResetModelRotation(model)
    addon:WireModelView(model, { scale = true })

    local strip = CreateFrame("Frame", nil, model)
    strip:SetHeight(BTN_SIZE)
    strip:SetPoint("BOTTOM", model, "BOTTOM", 0, 2)

    -- Held, not clicked: Blizzard's own hold-to-rotate lives in Model_OnUpdate, which finds its
    -- buttons by GLOBAL NAME and so can never drive ours. This is that loop, per button.
    local spinner = CreateFrame("Frame", nil, model)
    spinner:Hide()
    spinner:SetScript("OnUpdate", function(self, elapsed)
        model.rotation = model.rotation + self.step * elapsed
        model:SetRotation(model.rotation)
    end)
    model:HookScript("OnHide", function() spinner:Hide() end)

    local order = {}
    local function add(glyph, step)
        local btn = CreateFrame("Button", nil, strip)
        styleButton(btn, glyph)
        btn:RegisterForClicks("LeftButtonDown", "LeftButtonUp")
        btn:SetScript("OnMouseDown", function()
            spinner.step = step
            spinner:Show()
        end)
        -- Also on leave: releasing off the button never delivers OnMouseUp, and it would spin forever.
        btn:SetScript("OnMouseUp", function() spinner:Hide() end)
        btn:SetScript("OnLeave", function() spinner:Hide() end)
        order[#order + 1] = btn
    end

    add("common-icon-rotateright", -ROTATE_PER_SECOND)
    add("common-icon-rotateleft", ROTATE_PER_SECOND)

    local step = BTN_SIZE - BTN_OVERLAP
    strip:SetWidth(step * (#order - 1) + BTN_SIZE)
    for i, btn in ipairs(order) do
        btn:SetPoint("LEFT", strip, "LEFT", (i - 1) * step, 0)
    end
    return strip
end

CP:RegisterBuilder("modelcontrols", function()
    buildStrip(_G.CharacterModelFrame, {
        left = _G.CharacterModelFrameRotateLeftButton,
        right = _G.CharacterModelFrameRotateRightButton,
    })
end)
