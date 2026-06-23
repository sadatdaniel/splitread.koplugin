local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local logger = require("logger")

local Config = {}

local config_path = DataStorage:getSettingsDir() .. "/splitread.lua"

local defaults = {
    api_key = "",
    source_lang = "auto",
    target_lang = "en",
    panel_height_ratio = 0.50,
    auto_translate = true,
    font_size = 14,
}

function Config:load()
    local ok, settings = pcall(function()
        return LuaSettings:open(config_path)
    end)
    if not ok or not settings then
        logger.info("splitread config: using defaults")
        local result = {}
        for k, v in pairs(defaults) do result[k] = v end
        return result
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = settings:readSetting(k) or v
    end
    return result
end

function Config:save(data)
    local ok, settings = pcall(function()
        return LuaSettings:open(config_path)
    end)
    if not ok or not settings then
        logger.info("splitread config: failed to open settings file")
        return false
    end
    for k, v in pairs(data) do
        settings:saveSetting(k, v)
    end
    settings:flush()
    logger.info("splitread config: saved")
    return true
end

return Config
