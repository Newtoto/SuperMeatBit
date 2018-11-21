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
player_vertical_speed   .rs 2 ; Subpixels per frame -- 16 bits
player_position_sub_y   .rs 1
player_position_sub_x   .rs 1
score_1                 .rs 1
score_10                .rs 1
player_right_speed      .rs 2 ; Subpixels per frame -- 16 bits
player_left_speed       .rs 2 ; Subpixels per frame -- 16 bits
checking_bools          .rs 1 ; is_running, TOUCHING_GROUND, WALL_JUMP_RIGHT, WALL_JUMP_LEFT

IS_RUNNING      = %10000000
TOUCHING_GROUND = %01000000
WALL_JUMP_RIGHT = %00100000
WALL_JUMP_LEFT  = %00010000

collision_location      .rs 1 ; 
running_sprite_number   .rs 1 ; Stores point of run animation


    .rsset $0200
sprite_player               .rs 4
sprite_spike                .rs 4
sprite_bandage              .rs 24
sprite_score_10             .rs 4
sprite_score_1              .rs 4

    .rsset $0000
SPRITE_Y           .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X           .rs 1

GRAVITY             = 16            ; Subpixels per frame ^ 2
JUMP_SPEED          = -3 * 256      ; Subpixels per frame
RUN_SPEED           = 4 * 256       ; Subpixels per frame
RUN_ACC             = 8
MAX_SPEED           = 16
WALL_JUMP_SPEED     = 1 * 256       ; Subpixels per frame
RUN_ANIMATION_LENGTH = 3            ; Number of frames in run animation - 1

; Bandage collectables locations
BANDAGE_START_Y     = 19
BANDAGE_START_X     = 20

BANDAGE_1_START_Y   = 19
BANDAGE_1_START_X   = 228

BANDAGE_2_START_Y   = 91
BANDAGE_2_START_X   = 60

BANDAGE_3_START_Y   = 131
BANDAGE_3_START_X   = 204

BANDAGE_4_START_Y   = 167
BANDAGE_4_START_X   = 148

BANDAGE_5_START_Y   = 211
BANDAGE_5_START_X   = 20

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
    LDA #2      ; Tile number
    STA sprite_player + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_player + SPRITE_ATTRIB
    LDA #PLAYER_START_POSITION_X    ; X position
    STA sprite_player + SPRITE_X
    
; Write sprite data for spikes
InitSpikes:
    LDX #0
    ; InitSpikesLoop:
    LDA #140     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #1      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #0      ; Attributes
    STA sprite_spike + SPRITE_ATTRIB, X
    TXA
    LDA #140 + NUM_SPIKES * 4     ; X position
    STA sprite_spike + SPRITE_X, X
    ; ; Increment X register by 4
    ; TXA
    ; CLC
    ; ADC #4
    ; TAX
    ; ; See if 
    ; CPX NUM_SPIKES * 4     ; Compare X to dec 8
    ; BNE InitSpikesLoop

InitCollectables:
    LDX #0
    LDA #BANDAGE_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    INX
    INX
    INX
    INX
    LDA #BANDAGE_1_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_1_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    INX
    INX
    INX
    INX
    LDA #BANDAGE_2_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_2_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    INX
    INX
    INX
    INX
    LDA #BANDAGE_3_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_3_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    INX
    INX
    INX
    INX
    LDA #BANDAGE_4_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_4_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    INX
    INX
    INX
    INX
    LDA #BANDAGE_5_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_5_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X

InitScore:
    LDA #$0
    STA score_1    ; Set player score to 0
    STA score_10

    LDA #8      ; Y position
    STA sprite_score_10 + SPRITE_Y
    LDA #48      ; Tile number
    STA sprite_score_10 + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_score_10 + SPRITE_ATTRIB
    LDA #16    ; X position
    STA sprite_score_10 + SPRITE_X

    LDA #8      ; Y position
    STA sprite_score_1 + SPRITE_Y
    LDA #48      ; Tile number
    STA sprite_score_1 + SPRITE_TILE
    LDA #0      ; Attributes
    STA sprite_score_1 + SPRITE_ATTRIB
    LDA #24    ; X position
    STA sprite_score_1 + SPRITE_X

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

; --------------MACROS-------------------------------------------------------

