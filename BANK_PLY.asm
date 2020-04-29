; Copyright (C)2020 Andrew Davie
; andrew@taswegian.com


;---------------------------------------------------------------------------------------------------
; Define the RAM banks
; A "PLY" bank represents all the data required on any single ply of the search tree.
; The banks are organised sequentially, PLY_BANKS of them starting at RAMBANK_PLY
; The startup code copies the ROM shadow into each of these PLY banks, and from then on
; they act as independant switchable banks usable for data on each ply during the search.
; A ply will hold the move list for that position


    NEWRAMBANK PLY                                  ; RAM bank for holding the following ROM shadow
    REPEAT PLY_BANKS-1
        NEWRAMBANK .DUMMY_PLY
    REPEND


;---------------------------------------------------------------------------------------------------
; and now the ROM shadow - this is copied to ALL of the RAM ply banks

    NEWBANK BANK_PLY                   ; ROM SHADOW

;---------------------------------------------------------------------------------------------------
; The piece-lists
; ONLY the very first bank piecelist is used - all other banks switch to the first for
; piecelist usage. Note that this initialisation (below) comes from the shadow ROM/RAM copy
; but this needs to be initialised programatically on new game.

; We have TWO piecelists, in different banks
; WHITE pieces in bank BANK_PLY
; BLACK pieces in bank BANK_PLY+1

    VARIABLE savedEvaluation, 2                     ; THIS node's evaluation - used for reverting moves!

;---------------------------------------------------------------------------------------------------

MAX_MOVES =70

    VARIABLE MoveFrom, MAX_MOVES
    VARIABLE MoveTo, MAX_MOVES
    VARIABLE MovePiece, MAX_MOVES
    VARIABLE MoveCapture, MAX_MOVES

    VARIABLE kingSquare, 3                          ; traversing squares for castle/check

;---------------------------------------------------------------------------------------------------

; The X12 square at which a pawn CAN be taken en-passant. Normally 0.
; This is set/cleared whenever a move is made. The flag is indicated in the move description.

    VARIABLE enPassantSquare, 1
    VARIABLE capturedPiece, 1
    VARIABLE originalPiece, 1
    VARIABLE secondaryPiece, 1                      ; original piece on secondary (castle, enpassant)
    VARIABLE secondarySquare, 1                     ; original square of secondary piece
    VARIABLE secondaryBlank, 1                      ; square to blank on secondary

;---------------------------------------------------------------------------------------------------
; Move tables hold piece moves for this current ply

    VARIABLE moveIndex, 1                           ; points to first available 'slot' for move storage
    VARIABLE movePtr, 1
    VARIABLE bestMove, 1
    VARIABLE alpha, 2
    VARIABLE beta, 2
    VARIABLE value, 2
    VARIABLE depthLeft, 1
    VARIABLE restorePiece, 1
    
;---------------------------------------------------------------------------------------------------

    DEF NewPlyInitialise
    SUBROUTINE

        REFER GenerateAllMoves
        REFER negaMax
        VEND NewPlyInitialise

    ; This MUST be called at the start of a new ply
    ; It initialises the movelist to empty
    ; x must be preserved

    ; note that 'alpha' and 'beta' are set externally!!

                    lda #-1
                    sta@PLY moveIndex           ; no valid moves
                    sta@PLY bestMove

                    lda enPassantPawn               ; flag/square from last actual move made
                    sta@PLY enPassantSquare         ; used for backtracking, to reset the flag


    ; The value of the material (signed, 16-bit) is restored to the saved value at the reversion
    ; of a move. It's quicker to restore than to re-sum. So we save the current evaluation at the
    ; start of each new ply.

                    lda Evaluation
                    sta@PLY savedEvaluation
                    lda Evaluation+1
                    sta@PLY savedEvaluation+1

                    rts


;---------------------------------------------------------------------------------------------------

    DEF CheckMoveListFromSquare
    SUBROUTINE

        REFER IsValidP_MoveFromSquare
        VEND CheckMoveListFromSquare

    ; X12 in A
    ; y = -1 on return if NOT FOUND

                    ldy@RAM moveIndex
                    bmi .exit

