local InputContainer = require("ui/widget/container/inputcontainer")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local FrameContainer = require("ui/widget/container/framecontainer")
local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Screen = require("device").screen
local Event = require("ui/event")
local GestureRange = require("ui/gesturerange")
local Geom = require("ui/geometry")

local Config = require("config")
local Translator = require("translator")
local UI = require("ui_splitread")

local splitread = InputContainer:extend{
    name = "splitread",
    is_doc_only = true,
    panel_text = "splitread ready...",
    panel_height = 0,
    config = nil,
    is_initialized = false, 
}

function splitread:init()
    self.ui.menu:registerToMainMenu(self)
    local ok, config = pcall(function() return Config:load() end)
    self.config = ok and config or {
        source_lang = "auto",
        target_lang = "en",
        panel_height_ratio = 0.50,
        auto_translate = true,
        font_size = 14,
    }
    self.panel_height = math.floor(Screen:getHeight() * self.config.panel_height_ratio)

    local tap_size = Screen:scaleByDPI(60)
    self.ges_events.Tap = {
        GestureRange:new{
            ges = "tap",
            range = Geom:new{
                x = Screen:getWidth() - tap_size,
                y = Screen:getHeight() - tap_size,
                w = tap_size,
                h = tap_size,
            },
        },
    }
    logger.info("splitread: init, panel_height:", self.panel_height)
end

function splitread:onTap(_, ges)
    if not self:isEnabledForBook() then return end
    logger.info("splitread: TAP DETECTED at", ges.pos.x, ges.pos.y)
    self:showSettingsDialog()
    return true
end

function splitread:getFooterHeight()
    if self.view and self.view.footer and self.view.footer_visible then
        return self.view.footer:getHeight()
    end
    return 0
end

function splitread:getBookKey()
    if self.ui and self.ui.document and self.ui.document.file then
        return "book_" .. self.ui.document.file:gsub("[^%w]", "_")
    end
    return nil
end

function splitread:isEnabledForBook()
    local key = self:getBookKey()
    if not key then return false end
    local LuaSettings = require("luasettings")
    local DataStorage = require("datastorage")
    local s = LuaSettings:open(DataStorage:getSettingsDir() .. "/splitread.lua")
    return s:isTrue(key)
end

function splitread:setEnabledForBook(enabled)
    local key = self:getBookKey()
    if not key then return end
    local LuaSettings = require("luasettings")
    local DataStorage = require("datastorage")
    local s = LuaSettings:open(DataStorage:getSettingsDir() .. "/splitread.lua")
    s:saveSetting(key, enabled)
    s:flush()
    logger.info("splitread: book enabled state saved:", enabled, "key:", key)
end

function splitread:onReaderReady()
    logger.info("splitread: onReaderReady called, enabled:", self:isEnabledForBook(), "initialized:", self.is_initialized)
    if not self:isEnabledForBook() then
        logger.info("splitread: disabled for this book")
        return
    end
    if self.is_initialized then
        logger.info("splitread: already initialized, skipping")
        return
    end
    self.is_initialized = true
    logger.info("splitread: initializing...")
    self.panel_text = "splitread ready! Tap ⚙ to configure."
    self:shrinkReadingArea()
    UIManager:scheduleIn(0.5, function() self:refreshPanel() end)
    local orig_paintTo = self.view.paintTo
    self.view.paintTo = function(view, bb, x, y)
        orig_paintTo(view, bb, x, y)
        self:refreshPanel()
    end
end

function splitread:shrinkReadingArea()
    local footer_h = self:getFooterHeight()
    local screen_h = Screen:getHeight()
    local new_h = screen_h - self.panel_height - footer_h
    self.view.dimen.h = new_h
    self.ui.dimen.h = new_h
    local margins = self.ui.document:getPageMargins()
    self.ui:handleEvent(Event:new("SetPageMargins", {
        margins.left,
        margins.top,
        margins.right,
        2,
    }))
    logger.info("splitread: set bottom margin to 2")
    self.ui:handleEvent(Event:new("SetDimensions", self.ui.dimen))
end

function splitread:flattenText(t)
    if type(t) == "string" then return t end
    local words = {}
    for _, item in ipairs(t) do
        if type(item) == "table" and item.word then
            table.insert(words, item.word)
        elseif type(item) == "string" then
            table.insert(words, item)
        end
    end
    return table.concat(words, " ")
end

function splitread:getTextForPage(page)
    local doc = self.ui.document
    local ok, text = pcall(function()
        local pos0 = doc:getPageXPointer(page)
        local pos1 = doc:getPageXPointer(page + 1)
        return doc:getTextFromXPointers(pos0, pos1, false)
    end)
    if not ok or not text then return nil end
    return self:flattenText(text)
end

