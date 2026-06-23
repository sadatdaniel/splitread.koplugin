local UIManager = require("ui/uimanager")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local logger = require("logger")

local LANGUAGES = {
    { code = "auto", name = "Auto detect" },
    { code = "de",   name = "German" },
    { code = "en",   name = "English" },
    { code = "fr",   name = "French" },
    { code = "es",   name = "Spanish" },
    { code = "it",   name = "Italian" },
    { code = "pt",   name = "Portuguese" },
    { code = "nl",   name = "Dutch" },
    { code = "pl",   name = "Polish" },
    { code = "ru",   name = "Russian" },
    { code = "ja",   name = "Japanese" },
    { code = "zh",   name = "Chinese" },
    { code = "ar",   name = "Arabic" },
    { code = "tr",   name = "Turkish" },
    { code = "ko",   name = "Korean" },
}

local FONT_SIZES = {10, 12, 14, 16, 18, 20, 22}

local PANEL_SIZES = {
    { ratio = 0.25, name = "Small (25%)" },
    { ratio = 0.35, name = "Medium (35%)" },
    { ratio = 0.45, name = "Large (45%)" },
}


local UI = {}

function UI:getLanguageName(code)
    for _, lang in ipairs(LANGUAGES) do
        if lang.code == code then
            return lang.name
        end
    end
    return code:upper()
end

function UI:getPanelSizeName(ratio)
    for _, size in ipairs(PANEL_SIZES) do
        if size.ratio == ratio then
            return size.name
        end
    end
    return tostring(math.floor(ratio * 100)) .. "%"
end

function UI:showLanguagePicker(title, current_code, on_select, on_done)
    local picker_dialog
    local buttons = {}
    for _, lang in ipairs(LANGUAGES) do
        local is_current = lang.code == current_code
        table.insert(buttons, {
            {
                text = (is_current and "✓ " or "  ") .. lang.name,
                callback = function()
                    UIManager:close(picker_dialog)
                    on_select(lang.code)
                    on_done()
                end,
            }
        })
    end
    picker_dialog = ButtonDialogTitle:new{
        title = title,
        buttons = buttons,
    }
    UIManager:show(picker_dialog)
end

function UI:showFontSizePicker(current_size, on_select, on_done)
    local font_dialog
    local buttons = {}

    table.insert(buttons, {
        {
            text = "⚠ Larger fonts may cut off translation text",
            callback = function() end,
        }
    })

    for _, size in ipairs(FONT_SIZES) do
        local is_current = size == current_size
        table.insert(buttons, {
            {
                text = (is_current and "✓ " or "  ") .. tostring(size) .. " pt",
                callback = function()
                    UIManager:close(font_dialog)
                    on_select(size)
                    on_done()
                end,
            }
        })
    end

    font_dialog = ButtonDialogTitle:new{
        title = "Translation Font Size",
        buttons = buttons,
    }
    UIManager:show(font_dialog)
end

function UI:showPanelSizePicker(current_ratio, on_select, on_done)
    local panel_dialog
    local buttons = {}

    table.insert(buttons, {
        {
            text = "⚠ Reopen book to apply panel size change",
            callback = function() end,
        }
    })

    for _, size in ipairs(PANEL_SIZES) do
        local is_current = size.ratio == current_ratio
        table.insert(buttons, {
            {
                text = (is_current and "✓ " or "  ") .. size.name,
                callback = function()
                    UIManager:close(panel_dialog)
                    on_select(size.ratio)
                    on_done()
                end,
            }
        })
    end

    panel_dialog = ButtonDialogTitle:new{
        title = "Panel Size",
        buttons = buttons,
    }
    UIManager:show(panel_dialog)
end

function UI:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
    logger.info("splitread: showSettingsDialog called")

    if self.current_dialog then
        UIManager:close(self.current_dialog)
        self.current_dialog = nil
    end

    UIManager:scheduleIn(0.1, function()
        local dialog
        dialog = ButtonDialogTitle:new{
            title = "splitread Settings",
            buttons = {
                {
                    {
                        text = "Source: " .. self:getLanguageName(config.source_lang),
                        callback = function()
                            UIManager:close(dialog)
                            self:showLanguagePicker(
                                "Source Language",
                                config.source_lang,
                                function(code)
                                    config.source_lang = code
                                    Config:save(config)
                                end,
                                function()
                                    self:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
                                end
                            )
                        end,
                    },
                },
                {
                    {
                        text = "Target: " .. self:getLanguageName(config.target_lang),
                        callback = function()
                            UIManager:close(dialog)
                            self:showLanguagePicker(
                                "Target Language",
                                config.target_lang,
                                function(code)
                                    config.target_lang = code
                                    Config:save(config)
                                end,
                                function()
                                    self:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
                                end
                            )
                        end,
                    },
                },
                {
                    {
                        text = "Auto-translate: " .. (config.auto_translate and "ON" or "OFF"),
                        callback = function()
                            config.auto_translate = not config.auto_translate
                            Config:save(config)
                            UIManager:close(dialog)
                            self:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
                        end,
                    },
                },
                {
                    {
                        text = "Font size: " .. tostring(config.font_size) .. " pt",
                        callback = function()
                            UIManager:close(dialog)
                            self:showFontSizePicker(
                                config.font_size,
                                function(size)
                                    config.font_size = size
                                    Config:save(config)
                                end,
                                function()
                                    self:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
                                end
                            )
                        end,
                    },
                },
                {
                    {
                        text = "Panel size: " .. self:getPanelSizeName(config.panel_height_ratio),
                        callback = function()
                            UIManager:close(dialog)
                            self:showPanelSizePicker(
                                config.panel_height_ratio,
                                function(ratio)
                                    config.panel_height_ratio = ratio
                                    Config:save(config)
                                    if on_panel_resize then
                                        on_panel_resize(ratio)
                                    end
                                end,
                                function()
                                    self:showSettingsDialog(config, Config, on_refresh, on_panel_resize)
                                end
                            )
                        end,
                    },
                },
                {
                    {
                        text = "Close",
                        callback = function()
                            UIManager:close(dialog)
                            self.current_dialog = nil
                            
                        end,
                    },
                },
            },
        }
        self.current_dialog = dialog
        UIManager:show(dialog)
    end)
end

return UI