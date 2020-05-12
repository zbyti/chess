; Chess
; Copyright (c) 2019-2020 Andrew Davie
; andrew@taswegian.com

    SLOT 1
    NEWBANK NEGAMAX

;---------------------------------------------------------------------------------------------------

    DEF aiComputerMove
    SUBROUTINE

        REFER AiStateMachine
        VEND aiComputerMove


                    lda #RAMBANK_PLY
                    sta currentPly                    
                    sta SET_BANK_RAM;@2             ; switch in movelist
                    
                    lda #1
                    sta CTRLPF                      ; mirroring for thinkbars


                    jsr selectmove;@this


                    lda #0
                    sta CTRLPF                      ; clear mirroring
                    sta PF1
                    sta PF2

    ; correct ply is already switched

                    lda@PLY bestMove
                    bpl .notComputer

    ; Computer could not find a valid move. It's checkmate or stalemate. Find which...

                    SWAP
                    jsr GenerateAllMoves;@0
                    lda flagCheck
                    beq .gameDrawn

                    PHASE AI_CheckMate
                    rts


.gameDrawn          PHASE AI_Draw
                    rts
                    
.notComputer


                    lda #-1
                    sta cursorX12

                    PHASE AI_DelayAfterMove
.halted             rts


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

                    ;lda currentPly
                    ;sta SET_BANK_RAM ;tmp?

                    ldx@PLY bestMove
                    bmi .nomove

    ; Generate player's moves in reply
    ; Make the computer move, list player moves (PLY+1), unmake computer move

                    stx@PLY movePtr
                    jsr MakeMove;@this
                    jsr ListPlayerMoves;@0

                    dec currentPly
                    jsr unmakeMove;@0

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

    DEF MakeMove
    SUBROUTINE

        REFER selectmove
        REFER ListPlayerMoves
        REFER quiesce
        REFER negaMax

        VAR __capture, 1
        VAR __restore, 1

        VEND MakeMove

    ; Do a move without any GUI stuff
    ; This function is ALWAYS paired with "unmakeMove" - a call to both will leave board
    ; and all relevant flags in original state. This is NOT used for the visible move on the
    ; screen.


    ; fromPiece     piece doing the move
    ; fromX12       current square X12
    ; originX12     starting square X12
    ; toX12         ending square X12

    ; BANK:SLOT2 = currentPly


    ; There are potentially "two" moves, with the following
    ; a) Castling, moving both rook and king
    ; b) en-Passant, capturing pawn on "odd" square
    ; These both set "secondary" movers which are used for restoring during unmakeMove

                    lda #0
                    sta@PLY secondaryPiece

                    ldx@PLY movePtr
                    lda@PLY MoveFrom,x
                    sta fromX12
                    sta originX12
                    lda@PLY MoveTo,x
                    sta toX12
                    lda@PLY MovePiece,x
                    sta fromPiece                   

.move               CALL AdjustMaterialPositionalValue

    ; Modify the board
    
                    ldy #RAMBANK_BOARD
                    sty SET_BANK_RAM;@3
                    ldy originX12
                    lda@RAM Board,y
                    sta __restore
                    lda #0
                    sta@RAM Board,y
                    ldy toX12
                    lda@RAM Board,y
                    sta __capture
                    lda fromPiece
                    and #PIECE_MASK|FLAG_COLOUR
                    ora #FLAG_MOVED
                    sta@RAM Board,y

                    lda currentPly
                    sta SET_BANK_RAM;@2
                    lda __capture
                    sta@PLY capturedPiece
                    lda __restore
                    sta@PLY restorePiece

    IF CASTLING_ENABLED

        ; If the FROM piece has the castle bit set (i.e., it's a king that's just moved 2 squares)
        ; then we find the appropriate ROOK, set the secondary piece "undo" information, and then
        ; redo the moving code (for the rook, this time).

                    jsr GenCastleMoveForRook
                    bcs .move                       ; move the rook!
    ENDIF


    IF ENPASSANT_ENABLED    
                    jsr EnPassantCheck
                    beq .notEnPassant
                    jsr EnPassantRemovePiece        ; y = origin X12
.notEnPassant
    ENDIF

    ; Swap over sides

                    NEGEVAL
                    SWAP
                    rts


;---------------------------------------------------------------------------------------------------

;function negaMax(node, depth, α, β, color) is
;    if depth = 0 or node is a terminal node then
;        return color × the heuristic value of node

