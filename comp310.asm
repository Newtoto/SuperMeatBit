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

PLAYER__WIDTH   = 8
PLAYER__HEIGHT  = 8
PLAYER_START_POSITION_X = 128
PLAYER_START_POSITION_Y = 136

    .rsset $0000
joypad1_state           .rs 1
nametable_address       .rs 2
player_vertical_speed   .rs 2 ; Subpixels per frame -- 16 bits
player_position_sub_y   .rs 1
player_position_sub_x   .rs 1
player_right_speed      .rs 2 ; Subpixels per frame -- 16 bits
player_left_speed       .rs 2 ; Subpixels per frame -- 16 bits
gravity                 .rs 2 ; Subpixels per frame ^ 2
current_spike           .rs 1
is_running              .rs 1
touching_ground         .rs 1
wall_jump_right         .rs 1
wall_jump_left          .rs 1
bandages_collected      .rs 1
collision_location      .rs 1 ; 
running_sprite_number   .rs 1 ; Stores point of run animation
run_tick_counter        .rs 1
tick_counter            .rs 1
timer_seconds_units     .rs 1
timer_seconds_tens      .rs 1
timer_minutes_units     .rs 1
game_complete           .rs 1
faced_direction         .rs 1   ; 0 for left, 1 for right


    .rsset $0200
sprite_player               .rs 4
sprite_spike                .rs 40
sprite_bandage              .rs 24
sprite_seconds_units        .rs 4
sprite_seconds_tens         .rs 4
sprite_minutes_units        .rs 4
sprite_colon                .rs 4

    .rsset $0000
SPRITE_Y           .rs 1
SPRITE_TILE        .rs 1
SPRITE_ATTRIB      .rs 1
SPRITE_X           .rs 1

JUMP_SPEED          = -2 * 256      ; Subpixels per frame
RUN_SPEED           = 4 * 256       ; Subpixels per frame
RUN_ACC             = 8
MAX_SPEED           = 16
WALL_JUMP_SPEED     = 1 * 256       ; Subpixels per frame
RUN_ANIMATION_LENGTH = 8            ; Number of frames in run animation

; Bandage collectables locations starting top going left to right
BANDAGE_START_Y     = 19
BANDAGE_START_X     = 20

BANDAGE_1_START_Y   = 19
BANDAGE_1_START_X   = 228

BANDAGE_2_START_Y   = 87
BANDAGE_2_START_X   = 86

BANDAGE_3_START_Y   = 123
BANDAGE_3_START_X   = 164

BANDAGE_4_START_Y   = 163
BANDAGE_4_START_X   = 148

BANDAGE_5_START_Y   = 180
BANDAGE_5_START_X   = 72

; Timer location
TIMER_START_LOCATION_Y  = 4
TIMER_START_LOCATION_X  = 4

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
    
; Write sprite data for spikes, starting from top down from left to right
InitSpikes:
    ; SPIKE 1
    LDX #0
    LDA #33     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #5      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #232     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 2
    LDX #4
    LDA #67     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #5      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #88     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 3
    LDX #8
    LDA #79     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #5      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #152     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 4
    LDX #12
    LDA #79     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #7      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #176     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 5
    LDX #16
    LDA #111     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #3      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #164     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 6
    LDX #20
    LDA #135     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #1      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #164     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 7
    LDX #24
    LDA #159    ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #5      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #72     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 8
    LDX #28
    LDA #179    ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #7      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #16     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 9
    LDX #32
    LDA #199    ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #5      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #72     ; X position
    STA sprite_spike + SPRITE_X, X

    ; SPIKE 10
    LDX #36
    LDA #215     ; Y position
    STA sprite_spike + SPRITE_Y, X
    LDA #1      ; Tile number
    STA sprite_spike + SPRITE_TILE, X
    LDA #160     ; X position
    STA sprite_spike + SPRITE_X, X

    CLC
    LDX #0
    LDA #2
SpikeAttribLoop:
    STA sprite_spike + SPRITE_ATTRIB, X
    CPX #36         ; Check if it has reached the end of spikes
    BCS InitCollectables   ; Stop spike loop
    INX
    INX
    INX
    INX
    JMP SpikeAttribLoop

