local ITEM_ID = 2042
local ZONES = { ["Elwynn Forest"] = true, ["Westfall"] = true,
    ["Redridge Mountains"] = true, ["The Deadmines"] = true, ["Deadmines"] = true }
local ZONE_LIST = "Elwynn Forest, Westfall, Redridge Mountains, and the Deadmines"
local function InStaffZone()
    return ZONES[GetRealZoneText()] == true
end
local events = CreateFrame("Frame")
local button, holder, hideButton, hideHolder, settings, db
local preview = false
local lastCombatEnd
local Refresh
local settingsCategory
local fadeStart, reminderVisible
local temporarilySuppressed = false
local character, nextRestoreSlot

local function Weapon(slot)
    local link = GetInventoryItemLink("player", slot)
    return link and link:match("(item:[^|]+)") or false
end

local function FindItem(item)
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and not info.isLocked and info.hyperlink
                and info.hyperlink:match("(item:[^|]+)") == item then return bag, slot end
        end
    end
end

local function EmptyBagSlot()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        local free, family = C_Container.GetContainerNumFreeSlots(bag)
        if free and free > 0 and family == 0 then
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                if not C_Container.GetContainerItemInfo(bag, slot) then return bag, slot end
            end
        end
    end
end

local function RestoreAction()
    local saved = character.previous
    if not saved then return end
    for _, slot in ipairs({ 16, 17 }) do
        if Weapon(slot) ~= saved[slot] then
            if saved[slot] then
                local bag = FindItem(saved[slot])
                if bag then return slot, "/equipslot [nocombat] " .. slot .. " " .. saved[slot] end
                return -- Keep the saved setup if an item is missing or locked.
            else
                local bag, space = EmptyBagSlot()
                if bag then
                    return slot, "/run if not InCombatLockdown() and not GetCursorInfo() then PickupInventoryItem(" .. slot .. "); C_Container.PickupContainerItem(" .. bag .. "," .. space .. ") end"
                end
                return
            end
        end
    end
    character.previous = nil
end

local function UpdateFade()
    if not button or not hideHolder or InCombatLockdown() then return end
    if temporarilySuppressed and not preview then return end
    local now = GetTime()
    local hovering = reminderVisible and not preview and db.fadeEnabled
        and (button:IsMouseOver()
        or WestfallStaffEquipDismiss:IsMouseOver()
        or (db.showHideButton and hideButton:IsMouseOver()))
    if not reminderVisible or preview or not db.fadeEnabled or hovering then
        fadeStart = now
    end
    fadeStart = fadeStart or now
    local alpha = 1
    if reminderVisible and not preview and db.fadeEnabled and not hovering then
        alpha = 1 - math.max(0, math.min(1, (now - fadeStart - db.fadeSeconds) / 0.5))
    end
    holder:SetAlpha(alpha)
    hideHolder:SetAlpha(alpha)
end

local function Number(value, default, minimum, maximum)
    value = tonumber(value)
    if not value or value ~= value then return default end
    return math.max(minimum, math.min(maximum, value))
end

local function Place(frame, key, defaultY)
    local position = db[key]
    frame:ClearAllPoints()
    if type(position) == "table" and tonumber(position.x) and tonumber(position.y) then
        frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, defaultY)
    end
end

local function EnableDrag(control, frame, key)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    control:RegisterForDrag("LeftButton")
    control:SetScript("OnDragStart", function()
        if preview and not InCombatLockdown() then frame:StartMoving() end
    end)
    control:SetScript("OnDragStop", function()
        if InCombatLockdown() then return end
        frame:StopMovingOrSizing()
        local x, y = frame:GetCenter()
        local ux, uy = UIParent:GetCenter()
        if x and y and ux and uy then
            db[key] = { x = x - ux, y = y - uy }
            Place(frame, key, 0)
        end
    end)
end

local function Say(message)
    print("|cffffcc00Westfall Staff Equip:|r " .. message)
end

local function FindStaff()
    for bag = 0, (NUM_BAG_SLOTS or 4) do
        for slot = 1, C_Container.GetContainerNumSlots(bag) do
            if C_Container.GetContainerItemID(bag, slot) == ITEM_ID then
                return bag, slot
            end
        end
    end
end