;    childNodes := generateMoves(node)
;    childNodes := orderMoves(childNodes)
;    value := −∞
;    foreach child in childNodes do
;        value := max(value, −negaMax(child, depth − 1, −β, −α, −color))
;        α := max(α, value)
;        if α ≥ β then
;            break (* cut-off *)
;    return value
;(* Initial call for Player A's root node *)
;negaMax(rootNode, depth, −∞, +∞, 1)


    SUBROUTINE

.doQ                lda #-1
                    sta __quiesceCapOnly
                    jsr quiesce
                    inc __quiesceCapOnly
                    rts


.exit               lda@PLY value
                    sta __negaMax
                    lda@PLY value+1
                    sta __negaMax+1
                    rts
                    

.terminal

    IF QUIESCE_EXTRA_DEPTH > 0
                    cmp #0                          ; captured piece
                    bne .doQ                        ; last move was capture, so quiesce
    ENDIF


    IF 0
    ; king moves will also quiesce
    ; theory is - we need to see if it was an illegal move

                    lda fromPiece
                    and #PIECE_MASK
                    cmp #KING
                    beq .doQ
    ENDIF
                        
                    lda Evaluation
                    sta __negaMax
                    lda Evaluation+1
                    sta __negaMax+1

.inCheck2           rts



    DEF negaMax

    ; PARAMS depth-1, -beta, -alpha
    ; pased through temporary variables (__alpha, __beta) and X reg

    ; pass...
    ; x = depthleft
    ; a = captured piece
    ; SET_BANK_RAM      --> current ply
    ; __alpha[2] = param alpha
    ; __beta[2] = param beta


        COMMON_VARS_ALPHABETA
        REFER selectmove
        VEND negaMax

                    pha

                    jsr ThinkBar;@0
                    lda currentPly
                    sta SET_BANK_RAM;@2

                    pla
                    dex
                    bmi .terminal
                    stx@PLY depthLeft


    ; Allow the player to force computer to select a move. Press the SELECT switch

                    lda@PLY moveIndex
                    bmi .noCheat                    ; can't force if no move chosen!
                    lda SWCHB
                    and #2
                    beq .exit                       ; SELECT abort
.noCheat

                    lda #2
                    sta COLUPF                      ; grey thinkbars

                    lda __alpha
                    sta@PLY alpha
                    lda __alpha+1
                    sta@PLY alpha+1

                    lda __beta
                    sta@PLY beta
                    lda __beta+1
                    sta@PLY beta+1


    IF 1
                    lda Evaluation
                    adc randomness
                    sta Evaluation
                    bcc .evh
                    inc Evaluation+1
.evh
    ENDIF


                    jsr GenerateAllMoves;@0

                    lda flagCheck
                    bne .inCheck2                           ; OTHER guy in check

    IF 0
                    lda@PLY moveIndex
                    bmi .none
                    lsr
                    lsr
                    lsr
                    lsr
                    lsr
                    adc Evaluation
                    sta Evaluation
                    lda Evaluation+1
                    adc #0
                    sta Evaluation+1
.none
    ENDIF


                    lda #<-INFINITY
                    sta@PLY value
                    lda #>-INFINITY
                    sta@PLY value+1

                    ldx@PLY moveIndex
                    bpl .forChild
                    jmp .exit
                    
.forChild           stx@PLY movePtr

                    jsr MakeMove;@this


    ;        value := max(value, −negaMax(child, depth − 1, −β, −α, −color))

    ; PARAMS depth-1, -beta, -alpha
    ; pased through temporary variables (__alpha, __beta) and X reg

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


                    ldx@PLY depthLeft
                    lda@PLY capturedPiece

                    inc currentPly
                    ldy currentPly
                    sty SET_BANK_RAM                ; self-switch
                    
                    jsr negaMax;@this

                    dec currentPly
                    lda currentPly
                    sta SET_BANK_RAM

                    jsr unmakeMove;@0

                    sec
                    lda #0
                    sbc __negaMax
                    sta __negaMax
                    lda #0
                    sbc __negaMax+1
                    sta __negaMax+1                 ; -negaMax(...)

                    lda flagCheck
                    beq .notCheck
                    
    ; at this point we've determined that the move was illegal, because the next ply detected
    ; a king capture. So, the move should be totally discounted

                    lda #0
                    sta flagCheck                   ; so we don't retrigger in future - it's been handled!
                    beq .nextMove                   ; unconditional - move is not considered!

.notCheck           sec
                    lda@PLY value
                    sbc __negaMax
                    lda@PLY value+1
                    sbc __negaMax+1
                    bvc .lab0
                    eor #$80
.lab0               bpl .lt0                        ; branch if value >= negaMax

    ; so, negaMax > value!

                    lda __negaMax
                    sta@PLY value
                    lda __negaMax+1
                    sta@PLY value+1                 ; max(value, -negaMax)

                    lda@PLY movePtr
                    sta@PLY bestMove
.lt0

;        α := max(α, value)

                    sec
                    lda@PLY value
                    sbc@PLY alpha
                    lda@PLY value+1
                    sbc@PLY alpha+1
                    bvc .lab1
                    eor #$80
.lab1               bmi .lt1                        ; value < alpha

                    lda@PLY value
                    sta@PLY alpha
                    lda@PLY value+1
                    sta@PLY alpha+1                 ; alpha = max(alpha, value)

.lt1

;        if α ≥ β then
;            break (* cut-off *)

                    sec
                    lda@PLY alpha
                    sbc@PLY beta
                    lda@PLY alpha+1
                    sbc@PLY beta+1
                    bvc .lab2
                    eor #$80
.lab2               bpl .retrn                      ; alpha >= beta


.nextMove           ldx@PLY movePtr
.nextX              dex
                    bmi .retrn
                    jmp .forChild

.retrn              jmp .exit

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


;---------------------------------------------------------------------------------------------------

    DEF quiesce
    SUBROUTINE

    ; pass...
    ; x = depthleft
    ; SET_BANK_RAM      --> current ply
    ; __alpha[2] = param alpha
    ; __beta[2] = param beta


        COMMON_VARS_ALPHABETA
        REFER negaMax
        VEND quiesce

                    lda currentPly
                    cmp #RAMBANK_PLY + PLY_BANKS  -1
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

                    jsr MakeMove;@this

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

                    jsr quiesce;@this

                    dec currentPly
                    ;lda currentPly
                    ;sta SET_BANK_RAM

                    jsr unmakeMove;@0

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

    CHECK_BANK_SIZE "NEGAMAX"

;---------------------------------------------------------------------------------------------------
; EOF