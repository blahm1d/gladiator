-- Capture MAME's complete main-board state immediately after the diagnostic
-- first reaches 0xCBFF, completing its initial 0xC000-0xCBFF address sweep.
-- No state is patched.

local out_path = "sim/out/mame-first-sprite-pass-state.txt"
local machine = manager.machine
local screen = machine.screens[":screen"]
local maincpu = machine.devices[":maincpu"]
local main_program = maincpu.spaces["program"]
local main_io = maincpu.spaces["io"]

local taps = {}
local sprite_writes = 0
local sprite_buffer = 0
local sprite_bank = 2
local latch_value = 0
local video_attributes = 0
local captured = false
local should_exit = false

local function pc_of(device)
    local entry = device.state["CURPC"] or device.state["PC"]
    return entry and entry.value or 0
end

local function read_value(space, address, override_address, override_data)
    if address == override_address then
        return override_data & 0xff
    end
    return space:read_direct_u8(address)
end

local function range_hex(
        space, first, last, override_address, override_data)
    local values = {}
    for address = first, last do
        values[#values + 1] = string.format(
            "%02X",
            read_value(space, address, override_address, override_data))
    end
    return table.concat(values)
end

local function range_hash(
        space, first, last, override_address, override_data)
    local a = 1
    local b = 0
    for address = first, last do
        a = (a + read_value(
            space, address, override_address, override_data)) % 65521
        b = (b + a) % 65521
    end
    return ((b << 16) | a) & 0xffffffff
end

local function capture(address, data)
    local out = assert(io.open(out_path, "w"))
    out:write(string.format(
        "tick12m=%d\nframe=%d\nmain_pc=%04X\nsprite_writes=%d\n",
        machine.time:as_ticks(12000000),
        screen:frame_number(),
        pc_of(maincpu) & 0xffff,
        sprite_writes))
    out:write(string.format(
        "video_attributes=%02X\nlatch=%02X\nsprite_buffer=%d\n" ..
        "sprite_bank=%d\n",
        video_attributes,
        latch_value & 0xff,
        sprite_buffer,
        sprite_bank))
    out:write(string.format(
        "sprite_hash=%08X\nstate_hash=%08X\n",
        range_hash(main_program, 0xc000, 0xcbff, address, data),
        range_hash(main_program, 0xd000, 0xf7ff, -1, 0)))
    out:write("sprite_c000_cbff=" ..
        range_hex(main_program, 0xc000, 0xcbff, address, data) .. "\n")
    out:write("state_d000_f7ff=" ..
        range_hex(main_program, 0xd000, 0xf7ff, -1, 0) .. "\n")
    out:close()
    captured = true
    should_exit = true
end

taps[#taps + 1] = main_io:install_write_tap(
    0xc000,
    0xc007,
    "gladiatr-first-sprite-pass-latch",
    function(offset, data, mask)
        local bit = offset & 7
        local value = data & 1
        if value ~= 0 then
            latch_value = latch_value | (1 << bit)
        else
            latch_value = latch_value & (~(1 << bit))
        end
        if bit == 0 then
            sprite_buffer = value
        elseif bit == 1 then
            sprite_bank = value ~= 0 and 4 or 2
        end
    end)

taps[#taps + 1] = main_program:install_write_tap(
    0xcc80,
    0xcc80,
    "gladiatr-first-sprite-pass-attribute",
    function(offset, data, mask)
        video_attributes = data & 0xff
    end)

taps[#taps + 1] = main_program:install_write_tap(
    0xc000,
    0xcbff,
    "gladiatr-first-sprite-pass-writes",
    function(offset, data, mask)
        if captured then
            return
        end
        sprite_writes = sprite_writes + 1
        if offset == 0xcbff then
            capture(offset, data)
        end
    end)

emu.register_frame_done(function()
    for _, tap in ipairs(taps) do
        tap:reinstall()
    end
    if should_exit then
        machine:exit()
    end
end)
