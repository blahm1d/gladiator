focus :sub
observe :maincpu
wpi 20,2,r,1,{printf "CSND,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 20,2,w,1,{printf "CSND,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 60,2,r,1,{printf "CCTL,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 60,2,w,1,{printf "CCTL,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 80,2,r,1,{printf "CCPU,R,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
wpi 80,2,w,1,{printf "CCPU,W,%04X,%02X,%04X\n",wpaddr,wpdata,pc ; g}
bp 086b:maincpu,1,{quit}
g