.scan               cmp MoveFrom,y
                    beq .scanned
                    dey
                    bpl .scan
.exit               rts

.scanned            lda@PLY MovePiece,y
                    sta fromPiece
                    rts


;---------------------------------------------------------------------------------------------------

    DEF GetPieceGivenFromToSquares
    SUBROUTINE

        REFER GetPiece
        VEND GetPieceGivenFromToSquares

    ; returns piece in A+fromPiece
    ; or Y=-1 if not found

    ; We need to get the piece from the movelist because it contains flags (e.g., castling) about
    ; the move. We need to do from/to checks because moves can have multiple origin/desinations.
    ; This fixes the move with/without castle flag


                    ldy@PLY moveIndex
                    ;bmi .fail               ; shouldn't happen
.scan               lda fromX12
                    cmp@PLY MoveFrom,y
                    bne .next
                    lda toX12                    
                    cmp@PLY MoveTo,y
                    beq .found
.next               dey
                    bpl .scan
.fail               rts

.found              lda@PLY MovePiece,y
                    sta fromPiece
                    rts



;---------------------------------------------------------------------------------------------------
    
    DEF selectmove
    SUBROUTINE

        COMMON_VARS_ALPHABETA
        REFER aiComputerMove
        VEND selectmove



    ; RAM bank already switched in!!!
    ; returns with RAM bank switched


        IF DIAGNOSTICS
        
                    lda #0
                    sta positionCount
                    sta positionCount+1
                    sta positionCount+2
                    ;sta maxPly
        ENDIF


                    lda #<INFINITY
                    sta __beta
                    lda #>INFINITY
                    sta __beta+1

                    lda #<-INFINITY
                    sta __alpha
                    lda #>-INFINITY
                    sta __alpha+1                   ; player tries to maximise

                    ldx #SEARCH_DEPTH  
                    lda #0                          ; no captured piece
                    sta __quiesceCapOnly            ; ALL moves to be generated

                    jsr negaMax
 
                    ldx@PLY bestMove
                    bmi .nomove

    ; Generate player's moves in reply
    ; Make the computer move, list player moves (PLY+1), unmake computer move


                    stx@PLY movePtr
                    jsr MakeMove

                    jsr ListPlayerMoves

                    lda currentPly ;#RAMBANK_PLY
                    sta SET_BANK_RAM
                    
                    jsr unmakeMove

    ; Grab the computer move details for the UI animation

                    lda #RAMBANK_PLY
                    sta SET_BANK_RAM

                    ldx@PLY bestMove
                    lda@PLY MoveTo,x
                    sta toX12
                    lda@PLY MoveFrom,x
                    sta originX12
                    sta fromX12
                    lda@PLY MovePiece,x
                    sta fromPiece

.nomove
                    rts


;---------------------------------------------------------------------------------------------------

    DEF GenCastleMoveForRook
    SUBROUTINE

        REFER MakeMove
        REFER CastleFixupDraw
        VEND GenCastleMoveForRook

                    clc

                    lda fromPiece
                    and #FLAG_CASTLE
                    beq .exit                       ; NOT involved in castle!

                    ldx #4
                    lda fromX12                     ; *destination*
.findCast           clc
                    dex
                    bmi .exit
                    cmp KSquare,x
                    bne .findCast

                    lda RSquareEnd,x
                    sta toX12
                    sta@PLY secondaryBlank
                    ldy RSquareStart,x
                    sty fromX12
                    sty originX12
                    sty@PLY secondarySquare

                    lda fromPiece
                    and #128                        ; colour bit
                    ora #ROOK                       ; preserve colour
                    sta fromPiece
                    sta@PLY secondaryPiece

                    sec
.exit               rts


