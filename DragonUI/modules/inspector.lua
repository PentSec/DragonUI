local addon = select(2, ...)

local InspectorModule = { applied = false }
local ComparePanel, cpFrame, cpScroll, cpContent
local CP

if addon.RegisterModule then
    addon:RegisterModule("inspector", InspectorModule,
        "Talent Inspector",
        "Shows the CoA talent tree when inspecting a player",
        {
            lifecycle = {
                apply   = "ApplyInspectorSystem",
                restore = "RestoreInspectorSystem",
                refresh = "RefreshInspectorSystem",
            },
        })
end

local DEFAULTS = {
    enabled = true,
    scale = 0.83,
}

local db

local function EnsureConfig()
    if not addon.db or not addon.db.profile then return false end
    if not addon.db.profile.modules then
        addon.db.profile.modules = {}
    end
    if not addon.db.profile.modules.inspector then
        addon.db.profile.modules.inspector = {}
        for k, v in pairs(DEFAULTS) do
            addon.db.profile.modules.inspector[k] = v
        end
    end
    db = addon.db.profile.modules.inspector
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return true
end

local function IsModuleEnabled()
    return db and db.enabled == true
end

local function LogMsg(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff8080ff[Inspector]|r " .. tostring(msg))
    end
end

local function SafeCall(fn, ...)
    local ok, res = pcall(fn, ...)
    if not ok then LogMsg("error: " .. tostring(res)) end
    return ok, res
end

local VANILLA_CLASSES = {
    WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true,
    PRIEST = true, DEATHKNIGHT = true, SHAMAN = true, MAGE = true,
    WARLOCK = true, DRUID = true, HERO = true,
}

local function HasCoAAPI()
    return _G.C_CharacterAdvancement ~= nil
end

local function IsVanillaClass(unit)
    local _, classFile = UnitClass(unit)
    return classFile and VANILLA_CLASSES[classFile] or false
end

local assets = addon._dir
local TEX = {
    frame_metal   = assets .. 'UI\\uiframemetal2x',
    frame_metal_h = assets .. 'UI\\uiframemetalhorizontal2x',
    frame_metal_v = assets .. 'UI\\uiframemetalvertical2x',
    frame_bg      = assets .. 'UI\\ui-background-rock',
    close_btn     = assets .. 'UI\\redbutton2x',
}

local SOLID = "Interface\\ChatFrame\\ChatFrameBackground"

local BTN_UP        = "Interface\\Buttons\\UI-Panel-Button-Up"
local BTN_DOWN      = "Interface\\Buttons\\UI-Panel-Button-Down"
local BTN_HIGHLIGHT = "Interface\\Buttons\\UI-Panel-Button-Highlight"
local TAB_ACTIVE    = "Interface\\PaperDollInfoFrame\\UI-CharacterTab-Active"
local TAB_INACTIVE  = "Interface\\PaperDollInfoFrame\\UI-CharacterTab-Inactive"

local function AddInspectorBorder(frame)
    if frame._InspectorBorder then return end
    local ns = {}
    frame._InspectorBorder = ns

    ns.TopLeftCorner     = frame:CreateTexture(nil, 'ARTWORK')
    ns.TopRightCorner    = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomLeftCorner  = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomRightCorner = frame:CreateTexture(nil, 'ARTWORK')
    ns.TopEdge           = frame:CreateTexture(nil, 'ARTWORK')
    ns.BottomEdge        = frame:CreateTexture(nil, 'ARTWORK')
    ns.LeftEdge          = frame:CreateTexture(nil, 'ARTWORK')
    ns.RightEdge         = frame:CreateTexture(nil, 'ARTWORK')

    local bg = CreateFrame('Frame', nil, frame)
    bg:SetPoint('TOPLEFT', frame, 'TOPLEFT', 3, -18)
    bg:SetPoint('BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -3, 3)
    bg:SetFrameLevel(0)
    ns.Bg = bg

    -- Class-specific background atlas (Ascension: one per class)
    -- Must be on the bg frame so it draws above frame-level BACKGROUND textures
    ns.ClassBg = bg:CreateTexture(nil, 'BACKGROUND', nil, 1)
    ns.ClassBg:SetAllPoints(bg)
    ns.ClassBg:Hide()

    -- Spec passive background (wraps right-side talents, Ascension "ca-passive-bg" atlas)
    ns.SpecBg = frame:CreateTexture(nil, 'OVERLAY')
    ns.SpecBg:SetAtlas("ca-passive-bg")
    ns.SpecBg:Hide()

    local bgTex = bg:CreateTexture(nil, 'BACKGROUND')
    bgTex:SetTexture(TEX.frame_bg)
    bgTex:SetAllPoints(bg)
    -- bgTex:SetAlpha(0.85) -- background opacity
    ns.BgTex = bgTex

    local tlc = ns.TopLeftCorner
    tlc:SetTexture(TEX.frame_metal)
    tlc:SetTexCoord(0.00195312, 0.294922, 0.00195312, 0.294922)
    tlc:SetSize(75, 74)
    tlc:SetPoint('TOPLEFT', -12, 16)

    local trc = ns.TopRightCorner
    trc:SetTexture(TEX.frame_metal)
    trc:SetTexCoord(0.298828, 0.591797, 0.00195312, 0.294922)
    trc:SetSize(75, 74)
    trc:SetPoint('TOPRIGHT', 4, 16)

    local blc = ns.BottomLeftCorner
    blc:SetTexture(TEX.frame_metal)
    blc:SetTexCoord(0.298828, 0.423828, 0.298828, 0.423828)
    blc:SetSize(32, 32)
    blc:SetPoint('BOTTOMLEFT', -12, -3)

    local brc = ns.BottomRightCorner
    brc:SetTexture(TEX.frame_metal)
    brc:SetTexCoord(0.427734, 0.552734, 0.298828, 0.423828)
    brc:SetSize(32, 32)
    brc:SetPoint('BOTTOMRIGHT', 4, -3)

    local te = ns.TopEdge
    te:SetTexture(TEX.frame_metal_h)
    te:SetTexCoord(0, 1, 0.00390625, 0.589844)
    te:SetSize(32, 74)
    te:SetPoint('TOPLEFT', tlc, 'TOPRIGHT', 0, 0)
    te:SetPoint('TOPRIGHT', trc, 'TOPLEFT', 0, 0)

    local be = ns.BottomEdge
    be:SetTexture(TEX.frame_metal_h)
    be:SetTexCoord(0, 0.5, 0.597656, 0.847656)
    be:SetSize(16, 32)
    be:SetPoint('TOPLEFT', blc, 'TOPRIGHT', 0, 0)
    be:SetPoint('TOPRIGHT', brc, 'TOPLEFT', 0, 0)

    local le = ns.LeftEdge
    le:SetTexture(TEX.frame_metal_v)
    le:SetTexCoord(0.00195312, 0.294922, 0, 1)
    le:SetSize(75, 16)
    le:SetPoint('TOPLEFT', tlc, 'BOTTOMLEFT', 0, 0)
    le:SetPoint('BOTTOMLEFT', blc, 'TOPLEFT', 0, 0)

    local re = ns.RightEdge
    re:SetTexture(TEX.frame_metal_v)
    re:SetTexCoord(0.298828, 0.591797, 0, 1)
    re:SetSize(75, 16)
    re:SetPoint('TOPRIGHT', trc, 'BOTTOMRIGHT', 0, 0)
    re:SetPoint('BOTTOMRIGHT', brc, 'TOPRIGHT', 0, 0)
end

local NODE_SIZE = 32
local BASE_CELL = 44
local MIN_CELL = 22
local TITLE_H = 24
local SPEC_H = 24
local PAD = 12
local TAB_HEADER = 38
local TAB_COL_GAP = 26
local SECTION_GAP = 48

local NodeArtSet = {
    Square = {
        shadow   = "talents-node-square-shadow",
        normal   = "talents-node-square-yellow",
        disabled = "talents-node-square-gray",
        glow     = "talents-node-square-greenglow",
        mask     = "Interface\\TalentFrame\\TalentsMaskNodeChoiceFlyout.blp",
    },
    Circle = {
        shadow   = "talents-node-circle-shadow",
        normal   = "talents-node-circle-yellow",
        disabled = "talents-node-circle-gray",
        glow     = "talents-node-circle-greenglow",
        mask     = "Interface\\TalentFrame\\TalentsMaskNodeCircle.blp",
    },
    Choice = {
        shadow   = "talents-node-choice-shadow",
        normal   = "talents-node-choice-yellow",
        disabled = "talents-node-choice-gray",
        glow     = "talents-node-choice-greenglow",
        mask     = "Interface\\TalentFrame\\TalentsMaskNodeChoice.blp",
    },
}

local function SetPlateAtlas(texture, atlasName)
    if not texture then return end
    if texture.SetAtlas then
        pcall(texture.SetAtlas, texture, atlasName, false)
    end
end

local function GetNodeArtSet(node)
    local nt = node.nodeType or node.NodeType or ""
    if nt == "SpendCircle" then return NodeArtSet.Circle end
    if nt == "SpendHex" then return NodeArtSet.Choice end
    return NodeArtSet.Square
end

local NodeButton = {}

function NodeButton.Create(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetFrameLevel(10)
    b:SetWidth(NODE_SIZE)
    b:SetHeight(NODE_SIZE)

    b.plate = b:CreateTexture(nil, "BORDER")
    b.plate:SetAllPoints(b)

    b.icon = b:CreateTexture(nil, "BACKGROUND")
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    b.glow = b:CreateTexture(nil, "OVERLAY")
    b.glow:SetAllPoints(b)
    b.glow:Hide()

    b.rank = b:CreateFontString(nil, "OVERLAY")
    b.rank:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    b.rank:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 1, -1)

    b:SetHighlightTexture(SOLID)
    local hl = b:GetHighlightTexture()
    if hl then
        hl:SetBlendMode("ADD")
        hl:SetVertexColor(1, 1, 1, 0.12)
        hl:SetAllPoints(b)
    end

    return b
end

local function GetSpellId(node)
    local sp = node.spells
    if type(sp) ~= "table" then return nil end
    local function idOf(v)
        if type(v) == "number" then return v end
        if type(v) == "table" then return v.ID or v.SpellID or v.Spell end
        return nil
    end
    local r = (node.rank and node.rank > 0) and node.rank or 1
    local cand = idOf(sp[r]) or idOf(sp[1])
    if cand then return cand end
    for _, v in pairs(sp) do
        local id = idOf(v)
        if id then return id end
    end
    return nil
end

function NodeButton.Style(button, node)
    button.nodeData = node
    button.icon:SetTexture("Interface\\Icons\\" .. (node.icon or "INV_Misc_QuestionMark"))

    local artSet = GetNodeArtSet(node)
    local circle = artSet == NodeArtSet.Circle
    local inset = circle and 5 or 3
    button.icon:ClearAllPoints()
    button.icon:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
    button.icon:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)

    if node.known then
        SetPlateAtlas(button.plate, artSet.normal)
        button.glow:Hide()
        button.icon:SetDesaturated(false)
        button.icon:SetVertexColor(1, 1, 1)
        button.icon:SetAlpha(1)
        if button.icon.SetMask then
            pcall(button.icon.SetMask, button.icon, artSet.mask)
        end
    else
        SetPlateAtlas(button.plate, artSet.disabled)
        button.glow:Hide()
        button.icon:SetDesaturated(true)
        button.icon:SetVertexColor(0.8, 0.8, 0.8)
        button.icon:SetAlpha(1)
        if button.icon.SetMask then
            pcall(button.icon.SetMask, button.icon, artSet.mask)
        end
    end

    if node.known and node.rank and node.rank > 0 then
        if node.maxRank then
            button.rank:SetText(node.rank .. "/" .. node.maxRank)
        else
            button.rank:SetText(tostring(node.rank))
        end
        if node.maxRank and node.rank >= node.maxRank then
            button.rank:SetTextColor(1, 0.82, 0)
        else
            button.rank:SetTextColor(1, 1, 1)
        end
        button.rank:Show()
    else
        button.rank:Hide()
    end

    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sid = GetSpellId(node)
        local shown = false
        if sid then
            shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. sid)
        end
        if not shown then
            GameTooltip:SetText(node.name or "?")
        end
        if node.known and node.rank and node.rank > 0 then
            local r = node.maxRank and (node.rank .. "/" .. node.maxRank) or tostring(node.rank)
            GameTooltip:AddLine("Rank " .. r, 0.2, 0.85, 0.78)
        end
        if node.tab then GameTooltip:AddLine(node.tab, 0.6, 0.6, 0.6) end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local EdgeLines = {}

