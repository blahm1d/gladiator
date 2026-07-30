-- Deterministic board-observable Gladiator trace.
--
-- This is intentionally an oracle capture, not an implementation model.
-- MAME supplies the CPU/MCU/device behavior; the trace records the buses and
-- physical sprite-list state that the FPGA must reproduce.

local out_dir = "sim/out"
local stop_frame = tonumber(os.getenv("GLADIATR_TRACE_FRAMES") or "3600")
local snapshot_period = tonumber(
    os.getenv("GLADIATR_SNAPSHOT_PERIOD") or "60")
local screenshot_period = tonumber(
    os.getenv("GLADIATR_SCREENSHOT_PERIOD") or "300")
local starting_stage = tonumber(os.getenv("GLADIATR_START_STAGE") or "1")
-- ATTRACT MODE: inject NO cabinet inputs and leave the DIPs at factory
-- defaults, so the machine runs its own attract cycle. The scripted run
-- coins up at frame 360 and therefore never shows the title screen -- which
-- is exactly the screen reported missing on the cabinet, and which no gate
-- has ever had a reference image for.
local attract_only = (os.getenv("GLADIATR_ATTRACT") or "0") ~= "0"
local trace_until_frame = tonumber(
    os.getenv("GLADIATR_TRACE_UNTIL_FRAME") or tostring(stop_frame))

local machine = manager.machine
local screen = machine.screens[":screen"]
local maincpu = machine.devices[":maincpu"]
local soundcpu = machine.devices[":sub"]
local audiocpu = machine.devices[":audiocpu"]
local main_program = maincpu.spaces["program"]
local main_io = maincpu.spaces["io"]
local sound_program = soundcpu.spaces["program"]
local sound_io = soundcpu.spaces["io"]
local audio_program = audiocpu.spaces["program"]

local events = assert(io.open(out_dir .. "/mame-full-events.csv", "w"))
local frames = assert(io.open(out_dir .. "/mame-full-frames.csv", "w"))
local sprites = assert(io.open(out_dir .. "/mame-sprite-snapshots.csv", "w"))
local states = assert(io.open(out_dir .. "/mame-state-snapshots.csv", "w"))

events:write(
    "tick12m,frame,domain,kind,address,data,pc,count,last_tick12m\n")
frames:write(
    "frame,main_pc,sound_pc,audio_pc,main_work_hash,nvram_hash," ..
    "sprite_hash,nonzero_sprite_bytes,sprite_buffer,sprite_bank," ..
    "video_attributes,stage_select_state,scene_state\n")
sprites:write(
    "frame,sprite_buffer,sprite_bank,video_attributes,sprite_ram_hex\n")
states:write("frame,main_ram_d000_f7ff_hex\n")
events:flush()
frames:flush()
sprites:flush()
states:flush()

local taps = {}
local frame_number = 0
local sprite_buffer = 0
local sprite_bank = 2
local video_attributes = 0
local ym_register = 0
local read_counts = {}

local function tick12m()
    return machine.time:as_ticks(12000000)
end

local function pc_of(device)
    local entry = device.state["CURPC"] or device.state["PC"]
    return entry and entry.value or 0
end

local function log_event(domain, kind, address, data, device)
    if frame_number > trace_until_frame then
        return
    end
    local tick = tick12m()
    events:write(string.format(
        "%d,%d,%s,%s,%04X,%02X,%04X,1,%d\n",
        tick,
        frame_number,
        domain,
        kind,
        address & 0xffff,
        data & 0xff,
        pc_of(device) & 0xffff,
        tick))
end

local function count_read(domain, address, data, device)
    if frame_number > trace_until_frame then
        return
    end
    local pc = pc_of(device) & 0xffff
    local tick = tick12m()
    local key = string.format(
        "%s,%04X,%02X,%04X", domain, address & 0xffff, data & 0xff, pc)
    local entry = read_counts[key]
    if entry then
        entry.count = entry.count + 1
        entry.last_tick = tick
    else
        read_counts[key] = {
            domain = domain,
            address = address & 0xffff,
            data = data & 0xff,
            pc = pc,
            count = 1,
            first_tick = tick,
            last_tick = tick
        }
    end
end

local function flush_read_counts()
    local keys = {}
    for key, _ in pairs(read_counts) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local entry = read_counts[key]
        events:write(string.format(
            "%d,%d,%s,read_count,%04X,%02X,%04X,%d,%d\n",
            entry.first_tick,
            frame_number,
            entry.domain,
            entry.address,
            entry.data,
            entry.pc,
            entry.count,
            entry.last_tick))
    end
    read_counts = {}
end

local function add_write_tap(space, first, last, name, domain, device)
    taps[#taps + 1] = space:install_write_tap(
        first,
        last,
        name,
        function(offset, data, mask)
            log_event(domain, "write", offset, data, device)
        end)
end

