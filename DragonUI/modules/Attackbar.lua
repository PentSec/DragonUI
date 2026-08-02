-- ============================================================================
-- Attack Bar Module for DragonUI
-- Shows main hand, off hand, ranged, and enemy target swing timers.
-- ============================================================================

local addon = select(2, ...)

-- ============================================================================
-- Default Configuration
-- ============================================================================

local DEFAULTS = {
    enabled = false,  -- disabled by default, opt-in module
    showMainHand = true,
    showOffHand = true,
    showRanged = true,
    showEnemy = true,
    showTimer = true,
    showInfo = true,
    borderStyle = "standard",  -- "standard", "thin", "none"
    scale = 1.0,
}

-- ============================================================================
-- Module State
-- ============================================================================

local AttackbarModule = {
    applied = false,
}

if addon.RegisterModule then
    addon:RegisterModule("attackbar", AttackbarModule,
        "Attack Bar",
        "Shows main hand, off hand, ranged, and enemy target swing timers.",
        {
            lifecycle = {
                apply   = "ApplyAttackbarSystem",
                restore = "RestoreAttackbarSystem",
                refresh = "RefreshAttackbarSystem",
            },
        })
end

-- ============================================================================
-- Upvalues for frequently used APIs
-- ============================================================================

local GetTime = GetTime
local UnitAttackSpeed = UnitAttackSpeed
local UnitDamage = UnitDamage
local UnitRangedDamage = UnitRangedDamage
local UnitGUID = UnitGUID
local CreateFrame = CreateFrame
local GetNetStats = GetNetStats
local math_abs = math.abs
local math_fmod = math.fmod
local table_insert = table.insert

-- ============================================================================
-- Configuration Reference
-- ============================================================================

local db

local function EnsureConfig()
    if not addon.db or not addon.db.profile then return false end
    if not addon.db.profile.modules then
        addon.db.profile.modules = {}
    end
    if not addon.db.profile.modules.attackbar then
        addon.db.profile.modules.attackbar = {}
        for k, v in pairs(DEFAULTS) do
            addon.db.profile.modules.attackbar[k] = v
        end
    end
    db = addon.db.profile.modules.attackbar
    -- Apply any missing defaults
    for k, v in pairs(DEFAULTS) do
        if db[k] == nil then db[k] = v end
    end
    return true
end

local function IsModuleEnabled()
    return db and db.enabled == true
end

-- ============================================================================
-- Frame References
-- ============================================================================

local playerAnchor
local playerMHBar
local playerMHText
local playerMHTimer
local playerMHSpark
local playerMHTimerText
local playerOHBar
local playerOHText
local playerOHTimer
local playerOHSpark
local playerOHTimerText
local enemyAnchor
local enemyMHBar
local enemyMHText
local enemyMHTimer
local enemyMHSpark
local enemyMHTimerText
local eventFrame

-- Editor-mode overlay anchors (one per draggable bar)
local playerMHAnchor
local playerOHAnchor
local enemyMHAnchor

-- ============================================================================
-- Textures (matching castbar)
-- ============================================================================

local TEXTURE_PATH = "Interface\\AddOns\\DragonUI\\Textures\\Castbar\\"
local TEXTURES = {
    fill    = TEXTURE_PATH .. "CastingBarStandard2",
    spark   = TEXTURE_PATH .. "CastingBarSpark",
    atlas   = TEXTURE_PATH .. "uicastingbar2x",
    border  = "Interface\\CastingBar\\UI-CastingBar-Border",
    bordern = "Interface\\Tooltips\\UI-StatusBar-Border",
}

local UV_COORDS = {
    background = {0.0009765625, 0.4130859375, 0.3671875, 0.41796875},
    border     = {0.412109375, 0.828125, 0.001953125, 0.060546875},
}

-- ============================================================================
-- Utility Functions
-- ============================================================================

-- Original colors: white (0,0,1) for MH/OH, red (1,.1,.1) for enemy
local function GetBarColor(isEnemy)
    if isEnemy then
        return 1, 0.1, 0.1  -- Red for enemy (matches original)
    else
        return 0, 0, 1.0    -- White/blue for player (matches original)
    end