; Write sprite data for collectable bandages, starting from top down from left to right
InitCollectables:
    ; Set bandage locations
    ; BANDAGE 1
    LDX #0
    LDA #BANDAGE_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 2
    LDX #4
    LDA #BANDAGE_1_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_1_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 3
    LDX #8
    LDA #BANDAGE_2_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_2_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 4
    LDX #12
    LDA #BANDAGE_3_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_3_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 5
    LDX #16
    LDA #BANDAGE_4_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_4_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 6
    LDX #20
    LDA #BANDAGE_5_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #BANDAGE_5_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X

    ; Set bandage tile and attributes
    CLC
    LDX #0
BandageTileAttribLoop:
    LDA #0
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1
    STA sprite_bandage + SPRITE_ATTRIB, X
    CPX #20        ; Check if it has reached the end of bandages
    BCS InitTimer   ; Stop bandage loop
    INX
    INX
    INX
    INX
    JMP BandageTileAttribLoop

InitTimer:
    LDA #$0
    STA timer_seconds_units    ; Set timer to 0
    STA timer_seconds_tens
    STA timer_minutes_units
    
    ; Tile number
    LDA #48
    STA sprite_minutes_units + SPRITE_TILE
    STA sprite_seconds_tens + SPRITE_TILE
    STA sprite_seconds_units + SPRITE_TILE
    LDA #$3a
    STA sprite_colon + SPRITE_TILE
    ; Y Location
    LDA #TIMER_START_LOCATION_Y
    STA sprite_minutes_units + SPRITE_Y
    STA sprite_colon + SPRITE_Y
    STA sprite_seconds_tens + SPRITE_Y
    STA sprite_seconds_units + SPRITE_Y
    ; X Location
    LDA #TIMER_START_LOCATION_X
    STA sprite_minutes_units + SPRITE_X
    ADC #6
    STA sprite_colon + SPRITE_X
    ADC #6
    STA sprite_seconds_tens + SPRITE_X
    ADC #8
    STA sprite_seconds_units + SPRITE_X
    ; Attribute
    LDA #0
    STA sprite_minutes_units + SPRITE_ATTRIB
    STA sprite_colon + SPRITE_ATTRIB
    STA sprite_seconds_tens + SPRITE_ATTRIB
    STA sprite_seconds_units + SPRITE_ATTRIB
    

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
    SBC #8
    CMP \1
    BCS \3  ; Not colliding if x is greater than the right side
    CLC
    ADC #15
    CMP \1
    BCC \3  ; Not colliding if x is less than the left side
    ; Vertical check
    LDA sprite_player + SPRITE_Y
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

; Moves everything back to the start and resets timer, keeping blood on spikes
ResetPlayer .macro
    ; Reset timer and tick counter
    LDA #0
    STA timer_seconds_units              
    STA timer_seconds_tens                    
    STA timer_minutes_units
    STA tick_counter
    STA game_complete               ; Reset game
    ; Reset player momentum
    STA player_right_speed          ; Stop player run speed
    STA player_right_speed + 1
    STA player_left_speed
    STA player_left_speed + 1
    STA player_vertical_speed                ; Stop player fall
    STA player_vertical_speed + 1
    ; Move player back to start
    CLC
    LDA #PLAYER_START_POSITION_Y    ; Y position
    STA sprite_player + SPRITE_Y
    LDA #PLAYER_START_POSITION_X    ; X position
    STA sprite_player + SPRITE_X
    ; Reset timer sprites
    CLC
    ; Reset sprites to 0
    LDA #48
    STA sprite_minutes_units + SPRITE_TILE
    STA sprite_seconds_tens + SPRITE_TILE
    STA sprite_seconds_units + SPRITE_TILE
    ; Reset Location of timer
    LDA #TIMER_START_LOCATION_Y
    STA sprite_minutes_units + SPRITE_Y
    STA sprite_colon + SPRITE_Y
    STA sprite_seconds_tens + SPRITE_Y
    STA sprite_seconds_units + SPRITE_Y
    LDA #TIMER_START_LOCATION_X
    STA sprite_minutes_units + SPRITE_X
    ADC #6
    STA sprite_colon + SPRITE_X
    ADC #6
    STA sprite_seconds_tens + SPRITE_X
    ADC #8
    STA sprite_seconds_units + SPRITE_X

    ResetBandages
    .endm

