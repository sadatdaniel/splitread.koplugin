local logger = require("logger")
local NetworkMgr = require("ui/network/manager")

local Translator = {}

function Translator:isNetworkAvailable()
    return NetworkMgr:isConnected()
end

function Translator:translate(text, source_lang, target_lang)
    if not text or #text == 0 then
        return nil, "No text to translate"
    end

    local ok, result = pcall(function()
        local KOTranslator = require("ui/translator")
        -- loadPage returns decoded JSON table
        local data = KOTranslator:loadPage(text, target_lang:lower(), source_lang:lower())
        if not data then return nil end
        -- extract translated text from Google Translate JSON response
        -- structure: data[1] is array of translation segments
        local translated = {}
        if data[1] then
            for _, segment in ipairs(data[1]) do
                if segment[1] then
                    table.insert(translated, segment[1])
                end
            end
        end
        return table.concat(translated, "")
    end)

    if not ok or not result then
        logger.info("splitread translator: failed:", tostring(result))
        return nil, "Translation failed: " .. tostring(result)
    end

    logger.info("splitread translator: success, length:", #result)
    return result, nil
end

return Translator
