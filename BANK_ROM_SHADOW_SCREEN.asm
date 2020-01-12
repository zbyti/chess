
                NEWBANK BANK_ROM_SHADOW_OF_CHESS_BITMAP

; Template bank for a SINGLE ROW of the chessboard display.
; There are 8x of these.
; The bank contains the definition of the bitmap, and also the code to draw the bitmap
; The bank is copied from ROM into RAM at startup.
; The draw switches between consecutive row banks, with the last returning
; we effectively have 1K
;---------------------------------------------------------------------------------------------------

ROW_BITMAP_SIZE = 6 * 24            ; PF0/PF1/PF2/(PF0)/(PF1)/(PF2) x 8 ICC pixels

    OPTIONAL_PAGEBREAK ChessBitmap, ROW_BITMAP_SIZE

ChessBitmap
ChessBitmap0    ds 24
ChessBitmap1    ds 24
ChessBitmap2    ds 24
ChessBitmap3    ds 24
ChessBitmap4    ds 24
ChessBitmap5    ds 24

;---------------------------------------------------------------------------------------------------

    DEFINE_SUBROUTINE ClearRowBitmap

                lda #0
.OFFSET SET 0
    REPEAT ROW_BITMAP_SIZE
                sta ChessBitmap+RAM_WRITE+.OFFSET
.OFFSET SET .OFFSET + 1
    REPEND

                rts

;---------------------------------------------------------------------------------------------------

    DEFINE_SUBROUTINE CopyPieceToRowBitmap

                bcs .rightSide

                ldy #71
.copyPiece      lda __pieceShapeBuffer,y
                ora ChessBitmap,y
                sta ChessBitmap+RAM_WRITE,y
                dey
                bpl .copyPiece

                rts

.rightSide

                ldy #71
.copyPieceR     lda __pieceShapeBuffer,y
                eor ChessBitmap+72,y
                sta ChessBitmap+72+RAM_WRITE,y
                dey
                bpl .copyPieceR

                rts

;---------------------------------------------------------------------------------------------------

    DEFINE_SUBROUTINE DrawTheChessScreen

                jsr DrawRow                     ; draws all 8 rows with nifty bankswitching
                rts

;---------------------------------------------------------------------------------------------------

    DEFINE_SUBROUTINE DrawRow

    ; x = row # (and bank#)

.startLine      ldy #0                     ; 2

.drawLine       sta WSYNC                   ; 3 @0

                lda .LineColour,y           ; 5
                sta COLUPF                  ; 3 @8

                lda ChessBitmap0,y          ; 5
                sta PF0                     ; 3
                lda ChessBitmap1,y          ; 5
                sta PF1                     ; 3
                lda ChessBitmap2,y          ; 5
                sta PF2                     ; 3 @32

                SLEEP 6                     ; 6 @30

                lda ChessBitmap3,y          ; 5
                sta PF0                     ; 3 @38
                lda ChessBitmap4,y          ; 5
                sta PF1                     ; 3 @46
                lda ChessBitmap5,y          ; 5
                sta PF2                     ; 3 @52

                iny                         ; 2
                cpy #24
                bcc .drawLine               ; 3(2) @57 (taken)

; @56

    ; The following 'inx' is replaced in the LAST row bank with a 'RTS', thus ending the draw loop
    ; Note that the other 7 row banks are unmodified (keeping the 'inx')
SELFMOD_RTS_ON_LAST_ROW
                inx                         ; 2

                stx SET_BANK_RAM            ; 3 @61     BANK switch to next row
                bne .startLine              ; 3(2) @64 (taken)

.LineColour
; The ICC triplet colour definitions for a single row of the chessboard
    REPEAT 8
        .byte $44, $2c, $a6 ;$4A, $1A, $98
    REPEND

    MAC TEST
V SET "L"+{1}
V2 SET "LAB" + V
V2$
    ENDM

UNQ SET 0
    TEST UNQ
    .byte 1
UNQ SET UNQ + 1
    TEST UNQ


    ;VALIDATE_RAM_SIZE