function EdgeLines.Draw(content, edges, centers, thickness, linePool, nodeSize)
    thickness = thickness or 2
    nodeSize = nodeSize or 28
    local used = 0
    local contentH = content:GetHeight()
    if contentH == 0 then contentH = 1 end

    for _, e in ipairs(edges) do
        local a, b = centers[e.from], centers[e.to]
        if a and b then
            local known = a.known and b.known
            used = used + 1
            local conn = linePool[used]
            if not conn then
                conn = CreateFrame("Frame", nil, content.linesLayer, "CALineConnectionTemplate")
                conn.Arrow:SetParent(content)
                conn.Arrow:SetFrameLevel(20)
                linePool[used] = conn
            end

            local sx, sy = a.x, a.y + contentH
            local ex, ey = b.x, b.y + contentH

            local sizeX = math.abs(sx - ex)
            local sizeY = math.abs(sy - ey)
            conn:SetSize(math.max(sizeX, 4), math.max(sizeY, 4))

            local left = math.min(sx, ex)
            local bottom = math.min(sy, ey)
            conn:SetPoint("BOTTOMLEFT", left, bottom)

            local rpx = sx - left
            local rpy = sy - bottom
            local rqx = ex - left
            local rqy = ey - bottom

            conn.Line1:SetStartPoint(Vector2D(rpx, rpy))
            conn.Line1:SetEndPoint(Vector2D(rqx, rqy))
            conn.Line1:Draw()

            conn.Line2:SetStartPoint(Vector2D(rpx, rpy))
            conn.Line2:SetEndPoint(Vector2D(rqx, rqy))
            conn.Line2:Draw()

            if known then
                conn.Line2:SetVertexColor(0.25, 0.85, 0.80, 0.85)
                conn.Arrow.Texture:SetTexture("Interface\\TalentFrame\\talents-arrow-head-yellow")
            else
                conn.Line2:SetVertexColor(0.30, 0.30, 0.36, 0.45)
                conn.Arrow.Texture:SetTexture("Interface\\TalentFrame\\talents-arrow-head-gray")
            end

            local dx, dy = ex - sx, ey - sy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 0 then
                local deg = math.deg(math.atan2(dy, dx))
                local radians = math.rad(deg - 90)
                local ux, uy = math.cos(math.atan2(dy, dx)), math.sin(math.atan2(dy, dx))
                local offset = nodeSize / 2 + 4
                conn.Arrow:SetPoint("CENTER", conn, "BOTTOMLEFT", rpx + ux * offset, rpy + uy * offset)
                conn.Arrow.Texture:SetRotation(radians)
            end

            conn:Show()
        end
    end

    for i = used + 1, #linePool do linePool[i]:Hide() end
end

local TreeModel = {}

function TreeModel.Build(rawTree, buildMap)
    buildMap = buildMap or {}
    local model = { tabs = {}, nodes = {}, edges = {} }
    local seenTab = {}

    for _, raw in ipairs(rawTree) do
        local id = raw.ID
        local learned = buildMap[id]
        model.nodes[id] = {
            id       = id,
            name     = raw.Name,
            icon     = raw.Icon,
            tab      = raw.Tab,
            x        = raw.PositionX,
            y        = raw.PositionY,
            sizeX    = raw.SizeX,
            sizeY    = raw.SizeY,
            nodeType = raw.NodeType,
            type     = raw.Type,
            color    = raw.Color,
            quality  = raw.Quality,
            known    = learned ~= nil,
            rank     = learned and learned.rank or 0,
            maxRank  = learned and learned.maxRank or nil,
            connected = raw.ConnectedNodes or {},
            required  = raw.RequiredIDs or {},
            spells    = raw.Spells,
        }
        if raw.Tab and not seenTab[raw.Tab] then
            seenTab[raw.Tab] = true
            table.insert(model.tabs, raw.Tab)
        end
    end

    for id, node in pairs(model.nodes) do
        for _, targetId in ipairs(node.connected) do
            if model.nodes[targetId] then
                table.insert(model.edges, { from = id, to = targetId })
            end
        end
    end

    return model
