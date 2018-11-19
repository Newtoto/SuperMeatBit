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
NUM_BANDAGES = 1

PLAYER_HITBOX_WIDTH   = 8
PLAYER_HITBOX_HEIGHT  = 8
PLAYER_START_POSITION_X = 128
PLAYER_START_POSITION_Y = 120

    .rsset $0000
joypad1_state           .rs 1
nametable_address       .rs 2
player_speed            .rs 2 ; Subixels per frame -- 16 bits
player_position_sub_y   .rs 1
player_position_sub_x   .rs 1
player_right_speed      .rs 2 ; Subixels per frame -- 16 bits
player_left_speed       .rs 2 ; Subixels per frame -- 16 bits
left_momentum           .rs 2 ; Subixels per frame ^ 2 -- 16 bits
right_momentum          .rs 2 ; Subixels per frame ^ 2 -- 16 bits
is_running              .rs 1 ; Checks if player is running
touching_ground         .rs 1 ; Ground check

    .rsset $0200
sprite_player      .rs 4
sprite_wall        .rs 16
sprite_spike       .rs 4
sprite_bandage     .rs 4

    .rsset $0000
SPRITE_Y           .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X           .rs 1

GRAVITY             = 16        ; Subpixels per frame ^ 2
JUMP_SPEED          = -2 * 256  ; Subpixels per frame
RUN_SPEED           = 2* 256    ; Subpixels per frame
RUN_ACC             = 8
MAX_SPEED           = 16

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
    LDA #PLAYER_START_POSITION_Y    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #0      ; Tile number
    STA sprite_player + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_player + SPRITE_ATTRIB
    LDA #PLAYER_START_POSITION_X    ; X position
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
    LDA #2      ; Attributes
    STA sprite_wall + SPRITE_ATTRIB + 4
    LDA #136    ; X position
    STA sprite_wall + SPRITE_X + 4
	
	LDA #140    ; Y position
    STA sprite_wall + SPRITE_Y + 8
    LDA #2      ; Tile number
    STA sprite_wall + SPRITE_TILE + 8
    LDA #3      ; Attributes
    STA sprite_wall + SPRITE_ATTRIB + 8
    LDA #120    ; X position
    STA sprite_wall + SPRITE_X + 8
    
; Write sprite data for spikes
InitSpikes:
    LDX #0
    InitSpikesLoop:
    LDA #140     ; Y position
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

InitCollectables:
    LDX #0
    InitCollectablesLoop:
    LDA #180     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #140 + NUM_BANDAGES * 4     ; X position
    STA sprite_bandage + SPRITE_X, X
    ; Increment X register by 4
    TXA
    CLC
    ADC #4
    TAX
    ; See if 
    CPX NUM_BANDAGES * 4     ; Compare X to dec 8
    BNE InitCollectablesLoop

; ---------------------------------------------------------------------------

; Load background sprites
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
    INY                             ; Y = Y + 1
    BNE LoadBackground_InnerLoop    ; Branch to LoadBackgroundLoop if compare was Not Equal to zero
    INC nametable_address + 1
    JMP LoadBackground_OuterLoop
LoadBackground_End

; Load background sprites palette attributes
LoadAttribute:
    LDA $2002             ; read PPU status to reset the high/low latch
    LDA #$23
    STA $2006             ; write the high byte of $23C0 address
    LDA #$C0
    STA $2006             ; write the low byte of $23C0 address
    LDX #$00              ; start out at 0          
LoadAttributeLoop:
    LDA attribute, x      ; load data from address (attribute + the value in x)
    STA PPUDATA             ; write to PPU
    INX                   ; X = X + 1
    CPX #$40              ; Compare X to hex $08, decimal 8 - copying 8 bytes
                        ; Compare X to hex $  , decimal 64 - copying 64 bytes
    BNE LoadAttributeLoop

    RTS ; End subroutine

; ---------------------------------------------------------------------------