; Reset bandage position, tile and attributes
ResetBandages .macro
    LDA #0
    STA bandages_collected  ; Reset number of bandages collected
    ; BANDAGE 1
    LDX #0
    LDA #BANDAGE_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 2
    LDX #4
    LDA #BANDAGE_1_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_1_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 3
    LDX #8
    LDA #BANDAGE_2_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_2_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 4
    LDX #12
    LDA #BANDAGE_3_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_3_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 5
    LDX #16
    LDA #BANDAGE_4_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_4_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    ; BANDAGE 6
    CLC
    LDX #20
    LDA #BANDAGE_5_START_Y     ; Y position
    STA sprite_bandage + SPRITE_Y, X
    LDA #0      ; Tile number
    STA sprite_bandage + SPRITE_TILE, X
    LDA #1      ; Attributes
    STA sprite_bandage + SPRITE_ATTRIB, X
    LDA #BANDAGE_5_START_X    ; X position
    STA sprite_bandage + SPRITE_X, X
    
    .endm

; Checks if player is touching a floor using Y position and left and right parameters
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

; Checks if player is within left and right bounds
CheckHorizontalCollision .macro ; Parameters: Wall_X_Left, Wall_X_Right, Next_Collision_Check
    LDA sprite_player + SPRITE_X    ; Check player left is greater than right of collision 
    CMP \2                          
    BCC \3                          ; Branch if to the right of collision
    ADC #PLAYER__WIDTH              ; Add 8 (player width) to get right of player
    CMP \1                          ; Check player right is less than left of collision
    BCS \3                          ; Branch if to the left of collision
    .endm

; Checks if player is within top and bottom bounds
CheckVerticalCollision .macro ; Parameters: Wall_Y_Top, Wall_Y_Bottom, Next_Collision_Check
    LDA sprite_player + SPRITE_Y    ; Check player top is less than (above) bottom of wall
    CMP \2
    BCS \3                          ; Branch if above wall
    ADC #8                          ; Add 8 (player height) to get bottom of player
    CMP \1                          ; Check player bottom is more than (below) top of wall
    BCC \3                          ; Branch if below wall
    .endm

; Sets walljump and snaps player to wall
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
    STA touching_ground  ; Default ground touching to false
    STA wall_jump_right  ; Default wall jumping to false
    STA wall_jump_left
    
    ; Read joypad state
    LDX #0
    STX joypad1_state

; Collision check for ceilings
CheckCeilings:
CheckScreenTop:
    LDA sprite_player + SPRITE_Y
    CMP #15
    BCS CheckCeiling      ; If player y is greater than #16 they are not touching the top
    LDA #15
    STA sprite_player + SPRITE_Y
    LDA #0
    STA player_vertical_speed
    STA player_vertical_speed + 1
    ;JMP CheckWalls
CheckCeiling:
    CMP #159
    BCS CheckFloors     ; If player y is greater than #159 they are not touching the ceiling
    CMP #151
    BCC CheckFloors     ; If player y is less than #151 they are not touching the ceiling
    LDA sprite_player + SPRITE_X    ; Get left side of player
    CMP #169                        ; Compare with the right of ceiling
    BCS CheckFloors                 ; If left of player is greater than right of ceiling , it is not touching
    ADC #PLAYER__WIDTH              ; Add player width to get right of player
    CMP #88                         ; Compare with the left of ceiling
    BCC CheckFloors                 ; If right of player is greater than left of ceiling it is not touching
    LDA #159                                
    STA sprite_player + SPRITE_Y    ; Snap player to ceiling
    LDA #0
    STA player_vertical_speed
    STA player_vertical_speed + 1   ; Stop upward momentum 

; Floor checks, check must happen top down
CheckFloors:
CheckScreenBottom:
    LDA sprite_player + SPRITE_Y
    CMP #215
    BCC CheckFloor      ; If player is below #223 they are not touching the bottom
    LDA #215
    STA sprite_player + SPRITE_Y
    LDA #1
    STA touching_ground
    JMP CheckWalls

CheckFloor:   
    FloorCollisionCheck #63, #97, #127, CheckFloor1
    LDA #1
    STA touching_ground             ; Set touching ground to true
    JMP CheckWalls