end

function TreeModel.Bounds(model)
    local overallMaxX = 0
    local tabs = {}
    for _, tabName in ipairs(model.tabs) do
        local minX, maxX, minY, maxY
        for _, node in pairs(model.nodes) do
            if node.tab == tabName then
                local x, y = node.x or 0, node.y or 0
                if not minX or x < minX then minX = x end
                if not maxX or x > maxX then maxX = x end
                if not minY or y < minY then minY = y end
                if not maxY or y > maxY then maxY = y end
            end
        end
        minX = minX or 0; maxX = maxX or 0; minY = minY or 0; maxY = maxY or 0
        if maxX > overallMaxX then overallMaxX = maxX end
        table.insert(tabs, { name = tabName, minX = minX, maxX = maxX, minY = minY, maxY = maxY })
    end
    return { maxX = overallMaxX, tabs = tabs }
end

function TreeModel.LayoutTabs(model, slot)
    local CLASS = "Class"
    local specs = {}
    local hasClass = false
    for _, t in ipairs(model.tabs) do
        if t == CLASS then hasClass = true else specs[#specs + 1] = t end
    end

    local learnedSpec = {}
    for _, node in pairs(model.nodes) do
        if node.known and node.tab ~= CLASS then learnedSpec[node.tab] = true end
    end

    local ordered = {}
    if hasClass then table.insert(ordered, CLASS) end

    local added = false
    for _, t in ipairs(specs) do
        if learnedSpec[t] then
            table.insert(ordered, t)
            added = true
        end
    end

    if not added and #specs > 0 then
        local idx = slot or 1
        if idx < 1 or idx > #specs then idx = 1 end
        table.insert(ordered, specs[idx])
    end

    if #ordered == 0 then
        for _, t in ipairs(model.tabs) do table.insert(ordered, t) end
    end
    return ordered
end

function TreeModel.FitScale(cols, baseCell, maxWidth, minCell)
    minCell = minCell or 20
    if not cols or cols <= 0 then return baseCell end
    local cell = math.floor(maxWidth / cols)
    if cell > baseCell then cell = baseCell end
    if cell < minCell then cell = minCell end
    return cell
end

local CAReader = {}

local function CA()  return _G.C_CharacterAdvancement end
local function CAU() return _G.CharacterAdvancementUtil end

function CAReader.GetClassName(unit)
    local _, classFile = UnitClass(unit)
    local u = CAU()
    if not (u and type(u.GetClassDBCByFile) == "function") then return nil end
    local ok, name = pcall(u.GetClassDBCByFile, classFile)
    if ok then return name end
    return nil
end

function CAReader.GetClassTree(className, slot)
    local api = CA()
    if not (api and className) then return {} end

    local tabs, seenTab = {}, {}
    if type(api.GetTalentsByClass) == "function" then
        local ok, entries = pcall(api.GetTalentsByClass, className, slot, false)
        if ok and type(entries) == "table" then
            for _, e in ipairs(entries) do
                if e.Tab and not seenTab[e.Tab] then
                    seenTab[e.Tab] = true
                    tabs[#tabs + 1] = e.Tab
                end
            end
        end
    end

    local seen, out = {}, {}
    local function absorb(entries)
        if type(entries) ~= "table" then return end
        for _, e in ipairs(entries) do
            if e.ID and not seen[e.ID] then
                seen[e.ID] = true
                out[#out + 1] = e
            end
        end
    end

    if type(api.GetEntriesByClass) == "function" and #tabs > 0 then
        for _, tab in ipairs(tabs) do
            local ok, entries = pcall(api.GetEntriesByClass, className, tab, false)
            if ok then absorb(entries) end
        end
    end

    if #out == 0 and type(api.GetTalentsByClass) == "function" then
        for _, withMasteries in ipairs({ false, true }) do
            local ok, entries = pcall(api.GetTalentsByClass, className, slot, withMasteries)
            if ok then absorb(entries) end
        end
    end

    return out
end

function CAReader.GetUnitBuild(unit, slot)
    local api = CA()
    local out = {}
    if not (api and type(api.GetInspectedBuild) == "function") then return out end
    local ok, entries = pcall(api.GetInspectedBuild, unit, slot)
    if not (ok and type(entries) == "table") then return out end
    for _, e in ipairs(entries) do
        if e.EntryId then
            local rank, maxRank = e.Rank, nil
            if type(api.UnitTalentRankByID) == "function" then
                local rok, r, m = pcall(api.UnitTalentRankByID, unit, e.EntryId, slot)
                if rok then
                    if type(r) == "number" then rank = r end
                    maxRank = m
                end
            end
            out[e.EntryId] = { rank = rank, maxRank = maxRank }
        end
    end
    return out
end

function CAReader.GetPlayerBuild(slot, rawTree)
    local viaInspect = CAReader.GetUnitBuild("player", slot)
    local n = 0
    for _ in pairs(viaInspect) do n = n + 1 end
    if n > 0 then return viaInspect end

    local api = CA()
    local out = {}
    if api and type(api.UnitTalentRankByID) == "function" and type(rawTree) == "table" then
        for _, node in ipairs(rawTree) do
            local id = node.ID
            if id then
                local ok, rank, maxRank = pcall(api.UnitTalentRankByID, "player", id, slot)
                if ok and type(rank) == "number" and rank > 0 then
                    out[id] = { rank = rank, maxRank = maxRank }
                end
            end
        end
    end
    return out
end

function CAReader.GetInspectInfo(unit)
    local api = CA()
    if not (api and type(api.GetInspectInfo) == "function") then return nil, nil end
    local ok, active, unlocked = pcall(api.GetInspectInfo, unit)
    if ok then return active, unlocked end
    return nil, nil
end

local TreePanel = {}
local TP = TreePanel

local frame, scroll, content

function TP.Get()
    if frame then return frame end
    frame = CreateFrame("Frame", "DragonUIInspectorPanel", UIParent)
    frame:SetWidth(360)
    frame:SetHeight(700)
    AddInspectorBorder(frame)
    frame:SetFrameStrata("DIALOG")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -6)
    title:SetText("Talent Tree")
    frame.title = title

    -- Close button (same texture/style as combuctor)
    local closeBtn = CreateFrame("Button", "$parentCloseButton", frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    closeBtn:SetFrameLevel(frame:GetFrameLevel() + 20)
    closeBtn:SetNormalTexture(TEX.close_btn)
    closeBtn:GetNormalTexture():SetTexCoord(0.152344, 0.292969, 0.0078125, 0.304688)
    closeBtn:SetPushedTexture(TEX.close_btn)
    closeBtn:GetPushedTexture():SetTexCoord(0.152344, 0.292969, 0.632812, 0.929688)
    closeBtn:SetHighlightTexture(TEX.close_btn)
    closeBtn:GetHighlightTexture():SetTexCoord(0.449219, 0.589844, 0.0078125, 0.304688)
    closeBtn:SetScript("OnClick", function()
        -- Blizzard API: stops inspecting the current unit
        ClearInspectPlayer()
        -- Fallback: hide any known inspect frame
        for _, name in ipairs({ "AscensionInspectFrame", "InspectFrame", "InspectPaperDollFrame" }) do
            local f = _G[name]
            if f and f:IsShown() then
                HideUIPanel(f)
            end
        end
    end)

    local classIconFrame = CreateFrame("Frame", nil, frame)
    classIconFrame:SetSize(94, 94)
    classIconFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -25, 35)
    local iconLevel = frame:GetFrameLevel()
    classIconFrame:SetFrameLevel(iconLevel + 10)
    local corner = classIconFrame:CreateTexture(nil, "OVERLAY")
    corner:SetTexture("Interface\\AddOns\\DragonUI\\Textures\\Bags\\bagborder2")
    corner:SetAllPoints(classIconFrame)
    frame.classIconFrame = classIconFrame

    local classIcon = classIconFrame:CreateTexture(nil, "ARTWORK")
    classIcon:SetSize(74, 74)
    classIcon:SetPoint("CENTER", classIconFrame, "CENTER", 0, 0)
    classIcon:Hide()
    frame.classIcon = classIcon

    local cmp = CreateFrame("Button", nil, frame)
    cmp:SetWidth(130); cmp:SetHeight(35)
    cmp:SetPoint("BOTTOM", frame, "BOTTOM", 0, PAD + 2)
    cmp:SetNormalTexture(BTN_UP)
    cmp:SetPushedTexture(BTN_DOWN)
    cmp:SetHighlightTexture(BTN_HIGHLIGHT)
    local cmpNT = cmp:GetNormalTexture()
    if cmpNT then cmpNT:SetVertexColor(1, 1, 1) end
    cmp.txt = cmp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cmp.txt:SetPoint("CENTER", cmp, "CENTER", -19, 5)
    cmp.txt:SetText("Compare")
    cmp:Hide()
    frame.compareBtn = cmp

    frame:SetScale(0.83)
    frame.specRow = CreateFrame("Frame", nil, frame)
    frame.specRow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    frame.specRow:SetHeight(SPEC_H)
    frame.specRow:SetWidth(240)
    frame.specButtons = {}

    scroll = CreateFrame("ScrollFrame", "DragonUIInspectorScroll", frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -TITLE_H)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, -(SPEC_H + PAD))

    content = CreateFrame("Frame", "DragonUIInspectorContent", scroll)
    content:SetWidth(1)
    content:SetHeight(1)
    scroll:SetScrollChild(content)

    frame.content = content
    frame.scroll = scroll
    frame.buttons = {}
    frame.buttonsById = {}
    frame.linePool = {}

    local linesLayer = CreateFrame("Frame", nil, content)
    linesLayer:SetFrameLevel(0)
    linesLayer:SetAllPoints(content)
    content.linesLayer = linesLayer

    frame:Hide()
    return frame
end

function TP.AttachTo(inspectFrame, showCompare)
    local f = TP.Get()
    f:ClearAllPoints()
    f:SetPoint("CENTER", inspectFrame, "CENTER", 95, 15)
    if showCompare then
        local cf = CP.Get()
        cf:ClearAllPoints()
        cf:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, 0)
        cf:Show()
    else
        CP.Hide()
    end