; NMI is called on every frame
NMI:
    ; Initialise controller 1
    LDA #1
    STA JOYPAD1
    LDA #0
    STA JOYPAD1
    STA touching_ground ; Default ground touching to false

    ; Read joypad state
    LDX #0
    STX joypad1_state

CheckForPlayerCollision .macro ;parameters: object_x, object_y, no_collision_label, collision_label
    ; If there is no overlap horizontally or vertially jump out
    ; Else quit
    ; Get bottom left pixel of meatboy
    ; Get bottom right of meatboy

    ; Horizontal check
    LDA sprite_player + SPRITE_X
    SEC
    SBC #8
    CMP \1
    BCS \3  ; Not colliding if x is greater than the right side
    CLC
    ADC #16
    CMP \1
    BCC \3  ; Not colliding if x is less than the left side
    ; Vertical check
    LDA sprite_player + SPRITE_Y
    SEC
    SBC #8
    CMP \2
    BCS \3  ; Not colliding if y is less than the top
    CLC
    ADC #16
    CMP \2
    BCC \3	; Not colliding if y is greater than the bottom
    ; Set player y location to top of collided sprite
    LDA \2
    SBC #8
    STA sprite_player + SPRITE_Y
    JMP \4
    .endm

CollisionCheck:
    CheckForPlayerCollision sprite_wall + SPRITE_X, sprite_wall + SPRITE_Y, CheckWall2, TouchingGround	; TODO Separate function to slow falling if to the side
CheckWall2:
	CheckForPlayerCollision sprite_wall + SPRITE_X + 4, sprite_wall + SPRITE_Y + 4, CheckWall3, TouchingGround
CheckWall3:
	CheckForPlayerCollision sprite_wall + SPRITE_X + 8, sprite_wall + SPRITE_Y + 8, ReadController, TouchingGround

TouchingGround:
    LDA #1
    STA touching_ground ; Set touching ground to true