CheckFloor1:
    FloorCollisionCheck #63, #161, #175, CheckFloor2
    LDA #1
    STA touching_ground             ; Set touching ground to true
    JMP CheckWalls

CheckFloor2:
    FloorCollisionCheck #143, #81, #175, CheckWalls
    LDA #1
    STA touching_ground             ; Set touching ground to true
    JMP CheckWalls

CheckWalls:
    LDA sprite_player + SPRITE_X        ; Get left of player
ScreenRight:
    CMP #232
    BCC ScreenLeft                      ; If less than 232, try rest of collisions
    PlayerOnWall wall_jump_left, #232   ; Player is touching screen right
ScreenLeft:
    CMP #17
    BCS XCol1                           ; If greater than 17, try next column 
    PlayerOnWall wall_jump_right, #16   ; Player is touching screen left
XCol1:
    CMP #72
    BCC JumpToCollisionEnd              ; If #17 < sprite_player + SPRITE_X < #72, it is touching no walls
    CMP #80
    BCS XCol2                                                       ; If greater than 80, try next column
    ; LEFT MOST WALL ATTATCHED TO FLOOR (LEFT SIDE)
    CheckVerticalCollision #144, #255, XCol3                        ; If player isn't in range of wall, stop checking wall collisions
    PlayerOnWall wall_jump_left, #72                                ; Player is touching right wall
XCol2:
    CMP #88
    BCC JumpToCollisionEnd              ; If #80 < sprite_player + SPRITE_X < #88, it is touching no walls
    CMP #97
    BCS XCol3                                                       ; If greater than 97, try next column
    ; HORIZONTAL HOVERING WALL (LEFT SIDE)
    CheckVerticalCollision #64, #80, CheckOtherWall                 ; If player isn't in range of uppermost wall, check lower wall
    PlayerOnWall wall_jump_left, #88                                ; Player is touching left wall
CheckOtherWall:
    ; LEFT MOST WALL ATTATCHED TO FLOOR (RIGHT SIDE)
    CheckVerticalCollision #160, #255, XCol5                        ; If player isn't in range of wall, stop checking wall collisions
    PlayerOnWall wall_jump_right, #96                               ; Player is touching right wall
XCol3:
    CMP #120
    BCC JumpToCollisionEnd              ; If #97 < sprite_player + SPRITE_X < #120, it is touching no walls
    CMP #129
    BCS XCol4                                                       ; If greater than 129, try next column
    ; ; HORIZONTAL HOVERING WALL (RIGHT SIDE)
    CheckVerticalCollision #64, #80, JumpToCollisionEnd             ; If player isn't in range of wall, stop checking wall collisions
    PlayerOnWall wall_jump_right, #128                              ; Player is touching left wall
JumpToCollisionEnd:
    ; Needed to branch to end of collisions
    JMP ColumnCollisionCheckDone
XCol4:
    CMP #152
    BCC ColumnCollisionCheckDone        ; If #129 < sprite_player + SPRITE_X < #152, it is touching no walls
    CMP #160
    BCS XCol5                                                       ; If greater than 160, try next column
    ; VERTICAL HOVERING WALL (LEFT SIDE)
    CheckVerticalCollision #64, #112, CheckOtherWall2               ; If player isn't in range of uppermost wall, check lower wall
    PlayerOnWall wall_jump_left, #152                               ; Player is touching right wall
CheckOtherWall2:
    ; DANGLING WALL (LEFT SIDE)
    CheckVerticalCollision #160, #176, ColumnCollisionCheckDone     ; If player isn't in range of wall, stop checking wall collisions
    PlayerOnWall wall_jump_left, #152                               ; Player is touching right wall
XCol5:
    CMP #168
    BCC ColumnCollisionCheckDone        ; If #160 < sprite_player + SPRITE_X < #168, it is touching no walls
    CMP #177
    BCS ColumnCollisionCheckDone                                    ; If greater than 176, player is touching no walls
    ; VERTICAL HOVERING WALL (RIGHT SIDE)
    CheckVerticalCollision #64, #112, CheckOtherWall3               ; If player isn't in range of uppermost wall, check lower wall
    PlayerOnWall wall_jump_right, #176                              ; Player is touching left wall