end

local function GetBorderThickness(style)
    if style == "thin" then
        return 8
    elseif style == "standard" then
        return 16
    else
        return 0
    end
end

-- ============================================================================
-- Frame Creation
-- ============================================================================

local function CreateStatusBar(parent, name, isEnemy)
    local bar = CreateFrame("StatusBar", name, parent)
    bar:SetSize(256, 16)
    bar:SetStatusBarTexture(TEXTURES.fill)

    local r, g, b = GetBarColor(isEnemy)
    bar:SetStatusBarColor(r, g, b)

    -- Background (rounded, from atlas — matches castbar)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(TEXTURES.atlas)
    bg:SetTexCoord(unpack(UV_COORDS.background))
    bg:SetAllPoints()

    -- Lag texture (network lag indicator, anchored to RIGHT)
    local lag = bar:CreateTexture(nil, "ARTWORK")
    lag:SetTexture(TEXTURES.fill)
    lag:SetVertexColor(1, 1, 1, 0.35)
    lag:SetSize(32, 18)
    lag:SetPoint("RIGHT")
    bar.lag = lag

    -- Spark overlay
    local spark = bar:CreateTexture(nil, "OVERLAY")
    spark:SetTexture(TEXTURES.spark)
    spark:SetSize(32, 32)
    spark:SetBlendMode("ADD")
    spark:Hide()

    -- Info text (left-aligned, vertically centered)
    local infoText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    infoText:SetSize(246, 18)
    infoText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    infoText:SetJustifyH("LEFT")
    infoText:Hide()

    -- Timer text (right-aligned, vertically centered)
    local timerText = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    timerText:SetSize(246, 18)
    timerText:SetPoint("CENTER", bar, "CENTER", 0, 0)
    timerText:SetJustifyH("RIGHT")
    timerText:Hide()

    -- Border (standard casting bar border)
    local borderTex = bar:CreateTexture(nil, "ARTWORK", nil, 0)
    borderTex:SetTexture(TEXTURES.atlas)
    borderTex:SetTexCoord(unpack(UV_COORDS.border))
    borderTex:SetPoint("TOPLEFT", bar, "TOPLEFT", -2, 2)
    borderTex:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 2, -2)

    -- Store references
    bar.spark = spark
    bar.timerText = timerText
    bar.infoText = infoText
    bar.borderTex = borderTex
    bar.startTime = 0
    bar.endTime = 0
    bar.totalTime = 0
    bar.minDamage = 0
    bar.maxDamage = 0
    bar.isEnemy = isEnemy
    bar.barWidth = 256  -- for spark/lag calculations

    return bar
end

local function CreateAnchorFrame(name, title, yOffset)
    local anchor = CreateFrame("Frame", name, UIParent)
    anchor:SetSize(267, 56)
    anchor:SetPoint("TOP", UIParent, "TOP", 0, yOffset)
    anchor:EnableMouse(true)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)

    -- Backdrop
    anchor:SetBackdrop({
        bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    anchor:SetBackdropColor(0, 0, 0, 0.7)
    anchor:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    -- Title text
    local titleText = anchor:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", anchor, "TOP", 0, -5)
    titleText:SetText(title)
    titleText:SetJustifyH("CENTER")

    -- Drag handling
    anchor:HookScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self:StartMoving()
        end
    end)

    anchor:HookScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            self:StopMovingOrSizing()
        end
    end)

    anchor.titleText = titleText

    return anchor
end

local function CreatePlayerBars()
    -- Legacy drag anchor (hidden during normal use; kept for border/scale logic)
    playerAnchor = CreateAnchorFrame("DragonUIAttackbarAnchor", "Swing Timer", -125)
    playerAnchor:Hide()

    -- Editor-mode overlay anchors (created once via CreateUIFrame)
    if not playerMHAnchor and addon.CreateUIFrame then
        playerMHAnchor = addon.CreateUIFrame(256, 16, "AttackbarPlayer")
    end
    if not playerOHAnchor and addon.CreateUIFrame then
        playerOHAnchor = addon.CreateUIFrame(256, 16, "AttackbarOffhand")
    end

    -- MH bar — initially positioned from widget config
    playerMHBar = CreateStatusBar(UIParent, "DragonUIAttackbarMH", false)
    playerMHBar:Hide()

    -- OH bar — initially positioned from widget config
    playerOHBar = CreateStatusBar(UIParent, "DragonUIAttackbarOH", false)
    playerOHBar:Hide()
