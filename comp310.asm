    .inesprg 1   ; 1x 16KB PRG code
    .ineschr 1   ; 1x  8KB CHR data
    .inesmap 0   ; mapper 0 = NROM, no bank swapping
    .inesmir 1   ; background mirroring

; ---------------------------------------------------------------------------

PPUCTRL   = $2000
PPUMASK   = $2001
PPUSTATUS = $2002

OAMADDR   = $2003
OAMDATA   = $2004

PPUSCROLL = $2005
PPUADDR   = $2006
PPUDATA   = $2007

OAMDMA    = $4014

JOYPAD1   = $4016
JOYPAD2   = $4017

BUTTON_A      = %10000000
BUTTON_B      = %01000000
BUTTON_SELECT = %00100000
BUTTON_START  = %00010000
BUTTON_UP     = %00001000
BUTTON_DOWN   = %00000100
BUTTON_LEFT   = %00000010
BUTTON_RIGHT  = %00000001

SPIKE_HITBOX_WIDTH   = 8
SPIKE_HITBOX_HEIGHT  = 8
NUM_SPIKES = 2

PLAYER_HITBOX_WIDTH   = 8
PLAYER_HITBOX_HEIGHT  = 8

    .rsset $0000
joypad1_state      .rs 1
nametable_address  .rs 2

    .rsset $0200
sprite_player      .rs 4
sprite_wall        .rs 16
sprite_spike       .rs 4

    .rsset $0000
SPRITE_Y           .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X           .rs 1

    .bank 0
    .org $C000

; Initialisation code based on https://wiki.nesdev.com/w/index.php/Init_code
RESET:
    SEI        ; ignore IRQs
    CLD        ; disable decimal mode
    LDX #$40
    STX $4017  ; disable APU frame IRQ
    LDX #$ff
    TXS        ; Set up stack
    INX        ; now X = 0
    STX PPUCTRL  ; disable NMI
    STX PPUMASK  ; disable rendering
    STX $4010  ; disable DMC IRQs

    ; Optional (omitted):
    ; Set up mapper and jmp to further init code here.

    ; If the user presses Reset during vblank, the PPU may reset
    ; with the vblank flag still true.  This has about a 1 in 13
    ; chance of happening on NTSC or 2 in 9 on PAL.  Clear the
    ; flag now so the vblankwait1 loop sees an actual vblank.
    BIT PPUSTATUS

    ; First of two waits for vertical blank to make sure that the
    ; PPU has stabilized
vblankwait1:  
    BIT PPUSTATUS
    BPL vblankwait1

    ; We now have about 30,000 cycles to burn before the PPU stabilizes.
    ; One thing we can do with this time is put RAM in a known state.
    ; Here we fill it with $00, which matches what (say) a C compiler
    ; expects for BSS.  Conveniently, X is still 0.
    TXA
clrmem:
    LDA #0
    STA $000,x
    STA $100,x
    STA $300,x
    STA $400,x
    STA $500,x
    STA $600,x
    STA $700,x  ; Remove this if you're storing reset-persistent data

    ; We skipped $200,x on purpose.  Usually, RAM page 2 is used for the
    ; display list to be copied to OAM.  OAM needs to be initialized to
    ; $EF-$FF, not 0, or you'll get a bunch of garbage sprites at (0, 0).

    LDA #$FF
    STA $200,x

    INX
    BNE clrmem

    ; Other things you can do between vblank waits are set up audio
    ; or set up other mapper registers.
   
vblankwait2:
    BIT PPUSTATUS
    BPL vblankwait2

    ; End of initialisation code

    JSR InitialiseGame

    LDA #%10010000 ;enable NMI, sprites from Pattern 0, background from Pattern 1
    STA PPUCTRL

    LDA #%00011110 ; enable sprites, enable background
    STA PPUMASK

    LDA #$00
    STA PPUSCROLL
    STA PPUSCROLL

    LDA #0

    ; Enter an infinite loop
forever:
    JMP forever

; ---------------------------------------------------------------------------

InitialiseGame: ; Begin subroutine
    ; Reset the PPU high/low latch
    LDA PPUSTATUS

    ; Write address $3F00 (background palette) to the PPU
    LDA #$3F
    STA PPUADDR
    LDA #$00
    STA PPUADDR

    LDX #$00                ; start out at 0

