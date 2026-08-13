-- Ascension (custom-class private server) replaces the stock character window with
-- AscensionCharacterFrame -- a retail-style PortraitFrameTemplate (nineslice chrome, a tab
-- system, a model viewport and a right inset) that the stock CharacterFrame skin never sees.
-- Its client is retail-based, so SetAtlas, CallbackRegistry and hooksecurefunc on mixins are
-- available, and the addon's own atlas shim resolves its UI textures exactly as on 3.3.5a.
-- We skin in place: Ascension's layout and tab system stay, the art becomes DragonUI chrome.
local addon = select(2, ...)
local CP = addon.CharacterPanel

local ROCK = addon._dir .. "UI\\ui-background-rock"
local TAB_TEX = addon._dir .. "UI\\uiframetabs"

-- The mounts' 3D view in the collections window backdrops on this art; the pets tab's companion
-- viewport wears the same sheet so the two panes read as one surface.
local MOUNT_BG_TEX = addon._dir .. "Collections\\MountJournal-BG"
local MOUNT_BG_TC = { 0, 0.78515625, 0, 1 }

-- The three sidebar tabs above the right pane wear retail's PaperDollSidebarTabs sheet, the same
-- art sidebartabs.lua draws for the vanilla sidebar strip: the plates, the hider and highlight, and
-- the strip's end-pieces (decorLeft/decorRight) that frame the tab row at its base.
local SIDEBAR_SHEET = addon._dir .. "CharacterPanel\\paperdollsidebartabs"
local SIDEBAR_TC = {
    decorLeft = { 0.015625, 0.453125, 0.00390625, 0.046875 },
    decorRight = { 0.015625, 0.453125, 0.0546875, 0.10546875 },
    tabBg = { 0.015625, 0.796875, 0.61328125, 0.78125 },
    tabBgActive = { 0.015625, 0.796875, 0.7890625, 0.95703125 },
    tabHider = { 0.015625, 0.546875, 0.11328125, 0.1875 },
    tabHighlight = { 0.015625, 0.5, 0.1953125, 0.31640625 },
}

local STREAK_Y, STREAK_H = 21, 43

-- The class icon is a plain texture named *Portrait; Ascension parks it clear of the ring cutout
-- baked into our top-left chrome corner. Re-pin it into the ring slightly larger than the cutout --
-- the ring edge covers the excess, the same trick the vanilla skin uses (portrait.lua: 62x62 at
-- TOPLEFT(-5,7)) -- so the icon shows framed again.
local PORTRAIT_SIZE = 58
local PORTRAIT_X, PORTRAIT_Y = -5, 7

local NINESLICE_PIECES = {
    "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge",
}

-- Every Blizzard texture we hide and every texture we create, tracked so restore can walk both.
local hiddenRegions, createdTextures = {}, {}