end

local function CreateEnemyBars()
    -- Legacy drag anchor (hidden during normal use)
    enemyAnchor = CreateAnchorFrame("DragonUIAttackbarEnemyAnchor", "Enemy Swing Timer", -125)
    enemyAnchor:Hide()

    -- Editor-mode overlay anchor
    if not enemyMHAnchor and addon.CreateUIFrame then
        enemyMHAnchor = addon.CreateUIFrame(256, 16, "AttackbarEnemy")
    end

    -- Enemy MH bar — positioned from widget config
    enemyMHBar = CreateStatusBar(UIParent, "DragonUIAttackbarEnemyMH", true)
    enemyMHBar:Hide()
end

local function ApplyBarBorders(style)
    -- Toggle border textures on all bars (matches original abar.text logic)
    local bars = { playerMHBar, playerOHBar, enemyMHBar }
    for _, bar in ipairs(bars) do
        if bar and bar.borderTex then
            if style == "thin" then
                bar.borderTex:SetTexture(TEXTURES.bordern)
                bar.borderTex:SetTexCoord(0, 1, 0, 1)
                bar.borderTex:Show()
            elseif style == "none" then
                bar.borderTex:Hide()
            else
                -- standard
                bar.borderTex:SetTexture(TEXTURES.atlas)
                bar.borderTex:SetTexCoord(unpack(UV_COORDS.border))
                bar.borderTex:Show()
            end
        end
    end
end

