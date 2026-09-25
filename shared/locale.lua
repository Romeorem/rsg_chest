-- Choix de la langue. Une clé absente dans la langue choisie retombe sur le français.
local fallback = Locales['fr'] or {}
local chosen = Locales[Config.Locale] or fallback

Config.Text = setmetatable(chosen, {
    __index = function(_, key)
        return fallback[key] or key
    end,
})