;---------------------------------------------------------------------------------------------------

    DEF CastleFixupDraw
    SUBROUTINE

        REFER aiSpecialMoveFixup
        VEND CastleFixupDraw

    ; fixup any castling issues
    ; at this point the king has finished his two-square march
    ; based on the finish square, we determine which rook we're interacting with
    ; and generate a 'move' for the rook to position on the other side of the king


    IF CASTLING_ENABLED
                    jsr GenCastleMoveForRook
                    bcs .phase
    ENDIF
    
                SWAP
                rts

.phase

    ; in this siutation (castle, rook moving) we do not change sides yet!

                    PHASE AI_MoveIsSelected
                    rts



KSquare             .byte 24,28,94,98
RSquareStart        .byte 22,29,92,99
RSquareEnd          .byte 25,27,95,97


;---------------------------------------------------------------------------------------------------

    MAC XCHG ;{name}
        lda@PLY {1},x
        sta __xchg
        lda@PLY {1},y
        sta@PLY {1},x
        lda __xchg
        sta@PLY {1},y
    ENDM


    DEF Sort
    SUBROUTINE

        REFER GenerateAllMoves
        VAR __xchg, 1
        VEND Sort

                    ;lda currentPly
                    ;sta savedBank           ; ??

                    lda __quiesceCapOnly
                    bmi .exit                       ; only caps present so already sorted!

                    ldx@PLY moveIndex
                    ldy@PLY moveIndex
.next               dey
                    bmi .exit

                    lda@PLY MoveCapture,y
                    beq .next

                    XCHG MoveFrom
                    XCHG MoveTo
                    XCHG MovePiece
                    XCHG MoveCapture

                    dex
                    bpl .next

.exit




    ; Scan for capture of king

                    ldx@PLY moveIndex

.scanCheck          lda@PLY MoveCapture,x
                    beq .check                      ; since they're sorted with captures "first" we can exit
                    and #PIECE_MASK
                    cmp #KING
                    beq .check
                    dex
                    bpl .scanCheck

                    lda #0
.check              sta flagCheck
                    rts


;---------------------------------------------------------------------------------------------------
; QUIESCE!

;int Quiesce( int alpha, int beta ) {
;    int stand_pat = Evaluate();
;    if( stand_pat >= beta )
;        return beta;
;    if( alpha < stand_pat )
;        alpha = stand_pat;

;    until( every_capture_has_been_examined )  {
;        MakeCapture();
;        score = -Quiesce( -beta, -alpha );
;        TakeBackMove();

;        if( score >= beta )
;            return beta;
;        if( score > alpha )
;           alpha = score;
;    }
;    return alpha;
;}


    DEF quiesce
    SUBROUTINE

    ; pass...
    ; x = depthleft
    ; SET_BANK_RAM      --> current ply
    ; __alpha[2] = param alpha
    ; __beta[2] = param beta


        COMMON_VARS_ALPHABETA
        REFER selectmove
        REFER negaMax
        VEND quiesce

                    lda currentPly
                    cmp #MAX_PLY_DEPTH_BANK -1
                    bcs .retBeta

    ; The 'thinkbar' pattern...

                    lda #0
                    ldy INPT4
                    bmi .doThink
    
                    lda __thinkbar
                    asl
                    asl
                    asl
                    asl
                    ora #2
                    sta COLUPF

                    inc __thinkbar
                    lda __thinkbar
                    and #15
                    tay
                    lda SynapsePattern2,y

.doThink            sta PF1
                    sta PF2

    ; ^

                    lda __beta
                    sta@PLY beta
                    lda __beta+1
                    sta@PLY beta+1

                    lda __alpha
                    sta@PLY alpha
                    lda __alpha+1
                    sta@PLY alpha+1


    ;    int stand_pat = Evaluate();
    ;    if( stand_pat >= beta )
    ;        return beta;

                    sec
                    lda Evaluation
                    sbc@PLY beta
                    lda Evaluation+1
                    sbc@PLY beta+1
                    bvc .spat0
                    eor #$80
.spat0              bmi .norb ;pl .retBeta                    ; branch if stand_pat >= beta

.retBeta            lda beta
                    sta __negaMax
                    lda beta+1
                    sta __negaMax+1

.abort              rts                    

