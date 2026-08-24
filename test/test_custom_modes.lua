-- Tests for the custom modes module
-- Run with: busted .

describe("prompt loader integration", function()
    local config, prompt_loader

    before_each(function()
        package.loaded["trumpify.config"] = nil
        package.loaded["trumpify.prompt_loader"] = nil
        local ok_c, c = pcall(require, "trumpify.config")
        local ok_p, p = pcall(require, "trumpify.prompt_loader")
        if not ok_c or not ok_p then pending("modules not loadable") end
        config, prompt_loader = c, p
        config.init()

        -- Stub storage so tests are independent of the user's machine;
        -- keep the real merge/validate logic.
        local custom = require("trumpify.custom_modes")
        custom._load_backup = custom.load
        custom.load = function()
            return {
                { id = "pirate", name = "Pirate", description = "Talk like a pirate",
                  system = "Arr.", key = "p" },
                { id = "broken", name = "Broken", description = "no prompt here" },
            }
        end
    end)

    after_each(function()
        local custom = require("trumpify.custom_modes")
        if custom._load_backup then
            custom.load = custom._load_backup
            custom._load_backup = nil
        end
        package.loaded["trumpify.prompt_loader"] = nil
    end)

    it("merges valid custom modes into the mode table", function()
        local errors = prompt_loader.init()
        assert.is_not_nil(prompt_loader.get_all_modes()["custom_pirate"])
        assert.is_not_nil(prompt_loader.get_all_modes()["email"])
        -- invalid entries surface as load issues but don't break anything
        assert.are_equal(1, #errors)
        assert.truthy(errors[1]:find("Broken", 1, true))
    end)

    it("shows custom modes as chooser choices", function()
        prompt_loader.init()
        local found = false
        for _, choice in ipairs(prompt_loader.get_chooser_choices()) do
            if choice.modeKey == "custom_pirate" then found = true end
        end
        assert.is_true(found)
    end)

    it("reports invalid custom modes without dropping built-ins", function()
        local custom = require("trumpify.custom_modes")
        local orig = custom.validate
        custom.validate = function(mode)
            if mode.name == "Pirate" then
                return false, "'Pirate': forced failure"
            end
            return orig(mode)
        end

        local errors = prompt_loader.init()
        assert.is_nil(prompt_loader.get_all_modes()["custom_pirate"])
        assert.is_not_nil(prompt_loader.get_all_modes()["email"])

        custom.validate = orig
    end)
end)

describe("custom modes", function()
    local custom_modes

    before_each(function()
        package.loaded["trumpify.custom_modes"] = nil
        local ok, mod = pcall(require, "trumpify.custom_modes")
        if not ok then pending("custom_modes not loadable") end
        custom_modes = mod
    end)

    describe("normalize_id", function()
        it("creates a lowercase slug", function()
            assert.are_equal("my_cool_mode", custom_modes.normalize_id("My Cool Mode"))
        end)

        it("strips special characters", function()
            assert.are_equal("fix_it_pls", custom_modes.normalize_id("Fix it, pls!"))
        end)

        it("collapses consecutive separators", function()
            assert.are_equal("a_b", custom_modes.normalize_id("A -- B"))
        end)

        it("falls back to 'mode' for empty results", function()
            assert.are_equal("mode", custom_modes.normalize_id(""))
            assert.are_equal("mode", custom_modes.normalize_id("!!!"))
            assert.are_equal("mode", custom_modes.normalize_id(nil))
        end)
    end)

    describe("validate_mode", function()
        it("accepts a complete mode", function()
            local ok, err = custom_modes.validate({
                name = "Pirate",
                description = "Talk like a pirate",
                system = "Rewrite the text as a pirate would.",
                key = "p",
            })
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("accepts a mode without hotkey", function()
            local ok, err = custom_modes.validate({
                name = "Pirate",
                description = "Talk like a pirate",
                system = "Rewrite the text as a pirate would.",
            })
            assert.is_true(ok)
            assert.is_nil(err)
        end)

        it("rejects missing name", function()
            local ok = custom_modes.validate({ description = "d", system = "s" })
            assert.is_false(ok)
        end)

        it("rejects empty name", function()
            local ok = custom_modes.validate({ name = "  ", description = "d", system = "s" })
            assert.is_false(ok)
        end)

        it("rejects missing description", function()
            local ok = custom_modes.validate({ name = "n", system = "s" })
            assert.is_false(ok)
        end)

        it("rejects missing system prompt", function()
            local ok = custom_modes.validate({ name = "n", description = "d" })
            assert.is_false(ok)
        end)

        it("rejects multi-character keys", function()
            local ok = custom_modes.validate(
                { name = "n", description = "d", system = "s", key = "xy" })
            assert.is_false(ok)
        end)

        it("rejects non-table input", function()
            assert.is_false(custom_modes.validate(nil))
            assert.is_false(custom_modes.validate("nope"))
        end)
    end)

    describe("assign_ids", function()
        it("assigns slugged ids with prefix", function()
            local list = { { name = "Pirate Talk", description = "d", system = "s" } }
            local out = custom_modes.assign_ids(list)
            assert.are_equal("pirate_talk", out[1].id)
        end)

        it("makes ids unique when slugs collide", function()
            local list = {
                { name = "Mode A!", description = "d", system = "s" },
                { name = "Mode A?", description = "d", system = "s" },
            }
            local out = custom_modes.assign_ids(list)
            assert.are_equal("mode_a", out[1].id)
            assert.are_not_equal(out[1].id, out[2].id)
        end)
    end)

    describe("json round-trip", function()
        it("encodes and decodes a mode list", function()
            local list = {
                { id = "pirate", name = "Pirate", description = "Talk like a pirate",
                  system = "Arr.", key = "p" },
                { id = "haiku", name = "Haiku", description = "Write a haiku",
                  system = "5-7-5." },
            }
            local encoded = custom_modes.encode(list)
            assert.is_string(encoded)

            local decoded, err = custom_modes.decode(encoded)
            assert.is_not_nil(decoded, err)
            assert.are_equal(2, #decoded)
            assert.are_equal("pirate", decoded[1].id)
            assert.are_equal("p", decoded[1].key)
            assert.is_nil(decoded[2].key)
        end)

        it("returns nil for invalid json", function()
            assert.is_nil(custom_modes.decode("not json {{{"))
        end)

        it("returns an empty list for non-array payloads", function()
            local decoded = custom_modes.decode('{"foo": "bar"}')
            assert.are_equal(0, #decoded)
            assert.are_equal(0, #custom_modes.decode("null"))
        end)
    end)

    describe("storage", function()
        local tmp_path

        before_each(function()
            tmp_path = os.tmpname()
        end)

        after_each(function()
            os.remove(tmp_path)
        end)

        it("saves and loads a mode list", function()
            local list = {
                { id = "pirate", name = "Pirate", description = "Talk like a pirate",
                  system = "Arr.", key = "p" },
            }
            local ok, err = custom_modes.save(tmp_path, list)
            assert.is_true(ok, err)

            local loaded = custom_modes.load(tmp_path)
            assert.are_equal(1, #loaded)
            assert.are_equal("pirate", loaded[1].id)
            assert.are_equal("Arr.", loaded[1].system)
        end)

        it("returns an empty list for a missing file", function()
            local loaded = custom_modes.load("/nonexistent/path/modes.json")
            assert.are_same({}, loaded)
        end)

        it("returns an empty list for corrupt files", function()
            local f = io.open(tmp_path, "w")
            f:write("garbage{{{")
            f:close()
            assert.are_same({}, custom_modes.load(tmp_path))
        end)

        it("reports errors when the path is not writable", function()
            local ok, err = custom_modes.save("/nonexistent/dir/x.json", {})
            assert.is_false(ok)
            assert.is_not_nil(err)
        end)
    end)

    describe("merge", function()
        local builtins

        before_each(function()
            builtins = {
                email = { name = "Email", description = "d", system = "s", key = "e" },
                summarize = { name = "Summary", description = "d", system = "s", key = "s" },
            }
        end)

        it("adds custom modes with custom_ prefix", function()
            local merged, errors = custom_modes.merge(builtins, {
                { id = "pirate", name = "Pirate", description = "d", system = "s", key = "p" },
            })
            assert.are_equal(0, #errors)
            assert.is_not_nil(merged["email"])
            assert.is_not_nil(merged["custom_pirate"])
            assert.are_equal("Pirate", merged["custom_pirate"].name)
            assert.is_true(merged["custom_pirate"].paste_back)
        end)

        it("does not mutate the builtins table", function()
            custom_modes.merge(builtins, {
                { id = "pirate", name = "Pirate", description = "d", system = "s" },
            })
            assert.is_nil(builtins["custom_pirate"])
            assert.are_equal(2, keys_of(builtins))
        end)

        it("skips custom modes whose name collides with a builtin", function()
            local merged, errors = custom_modes.merge(builtins, {
                { id = "fake_email", name = "Email", description = "d", system = "s" },
            })
            assert.is_nil(merged["custom_fake_email"])
            assert.are_equal(1, #errors)
            assert.truthy(errors[1]:find("Email", 1, true))
        end)

        it("skips customs colliding with each other", function()
            local merged, errors = custom_modes.merge(builtins, {
                { id = "a", name = "Same Name", description = "d", system = "s" },
                { id = "b", name = "Same Name", description = "d", system = "s" },
            })
            assert.is_not_nil(merged["custom_a"])
            assert.is_nil(merged["custom_b"])
            assert.are_equal(1, #errors)
        end)

        it("skips invalid custom modes and reports them", function()
            local merged, errors = custom_modes.merge(builtins, {
                { id = "broken", description = "missing everything else" },
            })
            assert.is_nil(merged["custom_broken"])
            assert.are_equal(1, #errors)
        end)
    end)
end)

function keys_of(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end
