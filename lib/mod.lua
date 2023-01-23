local mod = require 'core/mods'
local matrix = require('matrix/lib/matrix')
local nb = require("nbin/lib/nb/lib/nb")


mod.hook.register('script_pre_init', 'nbin pre init', function()
    local midi_device = {} -- container for connected midi devices
    local midi_device_names = {"none"}
    local target = nil

    local old_event = nil

    local notes = {}

    local function process_midi(data)
        local p = params:lookup_param("nb_in_voice"):get_player()
        local d = midi.to_msg(data)

        if d.type == "note_on" then
            p:note_on(d.note, d.vel/127)
            notes[d.note] = p
        elseif d.type == "note_off" then
            if notes[d.note] ~= nil then
                notes[d.note]:note_off(d.note)
                notes[d.note] = nil
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

    for i = 1,#midi.vports do -- query all ports
        midi_device[i] = midi.connect(i) -- connect each device
        table.insert(midi_device_names,"port "..i..": "..util.trim_string_to_width(midi_device[i].name,40)) -- register its name
    end    
    matrix:add_post_init_hook(function()
        nb:init()
        params:add_separator("nb midi in", "nb midi in")
        params:add_option("nb in midi source", "midi source",midi_device_names,1,false)
        params:set_action("nb in midi source", midi_target)  
        nb:add_param("nb_in_voice", "voice")
    end)
end)