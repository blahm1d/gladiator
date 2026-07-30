trackpc 1,:ucpu,1
trackpc 1,:csnd,1
focus :maincpu
bp 086b
g
focus :ucpu
printf "MAME_UCPU pc=%03X a=%02X p1=%02X p2=%02X sts=%02X\n",pc,a,p1,p2,sts
history ,24
focus :csnd
printf "MAME_CSND pc=%03X a=%02X p1=%02X p2=%02X sts=%02X\n",pc,a,p1,p2,sts
history ,24
time
quit