local function neuter(region)
    if region._duiChromeHidden then return end
    region._duiChromeHidden = true
    hiddenRegions[#hiddenRegions + 1] = region
    -- Textures have no script handlers, so surviving Blizzard's re-Show means neutering Show itself.
    region._duiShow = region.Show
    region.Show = region.Hide
end

local function restoreHidden()
    for _, region in ipairs(hiddenRegions) do
        if region._duiShow then
            region.Show = region._duiShow
            region._duiShow = nil
        end
        region._duiChromeHidden = nil
        region:Show()
    end
end

local function own(tex)
    tex._duiOwned = true
    createdTextures[#createdTextures + 1] = tex
    return tex
end

-- Hide every texture a frame owns that is not one of ours, leaving FontStrings and the widget
-- tree (tabs, model, list rows) untouched. `keep` exempts specific textures and `keepFn` does the
-- same by predicate -- e.g. the frame's own portrait, which belongs over the metal cutout.
local function sweep(frame, keep, keepFn)
    if not frame or not frame.GetRegions then return end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture"
            and not region._duiOwned and not (keep and keep[region])
            and not (keepFn and keepFn(region)) then
            neuter(region)
            region:Hide()
        end
    end
end

local function isPortrait(region)
    local name = region.GetName and region:GetName()
    return name ~= nil and name:find("Portrait") ~= nil
end

-- The portrait texture survives sweep() via isPortrait, but on this client it stays where Ascension
-- put it -- outside our ring. Re-anchor it over the cutout, and keep re-asserting on OnShow since
-- the client re-layouts the window on some display changes. Our nineslice pieces are unnamed, so
-- the name filter can never match them.
local function repositionPortrait(cf)
    if not cf or not cf.GetRegions then return end
    for _, region in ipairs({ cf:GetRegions() }) do
        if region.GetObjectType and region:GetObjectType() == "Texture" and isPortrait(region) then
            region:SetSize(PORTRAIT_SIZE, PORTRAIT_SIZE)
            region:ClearAllPoints()
            region:SetPoint("TOPLEFT", cf, "TOPLEFT", PORTRAIT_X, PORTRAIT_Y)
            -- The ring draws at OVERLAY; park the icon on ARTWORK (vanilla's own portrait layer) so
            -- the ring metal frames it instead of hiding behind it.
            region:SetDrawLayer("ARTWORK")
        end
    end
end

-- A container may carry its own NineSlice child on top of the art we hide (the frame's is handled
-- by name above); the inset templates on the Ascension client draw theirs the same way. Neuter it
-- so restore() re-shows it like every other swept region.
local function hideNineSlice(host)
    if not host or not host.GetName then return end
    local ns = _G[host:GetName() .. "NineSlice"]
    if ns and ns.Hide then
        neuter(ns)
        ns:Hide()
    end
end

-- List panes put their parchment on the ScrollFrame they own, not on the panel, so sweep those
-- too -- but never the scroll content, whose rows keep Blizzard's own borders and icons.
local function sweepPanel(p)
    if not p then return end
    sweep(p)
    for _, child in ipairs({ p:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "ScrollFrame" then
            sweep(child)
        end
    end
end

-- The model viewport hides under a fixed global name on this client, but scan the paperdoll's
-- children for the model frame as a fallback so the backdrop lands wherever it actually is.
-- `opts` carries the per-window model global name (AscensionPaperDollPanelModel or
-- InspectPaperDollPanelModel) when the caller knows it; otherwise the scan alone resolves it.
local function findModel(panel, opts)
    if opts and opts.modelName then
        local m = _G[opts.modelName]
        if m then return m end
    end
    local m = _G.AscensionPaperDollPanelModel
    if m then return m end
    if panel and panel.GetChildren then
        for _, child in ipairs({ panel:GetChildren() }) do
            local t = child.GetObjectType and child:GetObjectType()
            if t == "PlayerModel" or t == "Model" then
                return child
            end
        end
    end
    return nil
end

-- Rock ground pinned to a host. The interior sheets (Inset, RightInset) tile their own so the
-- per-pane textures that used to cover them can simply be hidden.
local function addGround(host, key, topInset)
    local bg = host[key]
    if bg then return bg end
    bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(ROCK, "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    if topInset then
        -- The title band runs above the ground on the window; the streaks tile it instead.
        bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -topInset)
        bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)
    else
        bg:SetAllPoints(host)
    end
    host[key] = own(bg)
    return bg
end

-- Solid dark-brown ground for the pane-rimmed content areas (#100c08). The list panes and the
-- interior sheets used to wear parchment or rock; the rimmed panels now read as one flat field.
local PANE_FILL = { r = 0.062745, g = 0.047059, b = 0.031373 }
local function addFill(host)
    local bg = host._duiFill
    if bg then return bg end
    bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(PANE_FILL.r, PANE_FILL.g, PANE_FILL.b)
    bg:SetAllPoints(host)
    host._duiFill = own(bg)
    return bg
end

-- The companion viewport backdrops on the same MountJournal art the collections window draws
-- behind its mounts, cropped to the sheet's background frame like that window does.
local function addMountBg(host)
    local bg = host._duiMountBg
    if bg then return bg end
    bg = host:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(MOUNT_BG_TEX)
    bg:SetTexCoord(unpack(MOUNT_BG_TC))
    bg:SetAllPoints(host)
    host._duiMountBg = own(bg)
    return bg
end

-- The rim's textures land on the host frame; tag the ones DrawPaneBorder adds so restore hides
-- them with the rest of the art we created. Snapshot first so swept Blizzard textures never match.
local function addPaneBorder(host)
    if not CP.DrawPaneBorder or not host then return end
    local before = {}
    if host.GetRegions then
        for _, r in ipairs({ host:GetRegions() }) do before[r] = true end
    end
    CP.DrawPaneBorder(host, host)
    if host.GetRegions then
        for _, r in ipairs({ host:GetRegions() }) do
            if not before[r] and r.GetObjectType and r:GetObjectType() == "Texture" then
                own(r)
            end
        end
    end
end

-- Blizzard centers the name over the frame's top; retail sits it in the metal title band.
local function applyTitle(cf)
    local title = cf.TitleText or (cf:GetName() and _G[cf:GetName() .. "TitleText"])
    if not title or not title.SetPoint then return end
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", cf, "TOPLEFT", 48, -1)
    title:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -24, -1)
    title:SetHeight(20)
end

local CHARACTER_PANES = {
    "AscensionSkillsPanel",
    "AscensionReputationPanel",
    "AscensionCurrencyPanel",
    "AscensionCharacterTitlesPanel",
    "AscensionEquipmentManagerPanel",
    "AscensionMysticEnchantPanel",
    "AscensionCharacterCompanionPanel",
}

-- The Inspect window reuses the same AscensionCharacterFrameTemplate the character window wears, so
-- every helper here is parameterized by the root frame's name: "AscensionCharacterFrame" or
-- "AscensionInspectFrame". The Inset/RightInset/PaperDollPanel/CloseButton/NineSlice globals all
-- derive from that root name. Tab bits draw from the same templates and run through the same mixin
-- hooks, so the same buildChrome/buildTabs logic reskins both windows without a duplicate tree.
local function buildChrome(cfName, panes, opts)
    opts = opts or {}
    local cf = _G[cfName]
    if not cf then return end

    if not cf._duiChromeBuilt then
        cf._duiChromeBuilt = true

        -- Ascension's own retail nineslice hides; the shared layout draws DragonUI's metal over
        -- the rock instead, so the two can never double up.
        local ns = _G[cfName .. "NineSlice"]
        if ns then
            ns:Hide()
            cf._duiNineSliceFrame = ns
        end
        sweep(cf, nil, isPortrait)
        repositionPortrait(cf)

        addGround(cf, "_duiRockBg", STREAK_Y)

        if not cf._duiStreaks then
            local streaks = cf:CreateTexture(nil, "BORDER")
            streaks:set_atlas("_UI-Frame-TopTileStreaks")
            streaks:SetHorizTile(true)
            streaks:SetHeight(STREAK_H)
            streaks:SetPoint("TOPLEFT", cf, "TOPLEFT", 6, -STREAK_Y)
            streaks:SetPoint("TOPRIGHT", cf, "TOPRIGHT", -2, -STREAK_Y)
            cf._duiStreaks = own(streaks)
        end

        if not cf._duiNineSlice then
            local layout = NineSliceUtils and NineSliceUtils.GetLayout("PortraitFrameTemplate")
            if layout then
                NineSliceUtils.ApplyLayout(cf, layout)
                cf._duiNineSlice = true
                for _, piece in ipairs(NINESLICE_PIECES) do
                    if cf[piece] then
                        cf[piece]._duiOwned = true
                        -- The Ascension client may already own these pieces (its retail nineslice),
                        -- which makes the layout's SetDrawLayer a no-op; re-assert OVERLAY so the
                        -- portrait ring always draws above the class icon.
                        cf[piece]:SetDrawLayer("OVERLAY")
                    end
                end
            end
        end

        applyTitle(cf)
        CP.ModernizeCloseButton(_G[cfName .. "CloseButton"], cf)

        -- The shared body tint (the settings cog) shades the rock and streaks this block just
        -- drew; applied once at build so the stored config reads correctly from the first open.
        CP.ApplyBodyBackground()

        if not cf._duiPortraitHooked then
            cf._duiPortraitHooked = true
            cf:HookScript("OnShow", function(self)
                if self._duiChromeBuilt then repositionPortrait(self) end
            end)
        end
    end

    local inset = _G[cfName .. "Inset"]
    if inset then
        hideNineSlice(inset)
        sweep(inset)
        addGround(inset, "_duiBg")
    end
    local right = _G[cfName .. "RightInset"]
    if right then
        hideNineSlice(right)
        sweep(right)
        addFill(right)
        addPaneBorder(right)
    end

    -- The flat parchment grounds the list panes draw over the rock are hidden wholesale.
    for _, name in ipairs(panes or {}) do
        local panel = _G[name]
        if panel then
            sweepPanel(panel)
            addFill(panel)
            addPaneBorder(panel)
        end
    end

    -- The paperdoll tab re-stamps its race backdrop on every OnShow, so the hide has to be
    -- re-asserted after theirs runs rather than once at build; rock replaces the interior.
    local pdName = opts.paperDoll
    local pd = pdName and _G[pdName] or nil
    local model = findModel(pd, opts)
    if pd and pd.HookScript and not pd._duiBgHooked then
        pd._duiBgHooked = true
        pd:HookScript("OnShow", function(self)
            if self.Background then self.Background:Hide() end
        end)
        sweep(pd)
    end
    -- Dark fill plus the retail pane rim frame the whole tab content, the sidebar's mirror.
    if pd then
        addFill(pd)
        addPaneBorder(pd)
    end
    -- The model's own backdrop is swept and repainted by the shared builder (grey toggle included)
    -- the vanilla paperdoll wears. The Inspect viewport shows the *target*, so it builds the same
    -- backdrop from the target's race via opts.modelUnit, and hooks the model's SetUnit so a
    -- mid-open re-target repaints it too.
    if model then
        if model.HookScript and not model._duiBgHooked then
            model._duiBgHooked = true
            model:HookScript("OnShow", function(self)
                if self.Background then self.Background:Hide() end
            end)
        end
        -- The shared builder re-stamps the race backdrop on every Apply, so this sweep must
        -- spare the art an earlier pass created: those textures are not `own`ed, and a second
        -- pass (login's PLAYER_ENTERING_WORLD, the Inspect's ADDON_LOADED) would otherwise
        -- neuter their Show and blank the viewport. Blizzard's own backdrop still gets swept.
        local keep = {}
        if model._duiRaceBg then
            for _, tex in pairs(model._duiRaceBg) do keep[tex] = true end
        end
        if model._duiRaceBgOverlay then keep[model._duiRaceBgOverlay] = true end
        sweep(model, keep)
        if CP.BuildModelBackdrop then CP.BuildModelBackdrop(model, opts.modelUnit) end
        -- Re-targeting while the Inspect is open calls the frame's mixin OnShow directly, which
        -- never re-fires the OnShow script, so the backdrop would keep the previous target's race.
        -- The paperdoll's SetUnit forwards to the model on every swap, so hook that and re-apply
        -- for the new unit right after. The character window has no modelUnit and never hooks.
        if opts.modelUnit and model.SetUnit and not model._duiSetUnitHooked then
            model._duiSetUnitHooked = true
            pcall(hooksecurefunc, model, "SetUnit", function(self)
                if CP.BuildModelBackdrop then CP.BuildModelBackdrop(self, opts.modelUnit) end
            end)
        end
        addPaneBorder(model)
    end

    -- The pets tab's companion viewport wears retail's MountJournal sheet; the companion list
    -- beside it already gets the shared pane treatment. The 3D pane backdrops on the same
    -- MountJournal art the collections window draws behind its mounts, and the pane rim frames it
    -- like every other content pane (the model's Overlay shadow keeps the title readable).
    -- Character-only; Inspect has no pets tab.
    if opts.companionModel then
        local companionModel = _G[opts.companionModel]
        if companionModel then
            sweep(companionModel)
            addMountBg(companionModel)
            addPaneBorder(companionModel)
        end
    end
end

function CP.RestoreAscensionChrome()
    local cf = _G.AscensionCharacterFrame
    restoreHidden()
    if cf then
        if cf._duiNineSliceFrame then cf._duiNineSliceFrame:Show() end
        for _, key in ipairs({ "_duiRockBg", "_duiStreaks" }) do
            if cf[key] then cf[key]:Hide() end
        end
        for _, piece in ipairs(NINESLICE_PIECES) do
            if cf[piece] then cf[piece]:Hide() end
        end
    end
    for _, key in ipairs({ "AscensionCharacterFrameInset", "AscensionCharacterFrameRightInset" }) do
        local host = _G[key]
        if host and host._duiBg then host._duiBg:Hide() end
    end
    for _, tex in ipairs(createdTextures) do
        tex:Hide()
    end
    if cf and cf._duiTabArtHost then cf._duiTabArtHost:Hide() end
end

-- Restore mirrors for the Inspect window: it has no static Panes list (the Inspect's panels reset
-- individually via their own Hide), so we only clear shared owned textures and the per-window chrome
-- pieces the builder stamped on AscensionInspectFrame and its Inset/RightInset.
function CP.RestoreAscensionInspectChrome()
    local cf = _G.AscensionInspectFrame
    if cf then
        if cf._duiNineSliceFrame then cf._duiNineSliceFrame:Show() end
        for _, key in ipairs({ "_duiRockBg", "_duiStreaks" }) do
            if cf[key] then cf[key]:Hide() end
        end
        for _, piece in ipairs(NINESLICE_PIECES) do
            if cf[piece] then cf[piece]:Hide() end
        end
    end
    for _, key in ipairs({ "AscensionInspectFrameInset", "AscensionInspectFrameRightInset" }) do
        local host = _G[key]
        if host and host._duiBg then host._duiBg:Hide() end
    end
    if cf and cf._duiTabArtHost then cf._duiTabArtHost:Hide() end
end

-- The main tabs are bare text buttons (TabSystemTabs); the side tabs carry an icon. Both get the
-- same metal tab strip the retail character tabs wear, drawn from the shared uiframetabs sheet.
local CAP_OVERHANG = 5
local ACTIVE_OVERHANG_L, ACTIVE_OVERHANG_R = 4, 6
local TAB_PIECES = {
    { key = "Left", w = 35, h = 36, tc = { 0.015625, 0.5625, 0.816406, 0.957031 }, p = "TOPLEFT", x = -CAP_OVERHANG, y = 0 },
    { key = "Right", w = 37, h = 36, tc = { 0.015625, 0.59375, 0.667969, 0.808594 }, p = "TOPRIGHT", x = CAP_OVERHANG, y = 0 },
    { key = "LeftDisabled", w = 35, h = 42, tc = { 0.015625, 0.5625, 0.496094, 0.660156 }, p = "TOPLEFT", x = -ACTIVE_OVERHANG_L, y = 0 },
    { key = "RightDisabled", w = 37, h = 42, tc = { 0.015625, 0.59375, 0.324219, 0.488281 }, p = "TOPRIGHT", x = ACTIVE_OVERHANG_R, y = 0 },
}
local MIDDLES = {
    { key = "Middle", h = 36, tc = { 0, 0.015625, 0.175781, 0.316406 } },
    { key = "MiddleDisabled", h = 42, tc = { 0, 0.015625, 0.00390625, 0.16796875 } },
}
local HL_ALPHA = 0.4
local HL_H = 30
local HL_PIECES = {
    { key = "Left", w = 35, h = HL_H, tc = { 0.015625, 0.5625, 0.816406, 0.933594 }, p = "TOPLEFT" },
    { key = "Right", w = 37, h = HL_H, tc = { 0.015625, 0.59375, 0.667969, 0.785156 }, p = "TOPRIGHT" },
}
local HL_MIDDLE_TC = { 0, 0.015625, 0.175781, 0.292969 }
local TEXT_ACTIVE_DROP, TEXT_NUDGE_X = -7, -2

-- A child frame can never draw behind its parent, so the strip the FrameTabTabs draw -- textures
-- owned by the tab buttons, children of the window -- always painted OVER the window's top border
-- and streaks. The strip art moves to a sibling one level below the window: it renders before the
-- window, whose rock/streaks/nineslice cover the strip's lower body, leaving only the caps above
-- the top edge -- the retail tab-over-panel overlap. The textures still anchor to the tab buttons,
-- and the frame tracks the window, so geometry needs no re-derivation.
-- One host per window, stored on the frame: the Inspect window opens independently of the character
-- window, so a single shared host would track the wrong window's show/hide and let its strip art
-- linger or vanish with the other frame.
local function ensureTabArtHost(cf)
    local host = cf._duiTabArtHost
    if host then return host end
    host = CreateFrame("Frame", nil, cf:GetParent() or UIParent)
    host:EnableMouse(false)
    host:SetFrameLevel(cf:GetFrameLevel() - 1)
    host:SetAllPoints(cf)
    cf:HookScript("OnShow", function() host:Show() end)
    cf:HookScript("OnHide", function() host:Hide() end)
    host:SetShownReq(cf:IsShown())
    cf._duiTabArtHost = host
    return host
end

-- `paperdoll` swaps the metal strip for retail's PaperDollSidebarTabs face, the art the vanilla
-- sidebar strip draws from the same sheet (sidebartabs.lua): a plate that swaps dim/lit on
-- selection, the lit face as an additive hover, and a hider dropping the plate's bottom lip over
-- the pane. Same art table shape, so the shared sync logic drives both. `host` owns the created
-- textures: the main tabs draw their strip on the behind-window art host (one per window, tracked
-- on the frame), anchored to the button, so the window's own chrome covers the strip's overlap; the
-- side tabs keep the art on the button.
local function tabArt(t, layer, paperdoll, host)
    local art = t._duiTabArt
    if art then return art end
    art = { pieces = {}, middles = {} }
    t._duiTabArt = art
    host = host or t

    if paperdoll then
        art.PaperDoll = true

        local function plate(texCoord)
            local tex = t:CreateTexture(nil, layer)
            tex:SetTexture(SIDEBAR_SHEET)
            tex:SetSize(50, 43)
            tex:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", -9, -2)
            tex:SetTexCoord(unpack(texCoord))
            art.pieces[#art.pieces + 1] = own(tex)
            return tex
        end
        art.Normal = plate(SIDEBAR_TC.tabBg)
        art.Pushed = plate(SIDEBAR_TC.tabBgActive)

        local hider = t:CreateTexture(nil, "OVERLAY")
        hider:SetTexture(SIDEBAR_SHEET)
        hider:SetSize(34, 19)
        hider:SetPoint("BOTTOM", t, "BOTTOM", 0, -2)
        hider:SetTexCoord(unpack(SIDEBAR_TC.tabHider))
        art.Hider = own(hider)
        art.pieces[#art.pieces + 1] = hider

        -- A loose texture on our own HIGHLIGHT layer never lights -- the engine only drives the
        -- button's native HighlightTexture. Restyle that one in place, the way sidebartabs builds
        -- its hover; buildTabs keeps it out of sweep so its Show lives.
        if not t:GetHighlightTexture() then t:SetHighlightTexture(SIDEBAR_SHEET) end
        local hl = t:GetHighlightTexture()
        if hl then
            hl:SetTexture(SIDEBAR_SHEET)
            hl:SetTexCoord(unpack(SIDEBAR_TC.tabHighlight))
            hl:ClearAllPoints()
            hl:SetPoint("TOPLEFT", t, "TOPLEFT", 2, -3)
            hl:SetSize(31, 31)
            hl:SetBlendMode("ADD")
            hl:SetAlpha(HL_ALPHA)
            art.Highlight = { own(hl) }
        end
        return art
    end

    for _, piece in ipairs(TAB_PIECES) do
        local tex = host:CreateTexture(nil, layer)
        tex:SetTexture(TAB_TEX)
        tex:SetTexCoord(unpack(piece.tc))
        tex:SetSize(piece.w, piece.h)
        tex:SetPoint(piece.p, t, piece.p, piece.x, piece.y)
        art[piece.key] = own(tex)
        art.pieces[#art.pieces + 1] = tex
    end

    -- The strip spans between the caps by anchor; a width on top would leave the engine reconciling
    -- a 1px column against the span.
    for _, m in ipairs(MIDDLES) do
        local tex = host:CreateTexture(nil, layer)
        tex:SetTexture(TAB_TEX)
        tex:SetTexCoord(unpack(m.tc))
        tex:SetHorizTile(true)
        tex:SetHeight(m.h)
        local left, right = art.Left, art.Right
        if m.key ~= "Middle" then left, right = art.LeftDisabled, art.RightDisabled end
        tex:SetPoint("TOPLEFT", left, "TOPRIGHT")
        tex:SetPoint("TOPRIGHT", right, "TOPLEFT")
        art.middles[m.key] = own(tex)
        art.pieces[#art.pieces + 1] = tex
    end

    -- Additive inactive-art-again highlight, cut to the tab's solid body so the shadow never sums.
    local hl, ends = {}, {}
    for _, piece in ipairs(HL_PIECES) do
        local tex = host:CreateTexture(nil, "HIGHLIGHT")
        tex:SetTexture(TAB_TEX)
        tex:SetTexCoord(unpack(piece.tc))
        tex:SetSize(piece.w, piece.h)
        tex:SetPoint(piece.p, t, piece.p, 0, 0)
        tex:SetBlendMode("ADD")
        tex:SetAlpha(HL_ALPHA)
        hl[#hl + 1] = own(tex)
        ends[piece.key] = tex
    end
    local middle = host:CreateTexture(nil, "HIGHLIGHT")
    middle:SetTexture(TAB_TEX)
    middle:SetTexCoord(unpack(HL_MIDDLE_TC))
    middle:SetHorizTile(true)
    middle:SetHeight(HL_H)
    middle:SetPoint("TOPLEFT", ends.Left, "TOPRIGHT")
    middle:SetPoint("TOPRIGHT", ends.Right, "TOPLEFT")
    middle:SetBlendMode("ADD")
    middle:SetAlpha(HL_ALPHA)
    hl[#hl + 1] = own(middle)
    art.Highlight = hl

    return art
end

local function setShown(tex, shown)
    if shown then tex:Show() else tex:Hide() end
end

local function syncTab(t, selected)
    local art = t._duiTabArt
    if not art then return end

    if art.PaperDoll then
        setShown(art.Normal, not selected)
        setShown(art.Pushed, selected)
    else
        setShown(art.Left, not selected)
        setShown(art.Right, not selected)
        setShown(art.middles.Middle, not selected)
        setShown(art.LeftDisabled, selected)
        setShown(art.RightDisabled, selected)
        setShown(art.middles.MiddleDisabled, selected)
    end
    if art.Highlight then
        for _, tex in ipairs(art.Highlight) do tex:SetAlpha(selected and 0 or HL_ALPHA) end
    end

    local text = t.Text or (t:GetName() and _G[t:GetName() .. "Text"])
    if text then
        text:ClearAllPoints()
        text:SetPoint("CENTER", t, "CENTER", TEXT_NUDGE_X, selected and TEXT_ACTIVE_DROP or 0)
    end
end

local function collectTabs(host)
    local out = {}
    if not host or not host.GetChildren then return out end
    for _, child in ipairs({ host:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "CheckButton" and child:GetParent() == host then
            out[#out + 1] = child
        end
    end
    return out
end

local function getSelectedTab(host)
    if not host then return nil end
    if host.GetSelectedTab then return host:GetSelectedTab() end
    local ts = host.tabSystem or host._tabSystem
    if ts and ts.GetSelectedTab then return ts:GetSelectedTab() end
    return nil
end

-- The tab system drives selection through the mixin hooks, not the checked state -- on this
-- client GetChecked() reads true on every tab -- so the flags the hooks set are authoritative,
-- the tab system's own notion of the selected tab decides the initial build, and the checked
-- state is only a last resort for clients that do drive it. syncAll never persists these reads;
-- only the hooks write _duiSelected, so no stale state can stick.
local function selectedState(t, host, sel)
    if t._duiSelected ~= nil then return t._duiSelected end
    if sel then return sel == t end
    if t.GetChecked and t:GetChecked() then return true end
    return false
end

local function syncAll(host)
    local sel = getSelectedTab(host)
    for _, t in ipairs(collectTabs(host)) do
        syncTab(t, selectedState(t, host, sel))
    end
end

-- sidebartabs.lua caps the vanilla strip with a decor piece at each end of the tab row, behind the
-- plates. Ascension's tabs hang straight off the RightInset (no strip frame), so the same two
-- sprites land on the RightInset at the row's ends -- 3px clear of the first tab, 2px off the last,
-- on the tab bottoms -- and draw under the tabs' own plates.
-- sidebartabs.lua caps the vanilla strip with a decor piece at each end of the tab row, behind the
-- plates. Ascension's tabs hang straight off the RightInset (no strip frame), so the same two
-- sprites land on the RightInset, pinning to the first and last tab in the row. The pieces are
-- created once but re-anchored on every build pass: the Inspect adds its MysticEnchant tab
-- dynamically in OnShow, so the row's ends can move after the first build.
local function addSidebarDecor(host)
    if not host then return end
    local firstTab, lastTab
    for _, t in ipairs(collectTabs(host)) do
        if not firstTab then firstTab = t end
        lastTab = t
    end
    if not firstTab or not lastTab then return end

    local decorLeft = host._duiDecorLeft
    if not decorLeft then
        decorLeft = host:CreateTexture(nil, "ARTWORK")
        decorLeft:SetTexture(SIDEBAR_SHEET)
        decorLeft:SetSize(28, 11)
        decorLeft:SetTexCoord(unpack(SIDEBAR_TC.decorLeft))
        own(decorLeft)
        host._duiDecorLeft = decorLeft
    end
    decorLeft:SetPoint("BOTTOMRIGHT", firstTab, "BOTTOMLEFT", -3, 0)

    local decorRight = host._duiDecorRight
    if not decorRight then
        decorRight = host:CreateTexture(nil, "ARTWORK")
        decorRight:SetTexture(SIDEBAR_SHEET)
        decorRight:SetSize(28, 13)
        decorRight:SetTexCoord(unpack(SIDEBAR_TC.decorRight))
        own(decorRight)
        host._duiDecorRight = decorRight
    end
    decorRight:SetPoint("BOTTOMLEFT", lastTab, "BOTTOMRIGHT", 2, 0)
end

-- SelectTab fires OnDeselected on the outgoing tab and OnSelected on the incoming one; the hooks
-- mirror the state. Resyncing the whole strip on select also clears any stale flag a previous
-- build pass left on tabs the system never touched -- the exact cause of every tab glowing.
local function onSelectedOne(t)
    if not t or not t._duiTabArt then return end
    for _, other in ipairs(collectTabs(t:GetParent())) do
        local selected = other == t
        other._duiSelected = selected
        syncTab(other, selected)
    end
end

local function onDeselectedOne(t)
    if not t or not t._duiTabArt then return end
    t._duiSelected = false
    syncTab(t, false)
end

-- The Ascension client drives its own tabs through these mixins; hooking them keeps the art
-- in lockstep with whichever tab it selects, without us owning the selection logic.
local selectionHooked = false
local function hookSelectionMixins()
    if selectionHooked then return end
    selectionHooked = true
    for _, mixin in ipairs({ _G.TabSystemTabMixin, _G.CharacterFrameSideTabMixin }) do
        if mixin then
            if type(mixin.OnSelected) == "function" then
                pcall(hooksecurefunc, mixin, "OnSelected", onSelectedOne)
            end
            if type(mixin.OnDeselected) == "function" then
                pcall(hooksecurefunc, mixin, "OnDeselected", onDeselectedOne)
            end
        end
    end
end

-- The client's CallbackRegistry calls registered fns with its own leading argument (a numeric
-- tab id on Ascension), not the frame -- so capture the host in a closure and resync by re-reading
-- each tab's checked state, which the tab system sets before it fires the event.
local function registerTabCallbacks(host)
    if not host or not host.RegisterCallback or host._duiTabCB then return end
    host._duiTabCB = true
    host:RegisterCallback("OnTabSelected", function() syncAll(host) end)
    host:RegisterCallback("OnTabDeselected", function() syncAll(host) end)
end

-- The tab system on both windows is the same TabSystemMixin; the side tabs share
-- AscensionCharacterFrameSideTabTemplate (the Inspect's side-tab template inherits it), so the
-- portrait-icon side tab survives sweep. Parameterize the root frame name so the same build reskins
-- the AscensionCharacterFrame and the AscensionInspectFrame tabs.
local function buildTabs(cfName)
    local cf = _G[cfName]
    if not cf then return end

    hookSelectionMixins()

    local artHost = ensureTabArtHost(cf)
    for _, t in ipairs(collectTabs(cf)) do
        sweep(t)
        tabArt(t, "ARTWORK", nil, artHost)
    end
    registerTabCallbacks(cf)
    syncAll(cf)

    local right = _G[cfName .. "RightInset"]
    if right then
        for _, t in ipairs(collectTabs(right)) do
            -- The side tabs' icons are theirs to keep; the plate goes underneath at BACKGROUND so
            -- the icon always reads on top of the button face. The template's own HighlightTexture
            -- is the hover face tabArt restyles -- keep it too, or sweep neuters its Show.
            local keep = {}
            if t.Icon then keep[t.Icon] = true end
            local hl = t:GetHighlightTexture()
            if hl then keep[hl] = true end
            sweep(t, keep)
            tabArt(t, "BACKGROUND", true)
        end
        addSidebarDecor(right)
        registerTabCallbacks(right)
        syncAll(right)
    end
end

CP:RegisterBuilder("ascension-chrome", function() return buildChrome("AscensionCharacterFrame", CHARACTER_PANES, {
    paperDoll = "AscensionPaperDollPanel",
    companionModel = "AscensionPetPaperDollPanelCompanionTabCompanionModel",
}) end, { server = "ascension" })
CP:RegisterBuilder("ascension-tabs", function() return buildTabs("AscensionCharacterFrame") end, { server = "ascension" })

-- The Inspect window reuses the same AscensionCharacterFrameTemplate, so it gets the same skin:
-- metal nineslice over rock, the pane rim on Inset/RightInset, the sidebar tabs and the main tabs.
-- The Inspect's PaperDoll model shows the *target*, so the shared race backdrop builds from the
-- target's race (modelUnit = "target") and follows the grey toggle like the character viewport; it
-- has no pets tab. InspectPaperDollPanel is deliberately absent here -- its own paperdoll handling
-- below sweeps and frames it once, and double-listing it would draw the rim twice. InspectStatsPanel
-- is also absent, mirroring the character frame: it re-stamps a per-class background atlas on every
-- OnShow, so it keeps its own backdrop over the RightInset fill instead of the dark pane.
local INSPECT_PANES = {
    "InspectPvPPanel",
    "InspectBuildPanel",
    "InspectMysticEnchantPanel",
}
CP:RegisterBuilder("ascension-inspect-chrome", function() return buildChrome("AscensionInspectFrame", INSPECT_PANES, {
    paperDoll = "InspectPaperDollPanel",
    modelName = "InspectPaperDollPanelModel",
    modelUnit = "target",
}) end, { server = "ascension" })
CP:RegisterBuilder("ascension-inspect-tabs", function() return buildTabs("AscensionInspectFrame") end, { server = "ascension" })

-- The model control strip over the Ascension viewports: the model already has native drag-rotate,
-- drag-move and scroll-zoom via ModelMixin, so the strip is pure affordance -- its rotate pair
-- steps the facing, the zoom pair steps the camera, and reset restores the OnLoad defaults, all
-- the same state the native gestures write. The Inspect model only exists after the first inspect,
-- so the builders simply wait for theirs to appear.
CP:RegisterBuilder("ascension-model-controls", function()
    local model = _G.AscensionPaperDollPanelModel
    if model and CP.BuildModelControls then
        CP.BuildModelControls(model, {
            name = "DragonUIAscensionModelControls",
            prefix = "DragonUIAscensionModel",
            retail = true,
        })
    end
end)

CP:RegisterBuilder("ascension-inspect-model-controls", function()
    local model = _G.InspectPaperDollPanelModel
    if model and CP.BuildModelControls then
        CP.BuildModelControls(model, {
            name = "DragonUIAscensionInspectModelControls",
            prefix = "DragonUIAscensionInspectModel",
            retail = true,
        })
    end
end)

-- The settings cog: on this client the stock CharacterFrame never shows, so this gear is the
-- module's only settings entry point. The shared menu is trimmed to what the Ascension windows can
-- actually change -- the body tint shades the rock and streaks both windows draw, and the model
-- backdrop section only appears on the paperdoll tab, whose viewport the shared BuildModelBackdrop
-- paints. The Gear summary section is vanilla-sidebar-only and stays out.
local COG_SIZE = 20
-- Measured from the close button rather than the frame corner so the pair travels together.
local COG_X, COG_Y = -6, -3

-- The cogwheel the vanilla skin's settings button uses, so both gears in the addon are the same.
local GEAR = "Interface\\WorldMap\\Gear_64Grey"

local ascCog, ascMenu

local function ascSetDark(dark)
    CP:Config().dark_background = dark and true or false
    CP.ApplyBodyBackground()
end

-- The grey toggle writes the shared config the backdrop builder reads on every apply, so re-running
-- the build on both Ascension models is all the refresh needs -- the Inspect's reads the target's
-- race (it is nil-safe here: the Inspect model only exists after the first inspect).
local function ascSetGrey(grey)
    CP:Config().grey_model_backdrop = grey and true or false
    if not CP.BuildModelBackdrop then return end
    if _G.AscensionPaperDollPanelModel then
        CP.BuildModelBackdrop(_G.AscensionPaperDollPanelModel)
    end
    if _G.InspectPaperDollPanelModel then
        CP.BuildModelBackdrop(_G.InspectPaperDollPanelModel, "target")
    end
end

local function ascMenuTitle(text, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.isTitle = 1
    info.notCheckable = 1
    UIDropDownMenu_AddButton(info, level)
end

local function ascMenuRadio(text, checked, onSelect, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.checked = checked
    info.func = onSelect
    UIDropDownMenu_AddButton(info, level)
end

-- Re-read on every open, so the radios track whichever window last changed the shared config.
local function ascInitMenu(_, level)
    local dark = CP:Config().dark_background

    ascMenuTitle(addon.L["Background"], level)
    ascMenuRadio(addon.L["Stone"], not dark, function() ascSetDark(false) end, level)
    ascMenuRadio(addon.L["Dark"], dark, function() ascSetDark(true) end, level)

    -- Only where there is a model to put a backdrop behind: the paperdoll tab, whose viewport the
    -- shared BuildModelBackdrop paints. The pets tab's companion wears the MountJournal sheet, so
    -- the section is dropped there and on the collapsed list tabs.
    local cf = _G.AscensionCharacterFrame
    local paperdoll = false
    if cf and cf.GetTabForPanel and cf.GetCurrentTabID then
        local tab = cf:GetTabForPanel("AscensionPaperDollPanel")
        paperdoll = tab ~= nil and tab.GetTabID and tab:GetTabID() == cf:GetCurrentTabID()
    end
    if not paperdoll then return end

    local grey = CP:Config().grey_model_backdrop
    ascMenuTitle(addon.L["Model backdrop"], level)
    ascMenuRadio(addon.L["Greyscale"], grey, function() ascSetGrey(true) end, level)
    ascMenuRadio(addon.L["Full colour"], not grey, function() ascSetGrey(false) end, level)
end

-- One gear, always visible: unlike the vanilla window, every tab shares the same chrome, so the
-- background radios mean something on each of them.
local function buildCog()
    local cf = _G.AscensionCharacterFrame
    if ascCog or not cf then return end

    ascMenu = CreateFrame("Frame", "DragonUIAscensionSettingsMenu", UIParent, "UIDropDownMenuTemplate")
    UIDropDownMenu_Initialize(ascMenu, ascInitMenu, "MENU")

    ascCog = CreateFrame("Button", "DragonUIAscensionSettingsCog", cf)
    ascCog:SetSize(COG_SIZE, COG_SIZE)
    -- The nineslice corner and the title band both paint over this corner otherwise, the same way
    -- the close button has to clear them.
    ascCog:SetFrameLevel(cf:GetFrameLevel() + CP.SUBFRAME_LEVEL + 20)

    local close = _G.AscensionCharacterFrameCloseButton
    if close then
        ascCog:SetPoint("TOPRIGHT", close, "BOTTOMRIGHT", COG_X, COG_Y)
    else
        ascCog:SetPoint("TOPRIGHT", cf, "TOPRIGHT", COG_X - 6, COG_Y - 24)
    end

    local icon = ascCog:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(GEAR)
    icon:SetAllPoints(ascCog)
    ascCog.Icon = icon

    local hl = ascCog:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture(GEAR)
    hl:SetAllPoints(ascCog)
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)

    ascCog:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, ascMenu, self, 0, 0)
    end)
    -- Blizzard's DropDownList1 lives on UIParent, so it outlives the cog unless it is closed by hand.
    ascCog:SetScript("OnHide", function()
        if UIDROPDOWNMENU_OPEN_MENU == ascMenu then CloseDropDownMenus() end
    end)
    ascCog:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- Neutral wording: the same gear serves every tab we draw, so naming one of them is wrong
        -- on the others and would go stale again as more arrive.
        GameTooltip:SetText(addon.L["Panel settings"], 1, 1, 1)
        GameTooltip:Show()
    end)
    ascCog:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Switching main tabs re-reads the pane the model section gates on, so close a menu that is
    -- open -- otherwise it would float over a tab whose radios no longer apply.
    if cf.RegisterCallback and not cf._duiCogTabHooked then
        cf._duiCogTabHooked = true
        cf:RegisterCallback("OnTabSelected", function() CloseDropDownMenus() end)
    end
end

CP:RegisterBuilder("ascension-settings-cog", buildCog)

-- Ascension detection, matching the rest of the addon: the PathToAscension micro button exists only
-- on Ascension servers. (CP.SERVER is never assigned, so the old gate here could never fire.)
local isAscension = _G.PathToAscensionMicroButton ~= nil or _G.AscensionCharacterFrame ~= nil

-- The client builds AscensionCharacterFrame during login, but never sooner: poll briefly so the
-- skin lands the moment it exists, whatever order login events fired in. Stops on its own.
if isAscension then
    local tries = 0
    local retry = CreateFrame("Frame")
    retry:SetScript("OnUpdate", function(self)
        tries = tries + 1
        if _G.AscensionCharacterFrame then
            self:SetScript("OnUpdate", nil)
            if CP:Enabled() then CP.Apply() end
        elseif tries > 1200 then
            self:SetScript("OnUpdate", nil)
        end
    end)
end

-- Ascension_InspectUI is LoadOnDemand: the frame only exists after the player first inspects
-- someone, so no login-time pass can skin it. ADDON_LOADED fires the moment that addon loads --
-- and the XML has already run by then, so the builders skin the window in place. The OnShow hook
-- covers later opens, whose panels re-stamp their backdrops per inspect. Registered unconditionally:
-- the addon name never matches on a non-Ascension client, so there is no wasted work.
local inspectLoader = CreateFrame("Frame")
inspectLoader:RegisterEvent("ADDON_LOADED")
inspectLoader:SetScript("OnEvent", function(_, _, name)
    if name ~= "Ascension_InspectUI" then return end
    if not CP:Enabled() then return end
    -- Apply directly if the frame exists; otherwise the OnShow hook below catches it.
    CP.Apply()
    local f = _G.AscensionInspectFrame
    if f and not f._duiInspectShownHooked then
        f._duiInspectShownHooked = true
        f:HookScript("OnShow", function()
            if CP:Enabled() then CP.Apply() end
        end)
    end
end)