function splitread:translateCurrentPage()
    if not Translator:isNetworkAvailable() then
        self.panel_text = "No internet connection."
        self:refreshPanel()
        return
    end

    local doc = self.ui.document
    local current_page = doc:getCurrentPage()

    local current = self:getTextForPage(current_page)
    if not current or #current == 0 then
        self.panel_text = "No text found."
        self:refreshPanel()
        return
    end

    local prev_tail = ""
    if current_page > 1 then
        local prev = self:getTextForPage(current_page - 1)
        if prev and #prev > 0 then
            local last_dot = 0
            for i = #prev, 1, -1 do
                local c = prev:sub(i, i)
                if c == "." or c == "!" or c == "?" then
                    last_dot = i
                    break
                end
            end
            if last_dot > 0 and last_dot < #prev then
                prev_tail = prev:sub(last_dot + 1):gsub("^%s+", "")
            end
        end
    end

    local next_head = ""
    local next_text = self:getTextForPage(current_page + 1)
    if next_text and #next_text > 0 then
        local first_dot = 0
        for i = 1, #next_text do
            local c = next_text:sub(i, i)
            if c == "." or c == "!" or c == "?" then
                first_dot = i
                break
            end
        end
        if first_dot > 0 then
            next_head = next_text:sub(1, first_dot)
        end
    end

    local first_cap = current:find("[A-ZÄÖÜ]")
    local clean_current = current
    if first_cap and first_cap > 1 then
        local incomplete_start = current:sub(1, first_cap - 1):gsub("^%s+", "")
        clean_current = current:sub(first_cap)
        if #prev_tail > 0 then
            prev_tail = prev_tail .. incomplete_start
        end
    else
        prev_tail = ""
    end

    local last_dot = 0
    for i = #clean_current, 1, -1 do
        local c = clean_current:sub(i, i)
        if c == "." or c == "!" or c == "?" then
            last_dot = i
            break
        end
    end

    local incomplete_end = ""
    if last_dot > 0 and last_dot < #clean_current then
        incomplete_end = clean_current:sub(last_dot + 1):gsub("^%s+", "")
        clean_current = clean_current:sub(1, last_dot)
    end

    local parts = {}
    if #prev_tail > 0 then table.insert(parts, prev_tail) end
    if #clean_current > 0 then table.insert(parts, clean_current) end
    if #incomplete_end > 0 and #next_head > 0 then
        table.insert(parts, incomplete_end .. next_head)
    elseif #incomplete_end > 0 then
        table.insert(parts, incomplete_end)
    end

    local final_text = table.concat(parts, " ")
    if #final_text == 0 then
        self.panel_text = "No complete sentences found."
        self:refreshPanel()
        return
    end

    self.panel_text = "Translating..."
    self:refreshPanel()

    local translated, err = Translator:translate(
        final_text,
        self.config.source_lang,
        self.config.target_lang
    )

    if err then
        self.panel_text = "Error: " .. err
    else
        self.panel_text = translated or "Empty translation."
    end

    self:refreshPanel()
end

function splitread:onPageUpdate(pageno)
    if not self:isEnabledForBook() then return end
    if not self.config.auto_translate then return end
    UIManager:scheduleIn(0.5, function() self:translateCurrentPage() end)
end

function splitread:onPosUpdate(pos, pageno)
    if not self:isEnabledForBook() then return end
    if not self.config.auto_translate then return end
    UIManager:scheduleIn(0.5, function() self:translateCurrentPage() end)
end

function splitread:getPanelGearRegion()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local footer_h = self:getFooterHeight()
    local icon_size = Screen:scaleByDPI(32)
    local margin = Screen:scaleByDPI(8)
    return {
        x = screen_w - icon_size - margin,
        y = screen_h - footer_h - icon_size - margin,
        w = icon_size,
        h = icon_size,
    }
end

function splitread:showSettingsDialog()
    -- safety net: if config failed to load during init, try again now
    if not self.config then
        self.config = Config:load()
    end
    UI:showSettingsDialog(self.config, Config, function()
        self:refreshPanel()
    end)
end

function splitread:refreshPanel()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()
    local footer_h = self:getFooterHeight()
    local panel_y = screen_h - self.panel_height - footer_h
    local padding = 20

    local ok, face = pcall(function()
        return Font:getFace("cfont", self.config.font_size or 14)
    end)
    if not ok or not face then
        face = Font:getFace("cfont", 14)
    end

    local frame = FrameContainer:new{
        width = screen_w,
        height = self.panel_height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = padding,
        TextBoxWidget:new{
            text = self.panel_text,
            face = face,
            width = screen_w - (padding * 2),
            height = self.panel_height - (padding * 2) - 20,
            justified = true,
        }
    }
    frame:paintTo(Screen.bb, 0, panel_y)
    Screen.bb:paintRect(0, panel_y, screen_w, 1, Blitbuffer.COLOR_BLACK)

    local gear = self:getPanelGearRegion()
    local gear_widget = TextWidget:new{
        text = "⚙",
        face = Font:getFace("cfont", Screen:scaleByDPI(18)),
    }
    gear_widget:paintTo(Screen.bb, gear.x, gear.y)

    Screen:refreshUI(0, panel_y, screen_w, self.panel_height)
    logger.info("splitread: painted at y:", panel_y)
end

function splitread:addToMainMenu(menu_items)
    menu_items.splitread = {
        text = "splitread",
        sub_item_table = {
            {
                text_func = function()
                    return self:isEnabledForBook()
                        and "Disable for this book"
                        or "Enable for this book"
                end,
                callback = function()
                    local enabled = self:isEnabledForBook()
                    self:setEnabledForBook(not enabled)
                    if not enabled then
                        -- enabling
                        self.is_initialized = false  -- add this
                        self:onReaderReady()          -- add this
                    else
                        -- disabling — restore viewport
                        self.view.dimen.h = Screen:getHeight()
                        self.ui.dimen.h = Screen:getHeight()
                        self.ui:handleEvent(Event:new("SetDimensions", self.ui.dimen))
                        Screen.bb:paintRect(0, Screen:getHeight() - self.panel_height,
                            Screen:getWidth(), self.panel_height, Blitbuffer.COLOR_WHITE)
                        Screen:refreshUI(0, Screen:getHeight() - self.panel_height,
                            Screen:getWidth(), self.panel_height)
                    end
                end,
            },
            {
                text = "Settings",
                callback = function()
                    self:showSettingsDialog()
                end,
            },
        },
    }
end

return splitread
