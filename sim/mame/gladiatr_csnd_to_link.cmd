focus :sub
observe :maincpu
wpi 20,2,r,1,{printf "CSND,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 20,2,w,1,{printf "CSND,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
bp 08e6:maincpu,1,{quit}
g
