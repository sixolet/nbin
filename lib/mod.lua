local mod = require 'core/mods'
local matrix = require('matrix/lib/matrix')
local nb = require("nbin/lib/nb/lib/nb")


mod.hook.register('script_pre_init', 'nbin pre init', function()
    local midi_device = {} -- container for connected midi devices
    local midi_device_names = { "none" }
    local target = nil

    local old_event = nil

    local notes = {}
    for i = 0, 16 do
        notes[i] = {}
    end

    local function process_midi(data)
        local p = params:lookup_param("nb_in_voice"):get_player()
        local d = midi.to_msg(data)

        if d.type == "note_on" then
            p:note_on(d.note, d.vel / 127)
            notes[d.ch][d.note] = p
        elseif d.type == "note_off" then
            if notes[d.ch][d.note] ~= nil then
                notes[d.ch][d.note]:note_off(d.note)
                notes[d.ch][d.note] = nil
            end
        elseif d.type == "pitchbend" then
            local bend_st = (util.round(d.val / 2)) / 8192 * 2 - 1 -- Convert to -1 to 1
            for n, p2 in pairs(notes[d.ch]) do
                p2:pitch_bend(n, bend_st * params:get("nb in pitch bend range"))
            end
        elseif d.type == "channel_pressure" then
            local normalized = d.val / 127
            local normalized2 = 2 * util.clamp(normalized - 0.5, 0, 0.5)
            normalized2 = normalized2 * params:get("nb_in_pressure_2_sens")
            local key1 = params:string("nb_in_pressure_1")
            local key2 = params:string("nb_in_pressure_2")

            for n, p2 in pairs(notes[d.ch]) do
                if key1 ~= "none" then
                    p2:modulate_note(n, key1, normalized)
                end
                if key2 ~= "none" then
                    p2:modulate_note(n, key2, normalized2)
                end
            end
        elseif d.type == "key_pressure" then
            local normalized = d.val / 127
            local normalized2 = 2 * util.clamp(normalized - 0.5, 0, 0.5)
            normalized2 = normalized2 * params:get("nb_in_pressure_2_sens")
            local key1 = params:string("nb_in_pressure_1")
            local key2 = params:string("nb_in_pressure_2")
            if notes[d.ch][d.note] ~= nil then
                local p2 = notes[d.ch][d.note]
                if key1 ~= "none" then
                    p2:modulate_note(n, key1, normalized)
                end
                if key2 ~= "none" then
                    p2:modulate_note(n, key2, normalized2)
                end
            end
        end
    end

    local function midi_target(x)
        if x > 1 then
            if target ~= nil then
                midi_device[target].event = old_event
            end
            target = x - 1
            old_event = midi_device[target].event
            midi_device[target].event = process_midi
        else
            if target ~= nil then
                midi_device[target].event = old_event
            end
            target = nil
        end
    end

    for i = 1, #midi.vports do -- query all ports
        midi_device[i] = midi.connect(i) -- connect each device
        table.insert(midi_device_names, "port " .. i .. ": " .. util.trim_string_to_width(midi_device[i].name, 40)) -- register its name
    end
    matrix:add_post_init_hook(function()
        local set_up = false
        nb:init()
        params:add_separator("nb midi in", "nb midi in")
        params:add_option("nb in midi source", "midi source", midi_device_names, 1, false)
        params:add_number("nb in pitch bend range", "bend range", 2, 24, 12)
        params:set_action("nb in midi source", midi_target)
        clock.run(function()
            clock.sleep(0.5)
            params:lookup_param("nb in midi source"):bang()
            params:lookup_param("nb_in_voice"):bang()
            set_up = true
        end)
        nb:add_param("nb_in_voice", "voice")
        params:add_option("nb_in_pressure_1", "pressure", { "none", "none", "none", "none", "none" }, 1)
        params:add_option("nb_in_pressure_2", "more pressure", { "none", "none", "none", "none", "none" }, 1)
        params:add_control("nb_in_pressure_2_sens", "more pressure sensitivity", controlspec.BIPOLAR)
        local pressures = {
            params:lookup_param("nb_in_pressure_1"),
            params:lookup_param("nb_in_pressure_2")
        }
        local action = params:lookup_param("nb_in_voice").action
        params:set_action("nb_in_voice", function(x)
            action(x)
            local player = params:lookup_param("nb_in_voice"):get_player()
            for _, pressure in pairs(pressures) do
                if set_up then
                    pressure:set(1)
                end
                local options = { "none" }
                if player:describe().note_mod_targets ~= nil then
                    for _, target in ipairs(player:describe().note_mod_targets) do
                        table.insert(options, target)
                    end
                end
                pressure.options = options
                pressure.count = tab.count(options)
            end
            _menu.rebuild_params()
        end)

    end)
end)