LoadPalettesLoop:
    LDA paletteData, x      ; load data from address (paletteData + the value in x)
                            ; 1st time through loop it will load paletteData+0
                            ; 2nd time through loop it will load paletteData+1
                            ; 3rd time through loop it will load paletteData+2
                            ; etc
    STA PPUDATA               ; write to PPU
    INX                     ; X = X + 1
    CPX #$20                ; Compare X to hex $20, decimal 32
    BNE LoadPalettesLoop    ; Branch to LoadPalettesLoop if compare was Not Equal to zero
                            ; if compare was equal to 32, keep going down

; Write sprite data for player
InitPlayer:
    LDA #120    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #0      ; Tile number
    STA sprite_player + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_player + SPRITE_ATTRIB
    LDA #128    ; X position
    STA sprite_player + SPRITE_X

; Write sprite data for walls
InitWalls:
    LDA #140    ; Y position
    STA sprite_wall + SPRITE_Y
    LDA #2      ; Tile number
    STA sprite_wall + SPRITE_TILE
    LDA #1      ; Attributes
    STA sprite_wall + SPRITE_ATTRIB
    LDA #128    ; X position
    STA sprite_wall + SPRITE_X
	
	LDA #140    ; Y position
    STA sprite_wall + SPRITE_Y + 4
    LDA #2      ; Tile number
    STA sprite_wall + SPRITE_TILE + 4
    LDA #1      ; Attributes
    STA sprite_wall + SPRITE_ATTRIB + 4
    LDA #136    ; X position
    STA sprite_wall + SPRITE_X + 4
	
	LDA #140    ; Y position
    STA sprite_wall + SPRITE_Y + 8
    LDA #2      ; Tile number
    STA sprite_wall + SPRITE_TILE + 8
    LDA #1      ; Attributes
    STA sprite_wall + SPRITE_ATTRIB + 8
    LDA #120    ; X position
    STA sprite_wall + SPRITE_X + 8
    
; Write sprite data for spikes
InitSpikes:
    LDX #0
    InitSpikesLoop:
    LDA #120     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #1      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #0      ; Attributes
    STA sprite_spike + SPRITE_ATTRIB, X
    LDA #140 + NUM_SPIKES * 4     ; X position
    STA sprite_spike + SPRITE_X, X
    ; Increment X register by 4
    TXA
    CLC
    ADC #4
    TAX
    ; See if 
    CPX NUM_SPIKES * 4     ; Compare X to dec 8
    BNE InitSpikesLoop

; ---------------------------------------------------------------------------

LoadBackground:
    LDA #$20
    STA PPUADDR                 ; write the high byte of $2000 address
    LDA #$00
    STA PPUADDR                 ; write the low byte of $2000 address

    LDA #LOW(nametable)
    STA nametable_address
    LDA #HIGH(nametable)
    STA nametable_address + 1
LoadBackground_OuterLoop:
    LDY #0                          ;start out at 0
LoadBackground_InnerLoop:
    LDA [nametable_address], Y      ; load data from address (background + the value in y)
    BEQ LoadBackground_End          ; break out
    STA PPUDATA                     ; write to PPU
    INY                             ; X = X + 1
    BNE LoadBackground_InnerLoop    ; Branch to LoadBackgroundLoop if compare was Not Equal to zero
    INC nametable_address + 1
    JMP LoadBackground_OuterLoop
LoadBackground_End

; LoadAttribute:
;     LDA $2002             ; read PPU status to reset the high/low latch
;     LDA #$23
;     STA $2006             ; write the high byte of $23C0 address
;     LDA #$C0
;     STA $2006             ; write the low byte of $23C0 address
;     LDX #$00              ; start out at 0          
; LoadAttributeLoop:
;     LDA attribute, x      ; load data from address (attribute + the value in x)
;     STA PPUDATA             ; write to PPU
;     INX                   ; X = X + 1
;     CPX #$08              ; Compare X to hex $08, decimal 8 - copying 8 bytes
;     BNE LoadAttributeLoop

    RTS ; End subroutine

; ---------------------------------------------------------------------------

; NMI is called on every frame
NMI:
    ; Initialise controller 1
    LDA #1
    STA JOYPAD1
    LDA #0
    STA JOYPAD1

    ; Read joypad state
    LDX #0
    STX joypad1_state