local mealNames = { ["Food"] = true, ["Drink"] = true, ["Food & Drink"] = true, ["Refreshment"] = true }
local function IsEatingOrDrinking()
    -- Match active consumption buffs, not the long-lived Well Fed bonus.
    if C_Spell and C_Spell.GetSpellName then
        for _, id in ipairs({ 433, 430, 160903 }) do
            local name = C_Spell.GetSpellName(id)
            if name then mealNames[name] = true end
        end
    end
    for index = 1, 255 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
        if not aura then break end
        if aura.name and not (issecretvalue and issecretvalue(aura.name)) and mealNames[aura.name] then
            return true
        end
    end
    return false
end

Refresh = function()
    -- Never inspect combat auras or change protected frames in combat.
    if not button or InCombatLockdown() then return end
    local wasSuppressed = temporarilySuppressed
    temporarilySuppressed = false
    local show = preview and db.enabled
    if settings then settings.showHelper:SetChecked(db.enabled) end
    nextRestoreSlot = nil
    local macro = "/equipslot [nocombat] 16 item:" .. ITEM_ID
    local inZone = InStaffZone()
    if not inZone and character.previous then nextRestoreSlot, macro = RestoreAction() end
    button:SetText(nextRestoreSlot and "Restore Weapons" or "Equip Staff")
    local icon = C_Item.GetItemIconByID(ITEM_ID)
    if nextRestoreSlot then
        local item = character.previous[nextRestoreSlot]
        if item then
            local itemID = tonumber(item:match("^item:(%d+)"))
            icon = (itemID and C_Item.GetItemIconByID(itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark"
        else
            icon = nextRestoreSlot == 16 and "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand"
                or "Interface\\PaperDoll\\UI-PaperDoll-Slot-SecondaryHand"
        end
    end
    button.itemIcon:SetTexture(icon)
    hideButton:SetText("Hide")
    if not preview and db.enabled
        and GetServerTime() >= (db.hiddenUntil or 0)
        and (not lastCombatEnd or GetTime() >= lastCombatEnd + db.combatDelay)
        and not UnitIsDeadOrGhost("player") and not GetCursorInfo() then
        if not inZone then
            show = nextRestoreSlot ~= nil
        elseif GetInventoryItemID("player", 16) ~= ITEM_ID then
            local bag, slot = FindStaff()
            if bag then
            local info = C_Container.GetContainerItemInfo(bag, slot)
            show = info and not info.isLocked
            end
        end
        if show and (UnitCastingInfo("player") or UnitChannelInfo("player") or IsEatingOrDrinking()) then
                temporarilySuppressed = true
                show = false
        end
    end
    local action = show and not preview and "macro" or nil
    if button:GetAttribute("type1") ~= action then button:SetAttribute("type1", action) end
    if button:GetAttribute("macrotext1") ~= macro then button:SetAttribute("macrotext1", macro) end
    button:SetShown(not not show)
    hideButton:SetShown(not not (show and db.showHideButton))
    if (not show and not temporarilySuppressed)
        or (show and not reminderVisible and not wasSuppressed) then fadeStart = nil end
    reminderVisible = not not show
    UpdateFade()
end

local function OpenSettings()
    if InCombatLockdown() then Say("Open settings after combat ends."); return end
    if not settings then
        settings = CreateFrame("Frame", "WestfallStaffEquipSettings", UIParent, "BackdropTemplate")
        settings:SetSize(420, 502)
        settings:SetPoint("CENTER", UIParent, "CENTER", 250, 120)
        settings:SetFrameStrata("DIALOG")
        settings:SetClampedToScreen(true)
        settings:SetMovable(true)
        settings:EnableMouse(true)
        settings:RegisterForDrag("LeftButton")
        settings:SetScript("OnDragStart", function(self) self:StartMoving() end)
        settings:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
        settings:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true,
            tileSize = 32, edgeSize = 32, insets = { left = 8, right = 8, top = 8, bottom = 8 } })
        local title = settings:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -20)
        title:SetText("Westfall Staff Equip")
        local close = CreateFrame("Button", nil, settings, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -5, -5)
        close:SetScript("OnClick", function() settings:Hide() end)
        UISpecialFrames[#UISpecialFrames + 1] = "WestfallStaffEquipSettings"

        local instructions = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        instructions:SetPoint("TOPLEFT", 24, -54)
        instructions:SetWidth(372)
        instructions:SetJustifyH("LEFT")
        instructions:SetText("Drag a preview button to move it. Enable the Hide button below to preview it. Positions save automatically. Combat temporarily hides previews.")

        settings.showHelper = CreateFrame("CheckButton", "WestfallStaffEquipShowHelper", settings, "UICheckButtonTemplate")
        settings.showHelper:SetPoint("TOPLEFT", 20, -118)
        settings.showHelper.Text:SetText("Show staff helper")
        settings.showHelper:SetScript("OnClick", function(self)
            db.enabled = not not self:GetChecked()
            if db.enabled then db.hiddenUntil = 0 end
            Refresh()
        end)

        settings.showHide = CreateFrame("CheckButton", "WestfallStaffEquipShowHide", settings, "UICheckButtonTemplate")
        settings.showHide:SetPoint("TOPLEFT", 20, -154)
        settings.showHide.Text:SetText("Show Hide button")
        settings.showHide:SetScript("OnClick", function(self)
            db.showHideButton = not not self:GetChecked()
            if not db.showHideButton then db.hiddenUntil = 0 end
            Refresh()
        end)

        local function Field(label, y, name)
            local text = settings:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("TOPLEFT", 24, y)
            text:SetText(label)
            local input = CreateFrame("EditBox", name, settings, "InputBoxTemplate")
            input:SetSize(72, 26)
            input:SetPoint("TOPRIGHT", -30, y + 6)
            input:SetAutoFocus(false)
            input:SetMaxLetters(6)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            return input
        end
        settings.minutes = Field("Hide duration (minutes, 1-1440)", -206, "WestfallStaffEquipMinutes")
        settings.delay = Field("Delay after combat (seconds, 0-600)", -246, "WestfallStaffEquipDelay")
        settings.fade = CreateFrame("CheckButton", "WestfallStaffEquipFadeEnabled", settings, "UICheckButtonTemplate")
        settings.fade:SetPoint("TOPLEFT", 20, -274)
        settings.fade.Text:SetText("Fade buttons when not hovered")
        settings.fade:SetScript("OnClick", function(self)
            db.fadeEnabled = not not self:GetChecked()
            fadeStart = nil
            Refresh()
        end)
        settings.fadeSeconds = Field("Fade after (seconds, 1-600)", -322, "WestfallStaffEquipFadeSeconds")
        settings.message = settings:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        settings.message:SetPoint("TOPLEFT", 24, -359)
        settings.message:SetWidth(372)
        settings.message:SetJustifyH("LEFT")

        local function SmallButton(name, text, x, y, width, callback)
            local control = CreateFrame("Button", name, settings, "UIPanelButtonTemplate")
            control:SetSize(width, 26)
            control:SetPoint("BOTTOMLEFT", x, y)
            control:SetText(text)
            control:SetScript("OnClick", callback)
            return control
        end
        local function Save()
            local minutes, delay = tonumber(settings.minutes:GetText()), tonumber(settings.delay:GetText())
            local fadeSeconds = tonumber(settings.fadeSeconds:GetText())
            if not minutes or minutes ~= minutes or minutes < 1 or minutes > 1440
                or not delay or delay ~= delay or delay < 0 or delay > 600 then
                settings.message:SetText("Enter 1-1440 minutes and 0-600 seconds, then click Save.")
                return
            end
            if not fadeSeconds or fadeSeconds ~= fadeSeconds or fadeSeconds < 1 or fadeSeconds > 600 then
                settings.message:SetText("Enter a fade time from 1 to 600 seconds, then click Save.")
                return
            end
            db.hideMinutes, db.combatDelay = minutes, delay
            db.fadeSeconds = fadeSeconds
            fadeStart = nil
            settings.fadeSeconds:ClearFocus()
            settings.minutes:ClearFocus()
            settings.delay:ClearFocus()
            settings.message:SetText("Saved. Close this window to leave preview mode.")
            Refresh()
        end
        SmallButton("WestfallStaffEquipSave", "Save", 24, 26, 90, Save)
        SmallButton(nil, "Show again now", 24, 64, 160, function()
            db.hiddenUntil = 0
            fadeStart = nil
            settings.message:SetText("Hide timer cleared. Normal checks resume when you close settings.")
            Refresh()
        end)
        SmallButton(nil, "Reset positions", 204, 64, 190, function()
            if InCombatLockdown() then
                settings.message:SetText("Wait until combat ends to reset positions.")
                return
            end
            db.position, db.hidePosition = nil, nil
            Place(holder, "position", -240)
            Place(hideHolder, "hidePosition", -278)
            settings.message:SetText("Button positions reset.")
        end)
        SmallButton(nil, "Close", 304, 26, 90, function() settings:Hide() end)
        settings.minutes:SetScript("OnEnterPressed", Save)
        settings.delay:SetScript("OnEnterPressed", Save)
        settings.fadeSeconds:SetScript("OnEnterPressed", Save)
        settings:SetScript("OnHide", function()
            preview = false
            fadeStart = nil
            Refresh()
        end)
    end
    settings.minutes:SetText(tostring(db.hideMinutes))
    settings.showHide:SetChecked(db.showHideButton)
    settings.delay:SetText(tostring(db.combatDelay))
    settings.fade:SetChecked(db.fadeEnabled)
    settings.fadeSeconds:SetText(tostring(db.fadeSeconds))
    settings.message:SetText("Changes to the numbers take effect when you click Save.")
    preview = true
    settings:Show()
    Refresh()
end

local function RegisterOptions()
    if settingsCategory or not Settings or not Settings.RegisterCanvasLayoutCategory then return end
    local panel = CreateFrame("Frame", "WestfallStaffEquipOptions")
    panel:Hide()
    panel.name = "Westfall Staff Equip"
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Westfall Staff Equip")
    local description = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    description:SetPoint("TOPLEFT", 16, -52)
    description:SetWidth(500)
    description:SetJustifyH("LEFT")
    description:SetText("Show or hide the staff helper, set its timers, and move the buttons in the settings window. You can also open it with /wse.")
    local open = CreateFrame("Button", "WestfallStaffEquipOpenOptions", panel, "UIPanelButtonTemplate")
    open:SetSize(260, 28)
    open:SetPoint("TOPLEFT", 16, -112)
    open:SetText("Open settings and move buttons")
    open:SetScript("OnClick", function()
        if InCombatLockdown() then Say("Open settings after combat ends."); return end
        if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        OpenSettings()
    end)
    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(settingsCategory)
end

-- Keep the decoration on the action button so it shares visibility and fading.
local function StyleHelper(control, title)
    control:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    control:SetBackdropColor(0.055, 0.045, 0.035, 0.96)
    control:SetBackdropBorderColor(0.65, 0.51, 0.28, 1)
    local text = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("CENTER")
    control:SetFontString(text)
    control:SetNormalFontObject(GameFontHighlightSmall)
    control:SetHighlightFontObject(GameFontNormalSmall)
    local highlight = control:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetPoint("TOPLEFT", 4, -4)
    highlight:SetPoint("BOTTOMRIGHT", -4, 4)
    highlight:SetColorTexture(1, 0.82, 0.45, 0.10)
    control:SetHighlightTexture(highlight)
    if title then
        local icon = control:CreateTexture(nil, "ARTWORK")
        control.itemIcon = icon
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture(C_Item.GetItemIconByID(ITEM_ID))
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local heading = control:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        heading:SetPoint("TOPLEFT", 45, -9)
        heading:SetText(title)
        local label = control:GetFontString()
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", 45, -24)
        label:SetJustifyH("LEFT")
    end
end

local function Initialize()
    if button or InCombatLockdown() then return end
    WestfallStaffEquipDB = type(WestfallStaffEquipDB) == "table" and WestfallStaffEquipDB or {}
    db = WestfallStaffEquipDB
    db.characters = type(db.characters) == "table" and db.characters or {}
    local key = UnitName("player") .. "-" .. GetRealmName()
    db.characters[key] = type(db.characters[key]) == "table" and db.characters[key] or {}
    character = db.characters[key]
    if db.enabled == nil then db.enabled = true end
    db.hideMinutes = Number(db.hideMinutes, 5, 1, 1440)
    db.showHideButton = db.showHideButton == true
    if not db.showHideButton then db.hiddenUntil = 0 end
    -- Move the former zero default to ten once; preserve custom nonzero delays.
    if not db.delayDefault10Applied then
        if db.combatDelay == nil or db.combatDelay == 0 then db.combatDelay = 10 end
        db.delayDefault10Applied = true
    end
    db.combatDelay = Number(db.combatDelay, 10, 0, 600)
    db.fadeEnabled = db.fadeEnabled == true
    db.fadeSeconds = Number(db.fadeSeconds, 10, 1, 600)
    db.hiddenUntil = Number(db.hiddenUntil, 0, 0, GetServerTime() + 86400)
    RegisterOptions()

    -- A secure parent handles combat hiding without addon code touching it.
    holder = CreateFrame("Frame", "WestfallStaffEquipHolder", UIParent, "SecureHandlerStateTemplate")
    holder:SetSize(190, 46)
    Place(holder, "position", -240)
    RegisterStateDriver(holder, "visibility", "[combat] hide; show")

    button = CreateFrame("Button", "WestfallStaffEquipButton", holder, "SecureActionButtonTemplate,BackdropTemplate")
    button:SetAllPoints(holder)
    StyleHelper(button, "Westfall Staff")
    button:SetText("Equip Staff")
    button:RegisterForClicks("LeftButtonUp")
    button:SetAttribute("useOnKeyDown", false)
    button:SetAttribute("type1", "macro")
    button:SetAttribute("macrotext1", "/equipslot [nocombat] 16 item:" .. ITEM_ID)
    EnableDrag(button, holder, "position")
    button:SetScript("PreClick", function(_, mouseButton)
        if InCombatLockdown() then return end
        Refresh()
        if mouseButton ~= "LeftButton" or preview or not button:GetAttribute("type1") then return end
        if InStaffZone() and GetInventoryItemID("player", 16) ~= ITEM_ID and not character.previous then
            character.previous = { [16] = Weapon(16), [17] = Weapon(17) }
        end
    end)
    button:SetScript("OnEnter", function(self)
        UpdateFade()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if nextRestoreSlot then
            GameTooltip:SetText("Restore previous weapons")
            GameTooltip:AddLine("Click to restore the " .. (nextRestoreSlot == 16 and "main-hand" or "off-hand") .. " slot.", 1, 0.82, 0)
            GameTooltip:AddLine("A weapon pair may need two clicks.", 1, 1, 1)
        else
            GameTooltip:SetItemByID(ITEM_ID)
            GameTooltip:AddLine("Click to equip Staff of Westfall and remember your weapons.", 1, 0.82, 0)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:Hide()

    local dismiss = CreateFrame("Button", "WestfallStaffEquipDismiss", button, "UIPanelCloseButton")
    dismiss:SetSize(20, 20)
    dismiss:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    dismiss:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        db.enabled = false
        GameTooltip:Hide()
        Refresh()
        Say("Hidden. Use /wse and enable Show staff helper to bring it back.")
    end)
    dismiss:SetScript("OnEnter", function(self)
        UpdateFade()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Hide staff helper")
        GameTooltip:AddLine("Show it again in /wse settings.", 1, 1, 1)
        GameTooltip:Show()
    end)
    dismiss:SetScript("OnLeave", function() GameTooltip:Hide() end)

    hideHolder = CreateFrame("Frame", "WestfallStaffEquipHideHolder", UIParent, "SecureHandlerStateTemplate")
    hideHolder:SetSize(80, 24)
    Place(hideHolder, "hidePosition", -278)
    RegisterStateDriver(hideHolder, "visibility", "[combat] hide; show")
    hideButton = CreateFrame("Button", "WestfallStaffEquipHideButton", hideHolder, "BackdropTemplate")
    hideButton:SetAllPoints(hideHolder)
    StyleHelper(hideButton)
    hideButton:SetScript("OnEnter", UpdateFade)
    hideButton:SetScript("OnClick", function()
        if preview or InCombatLockdown() then return end
        db.hiddenUntil = GetServerTime() + db.hideMinutes * 60
        Refresh()
    end)
    EnableDrag(hideButton, hideHolder, "hidePosition")
    hideButton:Hide()
    -- Also catches casting/meal completion and inventory changes.
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.5 then
            elapsed = 0
            Refresh()
        end
        UpdateFade()
    end)
    Refresh()
