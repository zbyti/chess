; Chess
; Atari 2600 Chess display system
; Copyright (c) 2019-2020 Andrew Davie
; andrew@taswegian.com

;---------------------------------------------------------------------------------------------------
; OVERLAYS!
; These variables are overlays, and should be managed with care
; They co-exist (each "OVERLAY" starts at the zero-page variable "Overlay"
; and thus, overlays cannot be used at the same time (that is, you cannot
; use a variable in overlay #1 while at the same time using a variable in
; overlay #2

; for clarity, prefix ALL overlay variables with double-underscore (__)

; TOTAL SPACE USED BY ANY OVERLAY GROUP SHOULD BE <= SIZE OF 'Overlay'
; ensure this by using the VALIDATE_OVERLAY macro
;---------------------------------------------------------------------------------------------------

    MAC OVERLAY ; {name}
OVERLAY_NAME SET {1}
    SEG.U OVERLAY_{1}
        org Overlay
    ENDM

;---------------------------------------------------------------------------------------------------

    MAC VALIDATE_OVERLAY
        LIST OFF
OVERLAY_DELTA SET * - Overlay
        IF OVERLAY_DELTA > MAXIMUM_REQUIRED_OVERLAY_SIZE
MAXIMUM_REQUIRED_OVERLAY_SIZE SET OVERLAY_DELTA
        ENDIF
        IF OVERLAY_DELTA > OVERLAY_SIZE
            ECHO "Overlay", OVERLAY_NAME, "is too big!"
            ECHO "REQUIRED SIZE =", OVERLAY_DELTA
            ERR
        ENDIF
        LIST ON
        ECHO OVERLAY_NAME, "-", OVERLAY_SIZE - ( * - Overlay ), "bytes available"
    ENDM

;---------------------------------------------------------------------------------------------------

OVERLAY_SIZE    SET $4C           ; maximum size
MAXIMUM_REQUIRED_OVERLAY_SIZE       SET 0


; This overlay variable is used for the overlay variables.  That's OK.
; However, it is positioned at the END of the variables so, if on the off chance we're overlapping
; stack space and variable, it is LIKELY that that won't be a problem, as the temp variables
; (especially the latter ones) are only used in rare occasions.

; FOR SAFETY, DO NOT USE THIS AREA DIRECTLY (ie: NEVER reference 'Overlay' in the code)
; ADD AN OVERLAY FOR EACH ROUTINE'S USE, SO CLASHES CAN BE EASILY CHECKED

    DEF Overlay
    ds OVERLAY_SIZE       ;--> overlay (share) variables
END_OF_OVERLAY

;---------------------------------------------------------------------------------------------------
; And now... the overlays....

    ECHO "---- OVERLAYS (", OVERLAY_SIZE, "bytes ) ----"

;---------------------------------------------------------------------------------------------------

    ; Some overlays are used across multiple routines/calls, and they will need to be defined
    ; "globally" in this file.

    VAR __pieceShapeBuffer, PIECE_SHAPE_SIZE
    VAR __ptr, 2
    VAR __ptr2, 2

;---------------------------------------------------------------------------------------------------


    ORG END_OF_OVERLAY
    ECHO "---- END OF OVERLAYS ----"
    ECHO "MAXIMUM OVERLAY SIZE NEEDED = ", MAXIMUM_REQUIRED_OVERLAY_SIZE

;EOF