end

function TP.Show() TP.Get():Show() end
function TP.Hide()
    if frame then
        if frame.specDropdown then
            frame.specDropdown:Hide()
            frame.specDropdown = nil
        end
        frame:Hide()
    end
    if ComparePanel then ComparePanel.Hide() end
end

function TP.SetCompare(isOn, onClick)
    local f = TP.Get()
    local b = f.compareBtn
    if isOn then
        b:SetNormalTexture(BTN_DOWN)
    else
        b:SetNormalTexture(BTN_UP)
    end
    b:SetScript("OnClick", function() if onClick then onClick() end end)
    b:Show()
end

function TP.SetSpecs(specs, current, onClick)
    local f = TP.Get()
    for i = 1, #f.specButtons do f.specButtons[i]:Hide() end

    if f.specDropdown then
        CloseDropDownMenus()
        f.specDropdown:Hide()
        f.specDropdown = nil
    end

    if not specs or #specs == 0 then return end

    local dd = CreateFrame("Frame", "DragonUIInspectorSpecDropDown", f.specRow, "UIDropDownMenuTemplate")
    dd:SetPoint("RIGHT", f.specRow, "RIGHT", 16, 0)
    f.specDropdown = dd

    local label = current and "Spec " .. tostring(current) or "Spec"
    UIDropDownMenu_SetText(dd, label)

    local function buildMenu(frame, level)
        level = level or 1
        for _, slot in ipairs(specs) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = "Spec " .. tostring(slot)
            info.value = slot
            info.checked = (slot == current)
            info.func = function(self, arg1, arg2, checked)
                UIDropDownMenu_SetText(dd, self:GetText() or info.text)
                CloseDropDownMenus()
                if onClick then onClick(slot) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dd, buildMenu)
    UIDropDownMenu_SetWidth(dd, 120)
end

local function AcquireButton(f, i)
    local b = f.buttons[i]
    if not b then
        b = NodeButton.Create(f.content)
        f.buttons[i] = b
    end
    b:Show()
    return b
end

local function AcquireHeader(f, i)
    f.headers = f.headers or {}
    local h = f.headers[i]
    if not h then
        h = f.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.headers[i] = h
    end
    h:Show()
    return h
end

local function ShownCols(model, order)
    local bounds = TreeModel.Bounds(model)
    local byName = {}
    for _, ti in ipairs(bounds.tabs) do byName[ti.name] = ti end
    local cols, tabs = 0, 0
    for _, name in ipairs(order) do
        local ti = byName[name]
        if ti then cols = cols + (ti.maxX - ti.minX + 1); tabs = tabs + 1 end
    end
    return cols, tabs
end

local function SpecDisplayName(classFile, tabName)
    if tabName == "Class" then return nil end
    if not C_ClassInfo or not C_ClassInfo.GetAllSpecs then return tabName end
    local ok, specs = pcall(C_ClassInfo.GetAllSpecs, classFile)
    if not (ok and type(specs) == "table") then return tabName end
    local upperTab = tabName:upper()
    for _, s in ipairs(specs) do
        if s == upperTab then
            local ok2, info = pcall(C_ClassInfo.GetSpecInfo, classFile, s)
            if ok2 and info and info.Name then return info.Name end
        end
    end
    return tabName
end

