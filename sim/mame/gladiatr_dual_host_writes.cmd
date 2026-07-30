focus :maincpu
observe :sub
wpi c09e,2,w,1,{printf "MAIN,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
focus :sub
observe :maincpu
wpi 20,2,w,1,{printf "SOUND,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
bp 086b:maincpu,1,{quit}
g