end

events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" then
        lastCombatEnd = GetTime()
        fadeStart = nil
    end
    if event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" then
        Initialize()
    end
    if event ~= "UNIT_AURA" or unit == "player" then Refresh() end
end)
for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_AURA" }) do
    events:RegisterEvent(event)
end

SLASH_WESTFALLSTAFFEQUIP1 = "/wse"
SlashCmdList.WESTFALLSTAFFEQUIP = function(message)
    if not db then Say("Please wait until combat ends."); return end
    local command = (message or ""):lower():match("^%s*(.-)%s*$")
    if command == "on" or command == "off" then
        db.enabled = command == "on"
        Say(db.enabled and "Enabled." or "Disabled.")
    elseif command == "zones" then
        Say(ZONE_LIST .. ".")
    elseif command == "reset" then
        db.enabled = true
        db.hiddenUntil = 0
        Say("Enabled for " .. ZONE_LIST .. ".")
    elseif command == "" or command == "settings" or command == "options" then
        OpenSettings()
    elseif command == "show" then
        db.hiddenUntil = 0
        fadeStart = nil
    else
        Say((db.enabled and "Enabled" or "Disabled") .. " in " .. ZONE_LIST .. ".")
        Say("/wse: settings. /wse zones: staff zones. /wse on or off. /wse show: clear hide timer. /wse reset: enable and clear hide timer.")
    end
    Refresh()
end