CheckForPlayerCollision .macro ;parameters: object_x, object_y, no_collision_label, collision_label
    ; If there is no overlap horizontally or vertially branch out to no collision
    ; Else quit

    ; Horizontal check
    LDA sprite_player + SPRITE_X
    SEC
    SBC #8
    CMP \1
    BCS \3  ; Not colliding if x is greater than the right side
    CLC
    ADC #15
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
    STA LOW(collision_location)
    JMP \4
    .endm

CalculateSpeed .macro ; parameters: speed, acceleration
    ; Calculate player speed
    LDA \1    ; Low 8 bits
    CLC
    ADC #LOW(\2)
    STA \1
    LDA \1 + 1 ; High 8 bits
    ADC #HIGH(\2 + 1)   ; Don't clear carry flag
    STA \1 + 1
    .endm

CalculateNetSpeed .macro ; parameters: maxSpeed, speed_smaller, speed_larger, acceleration
    ; Check if speed is greater than max speed
    ;LDA \1
    ;CMP \2
    ;BCC \4  ; Branch if max speed is exceeded

    ; Subtract smaller speed from larger speed to get net speed
    LDA \3      ; Larger speed (Low 8 bits)
    CLC
    SBC \2      ; Subtract smaller speed
    STA \3
    LDA \3 + 1  ; Larger speed (High 8 bits)
    SBC \2 + 1  ; Subtract smaller speed (don't clear carry flag)
    STA \3 + 1
    LDA #0
    STA \2      ; Zero smaller speed
    .endm

    
ChangeSpriteCheck .macro ; parameters: check_value, dont_change_label, tile_if_changed, tile_to_change, end_jump_function

    LDA \1
    BEQ \2  ; Change sprite if value is true (1)
    LDA \3  ; Get new tile number value
    STA \4  ; Store new value
    JMP \5  ; Jump to skip other sprite checks
    .endm

ResetPlayer .macro
    LDA #0
    STA score_1                     ; Reset score units
    STA score_10                    ; Reset score tens
    STA player_right_speed          ; Stop player run speed
    STA player_right_speed + 1
    STA player_left_speed
    STA player_left_speed + 1
    STA player_vertical_speed                ; Stop player fall
    STA player_vertical_speed + 1
    ; Move player back to start
    LDA #PLAYER_START_POSITION_Y    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #PLAYER_START_POSITION_X    ; X position
    STA sprite_player + SPRITE_X
    .endm

; ResetBandages .macro
;     LDX #0
;     LDA BANDAGE_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_START_X
;     STA sprite_bandage + SPRITE_X, X
;     INX
;     INX
;     INX
;     INX
;     LDA BANDAGE_1_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_1_START_X
;     STA sprite_bandage + SPRITE_X, X
;     INX
;     INX
;     INX
;     INX
;     LDA BANDAGE_2_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_2_START_X
;     STA sprite_bandage + SPRITE_X, X
;     INX
;     INX
;     INX
;     INX
;     LDA BANDAGE_3_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_3_START_X
;     STA sprite_bandage + SPRITE_X, X
;     INX
;     INX
;     INX
;     INX
;     LDA BANDAGE_4_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_4_START_X
;     STA sprite_bandage + SPRITE_X, X
;     INX
;     INX
;     INX
;     INX
;     LDA BANDAGE_5_START_Y
;     STA sprite_bandage + SPRITE_Y, X
;     LDA BANDAGE_5_START_X
;     STA sprite_bandage + SPRITE_X, X
;     .endm

FloorCollisionCheck .macro ; Parameters: Ground_Y_Top, Ground_X_Left, Ground_X_Right, Next_Collision_Check, Break_Out_Label
    LDA sprite_player + SPRITE_X    ; Check player left is less than the right side
    CMP \3                          
    BCS \4                          ; Branch if player is to the right of collision
    ; Check player right is more than the right side
    ADC #8                          ; Add 8 to get right side of player
    CMP \2                          
    BCC \4                          ; Branch if player is to the right of collision
    ; Check player right is to the left of Ground_X2
    LDA sprite_player + SPRITE_Y    ; Get top of player sprite
    ; Check player head is above top of floor
    CMP \1
    BCS \4                          ; Branch to next collision if player is lower than the floor 
    ADC #8                          ; Add 8 (player height) to get feet
    CMP \1                          ; Top of floor
    BCC \4                          ; Branch to next collision if player is higher than the floor 
    LDA \1
    SBC #8                          ; Subtract 8 to get snap position of player
    STA sprite_player + SPRITE_Y
    .endm

CheckVerticalCollision .macro ; Parameters: Wall_Y_Top, Wall_Y_Bottom, Next_Collision_Check
    LDA sprite_player + SPRITE_Y    ; Check player top is less than (above) bottom of wall
    CMP \2
    BCS \3                          ; Branch if above wall
    ADC #8                          ; Add 8 (player width) to get bottom of player
    CMP \1                          ; Check player bottom is more than (below) top of wall
    BCC \3                          ; Branch if below wall
    .endm

PlayerOnWall .macro ; Parameters: WallJump, SnapToLocation
    LDA #1                          
    STA \1                          ; Allow wall jumping
    LDA \2                        
    STA sprite_player + SPRITE_X    ; Snap player to wall
    JMP StopHorizontalMomentum      ; Break out of wall collision checks
    .endm
; ---------------------------------------------------------------------------

; NMI is called on every frame
NMI:
    ; Initialise controller 1
    LDA #1
    STA JOYPAD1
    LDA #0
    STA JOYPAD1
    STA TOUCHING_GROUND  ; Default ground touching to false
    STA WALL_JUMP_RIGHT  ; Default wall jumping to false
    STA WALL_JUMP_LEFT
    
    ; Read joypad state
    LDX #0
    STX joypad1_state

; Floor checks, check must happen top down
CheckFloors:
    FloorCollisionCheck #63, #97, #127, CheckFloor1
    LDA #1
    STA TOUCHING_GROUND             ; Set touching ground to true
    JMP CheckWalls

CheckFloor1:
    FloorCollisionCheck #63, #161, #175, CheckFloor2
    LDA #1
    STA TOUCHING_GROUND             ; Set touching ground to true
    JMP CheckWalls

CheckFloor2:
    FloorCollisionCheck #143, #81, #175, CheckScreenBottom
    LDA #1
    STA TOUCHING_GROUND             ; Set touching ground to true
    JMP CheckWalls

CheckScreenBottom:
    ; Collision with bottom
    FloorCollisionCheck #223, #15, #240, CheckWalls
    STA TOUCHING_GROUND             ; Set touching ground to true
    JMP CheckWalls

CheckWalls:
; ScreenRight:
;     LDA sprite_player + SPRITE_X
;     CMP #17                         ; Pixel of leeway for wall jumping                         
;     BCS CheckSpace1                 ; Keep checking wall collisions if player is to the right of #17
;     LDA #16                         ; Player is touching left wall
;     STA sprite_player + SPRITE_X
;     LDA #1
;     STA WALL_JUMP_RIGHT
;     JMP StopHorizontalMomentum
; CheckSpace1:
;     CMP #88
;     BCC CheckColumn3                 ; If player is to the left of #80 and right of #17 it is not touching any right walls
; CheckColumn2:
;     CMP #97            
;     BCS CheckColumn3                ; Branch if player is to the right of #96
;     LDA sprite_player + SPRITE_Y    ; Player is in range of wall 1
;     CMP #144                        ; Branch if player is above wall 1
;     BCC CheckColumn3
;     LDA #96
;     STA sprite_player + SPRITE_X
;     LDA #1
;     STA WALL_JUMP_RIGHT
;     JMP StopHorizontalMomentum

; CheckColumn3:
;     ;TODO CHECK RIGHT WALL
;     JMP ReadController

ScreenRight:
    LDA sprite_player + SPRITE_X    ; Get left of player
    CMP #232
    BCC ScreenLeft                  ; If less than 232, try rest of collisions
    ; Player is on screen right
    PlayerOnWall WALL_JUMP_LEFT, #232
ScreenLeft:
    CMP #17
    BCS ColumnCollisionCheckDone    ; If greater than 17, try next column 
    ; Player is on screen left
    PlayerOnWall WALL_JUMP_RIGHT, #16
XCol1:
    CMP #72
    BCC ColumnCollisionCheckDone    ; If #17 < sprite_player + SPRITE_X < #72, it is touching no walls
    CMP #80
    BCS XCol2                       ; If greater than 80, try next column
    ; TODO CHECK Y VALUE
    ; Parameters: Wall_Y_Top, Wall_Y_Bottom, Next_Collision_Check
    CheckVerticalCollision #144, #255, XCol2

XCol2:
    CMP #88
    BCS XCol3                       ; If greater than 88, try next column
    ; TODO CHECK Y VALUE
XCol3:
    CMP #96
    BCS XCol4                       ; If greater than 96, try next column
    ; TODO CHECK Y VALUE
XCol4:
    CMP #120
    BCC ColumnCollisionCheckDone    ; If #96 < sprite_player + SPRITE_X < #120, it is touching no walls
XCol5:
XCol6:
XCol7:
XCol8:





ColumnCollisionCheckDone:
    JMP ReadController



; CheckCeilings:


; ; Check goes from left to right
; CheckLeftWalls:

; ; Parameters: Wall_X_Right, Wall_Y_Top, Wall_Y_Bottom, Next_Collision_Check, Break_Out_Label

; CheckScreenLeft:
;     LeftWallCollisionCheck #16, #15, #240, CheckLeftWall1, StopHorizontalMomentum

; CheckLeftWall1:
;     LeftWallCollisionCheck #96, #176, #240, CheckLeftWall2, StopHorizontalMomentum

; CheckLeftWall2:
;     LeftWallCollisionCheck #128, #64, #80, CheckLeftWall3, StopHorizontalMomentum

; CheckLeftWall3:
;     LeftWallCollisionCheck #176, #64, #112, CheckLeftWall4, StopHorizontalMomentum

; CheckLeftWall4:
;     LeftWallCollisionCheck #176, #144, #184, ReadController, StopHorizontalMomentum

; ; Check goes from right to left
; ; CheckRightWalls:

; CheckScreenRight:
;     RightWallCollisionCheck #240, #15, #240, CheckRightWall1, StopHorizontalMomentum

; CheckRightWall1:
;     RightWallCollisionCheck #160, #15, #140, CheckRightWall2, StopHorizontalMomentum
    
; CheckRightWall2:
;     LeftWallCollisionCheck #176, #64, #112, CheckRightWall3, StopHorizontalMomentum
    
; CheckRightWall3:
;     LeftWallCollisionCheck #128, #80, #96, CheckRightWall4, StopHorizontalMomentum

; CheckRightWall4:
;     LeftWallCollisionCheck #96, #176, #240, ReadController, StopHorizontalMomentum


StopHorizontalMomentum:
    LDA #0                          
    STA player_left_speed           ; Stop player horizonal momentum
    STA player_left_speed + 1
    STA player_right_speed
    STA player_right_speed + 1
    

    JMP ReadController

ReadController:
    LDA JOYPAD1
    LSR A
    ROL joypad1_state
    INX
    CPX #8
    BNE ReadController

    LDA #0
    STA IS_RUNNING      ; Default is running to false

    ; React to Right button
    LDA joypad1_state
    AND #BUTTON_RIGHT
    BEQ ReadRight_Done       ; if ((JOYPAD1 & 1) != 0) {
    LDA #1 
    STA IS_RUNNING           ; Set is running bool to true
    CalculateSpeed player_right_speed, RUN_ACC

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
    STA IS_RUNNING      ; Set is running bool to true
    CalculateSpeed player_left_speed, RUN_ACC


ReadLeft_Done:         ; }

    ; React to Up button
    LDA joypad1_state
    AND #BUTTON_UP
    BEQ ReadUp_Done  ; if ((JOYPAD1 & 1) != 0) {

ReadUp_Done:         ; }

    ; React to A button
    LDA joypad1_state
    AND #BUTTON_A
    BEQ ReadA_Done
    LDA TOUCHING_GROUND
    BNE Jump                ; Allow jump if touching ground is true
    LDA WALL_JUMP_RIGHT     
    BNE WallJumpRight       ; Allow wall jumping right
    LDA WALL_JUMP_LEFT     
    BNE WallJumpLeft        ; Allow wall jumping left
    JMP ReadA_Done          ; Don't jump if not touching a surface
WallJumpRight:
    LDA #LOW(WALL_JUMP_SPEED)    ; Apply horizontal momentum
    STA player_right_speed
    LDA #HIGH(WALL_JUMP_SPEED)
    STA player_right_speed + 1
    JMP Jump                     ; Apply upward force
WallJumpLeft:
    LDA #LOW(WALL_JUMP_SPEED)    ; Apply horizontal momentum
    STA player_left_speed
    LDA #HIGH(WALL_JUMP_SPEED)
    STA player_left_speed + 1
    JMP Jump                     ; Apply upward force    
Jump:
    LDA #LOW(JUMP_SPEED)    ; Jump, set player speed
    STA player_vertical_speed
    LDA #HIGH(JUMP_SPEED)
    STA player_vertical_speed + 1

ReadA_Done:
    
    ; React to B button
    LDA joypad1_state
    AND #BUTTON_B
    BEQ ReadB_Done
    ; Reset score, player location and bandages
    ResetPlayer
    JMP NMI

ReadB_Done:
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    LDX #0

    LDA IS_RUNNING
    BNE KeepMomentum        ; Keep momentum if running
    LDA TOUCHING_GROUND
    BEQ KeepMomentum        ; Keep momentum if not touching ground
StopLeftMomentum:
    LDA #0
    STA player_left_speed       ; Stop left run momentum
    STA player_left_speed + 1
StopRightMomentum
    STA player_right_speed      ; Stop right run momentum
    STA player_right_speed + 1    
KeepMomentum:

CheckSpikeCollision:
; Check collision with spikes
    CheckForPlayerCollision sprite_spike + SPRITE_X, sprite_spike + SPRITE_Y, NoCollisionWithSpike, SpikeHit

; Handle collision
SpikeHit:
    LDA #0                          ; Stop player run speed
    STA player_right_speed
    STA player_right_speed + 1
    STA player_left_speed
    STA player_left_speed + 1
    STA player_vertical_speed       ; Stop player fall
    ; Move player back to start
    LDA #PLAYER_START_POSITION_Y    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #PLAYER_START_POSITION_X    ; X position
    STA sprite_player + SPRITE_X
    
	
NoCollisionWithSpike:


CheckBandages:
    LDX #0
    CheckForPlayerCollision sprite_bandage + SPRITE_X, sprite_bandage + SPRITE_Y, CheckBandage1, BandageHit
CheckBandage1:
    INX
    INX
    INX
    INX    
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 4, sprite_bandage + SPRITE_Y + 4, CheckBandage2, BandageHit
CheckBandage2:   
    INX 
    INX
    INX
    INX
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 8, sprite_bandage + SPRITE_Y + 8, CheckBandage3, BandageHit
CheckBandage3:
    INX 
    INX
    INX
    INX    
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 12, sprite_bandage + SPRITE_Y + 12, CheckBandage4, BandageHit
CheckBandage4:
    INX 
    INX
    INX
    INX    
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 16, sprite_bandage + SPRITE_Y + 16, CheckBandage5, BandageHit
CheckBandage5:
    INX 
    INX
    INX
    INX    
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 20, sprite_bandage + SPRITE_Y + 20, NoCollisionWithBandage, BandageHit

BandageHit:
    ; Delete bandage + add to score?
    LDA sprite_bandage + SPRITE_X, X
    ADC #3
    STA sprite_bandage + SPRITE_X, X
    LDA score_1     ; Increment score units
    ADC #1
    STA score_1
    CMP #10         ; See if score units is greater than 10
    BCC ShowScore
    SBC #10         ; Subtract 10 from score units
    STA score_1
    LDA score_10    ; Add 1 to score tens
    CLC
    ADC #1
    STA score_10
ShowScore:
    LDA score_1
    ADC #48      ; Tile number
    STA sprite_score_1 + SPRITE_TILE
    LDA score_10
    ADC #48
    STA sprite_score_10 + SPRITE_TILE

NoCollisionWithBandage:

    LDA TOUCHING_GROUND
    BEQ CalculateFall    ; Skip breaking fall if not touching ground
    LDA player_vertical_speed + 1
    CMP #20              ; Check if player speed is negative (jumping)
    BCS CalculateFall    ; Don't stop speed if jumping
    LDA #0               ; Stop falling
    STA player_vertical_speed     ; Low 8 bits
    STA player_vertical_speed + 1 ; High 8 bits
    JMP ApplyMomentumRight

CalculateFall:
    ; Check if speed is greater than max speed
    ;LDA MAX_SPEED
    ;CMP player_vertical_speed
    ;BCC ApplyGravity

    ; Increment player speed
    LDA player_vertical_speed    ; Low 8 bits
    CLC
    ADC #LOW(GRAVITY)
    STA player_vertical_speed
    LDA player_vertical_speed + 1 ; High 8 bits
    ADC #HIGH(GRAVITY)   ; Don't clear carry flag
    STA player_vertical_speed + 1
ApplyGravity:
    ; Apply fall to player
	LDA player_position_sub_y       ; Low 8 bits
    CLC
    ADC player_vertical_speed
    STA player_position_sub_y
    LDA sprite_player + SPRITE_Y  ; High 8 bits
    ADC player_vertical_speed + 1          ; Don't clear carry flag
    STA sprite_player + SPRITE_Y

ApplyMomentumRight:
    ; Apply right momentum to player
    LDA player_position_sub_x       ; Low 8 bits
    CLC
    ADC player_right_speed
    STA player_position_sub_x
    LDA sprite_player + SPRITE_X    ; High 8 bits
    ADC player_right_speed + 1      ; Don't clear carry flag
    STA sprite_player + SPRITE_X

ApplyMomentumLeft:
    ; Apply left momentum to player
    LDA player_position_sub_x     ; Low 8 bits
    CLC
    SBC player_left_speed
    STA player_position_sub_x
    LDA sprite_player + SPRITE_X  ; High 8 bits
    SBC player_left_speed + 1      ; Don't clear carry flag
    STA sprite_player + SPRITE_X

ApplyDrag:

; Sprite switcher/animator
CheckLeftWall:
    ChangeSpriteCheck WALL_JUMP_LEFT, CheckRightWall, #34, sprite_player + SPRITE_TILE, EndSpriteSwitching
CheckRightWall:
    ChangeSpriteCheck WALL_JUMP_RIGHT, RunningCheck, #33, sprite_player + SPRITE_TILE, EndSpriteSwitching
RunningCheck:
    LDA IS_RUNNING
    BEQ Idle
    LDA running_sprite_number   ; Get point in run animation
    CLC
    CMP RUN_ANIMATION_LENGTH    ; Make sure it is smaller than animation length
    BCC UpdateRunSprite
    LDA #0
    STA running_sprite_number       ; Reset run animation
UpdateRunSprite:
    ; LDA running_sprite_number
    ; ADC #16
    LDA #17
    STA sprite_player + SPRITE_TILE
    LDA running_sprite_number
    ADC #1
    STA running_sprite_number
    JMP EndSpriteSwitching
Idle:
    LDA #0
    STA running_sprite_number       ; Reset run animation
    LDA #16      ; Tile number
    STA sprite_player + SPRITE_TILE
EndSpriteSwitching:
    ;LDA score
    ;ADC score
    ;STA sprite_score + SPRITE_TILE
    
    
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
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$12,$12,$03,$01,$01,$01,$01,$02,$03,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$04,$13,$13,$05,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$04,$05,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$02,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$03,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$14,$13,$13,$13,$13,$13,$13,$13,$13,$15,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$04,$05,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$16,$12,$12,$12,$12,$12,$12,$12,$12,$17,$16,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$17,$11
    .db $04,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$05
    .db $00
    
    ;   %BRBLTRTL - B = Bottom, T = Top, L = Left, R = Right
    ;   Below Key: Top left tile location relative to each side.
    ;   1L 15R    |3L 13R    |5L 11R    |7L 9R     |9L 7R     |11L 5R    |13L       |15L
attribute:
    .db %10000000, %10000000, %10000000, %10000000, %10000000, %10000000, %10000000, %00000000  ; Row 1 & 2
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 3 & 4
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 5 & 6
    .db %10000000, %10000010, %10000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 7 & 8
    .db %10000000, %10000010, %00000010, %00000010, %00000010, %10000010, %10000010, %00000010  ; Row 9 & 10
    .db %10000000, %10000010, %00000010, %10000010, %10000010, %10000000, %10000010, %00000010  ; Row 11 & 12
    .db %10000000, %10000010, %00000010, %10000010, %10000010, %10000010, %10000010, %00000010  ; Row 13 & 14
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