.norb


    ;    if( alpha < stand_pat )
    ;        alpha = stand_pat;

                    sec
                    lda alpha
                    sbc Evaluation
                    lda alpha+1
                    sbc Evaluation+1
                    bvc .spat1
                    eor #$80
.spat1              bpl .alpha                      ; branch if alpha >= stand_pat

    ; alpha < stand_pat

                    lda Evaluation
                    sta@PLY alpha
                    lda Evaluation+1
                    sta@PLY alpha+1

.alpha
                    jsr GenerateAllMoves
                    lda flagCheck
                    bne .abort                      ; pure abort

                    ldx@PLY moveIndex
                    bmi .exit
                    
.forChild           stx@PLY movePtr

    ; The movelist has captures ONLY (ref: __quiesceCapOnly != 0)

                    jsr MakeMove

                    sec
                    lda #0
                    sbc@PLY beta
                    sta __alpha
                    lda #0
                    sbc@PLY beta+1
                    sta __alpha+1

                    sec
                    lda #0
                    sbc@PLY alpha
                    sta __beta
                    lda #0
                    sbc@PLY alpha+1
                    sta __beta+1

                    inc currentPly
                    lda currentPly
                    sta SET_BANK_RAM                ; self-switch

                    jsr quiesce

                    dec currentPly
                    lda currentPly
                    sta SET_BANK_RAM

                    jsr unmakeMove

                    lda flagCheck                   ; don't consider moves which leave us in check
                    bne .inCheck
                    
                    sec
                    ;lda #0                         ; already 0
                    sbc __negaMax
                    sta __negaMax
                    lda #0
                    sbc __negaMax+1
                    sta __negaMax+1                 ; -negaMax(...)



;        if( score >= beta )
;            return beta;


                    sec
                    lda __negaMax
                    sbc@PLY beta
                    lda __negaMax+1
                    sbc@PLY beta+1
                    bvc .lab0
                    eor #$80
.lab0               bmi .nrb2 ; .retBeta                    ; branch if score >= beta
                    jmp .retBeta
.nrb2

;        if( score > alpha )
;           alpha = score;
;    }

                    sec
                    lda@PLY alpha
                    sbc __negaMax
                    lda@PLY alpha+1
                    sbc __negaMax+1
                    bvc .lab2
                    eor #$80
.lab2               bpl .nextMove                   ; alpha >= score

    ; score > alpha

                    lda __negaMax
                    sta@PLY alpha
                    lda __negaMax+1
                    sta@PLY alpha+1

.nextMove           ldx@PLY movePtr
                    dex
                    bpl .forChild

;    return alpha;

.exit
                    lda@PLY alpha
                    sta __negaMax
                    lda@PLY alpha+1
                    sta __negaMax+1
                    rts

.inCheck            lda #0
                    sta flagCheck
                    beq .nextMove



SynapsePattern2

    .byte %11000001
    .byte %01100000
    .byte %00110000
    .byte %00011000
    .byte %00001100
    .byte %00000110
    .byte %10000011
    .byte %11000001

    .byte %10000011
    .byte %00000110
    .byte %00001100
    .byte %00011000
    .byte %00110000
    .byte %01100000
    .byte %11000001
    .byte %10000011


;---------------------------------------------------------------------------------------------------

    DEF AddMovePly
    SUBROUTINE

        REFER AddMove
        VEND AddMovePly

                    tya
                    
                    ldy@PLY moveIndex
                    iny
                    sty@PLY moveIndex
                    
                    sta@PLY MoveTo,y
                    tax                             ; used for continuation of sliding moves
                    lda currentSquare
                    sta@PLY MoveFrom,y
                    lda currentPiece
                    sta@PLY MovePiece,y
                    lda capture
                    sta@PLY MoveCapture,y

                    rts


;---------------------------------------------------------------------------------------------------

    CHECK_HALF_BANK_SIZE "PLY -- 1K"

;---------------------------------------------------------------------------------------------------

; There is space here (1K) for use as ROM
; but NOT when the above bank is switched in as RAM, of course!




;---------------------------------------------------------------------------------------------------
; EOF