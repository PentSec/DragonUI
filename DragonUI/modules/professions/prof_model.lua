-- Copyright (c) 2026 NeticSoul. Licensed under the MIT License; see LICENSE.

local addon = select(2, ...)

local P = addon.Professions
local Model = {}
P.Model = Model

local function nameMatches(index, name, text)
    if name:lower():find(text, 1, true) then return true end
    for r = 1, GetTradeSkillNumReagents(index) do
        local reagent = GetTradeSkillReagentInfo(index, r)
        if reagent and reagent:lower():find(text, 1, true) then return true end
    end
    return false
end

-- Ranges go by item level, as Forever's SetRecipeItemLevelFilter; 3.3.5a's filter read the required level instead.
function Model.Matches(index, name, search)
    if search.name then return nameMatches(index, name, search.name) end
    local link = GetTradeSkillItemLink(index)
    if not (link and link:find("item:", 1, true)) then return false end
    local level = select(4, GetItemInfo(link))
    if not level then
        Model.pendingItems = true
        return false
    end
    return level >= search.minLevel and level <= search.maxLevel
end

-- Selection and toggles go through Blizzard's functions, so selectedSkill and addon hooks behave as with the stock list.
function Model.Build(skillUpOnly, search)
    local rows = {}
    Model.pendingItems = false
    for i = 1, GetNumTradeSkills() do
        local name, kind, numAvailable, isExpanded, altVerb = GetTradeSkillInfo(i)
        if name then
            if kind == "header" then
                rows[#rows + 1] = { index = i, name = name, header = true, expanded = isExpanded and true or false }
            elseif not (skillUpOnly and kind == "trivial") and not (search and not Model.Matches(i, name, search)) then
                rows[#rows + 1] = { index = i, name = name, difficulty = kind, count = numAvailable or 0, altVerb = altVerb }
            end
        end
    end
    if skillUpOnly or search then
        local kept = {}
        for n, row in ipairs(rows) do
            local nextRow = rows[n + 1]
            -- An expanded header left without recipes only lists what a filter removed.
            if not (row.header and row.expanded and (not nextRow or nextRow.header)) then
                kept[#kept + 1] = row
            end
        end
        rows = kept
    end
    return rows
end

function Model.Label(row)
    if row.header then return row.name end
    local prefix = ""
    if ENABLE_COLORBLIND_MODE == "1" and TradeSkillTypePrefix then
        prefix = TradeSkillTypePrefix[row.difficulty] or " "
    end
    return prefix .. row.name
end

-- Forever's " [%d] " after the label; nothing when none can be made.
function Model.CountText(row)
    if row.header or not row.count or row.count <= 0 then return "" end
    return string.format(" [%d]", row.count)
end

function Model.Color(row)
    local c = TradeSkillTypeColor and TradeSkillTypeColor[row.header and "header" or row.difficulty]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

function Model.SelectedIndex()
    return GetTradeSkillSelectionIndex()
end

-- Same two calls as Blizzard's TradeSkillSkillButton_OnClick; on a header SetSelection toggles it.
function Model.Select(index)
    TradeSkillFrame_SetSelection(index)
    TradeSkillFrame_Update()
end

-- Same branch as the stock row's OnClick: a modified click links the recipe instead of selecting it.
function Model.Click(index, button)
    if IsModifiedClick() then
        HandleModifiedItemClick(GetTradeSkillRecipeLink(index))
    elseif button == "LeftButton" then
        Model.Select(index)
    end
end

function Model.AllCollapsed()
    return TradeSkillCollapseAllButton and TradeSkillCollapseAllButton.collapsed and true or false
end

function Model.ToggleAll()
    TradeSkillCollapseAllButton_OnClick(TradeSkillCollapseAllButton)
end

function Model.Rank()
    local name, rank, maxRank = GetTradeSkillLine()
    return name, rank or 0, maxRank or 0
end


-- 3.3.5a has no recipe favourites, so they are kept per character and per profession, by recipe name.
local function favorites(create)
    local char = addon.db and addon.db.char
    local line = GetTradeSkillLine()
    if not (char and line) then return nil end
    char.favoriteRecipes = char.favoriteRecipes or {}
    local set = char.favoriteRecipes[line]
    if not set and create then
        set = {}
        char.favoriteRecipes[line] = set
    end
    return set
end

local NO_FAVORITES = {}

-- The open profession's favourites by name, read once per list build.
function Model.Favorites()
    return favorites(false) or NO_FAVORITES
end

function Model.IsFavorite(name)
    return name ~= nil and Model.Favorites()[name] == true
end

function Model.SetFavorite(name, on)
    local set = favorites(true)
    if not (set and name) then return end
    set[name] = on and true or nil
    P.Fire("FavoritesChanged")
end

-- A linked profession is someone else's book: Forever only offers favourites in local crafting.
function Model.CanFavorite()
    return not IsTradeSkillLinked()
end

function Model.IsSearching()
    return P.List ~= nil and P.List.SearchText() ~= ""
end