CheckOtherWall3:
    ; DANGLING WALL (RIGHT SIDE)
    CheckVerticalCollision #144, #176, ColumnCollisionCheckDone     ; If player isn't in range of wall, stop checking wall collisions
    PlayerOnWall wall_jump_right, #176                              ; Player is touching right wall



ColumnCollisionCheckDone:
    JMP ReadController

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
    STA is_running      ; Default is running to false

    ; React to Right button
    LDA joypad1_state
    AND #BUTTON_RIGHT
    BEQ ReadRight_Done      ; if ((JOYPAD1 & 1) != 0) {
    LDA #1 
    STA is_running          ; Set is running bool to true
    STA faced_direction     ; Set face direction to right (1)
    CalculateSpeed player_right_speed, RUN_ACC

ReadRight_Done:         ; }

;     ; React to Down button
;     LDA joypad1_state
;     AND #BUTTON_DOWN
;     BEQ ReadDown_Done  ; if ((JOYPAD1 & 1) != 0) {
    

ReadDown_Done:         ; }

    ; React to Left button
    LDA joypad1_state
    AND #BUTTON_LEFT
    BEQ ReadLeft_Done  ; if ((JOYPAD1 & 1) != 0) {
    LDA #1
    STA is_running      ; Set is running bool to true
    LDA #0
    STA faced_direction ; Set face direction to left (0)
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
    LDA touching_ground
    BNE Jump                ; Allow jump if touching ground is true
    LDA wall_jump_right     
    BNE WallJumpRight       ; Allow wall jumping right
    LDA wall_jump_left     
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
    BNE Reset     ; Reversed check because branch address is out of range
    JMP ReadB_Done      
    ; Reset timer, player location and bandages
Reset:
    ResetPlayer
    ResetBandages
    JMP NMI

ReadB_Done:

    ; Game complete check
    LDA game_complete
    BEQ ApplyMovement        ; Do movement if not complete
    JMP GameLoopDone

ApplyMovement:

    LDX #0

    LDA is_running
    BNE KeepMomentum        ; Keep momentum if running
    LDA touching_ground
    BEQ KeepMomentum        ; Keep momentum if not touching ground
StopLeftMomentum:
    LDA #0
    STA player_left_speed       ; Stop left run momentum
    STA player_left_speed + 1
StopRightMomentum
    STA player_right_speed      ; Stop right run momentum
    STA player_right_speed + 1    
KeepMomentum:

CheckSpikeCollisions:
; Check collision with spikes
CheckSpike1:
    LDY #0
    LDA #6
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike2, SpikeHit
CheckSpike2:
    LDY #4
    LDA #6
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike3, SpikeHit
CheckSpike3:
    LDY #8
    LDA #6
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike4, SpikeHit
CheckSpike4:
    LDY #12
    LDA #8
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike5, SpikeHit
CheckSpike5:
    LDY #16
    LDA #4
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike6, SpikeHit
CheckSpike6:
    LDY #20
    LDA #2
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike7, SpikeHit
CheckSpike7:
    LDY #24
    LDA #6
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike8, SpikeHit
CheckSpike8:
    LDY #28
    LDA #8
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike9, SpikeHit
CheckSpike9:
    LDY #32
    LDA #6
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , CheckSpike10, SpikeHit
CheckSpike10:
    LDY #36
    LDA #2
    STA current_spike
    CheckForPlayerCollision sprite_spike + SPRITE_X, Y , sprite_spike + SPRITE_Y, Y , NoCollisionWithSpike, SpikeHit

NoCollisionWithSpike:
    JMP CheckBandages

; Handle collision
SpikeHit:
    LDA current_spike
    STA sprite_spike + SPRITE_TILE, Y  ; Make spike bloody when hit
    ResetPlayer

CheckBandages:
    LDX #0
    CheckForPlayerCollision sprite_bandage + SPRITE_X, sprite_bandage + SPRITE_Y, CheckBandage1, BandageHit
CheckBandage1:
    LDX #4  
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 4, sprite_bandage + SPRITE_Y + 4, CheckBandage2, BandageHit
CheckBandage2:   
    LDX #8
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 8, sprite_bandage + SPRITE_Y + 8, CheckBandage3, BandageHit
CheckBandage3:
    LDX #12 
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 12, sprite_bandage + SPRITE_Y + 12, CheckBandage4, BandageHit
CheckBandage4:
    LDX #16     
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 16, sprite_bandage + SPRITE_Y + 16, CheckBandage5, BandageHit
CheckBandage5:
    LDX #20    
    CheckForPlayerCollision sprite_bandage + SPRITE_X + 20, sprite_bandage + SPRITE_Y + 20, NoCollisionWithBandage, BandageHit

BandageHit:
    ; Hide and move bandage
    CLC         
    LDA #0
    STA sprite_bandage + SPRITE_X, X    ; Move sprite into left border
    LDA #$0f
    STA sprite_bandage + SPRITE_TILE, X     ; Use invisible sprite
    LDA bandages_collected
    ADC #1
    STA bandages_collected              ; Increment bandage collected number
    CMP #6
    BCS WinState                        ; End game (win) if number of collected bandages is 6

NoCollisionWithBandage:
    JMP VerticalMomentum

WinState:
    ; Move time sprites down
    LDA #132
    STA sprite_seconds_units + SPRITE_Y
    STA sprite_seconds_tens + SPRITE_Y
    STA sprite_minutes_units + SPRITE_Y
    STA sprite_colon + SPRITE_Y
    ; Move time sprites across
    CLC
    LDA sprite_minutes_units + SPRITE_X
    ADC #28
    STA sprite_minutes_units + SPRITE_X
    ADC #8
    STA sprite_colon + SPRITE_X
    ADC #8
    STA sprite_seconds_tens + SPRITE_X
    ADC #8
    STA sprite_seconds_units + SPRITE_X
    
    ; Move bandage sprites to repurpose for "Your time" text
    LDA #116
    STA sprite_bandage + SPRITE_Y
    STA sprite_bandage + SPRITE_Y + 4
    STA sprite_bandage + SPRITE_Y + 8
    STA sprite_bandage + SPRITE_Y + 12
    CLC
    LDA #32
    STA sprite_bandage + SPRITE_X
    ADC #8
    STA sprite_bandage + SPRITE_X + 4
    ADC #8
    STA sprite_bandage + SPRITE_X + 8
    ADC #8
    STA sprite_bandage + SPRITE_X + 12
    ; Change bandage sprite to your time text
    LDA #$40
    STA sprite_bandage + SPRITE_TILE
    LDA #$41
    STA sprite_bandage + SPRITE_TILE + 4
    LDA #$42
    STA sprite_bandage + SPRITE_TILE + 8
    LDA #$43
    STA sprite_bandage + SPRITE_TILE + 12

    LDA #1
    STA game_complete   ; Set game complete to true

VerticalMomentum:
    LDA touching_ground
    BEQ CalculateFall    ; Skip breaking fall if not touching ground
    LDA player_vertical_speed + 1
    CMP #20              ; Check if player speed is negative (jumping)
    BCS CalculateFall    ; Don't stop speed if jumping
    LDA #0               ; Stop falling
    STA player_vertical_speed     ; Low 8 bits
    STA player_vertical_speed + 1 ; High 8 bits
    JMP ApplyMomentumRight

CalculateFall:
    LDA #16
    STA gravity     ; Default gravity to 16
CheckFallRightWall:
    LDA wall_jump_left
    BEQ CheckFallLeftWall
    LDA #5
    STA gravity     ; If on wall slow gravity
CheckFallLeftWall:
    LDA wall_jump_right
    BEQ IncrementFallSpeed
    LDA #5
    STA gravity     ; If on wall slow gravity
IncrementFallSpeed:    
    ; Increment player speed
    LDA player_vertical_speed    ; Low 8 bits
    CLC
    ADC gravity
    STA player_vertical_speed
    LDA player_vertical_speed + 1 ; High 8 bits
    ADC gravity + 1   ; Don't clear carry flag
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
    ChangeSpriteCheck wall_jump_left, CheckRightWall, #34, sprite_player + SPRITE_TILE, EndSpriteSwitching
CheckRightWall:
    ChangeSpriteCheck wall_jump_right, RunningCheck, #33, sprite_player + SPRITE_TILE, EndSpriteSwitching
RunningCheck:
    LDA is_running
    BEQ Idle
    CLC 
    LDA run_tick_counter
    ADC #1
    STA run_tick_counter        ; Increment run tick counter
    CMP #5                      ; If tick counter reaches #20 increment sprite number
    BCC CheckRunDirection
    LDA #0
    STA run_tick_counter        ; Reset run tick counter
    LDA running_sprite_number   ; Get point in run animation
    ADC #1
    STA running_sprite_number
    CMP #RUN_ANIMATION_LENGTH    ; Make sure it is smaller than animation length
    BCC CheckRunDirection
    LDA #0
    STA running_sprite_number       ; Reset run animation
CheckRunDirection:
    CLC
    LDA faced_direction
    BNE RunRight             ; Facing right
RunLeft:                     ; Default to left
    LDA running_sprite_number
    ADC #$23                    ; Add on location of first left run sprite
    JMP UpdateRunSprite
RunRight:
    LDA running_sprite_number
    ADC #$11                    ; Add on location of first right run sprite
UpdateRunSprite:
    STA sprite_player + SPRITE_TILE
    JMP EndSpriteSwitching
Idle:
    LDA #0
    STA run_tick_counter            ; Reset run tick counter
    STA running_sprite_number       ; Reset run animation
    LDA #16      ; Tile number
    STA sprite_player + SPRITE_TILE
EndSpriteSwitching:

; Use number of ticks to increment the timer
CountUpTimer:
    ; Count up tick_counter
    LDA tick_counter
    ADC #1
    STA tick_counter
    CMP #60                 ; If ticks reach 60, reset counter and add increment second units
    BCC DontIncrementTimer
    CLC
    LDA #0
    STA tick_counter
    LDA timer_seconds_units
    ADC #1
    STA timer_seconds_units
    CMP #10                 ; If second units reach 10, reset second units and increment second tens
    BCC ShowTimer
    CLC
    LDA #0
    STA timer_seconds_units
    LDA timer_seconds_tens
    ADC #1
    STA timer_seconds_tens
    CMP #6                  ; If second tens reach 6, reset second tens and increment minute units
    BCC ShowTimer
    LDA #0
    STA timer_seconds_tens
    CLC
    LDA timer_minutes_units
    ADC #1
    STA timer_minutes_units
    CMP #10                 ; If minutes units reach 10, reset player
    BCC ShowTimer
    JMP TimeUp
ShowTimer:
    LDA timer_seconds_units
    ADC #48
    STA sprite_seconds_units + SPRITE_TILE
    LDA timer_seconds_tens
    ADC #48
    STA sprite_seconds_tens + SPRITE_TILE
    LDA timer_minutes_units
    ADC #48
    STA sprite_minutes_units + SPRITE_TILE

DontIncrementTimer:
    JMP GameLoopDone

; Times out if play time exceeds 9 minutes and 59 seconds
TimeUp:
    ResetPlayer

GameLoopDone:
    LDA #0
    STA OAMADDR
    LDA #$02
    STA OAMDMA

    RTI         ; Return from interrupt




; ---------------------------------------------------------------------------

; Background sprite layout
nametable:
    .db $02,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$03
    .db $10,$14,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$15,$11
    .db $20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11
    .db $10,$21,$01,$44,$45,$46,$47,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $30,$11,$01,$54,$55,$56,$57,$01,$01,$01,$01,$01,$01,$01,$01,$65,$66,$67,$68,$69,$6a,$6b,$01,$01,$01,$01,$4a,$4b,$4c,$01,$20,$11
    .db $10,$21,$4a,$4b,$4c,$01,$01,$01,$01,$01,$01,$01,$01,$01,$74,$75,$76,$77,$78,$79,$7a,$7b,$7c,$01,$58,$59,$5a,$5b,$5c,$5d,$10,$11
    .db $20,$21,$5a,$5b,$5c,$5d,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$0d,$0c,$01,$08,$01,$01,$01,$01,$09,$01,$01,$01,$01,$01,$01,$01,$01,$01,$20,$11
    .db $20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$02,$12,$12,$03,$01,$01,$01,$01,$02,$03,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11
    .db $20,$21,$01,$01,$01,$01,$01,$01,$01,$44,$45,$46,$04,$13,$13,$05,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$54,$55,$56,$57,$01,$01,$01,$01,$01,$01,$01,$20,$21,$01,$01,$01,$01,$01,$01,$01,$01,$20,$11
    .db $20,$21,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11,$4b,$4c,$01,$01,$01,$01,$01,$01,$10,$11
    .db $30,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$41,$42,$01,$01,$01,$58,$10,$21,$5b,$5c,$5d,$01,$01,$01,$01,$01,$20,$11
    .db $20,$21,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$51,$52,$01,$01,$01,$01,$04,$05,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11
    .db $30,$21,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$60,$61,$62,$63,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$41,$42,$01,$70,$71,$72,$73,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$20,$11
    .db $30,$21,$01,$01,$01,$01,$01,$01,$01,$01,$51,$52,$01,$01,$50,$53,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$40,$43,$0c,$0d,$40,$43,$01,$08,$01,$09,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11
    .db $10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$02,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$03,$01,$01,$01,$01,$01,$01,$01,$01,$20,$11
    .db $20,$21,$01,$01,$01,$01,$01,$01,$01,$01,$10,$14,$13,$13,$13,$13,$13,$13,$13,$13,$15,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11
    .db $10,$21,$01,$01,$01,$01,$01,$01,$01,$01,$30,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$41,$42,$20,$11
    .db $20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$04,$05,$01,$01,$01,$01,$01,$01,$70,$73,$10,$11
    .db $30,$21,$01,$01,$01,$01,$01,$01,$01,$01,$20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$41,$61,$62,$20,$11
    .db $10,$11,$01,$01,$41,$42,$01,$01,$01,$01,$10,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$51,$61,$62,$30,$11
    .db $20,$21,$01,$01,$51,$52,$01,$01,$01,$01,$20,$11,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$60,$61,$62,$62,$10,$11
    .db $30,$11,$01,$60,$61,$62,$63,$01,$01,$01,$30,$11,$01,$01,$41,$42,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$70,$71,$71,$72,$20,$11
    .db $20,$11,$01,$70,$71,$72,$73,$01,$01,$01,$20,$11,$01,$01,$51,$52,$01,$01,$0a,$0b,$01,$01,$01,$01,$01,$01,$01,$01,$50,$53,$10,$11
    .db $10,$21,$0c,$0d,$40,$43,$09,$01,$09,$08,$20,$11,$09,$01,$40,$43,$01,$01,$1a,$1b,$01,$1d,$09,$01,$0d,$01,$4a,$4c,$40,$43,$20,$11
    .db $10,$16,$12,$12,$12,$12,$12,$12,$12,$12,$17,$16,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$12,$17,$11
    .db $04,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$13,$05
    .db $00
    
    ;   %BRBLTRTL - B = Bottom, T = Top, L = Left, R = Right
    ;   Below Key: Top left tile location relative to each side.
    ;   1L 15R    |3L 13R    |5L 11R    |7L 9R     |9L 7R     |11L 5R    |13L       |15L
attribute:
    .db %11010101, %11110101, %11110101, %11110101, %11110101, %11110101, %11110101, %01110101  ; Row 1 & 2
    .db %11011101, %11111111, %11111111, %10001111, %11111111, %11101111, %11111111, %01000111  ; Row 3 & 4
    .db %11011101, %11111111, %11111111, %11110101, %11111111, %11011101, %11111111, %01000110  ; Row 5 & 6
    .db %10010001, %11111111, %00000010, %11111111, %11111111, %10101101, %11111111, %01000110  ; Row 7 & 8
    .db %00010001, %11111111, %01000000, %01010000, %01011000, %11011010, %11111111, %01100110  ; Row 9 & 10
    .db %00010001, %00000000, %01000100, %00000000, %00000000, %00000001, %10000000, %01100110  ; Row 11 & 12
    .db %00010001, %00000000, %01100100, %00100000, %10101010, %10101010, %01101010, %01000110  ; Row 13 & 14
    .db %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101, %01010101  ; Row 15

paletteData:
    .db $3C,$39,$08,$29,$3C,$09,$19,$29,$3C,$05,$09,$28,$3C,$00,$10,$20  ; Background palette data
    .db $3C,$05,$0D,$39,$3C,$26,$15,$36,$3C,$05,$1D,$10,$3C,$30,$10,$00  ; Sprite palette data

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