local function RenderColumns(f, model, order, keyPrefix, headerPrefix, startX, cell, iconSize, btnIndex, headerIndex, rects, placed, className, classFile)
    local bounds = TreeModel.Bounds(model)
    local byName = {}
    for _, ti in ipairs(bounds.tabs) do byName[ti.name] = ti end

    local xOffset = startX
    local maxColH = 0
    local CLASS = "Class"
    for _, tabName in ipairs(order) do
        local tabInfo = byName[tabName]
        if tabInfo then
            local colW = (tabInfo.maxX - tabInfo.minX + 1) * cell

            headerIndex = headerIndex + 1
            local header = AcquireHeader(f, headerIndex)
            header:ClearAllPoints()
            header:SetJustifyH("CENTER")
            header:SetPoint("TOP", f.content, "TOPLEFT", xOffset + colW / 2, 0)
            local label = (tabName == CLASS and className) or SpecDisplayName(classFile, tabName)
            header:SetText(headerPrefix .. label)

            for id, node in pairs(model.nodes) do
                if node.tab == tabName then
                    btnIndex = btnIndex + 1
                    local b = AcquireButton(f, btnIndex)
                    b:SetWidth(iconSize)
                    b:SetHeight(iconSize)
                    NodeButton.Style(b, node)
                    b:ClearAllPoints()
                    local px = xOffset + ((node.x or 0) - tabInfo.minX) * cell
                    local py = -TAB_HEADER - (((node.y or 0) - tabInfo.minY) * cell)
                    b:SetPoint("TOPLEFT", f.content, "TOPLEFT", px, py)
                    f.buttonsById[keyPrefix .. id] = b
                    placed[keyPrefix .. id] = { px = px, py = py, known = node.known }
                end
            end

            local colH = TAB_HEADER + (tabInfo.maxY - tabInfo.minY + 1) * cell
            if colH > maxColH then maxColH = colH end
            rects[#rects + 1] = { x = xOffset, w = colW }
            xOffset = xOffset + colW + TAB_COL_GAP
        end
    end
    return xOffset, maxColH, btnIndex, headerIndex
end

local function DrawDividers(f, rects, height)
    f.dividers = f.dividers or {}
    for i = 1, #f.dividers do f.dividers[i]:Hide() end
    for i = 1, #rects - 1 do
        local rightEdge = rects[i].x + rects[i].w
        local nextStart = rects[i + 1].x
        local mid = (rightEdge + nextStart) / 2
        local d = f.dividers[i]
        if not d then
            d = f.content:CreateTexture(nil, "BACKGROUND")
            f.dividers[i] = d
        end
        d:SetTexture(0.28, 0.28, 0.34, 0.7)
        d:ClearAllPoints()
        d:SetPoint("TOPLEFT", f.content, "TOPLEFT", mid - 1, 0)
        d:SetWidth(2)
        d:SetHeight(height)
        d:Show()
    end
end

function TP.Render(model, slot, className, classFile)
    local f = TP.Get()
    for i = 1, #f.buttons do f.buttons[i]:Hide() end
    if f.headers then for i = 1, #f.headers do f.headers[i]:Hide() end end
    f.buttonsById = {}

    local sw = (UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1024
    local sh = (UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 768

    local order = TreeModel.LayoutTabs(model, slot)
    local cols, tabs = ShownCols(model, order)
    local nGaps = math.max(0, tabs - 1)
    local maxContentW = math.floor(sw * 0.55) - nGaps * TAB_COL_GAP
    local cell = TreeModel.FitScale(cols, BASE_CELL, maxContentW, MIN_CELL)
    local iconSize = math.max(14, cell - 8)

    local rects, placed = {}, {}
    local x, maxColH = RenderColumns(f, model, order, "t", "", 0, cell, iconSize, 0, 0, rects, placed, className, classFile)

    local contentW = math.max(1, x - TAB_COL_GAP)
    local contentH = math.max(1, maxColH + 10)
    f.content:SetWidth(contentW)
    f.content:SetHeight(contentH)

    local centers = {}
    for key, p in pairs(placed) do
        centers[key] = { x = p.px + iconSize / 2, y = p.py - iconSize / 2, known = p.known }
    end
    local edges = {}
    for _, e in ipairs(model.edges) do edges[#edges + 1] = { from = "t" .. e.from, to = "t" .. e.to } end
    EdgeLines.Draw(f.content, edges, centers, 2, f.linePool, iconSize)

    -- Position spec passive background (ca-passive-bg) on right edge
    local border = f._InspectorBorder
    if border and border.SpecBg then
        if #rects >= 2 then
            local rightCol = rects[#rects]
            local rightEdge = PAD + rightCol.x + rightCol.w
            border.SpecBg:ClearAllPoints()
            border.SpecBg:SetPoint("RIGHT", f, "LEFT", rightEdge + 10, 15)
            border.SpecBg:SetPoint("TOP", f, "TOP", 0, -TITLE_H + 5)
            border.SpecBg:SetSize(74, math.min(maxColH + 10, 480))
            border.SpecBg:Show()
        else
            border.SpecBg:Hide()
        end
    end

    local headerTotal = TITLE_H + SPEC_H
    local maxPanelInner = math.floor(sh * 0.9) - headerTotal - PAD
    local innerH = math.min(contentH, maxPanelInner)
    f:SetWidth(contentW + 2 * PAD)
    f:SetHeight(innerH + headerTotal + PAD)
end

--
-- ComparePanel — second panel for the player's own build
--
CP = {}
ComparePanel = CP

function CP.Get()
    if cpFrame then return cpFrame end
    cpFrame = CreateFrame("Frame", "DragonUIInspectorCompare", UIParent)
    cpFrame:SetWidth(360)
    cpFrame:SetHeight(400)
    AddInspectorBorder(cpFrame)
    cpFrame:SetFrameStrata("DIALOG")
    cpFrame:SetScale(0.83)

    cpScroll = CreateFrame("ScrollFrame", nil, cpFrame)
    cpScroll:SetPoint("TOPLEFT", cpFrame, "TOPLEFT", PAD, -PAD)
    cpScroll:SetPoint("BOTTOMRIGHT", cpFrame, "BOTTOMRIGHT", -PAD, PAD)

    cpContent = CreateFrame("Frame", nil, cpScroll)
    cpContent:SetWidth(1)
    cpContent:SetHeight(1)
    cpScroll:SetScrollChild(cpContent)
    cpFrame.content = cpContent
    cpFrame.linePool = {}
    cpFrame.buttons = {}
    cpFrame.buttonsById = {}

    local cpLinesLayer = CreateFrame("Frame", nil, cpContent)
    cpLinesLayer:SetFrameLevel(0)
    cpLinesLayer:SetAllPoints(cpContent)
    cpContent.linesLayer = cpLinesLayer

    cpFrame:Hide()
    return cpFrame
end

function CP.Show()
    CP.Get():Show()
end

function CP.Hide()
    if cpFrame then cpFrame:Hide() end
end

function CP.Render(model, slot, className, classFile)
    local f = CP.Get()
    for i = 1, #f.buttons do f.buttons[i]:Hide() end
    if f.headers then for i = 1, #f.headers do f.headers[i]:Hide() end end

    local order = TreeModel.LayoutTabs(model, slot)
    local cols, tabs = ShownCols(model, order)
    local nGaps = math.max(0, tabs - 1)
    local maxContentW = 280 - nGaps * TAB_COL_GAP
    local cell = TreeModel.FitScale(cols, BASE_CELL, maxContentW, MIN_CELL)
    local iconSize = math.max(14, cell - 8)

    local rects, placed = {}, {}
    local x, maxColH = RenderColumns(f, model, order, "m", "YOU · ", 0, cell, iconSize, 0, 0, rects, placed, className, classFile)
    local contentW = math.max(1, x - TAB_COL_GAP)
    local contentH = math.max(1, maxColH + 10)
    cpContent:SetWidth(contentW)
    cpContent:SetHeight(contentH)

    local centers = {}
    for key, p in pairs(placed) do
        centers[key] = { x = p.px + iconSize / 2, y = p.py - iconSize / 2, known = p.known }
    end
    local edges = {}
    for _, e in ipairs(model.edges) do edges[#edges + 1] = { from = "m" .. e.from, to = "m" .. e.to } end
    EdgeLines.Draw(f.content, edges, centers, 2, f.linePool, iconSize)

    local maxPanelInner = 600
    local innerH = math.min(contentH, maxPanelInner)
    cpFrame:SetWidth(contentW + 2 * PAD)
    cpFrame:SetHeight(innerH + 2 * PAD)
end

local current = { unit = nil, className = nil, tree = nil, slot = nil }

-- Ascension resolves the class backdrop in its talent tree's SetSpecID (CoATreeViewMixin), by
-- which time the class DBC is loaded. The inspector fires off the inspect result instead, so the
-- first inspect of a class can run before that data landed: GetBackgroundAtlas returns nil and the
-- backdrop stays hidden until some later inspect happens to re-render. Re-resolve on a short timer
-- (the tree's own "Loading talents..." retry, mirrored) so the backdrop appears as soon as the
-- data does instead of waiting for the player to inspect around.
local CLASS_BG_RETRY_INTERVAL, CLASS_BG_RETRY_MAX = 0.5, 10

local function SetClassBackground(frame, classFile, slot)
    if not classFile then return end
    local util = CAU()
    if not util or type(util.GetBackgroundAtlas) ~= "function" then
        LogMsg("GetBackgroundAtlas not available")
        return
    end

    local border = frame._InspectorBorder
    if not border or not border.ClassBg then return end

    -- A new inspect replaces any pending re-resolve for the same panel.
    local pending = frame._duiClassBgRetry
    if pending then
        pending:SetScript("OnUpdate", nil)
        frame._duiClassBgRetry = nil
    end

    local function resolve()
        -- Resolve spec name. Ascension slots (1,2,3) are NOT Blizzard spec IDs (71,72,73).
        -- Try GetAllSpecs indexed by slot position as a heuristic.
        local specFile = nil
        if slot and C_ClassInfo and C_ClassInfo.GetAllSpecs then
            local ok, specs = pcall(C_ClassInfo.GetAllSpecs, classFile)
            if ok and type(specs) == "table" and #specs >= slot then
                specFile = specs[slot]
            end
        end

        -- Try with spec first, then class-only.
        local atlas = nil
        if specFile then
            local ok, a = pcall(util.GetBackgroundAtlas, classFile, specFile)
            if ok and a and type(a) == "string" and a ~= "" then atlas = a end
        end
        if not atlas then
            local ok, a = pcall(util.GetBackgroundAtlas, classFile, nil)
            if ok and a and type(a) == "string" and a ~= "" then atlas = a end
        end

        if not atlas then return false end
        -- SetAtlas errors until the client has the atlas data, so a failed apply counts as
        -- "not ready yet" and keeps the retry running.
        local ok = pcall(border.ClassBg.SetAtlas, border.ClassBg, atlas)
        if not ok then return false end
        border.ClassBg:Show()
        return true
    end

    if resolve() then return end

    local retries = 0
    local retry = CreateFrame("Frame")
    frame._duiClassBgRetry = retry
    local waited = 0
    retry:SetScript("OnUpdate", function(self, elapsed)
        waited = waited + elapsed
        if waited < CLASS_BG_RETRY_INTERVAL then return end
        waited = 0
        retries = retries + 1
        if resolve() or retries >= CLASS_BG_RETRY_MAX then
            self:SetScript("OnUpdate", nil)
            if frame._duiClassBgRetry == self then frame._duiClassBgRetry = nil end
        end
    end)
end

local function GetInspectFrame()
    local names = { "AscensionInspectFrame", "InspectFrame", "InspectPaperDollFrame" }
    for _, n in ipairs(names) do
        local f = _G[n]
        if f and f.IsVisible and f:IsVisible() then return f end
    end
    return nil
end

-- The unit token the Ascension inspect frame actually queried. The frame tracks
-- a token ("target", "party1", ...) not a GUID, so in combat the referent can
-- drift (e.g. "target" now points to the mob being fought). Always use this
-- token for the advancement queries instead of a hardcoded "target".
local function GetInspectedUnit()
    local f = _G.AscensionInspectFrame
    if f and f.GetUnit then
        local u = f:GetUnit()
        if u and u ~= "" then return u end
    end
    return "target"
end

local function RenderFor(unit, slot)
    if not IsModuleEnabled() then return end
    if IsVanillaClass(unit) then TP.Hide(); return end
    if not GetInspectFrame() then TP.Hide(); return end
    local className = CAReader.GetClassName(unit)
    if not className then return end
    current.unit = unit
    current.className = className
    current.slot = slot
    current.tree = CAReader.GetClassTree(className, slot)
    if #current.tree == 0 then
        current.retries = (current.retries or 0) + 1
        TP.Get().title:SetText("Loading talents...")
        TP.Show()
        if current.retries <= 5 then
            local u, s = unit, slot
            local t = CreateFrame("Frame")
            local waited = 0
            t:SetScript("OnUpdate", function(self, e)
                waited = waited + e
                if waited >= 0.5 then
                    self:SetScript("OnUpdate", nil)
                    RenderFor(u, s)
                end
            end)
        else
            TP.Get().title:SetText("No talent data")
        end
        return
    end
    current.retries = 0
    local buildMap = CAReader.GetUnitBuild(unit, slot)
    local model = TreeModel.Build(current.tree, buildMap)
    local inspectFrame = GetInspectFrame()
    if inspectFrame then TP.AttachTo(inspectFrame, current.compare) end
    local f = TP.Get()
    f.title:SetText(UnitName(unit))

    local _, classFile = UnitClass(unit)
    SetClassBackground(f, classFile, slot)

    local CLASS_ICON_ROUND = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES-ROUND"
    local roundCoords = CLASS_ICON_TCOORDS_ROUND and CLASS_ICON_TCOORDS_ROUND[classFile]
    if roundCoords then
        f.classIcon:SetTexture(CLASS_ICON_ROUND)
        f.classIcon:SetTexCoord(roundCoords[1], roundCoords[2], roundCoords[3], roundCoords[4])
        f.classIcon:Show()
    elseif classFile and CLASS_ICON_TCOLS and CLASS_ICON_TCOLS[classFile] then
        f.classIcon:SetTexture("Interface\\WorldStateFrame\\Icons-Classes")
        f.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOLS[classFile]))
        f.classIcon:Show()
    else
        local ca = CA()
        local found
        if ca then
            for _, m in ipairs({ "GetClassIcon", "GetClassTexture" }) do
                if type(ca[m]) == "function" then
                    local ok, v = pcall(ca[m], classFile)
                    if ok and v and type(v) == "string" then
                        f.classIcon:SetTexture(v)
                        found = true
                        break
                    end
                end
            end
        end
        if found then
            f.classIcon:Show()
        else
            f.classIcon:SetTexture(SOLID)
            f.classIcon:SetVertexColor(1, 1, 1, 0.3)
            f.classIcon:Show()
        end
    end

    local _, unlocked = CAReader.GetInspectInfo(unit)
    local specs = {}
    if type(unlocked) == "table" then
        for _, s in ipairs(unlocked) do specs[#specs + 1] = s end
    elseif type(unlocked) == "number" then
        for s = 1, unlocked do specs[#specs + 1] = s end
    end
    if #specs == 0 then specs = { slot } end
    TP.SetSpecs(specs, slot, function(s) RenderFor(current.unit, s) end)

    TP.SetCompare(current.compare, function()
        current.compare = not current.compare
        RenderFor(current.unit, current.slot)
    end)

    if current.compare then
        local myClass = CAReader.GetClassName("player")
        local mySlot = (CAReader.GetInspectInfo("player")) or 1
        if myClass then
            local myTree = CAReader.GetClassTree(myClass, mySlot)
            if #myTree > 0 then
                local myBuild = CAReader.GetPlayerBuild(mySlot, myTree)
                local myModel = TreeModel.Build(myTree, myBuild)
                local _, myClassFile = UnitClass("player")
                SetClassBackground(CP.Get(), myClassFile, mySlot)
                CP.Render(myModel, mySlot, myClass, myClassFile)
            end
        end
    else
        CP.Hide()
    end

    TP.Render(model, slot, current.className, classFile)
    TP.Show()
end

local eventFrame
local buildTabWatcher

-- The Ascension inspect frame resets to the first tab (Character) every time it
-- re-inspects, which happens on every PLAYER_TARGET_CHANGED while the frame is
-- open (very common in combat). Track which tab the user actually clicked so we
-- can restore it after that auto-reset instead of letting the build panel hide.
local userWantsBuild = false
local inspectUIHooked = false

local function HookInspectUI()
    local f = _G.AscensionInspectFrame
    if not f or inspectUIHooked then return false end
    if not f.Tabs or not f.GetTabForPanel then return false end

    local function hookTabButton(panelName, wantsBuild)
        local ok, tabBtn = pcall(f.GetTabForPanel, f, panelName)
        if ok and tabBtn and tabBtn.HookScript then
            tabBtn:HookScript("OnClick", function()
                userWantsBuild = wantsBuild
            end)
        end
    end

    hookTabButton("InspectBuildPanel", true)
    hookTabButton("InspectPaperDollPanel", false)
    hookTabButton("InspectPvPPanel", false)

    -- A new inspect session starts once the frame is closed again.
    if f.HookScript then
        f:HookScript("OnHide", function()
            userWantsBuild = false
        end)
    end

    inspectUIHooked = true
    return true
end

function addon.ApplyInspectorSystem()
    if InspectorModule.applied then return end
    if not HasCoAAPI() then return end
    if IsVanillaClass("player") then return end
    if not EnsureConfig() then return end

    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "INSPECT_CHARACTER_ADVANCEMENT_RESULT" then
            local unit = GetInspectedUnit()
            local active = CAReader.GetInspectInfo(unit) or 1
            RenderFor(unit, active)
        elseif event == "PLAYER_TARGET_CHANGED" then
            if not IsModuleEnabled() then return end
            current.unit = nil; current.className = nil; current.tree = nil
            current.slot = nil; current.retries = 0
            local f = GetInspectFrame()
            if not f then TP.Hide(); return end
            local unit = GetInspectedUnit()
            if UnitExists(unit) and UnitIsPlayer(unit) then
                local api = _G.C_CharacterAdvancement
                if api and type(api.InspectUnit) == "function" then
                    SafeCall(api.InspectUnit, unit)
                end
                local active = CAReader.GetInspectInfo(unit) or 1
                RenderFor(unit, active)
            else
                TP.Hide()
            end
        elseif event == "PLAYER_REGEN_ENABLED" then
            -- The advancement query is refused while in combat (no
            -- INSPECT_CHARACTER_ADVANCEMENT_RESULT arrives). Once combat ends,
            -- re-request the build data so the rendered tree gains the learned
            -- nodes; the result event re-renders when it arrives.
            local f = GetInspectFrame()
            if f and current.unit then
                local api = _G.C_CharacterAdvancement
                if api and type(api.InspectUnit) == "function" then
                    SafeCall(api.InspectUnit, current.unit)
                end
            end
        end
    end)
    eventFrame:RegisterEvent("INSPECT_CHARACTER_ADVANCEMENT_RESULT")
    eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

    local accum = 0
    local lastRenderAttempt = 0
    buildTabWatcher = CreateFrame("Frame")
    buildTabWatcher:SetScript("OnUpdate", function(_, elapsed)
        if not IsModuleEnabled() then return end
        accum = accum + elapsed
        if accum < 0.2 then return end
        accum = 0
        local f = GetInspectFrame()
        if not f then TP.Hide(); return end

        local inspectFrame = _G.AscensionInspectFrame
        HookInspectUI()
        local buildTabID = inspectFrame and inspectFrame.Tabs and inspectFrame.Tabs.Build
        local currentTabID = inspectFrame and inspectFrame.GetCurrentTabID and inspectFrame:GetCurrentTabID()

        if buildTabID and currentTabID then
            if currentTabID == buildTabID then
                if current.unit then
                    TP.Show()
                    if current.compare then CP.Show() end
                else
                    -- Build tab is active but no inspect data arrived yet: the
                    -- advancement query is ignored while in combat, so no
                    -- INSPECT_CHARACTER_ADVANCEMENT_RESULT fires. Request the
                    -- data and render the static tree anyway; the learned nodes
                    -- fill in once the result arrives (see PLAYER_REGEN_ENABLED).
                    local now = GetTime()
                    if now - lastRenderAttempt >= 1 then
                        lastRenderAttempt = now
                        local unit = GetInspectedUnit()
                        local api = _G.C_CharacterAdvancement
                        if api and type(api.InspectUnit) == "function" then
                            SafeCall(api.InspectUnit, unit)
                        end
                        local active = CAReader.GetInspectInfo(unit) or 1
                        SafeCall(RenderFor, unit, active)
                    end
                    -- RenderFor shows/hides the panel itself; do not force-show.
                end
            elseif userWantsBuild then
                -- The inspect frame auto-reset the tab after a re-inspect
                -- (target change in combat). Restore the tab the user had
                -- selected so the inspector stays on screen.
                if pcall(inspectFrame.SelectTabID, inspectFrame, buildTabID) then
                    if current.unit then
                        TP.Show()
                        if current.compare then CP.Show() end
                    else
                        TP.Hide()
                    end
                else
                    TP.Hide()
                end
            else
                TP.Hide()
            end
        else
            -- Fallback: drive visibility off the build panel directly.
            local buildPanel = _G.InspectBuildPanelSpecs
            if current.unit and buildPanel and buildPanel:IsVisible() then
                TP.Show()
                if current.compare then CP.Show() end
            else
                TP.Hide()
            end
        end
    end)

    InspectorModule.applied = true
end

function addon.RestoreInspectorSystem()
    if not InspectorModule.applied then return end

    userWantsBuild = false
    TP.Hide()

    if eventFrame then
        eventFrame:SetScript("OnEvent", nil)
        eventFrame:UnregisterAllEvents()
        eventFrame = nil
    end

    if buildTabWatcher then
        buildTabWatcher:SetScript("OnUpdate", nil)
        buildTabWatcher = nil
    end

    InspectorModule.applied = false
end

function addon.RefreshInspectorSystem()
    if not EnsureConfig() then return end
    if not IsModuleEnabled() then
        addon.RestoreInspectorSystem()
    else
        addon.ApplyInspectorSystem()
    end
end

local DebugTools = {}

function DebugTools.DumpTarget()
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no CoA class on target (inspect a player first)."); return end
    local active = CAReader.GetInspectInfo(u) or 1
    local tree = CAReader.GetClassTree(cn, active)
    if #tree == 0 then LogMsg("debug: empty tree (data not loaded yet?)."); return end

    local byId, total, order = {}, {}, {}
    for _, n in ipairs(tree) do
        byId[n.ID] = n.Tab
        if total[n.Tab] == nil then total[n.Tab] = 0; order[#order + 1] = n.Tab end
        total[n.Tab] = total[n.Tab] + 1
    end

    local build = CAReader.GetUnitBuild(u, active)
    local learned, totalLearned = {}, 0
    for id in pairs(build) do
        local tb = byId[id]
        if tb then learned[tb] = (learned[tb] or 0) + 1 end
        totalLearned = totalLearned + 1
    end

    LogMsg("class=" .. tostring(cn) .. " slot=" .. tostring(active)
        .. " nodes=" .. #tree .. " learned=" .. totalLearned)
    for _, tb in ipairs(order) do
        LogMsg("  TAB " .. tb .. " total=" .. total[tb] .. " learned=" .. (learned[tb] or 0))
    end
end

function DebugTools.DumpClass()
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no CoA class on target."); return end
    local active = CAReader.GetInspectInfo(u) or 1
    local tree = CAReader.GetClassTree(cn, active)
    local build = CAReader.GetUnitBuild(u, active)
    local n = 0
    for _, node in ipairs(tree) do
        if node.Tab == "Class" then
            n = n + 1
            local mark = build[node.ID] and "*" or "-"
            LogMsg(mark .. " " .. node.ID .. " " .. (node.Name or "?")
                .. " x=" .. tostring(node.PositionX) .. " y=" .. tostring(node.PositionY))
        end
    end
    LogMsg("Class nodes: " .. n)
end

function DebugTools.DumpAPI()
    local function dumpTbl(name, t)
        if type(t) ~= "table" then LogMsg(name .. " = nil"); return end
        local names = {}
        for k, v in pairs(t) do
            if type(v) == "function" then names[#names + 1] = k end
        end
        table.sort(names)
        LogMsg(name .. " (" .. #names .. " funcs):")
        local line = ""
        for _, n in ipairs(names) do
            if #line + #n + 2 > 90 then LogMsg("  " .. line); line = "" end
            line = (line == "") and n or (line .. ", " .. n)
        end
        if line ~= "" then LogMsg("  " .. line) end
    end
    dumpTbl("C_CharacterAdvancement", _G.C_CharacterAdvancement)
    dumpTbl("CharacterAdvancementUtil", _G.CharacterAdvancementUtil)
end

function DebugTools.DumpMissing()
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no class."); return end
    local active = CAReader.GetInspectInfo(u) or 1
    local tree = CAReader.GetClassTree(cn, active)
    local inTree = {}
    for _, n in ipairs(tree) do inTree[n.ID] = true end
    local build = CAReader.GetUnitBuild(u, active)
    local miss = {}
    for id in pairs(build) do if not inTree[id] then miss[#miss + 1] = id end end
    LogMsg("learned NOT in tree: " .. #miss)
    if #miss > 0 then
        LogMsg(table.concat(miss, ",", 1, math.min(#miss, 25)))
    end
end

function DebugTools.DumpEntries()
    local api = _G.C_CharacterAdvancement
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no class."); return end
    local active = CAReader.GetInspectInfo(u) or 1

    local tree = CAReader.GetClassTree(cn, active)
    local inTree = {}
    for _, n in ipairs(tree) do inTree[n.ID] = true end
    local build = CAReader.GetUnitBuild(u, active)
    local miss, missN = {}, 0
    for id in pairs(build) do if not inTree[id] then miss[id] = true; missN = missN + 1 end end

    local function analyze(label, res)
        if type(res) ~= "table" then LogMsg(label .. " -> " .. type(res)); return end
        local n, total, ord, found = 0, {}, {}, 0
        for _, e in ipairs(res) do
            n = n + 1
            local tb = e.Tab or "?"
            if total[tb] == nil then total[tb] = 0; ord[#ord + 1] = tb end
            total[tb] = total[tb] + 1
            if e.ID and miss[e.ID] then found = found + 1 end
        end
        LogMsg(label .. " -> " .. n .. " entries; faltantes: " .. found .. "/" .. missN)
        local line = ""
        for _, tb in ipairs(ord) do
            local seg = tb .. "=" .. total[tb]
            if #line + #seg + 2 > 90 then LogMsg("   " .. line); line = "" end
            line = (line == "") and seg or (line .. ", " .. seg)
        end
        if line ~= "" then LogMsg("   " .. line) end
    end

    local function tryFn(label, fn, ...)
        if type(fn) ~= "function" then LogMsg(label .. " = nil"); return end
        local ok, res = pcall(fn, ...)
        if not ok then LogMsg(label .. " error: " .. tostring(res)); return end
        analyze(label, res)
    end

    local tabs, seen = {}, {}
    local ok0, base = pcall(api.GetTalentsByClass, cn, active, false)
    if ok0 and type(base) == "table" then
        for _, e in ipairs(base) do
            if e.Tab and not seen[e.Tab] then seen[e.Tab] = true; tabs[#tabs + 1] = e.Tab end
        end
    end

    LogMsg("GetEntriesByClass por tab (faltan " .. missN .. "):")
    local totalFound = 0
    for _, tab in ipairs(tabs) do
        local ok, res = pcall(api.GetEntriesByClass, cn, tab, false)
        if ok and type(res) == "table" then
            local n, found, hasPos = 0, 0, false
            for _, e in ipairs(res) do
                n = n + 1
                if e.ID and miss[e.ID] then found = found + 1 end
                if e.PositionX ~= nil then hasPos = true end
            end
            totalFound = totalFound + found
            LogMsg("  " .. tab .. " -> " .. n .. " entries, faltantes_aqui=" .. found
                .. ", hasPos=" .. tostring(hasPos))
        else
            LogMsg("  " .. tab .. " error: " .. tostring(res))
        end
    end
    LogMsg("total faltantes cubiertos por GetEntriesByClass: " .. totalFound .. "/" .. missN)
end

function DebugTools.FindMissing()
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no class."); return end
    local active = CAReader.GetInspectInfo(u) or 1
    local tree = CAReader.GetClassTree(cn, active)
    local inTree = {}
    for _, n in ipairs(tree) do inTree[n.ID] = true end
    local build = CAReader.GetUnitBuild(u, active)
    local miss = {}
    for id in pairs(build) do if not inTree[id] then miss[id] = true end end

    local api = _G.C_CharacterAdvancement
    local info = {}
    local all = api.GetAllEntries and api.GetAllEntries()
    if type(all) == "table" then
        for _, e in ipairs(all) do
            if e.ID and miss[e.ID] then info[e.ID] = (tostring(e.Class) .. "/" .. tostring(e.Tab)) end
        end
    end
    for id in pairs(miss) do
        local isTal = api.IsTalentID and api.IsTalentID(id)
        local isMas = api.IsMastery and api.IsMastery(id)
        LogMsg(id .. " " .. (info[id] or "notfound")
            .. " talent=" .. tostring(isTal) .. " mastery=" .. tostring(isMas))
    end
end

function DebugTools.DumpCategories()
    local api = _G.C_CharacterAdvancement
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no class."); return end
    local active = CAReader.GetInspectInfo(u) or 1
    local tabs, seen = {}, {}
    local ok, base = pcall(api.GetTalentsByClass, cn, active, false)
    if ok and type(base) == "table" then
        for _, e in ipairs(base) do
            if e.Tab and not seen[e.Tab] then seen[e.Tab] = true; tabs[#tabs + 1] = e.Tab end
        end
    end
    for _, tab in ipairs(tabs) do
        local ok2, res = pcall(api.GetEntriesByClass, cn, tab, false)
        if ok2 and type(res) == "table" then
            local combo, ord = {}, {}
            for _, e in ipairs(res) do
                local k = tostring(e.Type) .. "|" .. tostring(e.NodeType)
                    .. "|" .. tostring(e.Quality) .. "|" .. tostring(e.Color)
                if combo[k] == nil then combo[k] = 0; ord[#ord + 1] = k end
                combo[k] = combo[k] + 1
            end
            LogMsg(tab .. ":")
            for _, k in ipairs(ord) do LogMsg("   " .. k .. " = " .. combo[k]) end
        end
    end
end

function DebugTools.DumpState()
    local iframe = _G.AscensionInspectFrame
    local buildPanel = _G.InspectBuildPanelSpecs
    LogMsg("combat=" .. tostring(InCombatLockdown()))
    LogMsg("inspectFrameShown=" .. tostring(iframe and iframe:IsShown()))
    LogMsg("getInspectFrame=" .. tostring(GetInspectFrame()))
    local unit = GetInspectedUnit()
    local _, classFile = UnitClass(unit)
    LogMsg("unit=" .. tostring(unit)
        .. " exists=" .. tostring(UnitExists(unit))
        .. " isPlayer=" .. tostring(UnitIsPlayer(unit))
        .. " classFile=" .. tostring(classFile)
        .. " vanilla=" .. tostring(classFile and VANILLA_CLASSES[classFile] or false))
    if iframe then
        LogMsg("currentTab=" .. tostring(iframe.GetCurrentTabID and iframe:GetCurrentTabID())
            .. " buildTab=" .. tostring(iframe.Tabs and iframe.Tabs.Build)
            .. " wantsBuild=" .. tostring(userWantsBuild))
    end
    LogMsg("buildPanelSpecsVisible=" .. tostring(buildPanel and buildPanel:IsVisible()))
    LogMsg("current.unit=" .. tostring(current.unit)
        .. " tpShown=" .. tostring(TP.Get():IsShown()))
    local api = _G.C_CharacterAdvancement
    if api and type(api.GetInspectedBuild) == "function" then
        local okb, bld = pcall(api.GetInspectedBuild, unit, 1)
        local n = 0
        if okb and type(bld) == "table" then
            for _ in pairs(bld) do n = n + 1 end
        end
        LogMsg("inspectedBuild(" .. tostring(unit) .. ",1) entries=" .. n)
    end
    local active, unlocked = CAReader.GetInspectInfo(unit)
    LogMsg("inspectInfo active=" .. tostring(active)
        .. " unlocked=" .. tostring(type(unlocked) == "table" and #unlocked or unlocked))
end

function DebugTools.DumpSpecs()
    local api = _G.C_CharacterAdvancement
    local u = "target"
    local cn = CAReader.GetClassName(u)
    if not cn then LogMsg("debug: no class."); return end
    local active, unlocked = CAReader.GetInspectInfo(u)
    local unlockedStr = type(unlocked) == "table" and ("{" .. table.concat(unlocked, ",") .. "}") or tostring(unlocked)
    LogMsg("active=" .. tostring(active) .. " unlocked=" .. unlockedStr)

    if type(api.GetCategories) == "function" then
        local ok, cats = pcall(api.GetCategories, cn)
        if ok and type(cats) == "table" then
            for i, c in ipairs(cats) do
                if type(c) == "table" then
                    local parts = {}
                    for k, v in pairs(c) do parts[#parts + 1] = k .. "=" .. tostring(v) end
                    LogMsg("  cat[" .. i .. "] " .. table.concat(parts, " "))
                else
                    LogMsg("  cat[" .. i .. "] " .. tostring(c))
                end
            end
        else
            LogMsg("  GetCategories -> " .. tostring(cats))
        end
    end

    local slot = active or 1
    local tree = CAReader.GetClassTree(cn, slot)
    local build = CAReader.GetUnitBuild(u, slot)
    local total, learned, ord = {}, {}, {}
    for _, n in ipairs(tree) do
        if total[n.Tab] == nil then total[n.Tab] = 0; ord[#ord + 1] = n.Tab end
        total[n.Tab] = total[n.Tab] + 1
        if build[n.ID] then learned[n.Tab] = (learned[n.Tab] or 0) + 1 end
    end
    for _, tb in ipairs(ord) do
        LogMsg("  TAB " .. tb .. " total=" .. total[tb] .. " learned=" .. (learned[tb] or 0))
    end
end

_G.SLASH_COAIT1 = "/coait"
_G.SlashCmdList = _G.SlashCmdList or {}
_G.SlashCmdList["COAIT"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "class" then
        SafeCall(DebugTools.DumpClass)
    elseif msg == "api" then
        SafeCall(DebugTools.DumpAPI)
    elseif msg == "miss" then
        SafeCall(DebugTools.DumpMissing)
    elseif msg == "entries" then
        SafeCall(DebugTools.DumpEntries)
    elseif msg == "findmiss" then
        SafeCall(DebugTools.FindMissing)
    elseif msg == "cats" then
        SafeCall(DebugTools.DumpCategories)
    elseif msg == "specs" then
        SafeCall(DebugTools.DumpSpecs)
    elseif msg == "state" then
        SafeCall(DebugTools.DumpState)
    else
        SafeCall(DebugTools.DumpTarget)
    end
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not IsModuleEnabled() then return end
        if not EnsureConfig() then return end

        addon:After(0.5, function()
            if addon.db and addon.db.RegisterCallback then
                addon.db.RegisterCallback(addon, "OnProfileChanged", function()
                    addon.RefreshInspectorSystem()
                end)
                addon.db.RegisterCallback(addon, "OnProfileCopied", function()
                    addon.RefreshInspectorSystem()
                end)
                addon.db.RegisterCallback(addon, "OnProfileReset", function()
                    addon.RefreshInspectorSystem()
                end)
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
        if not IsModuleEnabled() then return end
        if not HasCoAAPI() then return end
        addon.ApplyInspectorSystem()
    end
end)