ReadController:
    LDA JOYPAD1
    LSR A
    ROL joypad1_state
    INX
    CPX #8
    BNE ReadController

    LDA #0
    STA is_running      ; Default is running to false

    ; React to Right button
    LDA joypad1_state
    AND #BUTTON_RIGHT
    BEQ ReadRight_Done       ; if ((JOYPAD1 & 1) != 0) {
    LDA #1 
    STA is_running           ; Set is running bool to true
    LDA #RUN_ACC
    STA right_momentum         ; Start momentum

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
    LDA #1
    STA is_running      ; Set is running bool to true
    LDA #RUN_ACC
    STA left_momentum    ; Start momentum


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
    LDA touching_ground
    BEQ ReadA_Done          ; Don't jump if not touching ground
    LDA #LOW(JUMP_SPEED)    ; Jump, set player speed
    STA player_speed
    LDA #HIGH(JUMP_SPEED)
    STA player_speed + 1

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

CheckForRunning:
    LDA is_running
    BNE CheckSpikeCollision     ; Branch if running
    STA right_momentum            ; Stop momentum if not running
    STA left_momentum

CheckSpikeCollision:
; Check collision with spikes
    CheckForPlayerCollision sprite_spike + SPRITE_X, sprite_spike + SPRITE_Y, NoCollisionWithSpike, SpikeHit

; Handle collision
SpikeHit:
    ; Move player back to start
    LDA #PLAYER_START_POSITION_Y    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #PLAYER_START_POSITION_X    ; X position
    STA sprite_player + SPRITE_X
    LDA #0                          ; Stop player run speed
    STA player_right_speed
    STA player_right_speed + 1
    STA player_left_speed
    STA player_left_speed + 1
	
NoCollisionWithSpike:

    CheckForPlayerCollision sprite_bandage + SPRITE_X, sprite_bandage + SPRITE_Y, NoCollisionWithBandage, BandageHit

BandageHit:
    ; Delete bandage + add to score?
    LDA #50
    STA sprite_bandage

NoCollisionWithBandage:

    LDA touching_ground
    BEQ CalculateFall    ; Skip breaking fall if not touching ground
    LDA player_speed + 1
    CMP #20              ; Check if player speed is negative (jumping)
    BCS CalculateFall    ; Don't stop speed if jumping
    LDA #0               ; Stop falling
    STA player_speed     ; Low 8 bits
    STA player_speed + 1 ; High 8 bits
    JMP CalculateMomentum

CalculateFall:
    ; Check if speed is greater than max speed
    ;LDA MAX_SPEED
    ;CMP player_speed
    ;BCC ApplyGravity

    ; Increment player speed
    LDA player_speed    ; Low 8 bits
    CLC
    ADC #LOW(GRAVITY)
    STA player_speed
    LDA player_speed + 1 ; High 8 bits
    ADC #HIGH(GRAVITY)   ; Don't clear carry flag
    STA player_speed + 1
ApplyGravity:
    ; Apply fall to player
	LDA player_position_sub_y       ; Low 8 bits
    CLC
    ADC player_speed
    STA player_position_sub_y
    LDA sprite_player + SPRITE_Y  ; High 8 bits
    ADC player_speed + 1          ; Don't clear carry flag
    STA sprite_player + SPRITE_Y


AddMomentum .macro ; parameters: maxSpeed, speed, acceleration, endFunction
    ; Check if speed is greater than max speed
    ;LDA \1
    ;CMP \2
    ;BCC \4  ; Branch if max speed is exceeded

    ; Calculate player speed
    LDA \2    ; Low 8 bits
    CLC
    ADC \3
    STA \2
    LDA \2 + 1 ; High 8 bits
    ADC \3 + 1   ; Don't clear carry flag
    STA \2 + 1
    .endm

; Left and right momentum
CalculateMomentum:
    AddMomentum MAX_SPEED, player_right_speed, right_momentum, ApplyDrag     ; Right momentum
    ; Apply right momentum to player
    LDA player_position_sub_x     ; Low 8 bits
    CLC
    ADC player_right_speed
    STA player_position_sub_x
    LDA sprite_player + SPRITE_X  ; High 8 bits
    ADC player_right_speed + 1      ; Don't clear carry flag
    STA sprite_player + SPRITE_X
    AddMomentum MAX_SPEED, player_left_speed, left_momentum, ApplyDrag     ; Left momentum
    ; Apply left momentum to player
    LDA player_position_sub_x     ; Low 8 bits
    CLC
    SBC player_left_speed
    STA player_position_sub_x
    LDA sprite_player + SPRITE_X  ; High 8 bits
    SBC player_left_speed + 1      ; Don't clear carry flag
    STA sprite_player + SPRITE_X

ApplyDrag:

	RTI         ; Return from interrupt

; ---------------------------------------------------------------------------
sprites:
    ;vert tile attr horiz
    .db $80, $32, $00, $80   ;sprite 0
    .db $80, $33, $00, $88   ;sprite 1
    .db $88, $34, $00, $80   ;sprite 2
    .db $88, $35, $00, $88   ;sprite 3

nametable:
    .db $02,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$03
    .db $10,$14,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$15,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$16,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$17,$11
    .db $04,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$05
    .db $00
    
attribute:
    .db %10000000, %10000000, %10000000, %10000000, %10000000, %10000000, %10000000, %00000000  ; Row 1 & 2
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 3 & 4
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 5 & 6
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 7 & 8
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 9 & 10
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 11 & 12
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 13 & 14
    .db %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000, %00000000  ; Row 15

paletteData:
    .db $00,$10,$20,$30,$0F,$33,$0F,$33,$1C,$0F,$33,$33,$1C,$0F,$33,$30  ; Background palette data
    .db $1C,$05,$0D,$39,$1C,$26,$15,$36,$08,$09,$10,$11,$1C,$05,$0D,$39  ; Sprite palette data

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
