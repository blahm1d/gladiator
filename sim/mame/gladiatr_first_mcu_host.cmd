focus :maincpu
wpi c09e,2,w,1,{printf "FIRST_UCPU_WRITE pc=%04X port=%04X data=%02X\n",pc,wpaddr,wpdata ; time ; quit}
g