local function add_read_tap(space, first, last, name, domain, device)
    taps[#taps + 1] = space:install_read_tap(
        first,
        last,
        name,
        function(offset, data, mask)
            count_read(domain, offset, data, device)
        end)
end

-- Main-board RAM visible to the renderer and progression logic.
taps[#taps + 1] = main_program:install_write_tap(
    0xc000,
    0xffff,
    "gladiatr-main-state-write",
    function(offset, data, mask)
        log_event("main_mem", "write", offset, data, maincpu)
        if (offset == 0xcc80) then
            video_attributes = data & 0xff
        end
    end)

-- Main LS259 and host link to the UCPU.
-- ORDERED ucpu host-port log. The main CPU's ONLY external input during
-- attract is C09E/C09F (measured: 36,060 + 99,102 reads, nothing else), so the
-- ucpu decides everything the game does -- including whether it reaches the
-- title screen. The generic read tap AGGREGATES by (addr,data,pc) and loses
-- ordering, which is exactly what a protocol replay needs.
local ucpu_log = assert(io.open(out_dir .. "/mame-ucpu-host.csv", "w"))
ucpu_log:write("tick12m,frame,dir,a0,data,pc\n")
local function ucpu_event(dir, offset, data)
    if frame_number > trace_until_frame then return end
    ucpu_log:write(string.format("%d,%d,%s,%d,%02X,%04X\n",
        tick12m(), frame_number, dir, offset & 1, data & 0xff,
        pc_of(maincpu) & 0xffff))
end
taps[#taps + 1] = main_io:install_read_tap(0xc09e, 0xc09f, "ucpu-host-r",
    function(offset, data, mask) ucpu_event("R", offset, data) end)
taps[#taps + 1] = main_io:install_write_tap(0xc09e, 0xc09f, "ucpu-host-w",
    function(offset, data, mask) ucpu_event("W", offset, data) end)

taps[#taps + 1] = main_io:install_write_tap(
    0xc000,
    0xc09f,
    "gladiatr-main-io-write",
    function(offset, data, mask)
        log_event("main_io", "write", offset, data, maincpu)
        local port = offset & 0xffff
        if port >= 0xc000 and port <= 0xc007 then
            local bit = port & 7
            local value = data & 1
            if bit == 0 then
                sprite_buffer = value
            elseif bit == 1 then
                sprite_bank = value ~= 0 and 4 or 2
            end
        end
    end)
add_read_tap(
    main_io, 0xc09e, 0xc09f, "gladiatr-main-io-read",
    "main_io", maincpu)

-- Sound Z80 RAM, YM2203, all four MCU hosts, filter latch and ADPCM command.
add_write_tap(
    sound_program, 0x8000, 0x83ff, "gladiatr-sound-ram-write",
    "sound_mem", soundcpu)
add_read_tap(
    sound_io, 0x00, 0xe0, "gladiatr-sound-io-read",
    "sound_io", soundcpu)
taps[#taps + 1] = sound_io:install_write_tap(
    0x00,
    0xe0,
    "gladiatr-sound-io-write",
    function(offset, data, mask)
        local port = offset & 0xff
        log_event("sound_io", "write", port, data, soundcpu)
        if port == 0x00 then
            ym_register = data & 0xff
        elseif port == 0x01 then
            log_event(
                "ym2203", "register", ym_register, data, soundcpu)
        end
    end)

-- The 6809 presents the nibble, reset, VCLK and sample-ROM bank on one port.
add_write_tap(
    audio_program, 0x1000, 0x1fff, "gladiatr-adpcm-pin-write",
    "adpcm", audiocpu)
add_read_tap(
    audio_program, 0x2000, 0x2fff, "gladiatr-adpcm-command-read",
    "adpcm", audiocpu)

local ports = machine.ioport.ports
local input = {
    right = assert(ports[":IN0"]:field(0x01)),
    left = assert(ports[":IN0"]:field(0x02)),
    up = assert(ports[":IN0"]:field(0x04)),
    down = assert(ports[":IN0"]:field(0x08)),
    button1 = assert(ports[":IN0"]:field(0x10)),
    button2 = assert(ports[":IN0"]:field(0x20)),
    start1 = assert(ports[":IN0"]:field(0x40)),
    button3 = assert(ports[":IN2"]:field(0x40)),
    coin1 = assert(ports[":COINS"]:field(0x02))
}

-- Keep the deterministic run alive long enough to cross stages.  The DIP
-- assignments are MAME input values, not fabricated memory patches.
-- Factory default for SW3:1 is OFF (0x01). The scripted run forces it ON to
-- survive unattended play; attract must NOT, or the capture stops matching
-- what the cabinet actually has set.
ports[":DSW3"]:field(0x01).user_value = attract_only and 0x01 or 0x00
local stage_dip = ({0x0c, 0x08, 0x04, 0x00})[starting_stage]
assert(stage_dip, "GLADIATR_START_STAGE must be 1 through 4")
ports[":DSW3"]:field(0x0c).user_value = stage_dip
ports[":DSW3"]:field(0x80).user_value = 0x80 -- service mode off
ports[":DSW2"]:field(0x80).user_value = 0x80 -- normal monitor orientation