ReadController:
    LDA JOYPAD1
    LSR A
    ROL joypad1_state
    INX
    CPX #8
    BNE ReadController

    ; React to Right button
    LDA joypad1_state
    AND #BUTTON_RIGHT
    BEQ ReadRight_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_X
    CLC
    ADC #1
    STA sprite_player + SPRITE_X

ReadRight_Done:         ; }

    ; React to Down button
    LDA joypad1_state
    AND #BUTTON_DOWN
    BEQ ReadDown_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_Y
    CLC
    ADC #1
    STA sprite_player + SPRITE_Y

ReadDown_Done:         ; }

    ; React to Left button
    LDA joypad1_state
    AND #BUTTON_LEFT
    BEQ ReadLeft_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_X
    CLC
    SEC
    SBC #1
    STA sprite_player + SPRITE_X

ReadLeft_Done:         ; }

    ; React to Up button
    LDA joypad1_state
    AND #BUTTON_UP
    BEQ ReadUp_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA sprite_player + SPRITE_Y
    CLC
    SEC
    SBC #1
    STA sprite_player + SPRITE_Y

ReadUp_Done:         ; }

    ; React to A button
    LDA joypad1_state
    AND #BUTTON_A
    BEQ ReadA_Done

ReadA_Done:
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    ; ; Apply gravity to player
    ; LDA $0200
    ; CLC
    ; ADC #1
    ; STA $0200

    LDX #0

CheckForPlayerCollision .macro ;parameters: object_x, object_y, no_collision_label
    ; If there is no overlap horizontally or vertially jump out
    ; Else quit

    ; Horizontal check
    LDA sprite_player + SPRITE_X
    SEC
    SBC #8
    CMP \1
    BCS \3  ; >
    CLC
    ADC #16
    CMP \1
    BCC \3  ; <
    ; Vertical check
    LDA sprite_player + SPRITE_Y
    SEC
    SBC #8
    CMP \2
    BCS \3  ; >
    CLC
    ADC #16
    CMP \2
    BCC \3	; <
	JMP \4
    .endm

    ; Check collision with spikes
    CheckForPlayerCollision sprite_spike + SPRITE_X, sprite_spike + SPRITE_Y, noCollisionWithSpike, spikeHit
	; Handle collision
spikeHit:
	JSR InitialiseGame
	
noCollisionWithSpike:

	CheckForPlayerCollision sprite_wall + SPRITE_X, sprite_wall + SPRITE_Y, checkWall2, gravityDone	; TODO Separate function to slow falling if to the side
checkWall2:
	CheckForPlayerCollision sprite_wall + SPRITE_X + 4, sprite_wall + SPRITE_Y + 4, checkWall3, gravityDone
checkWall3:
	CheckForPlayerCollision sprite_wall + SPRITE_X + 8, sprite_wall + SPRITE_Y + 8, applyGravity, gravityDone
	JMP gravityDone
	
applyGravity:
	LDA sprite_player + SPRITE_Y
    CLC
    ADC #1
    STA sprite_player + SPRITE_Y
	
slowGravity:
	LDA sprite_player + SPRITE_Y
    CLC
    ADC #1
    STA sprite_player + SPRITE_Y
	
gravityDone:
	
	
	RTI         ; Return from interrupt

; ---------------------------------------------------------------------------
sprites:
    ;vert tile attr horiz
    .db $80, $32, $00, $80   ;sprite 0
    .db $80, $33, $00, $88   ;sprite 1
    .db $88, $34, $00, $80   ;sprite 2
    .db $88, $35, $00, $88   ;sprite 3

nametable:
    .db $02,$02,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
    .db $00 ; NULL terminator

; attribute:
;     .db %00000000, %00010000, %0010000, %00010000, %00000000, %00000000, %00000000, %00110000

paletteData:
    .db $0F,$17,$28,$39,$0F,$33,$0F,$33,$1C,$0F,$33,$33,$1C,$0F,$33,$30  ; Background palette data
    .db $1C,$05,$0D,$39,$1C,$05,$0D,$39,$1C,$05,$0D,$39,$1C,$05,$0D,$39  ; Sprite palette data

; ---------------------------------------------------------------------------

    .bank 1
    .org $FFFA
    .dw NMI
    .dw RESET
    .dw 0

; ---------------------------------------------------------------------------

    .bank 2
    .org $0000
    .incbin "comp310.chr"