local function ApplyBorderStyle(style)
    local thickness = GetBorderThickness(style)

    if thickness > 0 then
        if playerAnchor then
            playerAnchor:SetBackdrop({
                bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                edgeSize = thickness,
                insets = { left = 5, right = 5, top = 5, bottom = 5 },
            })
        end
        if enemyAnchor then
            enemyAnchor:SetBackdrop({
                bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                edgeSize = thickness,
                insets = { left = 5, right = 5, top = 5, bottom = 5 },
            })
        end
    else
        if playerAnchor then
            playerAnchor:SetBackdrop({
                bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                edgeFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                tile = true,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
        end
        if enemyAnchor then
            enemyAnchor:SetBackdrop({
                bgFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                edgeFile = "Interface\\TutorialFrame\\TutorialFrameBackground",
                tile = true,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
        end
    end

    -- Also apply bar border textures
    ApplyBarBorders(style)
end

local function ApplyScale()
    local s = db.scale or 1.0

    if playerAnchor then
        playerAnchor:SetScale(s)
    end
    if enemyAnchor then
        enemyAnchor:SetScale(s)
    end

    if playerMHBar then
        playerMHBar:SetScale(s)
    end
    if playerOHBar then
        playerOHBar:SetScale(s)
    end
    if enemyMHBar then
        enemyMHBar:SetScale(s)
    end

    if playerMHAnchor then
        playerMHAnchor:SetScale(s)
    end
    if playerOHAnchor then
        playerOHAnchor:SetScale(s)
    end
    if enemyMHAnchor then
        enemyMHAnchor:SetScale(s)
    end
end

-- Reads widget positions from DB and re-anchors each bar (and its overlay) to UIParent.
-- Guard: does nothing while the editor is active (the overlay drives position then).
local function ApplyAttackbarWidgetPositions()
    if InCombatLockdown() then return end
    if addon.EditorMode and addon.EditorMode:IsActive() then return end

    local widgets = addon.db and addon.db.profile and addon.db.profile.widgets
    if not widgets then return end

    -- Main-hand bar
    if playerMHBar and playerMHAnchor then
        local cfg = widgets.attackbarPlayer
        if cfg then
            local a = cfg.anchor or "TOP"
            playerMHAnchor:ClearAllPoints()
            playerMHAnchor:SetPoint(a, UIParent, a, cfg.posX or 0, cfg.posY or -140)
        end
        playerMHBar:ClearAllPoints()
        playerMHBar:SetPoint("CENTER", playerMHAnchor, "CENTER", 0, 0)
    end

    -- Off-hand bar
    if playerOHBar and playerOHAnchor then
        local cfg = widgets.attackbarOffhand
        if cfg then
            local a = cfg.anchor or "TOP"
            playerOHAnchor:ClearAllPoints()
            playerOHAnchor:SetPoint(a, UIParent, a, cfg.posX or 0, cfg.posY or -165)
        end
        playerOHBar:ClearAllPoints()
        playerOHBar:SetPoint("CENTER", playerOHAnchor, "CENTER", 0, 0)
    end

    -- Enemy MH bar
    if enemyMHBar and enemyMHAnchor then
        local cfg = widgets.attackbarEnemy
        if cfg then
            local a = cfg.anchor or "TOP"
            enemyMHAnchor:ClearAllPoints()
            enemyMHAnchor:SetPoint(a, UIParent, a, cfg.posX or 0, cfg.posY or -200)
        end
        enemyMHBar:ClearAllPoints()
        enemyMHBar:SetPoint("CENTER", enemyMHAnchor, "CENTER", 0, 0)
    end
end

-- ============================================================================
-- Update Handlers
-- ============================================================================

local function UpdateBar(bar, elapsed)
    if not bar.totalTime or bar.totalTime <= 0 then
        bar:Hide()
        bar.spark:Hide()
        return
    end

    local currentTime = GetTime()
    local remaining = bar.endTime - currentTime

    bar:SetValue(currentTime)
    local barW = bar.barWidth or 256
    bar.spark:SetPoint("CENTER", bar, "LEFT",
        (currentTime - bar.startTime) / bar.totalTime * barW, 2)
    bar.spark:Show()

    -- Lag texture width (matches original: lag * barW / (1000 * totalTime))
    if bar.lag then
        local _, _, lag = GetNetStats()
        bar.lag:SetWidth((lag * barW) / (1000 * bar.totalTime))
    end

    -- Timer text: "{"..left.."}" format matching original
    if db.showTimer and remaining > 0 then
        local left = remaining - math_fmod(remaining, 0.01)
        bar.timerText:SetText("{" .. left .. "}")
        bar.timerText:Show()
    else
        bar.timerText:Hide()
    end

    if remaining <= 0 then
        bar:Hide()
        bar.spark:Hide()
    end
end

local function SetMHBar(bar, startTime, duration, infoLabel, minDam, maxDam, isEnemy)
    bar.startTime = startTime
    bar.endTime = startTime + duration
    bar.totalTime = duration
    bar.minDamage = minDam or 0
    bar.maxDamage = maxDam or 0
    bar.isEnemy = isEnemy

    bar:SetMinMaxValues(bar.startTime, bar.endTime)
    bar:SetValue(bar.startTime)
    bar:Show()
    bar.spark:Hide()

    -- Update color based on enemy status
    local r, g, b = GetBarColor(isEnemy)
    bar:SetStatusBarColor(r, g, b)

    -- Info text: use the pre-formatted label from caller
    if db.showInfo and infoLabel and infoLabel ~= "" then
        bar.infoText:SetText(infoLabel)
        bar.infoText:Show()
    else
        bar.infoText:Hide()
    end

    bar:SetScript("OnUpdate", function(self, elapsed)
        UpdateBar(self, elapsed)
    end)
end

-- ============================================================================
-- Swing Tracking State (matches original Abar_* variables)
-- ============================================================================

-- Main hand / off-hand swing tracking
local mhLastTime = 0      -- pont: last MH swing time
local ohLastTime = 0      -- pofft: last OH swing time
local mhSwingCount = 0    -- onh:  consecutive MH swings
local ohSwingCount = 0    -- offh: consecutive OH swings
local lastAttackSpeed = 0  -- lastus: for UNIT_ATTACK_SPEED change detection

-- Reset all swing state (called on PLAYER_LEAVE_COMBAT)
local function ResetSwingState()
    mhLastTime = 0
    ohLastTime = 0
    mhSwingCount = 0
    ohSwingCount = 0
    lastAttackSpeed = 0
end

-- ============================================================================
-- Combat Log Parsing — Melee Swing Detection
-- ============================================================================

-- Port of Abar_selfhit(): determines whether the swing was main-hand or
-- off-hand using the original's timing heuristic, then shows the
-- appropriate bar exactly once per swing.

local function OnSelfSwing()
    if not db or not IsModuleEnabled() then return end

    local mhSpeed, ohSpeed = UnitAttackSpeed("player")
    local hd, ld, ohD, ohL = UnitDamage("player")
    hd = hd - math_fmod(hd, 1)
    ld = ld - math_fmod(ld, 1)
    if ohD then
        ohD = ohD - math_fmod(ohD, 1)
        ohL = ohL - math_fmod(ohL, 1)
    end

    local now = GetTime()

    if ohSpeed then
        -- Dual-wield: decide which hand swung using timing heuristic
        local mhDelta = math_abs(now - mhLastTime - mhSpeed)
        local ohDelta = math_abs(now - ohLastTime - ohSpeed)
        local dominatedByMH = not (mhSwingCount <= ohSpeed / mhSpeed)
        local dominatedByOH = ohSwingCount >= mhSpeed / ohSpeed

        if (mhDelta <= ohDelta and not dominatedByMH) or dominatedByOH then
            -- This was a main-hand swing
            if ohLastTime == 0 then ohLastTime = now end
            mhLastTime = now
            ohSwingCount = 0
            mhSwingCount = mhSwingCount + 1
            local roundedMH = mhSpeed - math_fmod(mhSpeed, 0.01)
            if db.showMainHand then
                SetMHBar(playerMHBar, now, roundedMH,
                    "Main[" .. roundedMH .. "s](" .. hd .. "-" .. ld .. ")",
                    hd, ld, false)
            end
        else
            -- This was an off-hand swing
            ohLastTime = now
            ohSwingCount = ohSwingCount + 1
            mhSwingCount = 0
            local roundedOH = ohSpeed - math_fmod(ohSpeed, 0.01)
            if db.showOffHand then
                SetMHBar(playerOHBar, now, roundedOH,
                    "Off[" .. roundedOH .. "s](" .. ohD .. "-" .. ohL .. ")",
                    ohD or 0, ohL or 0, false)
            end
        end
    else
        -- Single-wield: always main hand
        mhLastTime = now
        local roundedMH = mhSpeed - math_fmod(mhSpeed, 0.01)
        if db.showMainHand then
            SetMHBar(playerMHBar, now, roundedMH,
                "Main[" .. roundedMH .. "s](" .. hd .. "-" .. ld .. ")",
                hd, ld, false)
        end
    end
end

-- ============================================================================
-- Combat Log Parsing — Enemy Swing Detection
-- ============================================================================

-- Port of ebar_set(): shows enemy attack bar when target hits the player.
-- Original condition: arg3==target's GUID, arg6==player's GUID

local function OnEnemySwing()
    if not db or not IsModuleEnabled() or not db.showEnemy then return end

    local eSpeed = UnitAttackSpeed("target")
    if eSpeed then
        eSpeed = eSpeed - math_fmod(eSpeed, 0.01)
        SetMHBar(enemyMHBar, GetTime(), eSpeed,
            "Target[" .. eSpeed .. "s]", 0, 0, true)
    end
end

-- ============================================================================
-- Combat Log Parsing — Ranged / Spell Detection
-- ============================================================================

-- Port of abar_spelldir(): shows ranged bar for Throw/Shoot/Aimed Shot etc.
-- Called from UNIT_SPELLCAST_SENT (cast start) and CLEU (spell landed).

local function OnRangedSpell(spellName, fromCLEU)
    if not db or not IsModuleEnabled() or not db.showRanged then
        return
    end
    if not spellName or spellName == "" then
        return
    end

    local mhSpeed = UnitAttackSpeed("player")
    local rSpeed, rhd, rld = UnitRangedDamage("player")
    rhd = rhd and (rhd - math_fmod(rhd, 1)) or 0
    rld = rld and (rld - math_fmod(rld, 1)) or 0

    -- Heroic Strike / Raptor Strike / Maul / Cleave — treated as melee
    if spellName == "Heroic Strike" or spellName == "Raptor Strike"
    or spellName == "Maul" or spellName == "Cleave" then
        if fromCLEU and mhSpeed then
            local hd, ld = UnitDamage("player")
            hd = hd - math_fmod(hd, 1)
            ld = ld - math_fmod(ld, 1)
            local roundedMH = mhSpeed - math_fmod(mhSpeed, 0.01)
            SetMHBar(playerMHBar, GetTime(), roundedMH,
                "Main[" .. roundedMH .. "s](" .. hd .. "-" .. ld .. ")",
                hd, ld, false)
        end
        return
    end

    -- Ranged weapon spells
    if not fromCLEU then
        -- Cast start (UNIT_SPELLCAST_SENT)
        local label
        if spellName == "Throw" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = spellName .. "[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), 0.5, label, rhd, rld, false)
        elseif spellName == "Shoot" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = "Range[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), 0.5, label, rhd, rld, false)
        elseif spellName == "Shoot Bow" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = "Bow[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), 0.5, label, rhd, rld, false)
        elseif spellName == "Shoot Gun" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = "Gun[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), 0.5, label, rhd, rld, false)
        elseif spellName == "Shoot Crossbow" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = "X-Bow[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), 0.5, label, rhd, rld, false)
        elseif spellName == "Auto Shot" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            label = "Auto[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), rSpeed, label, rhd, rld, false)
        elseif spellName == "Aimed Shot" then
            SetMHBar(playerMHBar, GetTime(), 3, "Aiming[3s]", 0.1, 0.1, false)
        else
            -- unhandled ranged spell
        end
    else
        -- Spell landed (CLEU) — update with actual ranged speed
        if spellName == "Shoot" or spellName == "Throw"
        or spellName == "Auto Shot" then
            rSpeed = rSpeed and (rSpeed - math_fmod(rSpeed, 0.01)) or 0.5
            local label = spellName .. "[" .. rSpeed .. "s](" .. rhd .. "-" .. rld .. ")"
            SetMHBar(playerMHBar, GetTime(), rSpeed, label, rhd, rld, false)
        else
            -- unhandled CLEU spell
        end
    end
end

-- ============================================================================
-- CLEU Dispatcher
-- ============================================================================

local function OnCombatLogEvent(subevent, sourceGUID, destGUID,
                                 missType, spellName)
    if not db or not IsModuleEnabled() then return end

    local myGUID = UnitGUID("player")
    local tgtGUID = UnitGUID("target")

    -- Self swing: source=player, dest=target
    if sourceGUID == myGUID and destGUID == tgtGUID then
        if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
            OnSelfSwing()
            return
        end
        if subevent == "RANGE_DAMAGE" or subevent == "RANGE_MISSED"
        or subevent == "SPELL_DAMAGE" or subevent == "SPELL_MISSED" then
            OnRangedSpell(spellName, true)
            return
        end
    end

    -- Enemy swing: source=target, dest=target's target (should be player)
    if sourceGUID == tgtGUID and destGUID == myGUID then
        if subevent == "SWING_DAMAGE" or subevent == "SWING_MISSED" then
            OnEnemySwing()
            return
        end
    end
end

-- ============================================================================
-- UNIT_SPELLCAST_SENT Handler
-- ============================================================================

local function OnUnitSpellCastSent(...)
    if not db or not IsModuleEnabled() then return end

    local unit, spellName = ...
    if unit ~= "player" then return end

    OnRangedSpell(spellName, false)
end

-- ============================================================================
-- UNIT_ATTACK_SPEED Handler
-- ============================================================================

-- Port of original: only updates bar if it's already showing (bar.st exists).
-- Does NOT create a new bar — just extends/shortens the current one.

local function OnUnitAttackSpeed(...)
    if not db or not IsModuleEnabled() then return end

    local unit = ...
    if unit ~= "player" then return end

    local mhSpeed, ohSpeed = UnitAttackSpeed("player")

    -- Update main hand bar only if it's already active
    if mhSpeed and playerMHBar:IsShown() and playerMHBar.startTime then
        if lastAttackSpeed ~= mhSpeed then
            lastAttackSpeed = mhSpeed
            playerMHBar.endTime = playerMHBar.startTime + mhSpeed
            playerMHBar.totalTime = mhSpeed
            playerMHBar:SetMinMaxValues(playerMHBar.startTime, playerMHBar.endTime)
            playerMHBar:SetValue(GetTime())
        end
    end

    -- Update off-hand bar only if it's already active
    if ohSpeed and playerOHBar:IsShown() and playerOHBar.startTime then
        playerOHBar.endTime = playerOHBar.startTime + ohSpeed
        playerOHBar.totalTime = ohSpeed
        playerOHBar:SetMinMaxValues(playerOHBar.startTime, playerOHBar.endTime)
        playerOHBar:SetValue(GetTime())
    end
end

-- ============================================================================
-- PLAYER_LEAVE_COMBAT Handler
-- ============================================================================

local function OnPlayerLeaveCombat()
    if not db or not IsModuleEnabled() then return end

    ResetSwingState()

    if playerMHBar then
        playerMHBar:Hide()
        playerMHBar.spark:Hide()
        playerMHBar.startTime = 0
    end
    if playerOHBar then
        playerOHBar:Hide()
        playerOHBar.spark:Hide()
        playerOHBar.startTime = 0
    end
end

-- ============================================================================
-- DragonUI Lifecycle
-- ============================================================================

function addon.ApplyAttackbarSystem()
    if AttackbarModule.applied then return end
    if not EnsureConfig() then return end

    -- Create frames
    CreatePlayerBars()
    CreateEnemyBars()
    ApplyBorderStyle(db.borderStyle or "standard")
    ApplyScale()
    ApplyAttackbarWidgetPositions()

    -- Register editor-mode overlays (idempotent guard via Registered check)
    if addon.RegisterEditableFrame then
        addon:RegisterEditableFrame({
            name = "AttackbarPlayer",
            frame = playerMHAnchor,
            configPath = {"widgets", "attackbarPlayer"},
            editorVisible = function()
                return db and db.enabled and db.showMainHand
            end,
            showTest = function()
                if playerMHAnchor then playerMHAnchor:Show() end
            end,
            hideTest = function()
                if playerMHAnchor then playerMHAnchor:Hide() end
            end,
            onHide = function()
                ApplyAttackbarWidgetPositions()
            end,
        })

        addon:RegisterEditableFrame({
            name = "AttackbarOffhand",
            frame = playerOHAnchor,
            configPath = {"widgets", "attackbarOffhand"},
            editorVisible = function()
                return db and db.enabled and db.showOffHand
            end,
            showTest = function()
                if playerOHAnchor then playerOHAnchor:Show() end
            end,
            hideTest = function()
                if playerOHAnchor then playerOHAnchor:Hide() end
            end,
            onHide = function()
                ApplyAttackbarWidgetPositions()
            end,
        })

        addon:RegisterEditableFrame({
            name = "AttackbarEnemy",
            frame = enemyMHAnchor,
            configPath = {"widgets", "attackbarEnemy"},
            editorVisible = function()
                return db and db.enabled and db.showEnemy
            end,
            showTest = function()
                if enemyMHAnchor then enemyMHAnchor:Show() end
            end,
            hideTest = function()
                if enemyMHAnchor then enemyMHAnchor:Hide() end
            end,
            onHide = function()
                ApplyAttackbarWidgetPositions()
            end,
        })
    end

    -- Create event handler
    eventFrame = CreateFrame("Frame")
    eventFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "COMBAT_LOG_EVENT_UNFILTERED" then
            -- 3.3.5a CLEU varargs (this server omits hideCaster):
            -- timestamp, subevent, sourceGUID, sourceName, sourceFlags,
            -- destGUID, destName, destFlags, [missType|spellId, spellName, ...]
            local _, subevent, sourceGUID, _, _, destGUID, _, _,
                  extra1, extra2 = ...
            -- extra1 = missType for SWING_MISSED, spellId for RANGE/SPELL
            -- extra2 = spellName for RANGE/SPELL events
            OnCombatLogEvent(subevent, sourceGUID, destGUID,
                             extra1, extra2)
        elseif event == "UNIT_SPELLCAST_SENT" then
            OnUnitSpellCastSent(...)
        elseif event == "UNIT_ATTACK_SPEED" then
            OnUnitAttackSpeed(...)
        elseif event == "PLAYER_LEAVE_COMBAT" then
            OnPlayerLeaveCombat()
        end
    end)

    eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    eventFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
    eventFrame:RegisterEvent("UNIT_ATTACK_SPEED")
    eventFrame:RegisterEvent("PLAYER_LEAVE_COMBAT")

    AttackbarModule.applied = true
end

function addon.RestoreAttackbarSystem()
    if not AttackbarModule.applied then return end

    -- Unregister events
    if eventFrame then
        eventFrame:SetScript("OnEvent", nil)
        eventFrame:UnregisterAllEvents()
    end

    -- Hide frames
    if playerAnchor then playerAnchor:Hide() end
    if enemyAnchor then enemyAnchor:Hide() end
    if playerMHBar then playerMHBar:Hide() end
    if playerOHBar then playerOHBar:Hide() end
    if enemyMHBar then enemyMHBar:Hide() end

    AttackbarModule.applied = false
end

function addon.RefreshAttackbarSystem()
    if not EnsureConfig() then return end

    if IsModuleEnabled() then
        -- Ensure frames exist (ModuleRegistry calls Refresh, not Apply)
        if not AttackbarModule.applied then
            addon.ApplyAttackbarSystem()
            return  -- Apply already sets everything up
        end

        -- Re-apply visual settings (border style, scale, widget positions)
        ApplyBorderStyle(db.borderStyle or "standard")
        ApplyScale()
        ApplyAttackbarWidgetPositions()
    else
        addon.RestoreAttackbarSystem()
    end
end

-- ============================================================================
-- Self-Initialization
-- ============================================================================

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DragonUI" then
        if not EnsureConfig() then return end

        -- Register profile callback
        if addon.db and addon.db.RegisterCallback then
            addon.db.RegisterCallback(addon, "OnProfileChanged", function()
                if IsModuleEnabled() then
                    addon.ApplyAttackbarSystem()
                else
                    addon.RestoreAttackbarSystem()
                end
            end)
            addon.db.RegisterCallback(addon, "OnProfileCopied", function()
                if IsModuleEnabled() then
                    addon.ApplyAttackbarSystem()
                else
                    addon.RestoreAttackbarSystem()
                end
            end)
            addon.db.RegisterCallback(addon, "OnProfileReset", function()
                if IsModuleEnabled() then
                    addon.ApplyAttackbarSystem()
                else
                    addon.RestoreAttackbarSystem()
                end
            end)
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsModuleEnabled() then
            addon.ApplyAttackbarSystem()
        end
    end
end)

-- ============================================================================
-- Slash Commands
-- ============================================================================

SLASH_ATTACKBAR1 = "/attackbar"
SLASH_ATTACKBAR2 = "/atkbar"

SlashCmdList["ATTACKBAR"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "toggle" or msg == "enable" or msg == "disable" then
        EnsureConfig()
        if not db then return end
        db.enabled = not db.enabled
        print("|cffFFD700[AttackBar]|r " .. (db.enabled and "|cff00ff00Enabled|r" or "|cffff4444Disabled|r"))
        if db.enabled then
            if addon.ApplyAttackbarSystem then addon.ApplyAttackbarSystem() end
        else
            if addon.RestoreAttackbarSystem then addon.RestoreAttackbarSystem() end
        end
    elseif msg == "status" then
        EnsureConfig()
        if db then
            print("|cffFFD700[AttackBar]|r Status:")
            print("  Enabled: " .. tostring(db.enabled))
            print("  Show MH: " .. tostring(db.showMainHand))
            print("  Show OH: " .. tostring(db.showOffHand))
            print("  Show Ranged: " .. tostring(db.showRanged))
            print("  Show Enemy: " .. tostring(db.showEnemy))
        end
    else
        -- Open options panel
        if addon.ToggleOptionsUI then
            addon:ToggleOptionsUI("attackbar")
        end
    end
end
