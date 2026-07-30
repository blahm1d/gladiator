local applied = false

emu.register_frame_done(function()
    if applied then
        return
    end
    applied = true

    manager.machine.ioport.ports[":DSW2"].fields["Flip Screen"].user_value = 0
    manager.machine.ioport.ports[":DSW3"].fields["Service Mode"].user_value = 0
end)