local function set_input(field, active)
    field:set_value(active and 1 or 0)
end

local function drive_inputs(frame)
    if attract_only then
        set_input(input.coin1, false)
        set_input(input.start1, false)
        set_input(input.right, false)   set_input(input.left, false)
        set_input(input.up, false)      set_input(input.down, false)
        set_input(input.button1, false) set_input(input.button2, false)
        set_input(input.button3, false)
        return
    end
    -- Boot diagnostics finish at roughly frame 280 on a clean NVRAM image.
    -- Insert/start after the title hardware is accepting cabinet inputs.
    set_input(input.coin1, frame >= 360 and frame < 364)
    set_input(input.start1, frame >= 420 and frame < 424)

    local playing = frame >= 480
    local phase = playing and ((frame - 480) % 240) or 0
    set_input(input.right, playing and phase < 190)
    set_input(input.left, playing and phase >= 210)
    set_input(input.up, playing and ((frame - 480) % 180) < 8)
    set_input(input.down, false)
    set_input(input.button1, playing and ((frame - 480) % 30) < 4)
    set_input(input.button2, playing and ((frame - 495) % 45) < 4)
    set_input(input.button3, playing and ((frame - 510) % 90) < 4)
end

local function range_hash(space, first, last)
    -- Adler-like pair is deterministic in Lua without relying on native
    -- integer overflow behavior.
    local a = 1
    local b = 0
    for address = first, last do
        a = (a + space:read_direct_u8(address)) % 65521
        b = (b + a) % 65521
    end
    return ((b << 16) | a) & 0xffffffff
end

local function sprite_state()
    local values = {}
    local nonzero = 0
    local a = 1
    local b = 0
    for offset = 0, 0xbff do
        local value = main_program:read_direct_u8(0xc000 + offset)
        values[#values + 1] = string.format("%02X", value)
        if value ~= 0 then
            nonzero = nonzero + 1
        end
        a = (a + value) % 65521
        b = (b + a) % 65521
    end
    return table.concat(values), (((b << 16) | a) & 0xffffffff), nonzero
end

local function range_hex(space, first, last)
    local values = {}
    for address = first, last do
        values[#values + 1] = string.format(
            "%02X", space:read_direct_u8(address))
    end
    return table.concat(values)
end

local closed = false
local function close_outputs()
    if closed then
        return
    end
    closed = true
    events:flush()
    frames:flush()
    sprites:flush()
    states:flush()
    events:close()
    ucpu_log:close()
    frames:close()
    sprites:close()
    states:close()
end

emu.register_stop(close_outputs)

emu.register_frame_done(function()
    frame_number = screen:frame_number()
    flush_read_counts()

    -- MAME may replace memory handlers while the driver finishes reset and
    -- configures its banks.  Pass-through taps are displaced by that action;
    -- reinstalling them at the frame boundary keeps the trace live without
    -- changing any emulated bus value.
    for _, tap in ipairs(taps) do
        tap:reinstall()
    end

    drive_inputs(frame_number)

    if (frame_number % snapshot_period) == 0 then
        local sprite_hex, sprite_hash, nonzero = sprite_state()
        local main_hash = range_hash(main_program, 0xd000, 0xefff)
        local nvram_hash = range_hash(main_program, 0xf000, 0xf7ff)
        frames:write(string.format(
            "%d,%04X,%04X,%04X,%08X,%08X,%08X,%d,%d,%d,%02X,%02X,%02X\n",
            frame_number,
            pc_of(maincpu) & 0xffff,
            pc_of(soundcpu) & 0xffff,
            pc_of(audiocpu) & 0xffff,
            main_hash,
            nvram_hash,
            sprite_hash,
            nonzero,
            sprite_buffer,
            sprite_bank,
            video_attributes,
            main_program:read_direct_u8(0xf6a2),
            main_program:read_direct_u8(0xf440)))
        sprites:write(string.format(
            "%d,%d,%d,%02X,%s\n",
            frame_number,
            sprite_buffer,
            sprite_bank,
            video_attributes,
            sprite_hex))
        states:write(string.format(
            "%d,%s\n",
            frame_number,
            range_hex(main_program, 0xd000, 0xf7ff)))
        events:flush()
        frames:flush()
        sprites:flush()
        states:flush()
    end

    if (frame_number % screenshot_period) == 0 then
        screen:snapshot(string.format("frame-%05d.png", frame_number))
    end

    if frame_number >= stop_frame then
        close_outputs()
        machine:exit()
    end
end)
