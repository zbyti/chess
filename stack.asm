; Chess
; Atari 2600 Chess display system
; Copyright (c) 2019-2020 Andrew Davie
; andrew@taswegian.com


RESERVED_FOR_STACK              = 12               ; bytes guaranteed not overwritten by variable use

                ds RESERVED_FOR_STACK

; WARNING/NOTE - the alphabeta search violates the above size constraints
; HOWEVER, the "OVERLAY" segment is beneath this, and will be stomped, depending on # plys
;  but since overlay is not generally stressed during alphabeta, we're good.
