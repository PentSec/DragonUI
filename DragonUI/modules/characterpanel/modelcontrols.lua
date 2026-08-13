local addon = select(2, ...)
local CP = addon.CharacterPanel

-- Retail's model control strip: rotate, zoom and reset, faded in while the cursor is over it.
local BTN_SIZE = 29
local BTN_OVERLAP = 5
local GLYPH_SIZE = 17
local FADE_SECONDS = 0.15

local PLATE_SHEET = addon._dir .. "CharacterPanel\\commonbuttons"
local ICON_SHEET = addon._dir .. "CharacterPanel\\commonicons"

-- 3.3.5a's model zooms through the depth axis of SetPosition; the Ascension window's PlayerModel
-- wears retail-style method names, but this engine has no camera (SetCamDistanceScale only arrives
-- in Cataclysm), so its native scroll-zoom still moves that same depth -- SetCameraDistance does
-- nothing here, which is exactly why a camera-based strip button would be dead. Both modes rotate
-- through whatever the native drag-rotate writes: the `rotation` field on vanilla, the facing on
-- the Ascension model, so the strip's buttons and the mouse gestures stay in step.
local ZOOM_STEP = 0.25
local ZOOM_MIN, ZOOM_MAX = -3, 3
-- Fallbacks only: the Ascension clamp is read off the model's own SetMinMaxDistance when available.
local RETAIL_ZOOM_MIN, RETAIL_ZOOM_MAX = -1.4, 1.4
local PAN_LIMIT = 1.5
local PAN_SPEED = 0.004
-- Model_OnLoad's own starting rotation, so reset returns to exactly Blizzard's default.
local DEFAULT_ROTATION = 0.61
-- The Ascension model's OnLoad facing (PaperDollPanel.xml), so reset returns to exactly its default.
local DEFAULT_FACING = 0.45
-- Matches the collections model, so both windows spin at the same rate under the same drag.
local ROTATION_SPEED = 0.012
-- One click of a strip rotate button, matching Blizzard's own 0.15-per-press step.
local ROTATE_STEP = 0.15

-- Draw order of the whole strip; the settings decide which of these actually stand.
local STRIP_ORDER = { "left", "right", "zoomOut", "zoomIn", "reset" }

-- One entry per viewport the strip is built over, keyed by the model itself.
local strips = {}

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

-- The strip's zoom writes the same axis the native gestures drive: the model's depth position,
-- clamped to whichever range the viewport configured (the vanilla constant or the Ascension
-- model's OnLoad SetMinMaxDistance). The vanilla model's first SetPosition axis is depth; the
-- Ascension model's drag-move owns the other two axes, so the buttons and the mouse stay in step.
local function applyZoom(strip, delta)
    local model = strip.model
    local x, y, z = position(model)
    pcall(model.SetPosition, model,
          clamp(x + delta, strip.zoomMin, strip.zoomMax), y, z)
end

local function applyPan(model, dy, dz)
    local x, y, z = position(model)
    pcall(model.SetPosition, model, x,
          clamp(y + dy, -PAN_LIMIT, PAN_LIMIT),
          clamp(z + dz, -PAN_LIMIT, PAN_LIMIT))
end

local function resetModel(strip)
    local model = strip.model
    if strip.retail then
        if model.SetFacing then pcall(model.SetFacing, model, DEFAULT_FACING) end
        -- Clears the depth (zoom) and the drag-move pan in one go.
        if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
    else
        if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
        model.rotation = DEFAULT_ROTATION
        if model.SetRotation then pcall(model.SetRotation, model, DEFAULT_ROTATION) end
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

-- Hooked, not set: the model's XML OnUpdate drives hold-to-rotate and its OnMouseUp is what lets an
-- item be dropped on the model. Driving the pan through either one wiped that behaviour. The
-- Ascension model needs none of this: ModelMixin already wires drag-rotate and drag-move natively.
local panner = CreateFrame("Frame")
panner:Hide()

local rotator = CreateFrame("Frame")
rotator:Hide()

local function wireDrag(model)
    if model._duiDragWired then return end
    model._duiDragWired = true

    -- The button state is polled, as Blizzard's own drag loops do: a release with the cursor off the
    -- model never delivers OnMouseUp here, and this frame outlives the panel, so it would never stop.
    panner:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("RightButton") then self:Hide(); return end
        local cx, cy = GetCursorPosition()
        local dx, dy = cx - (self.x or cx), cy - (self.y or cy)
        self.x, self.y = cx, cy
        -- Screen x maps to the model's lateral axis, screen y to its vertical one.
        applyPan(model, dx * PAN_SPEED, dy * PAN_SPEED)
    end)

    -- Writes model.rotation, not just SetRotation: Model_OnUpdate reads that field to carry a held
    -- rotate button on, so a drag that skipped it would be snapped away by the next button press.
    rotator:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then self:Hide(); return end
        local cx = GetCursorPosition()
        model.rotation = (model.rotation or DEFAULT_ROTATION) + (cx - (self.x or cx)) * ROTATION_SPEED
        self.x = cx
        model:SetRotation(model.rotation)
    end)

    model:HookScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            rotator.x = GetCursorPosition()
            rotator:Show()
        elseif button == "RightButton" then
            panner.x, panner.y = GetCursorPosition()
            panner:Show()
        end
    end)
    -- The XML OnMouseUp still runs first, so dropping an item on the model still equips it.
    model:HookScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then rotator:Hide() end
        if button == "RightButton" then panner:Hide() end
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

    -- The zoom clamp each mode's native gesture obeys, so the buttons can never push past it: the
    -- vanilla constant for the stock model, the Ascension model's live SetMinMaxDistance (with the
    -- same fallback the XML configures). Some getters hand back (max, min), so normalize first.
    local min, max = ZOOM_MIN, ZOOM_MAX
    if strip.retail then
        min, max = RETAIL_ZOOM_MIN, RETAIL_ZOOM_MAX
        if model.GetMinMaxDistance then
            local ok, lo, hi = pcall(model.GetMinMaxDistance, model)
            if ok and type(lo) == "number" and type(hi) == "number" then
                if lo > hi then lo, hi = hi, lo end
                min, max = lo, hi
            end
        end
    end
    strip.zoomMin, strip.zoomMax = min, max

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
                              function() applyZoom(strip, ZOOM_STEP) end)
    local zoomOut = makeButton(prefix .. "ZoomOut", "common-icon-zoomout",
                               function() applyZoom(strip, -ZOOM_STEP) end)
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
    -- wheel hook and the pan/rotate drag loops below are vanilla-only.
    if not strip.retail then
        wireDrag(model)
        -- 3.3.5a has no Model_OnMouseWheel, so wheel-zoom is ours to wire.
        model:EnableMouseWheel(true)
        model:HookScript("OnMouseWheel", function(_, delta)
            applyZoom(strip, delta * ZOOM_STEP)
        end)
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

CP:RegisterBuilder("modelcontrols", function()
    buildStrip(_G.CharacterModelFrame, {
        left = _G.CharacterModelFrameRotateLeftButton,
        right = _G.CharacterModelFrameRotateRightButton,
    })
end)
