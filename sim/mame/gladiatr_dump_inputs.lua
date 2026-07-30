local done = false

emu.register_frame_done(function()
    if done then
        return
    end
    done = true

    for _, tag in ipairs({":DSW1", ":DSW2", ":DSW3"}) do
        local port = manager.machine.ioport.ports[tag]
        print(string.format("%s read=%02X", tag, port:read()))
        for _, field in pairs(port.fields) do
            print(string.format(
                "  mask=%02X name=%s def=%02X user=%02X",
                field.mask,
                field.name,
                field.defvalue,
                field.user_value))
        end
    end
end)
