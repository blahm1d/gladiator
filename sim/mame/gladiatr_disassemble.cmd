focus :maincpu
dasm sim/out/mame-main.dasm,0000,ffff
focus :audiocpu
dasm sim/out/mame-sound.dasm,0000,3fff
focus :ucpu
dasm sim/out/mame-ucpu.dasm,000,3ff
focus :csnd
dasm sim/out/mame-csnd.dasm,000,7ff
quit
