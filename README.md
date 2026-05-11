# 8-Band Graphic Equalizer (FPGA)

This project implements an 8-band digital graphic equalizer on an Altera DE2-115 FPGA board.

## Current Progress

### ✅ Phase 1 — UI & VGA Display (Stable — Compiles & Tested on Hardware)
- **VGA Interface**: Displays 8 vertical bars corresponding to the gain of each frequency band (640x480 @ 60Hz).
- **User Interface**: Handles button debouncing and a state machine to select and edit the gain of individual bands using physical switches and buttons.
- **Top Level Integration**: Maps the internal modules to the DE2-115 physical pins.
- **Clock Generation**: 25MHz pixel clock derived from 50MHz board clock via simple divider (no PLL IP required).

## Hardware Requirements
- Altera DE2-115 Development Board
- VGA Monitor

## Getting Started
1. Open `top_equalizer.qpf` in Quartus Prime (Tested on 23.1std).
2. Compile the design.
3. Program the DE2-115 board.
4. Connect a VGA monitor to view the equalizer interface.
5. Use `SW[2..0]` to select a band.
6. Press `KEY[1]` to enter edit mode (the selected bar will turn yellow).
7. Use `KEY[2]` (Up) and `KEY[3]` (Down) to adjust the gain.
8. Press `KEY[1]` again to exit edit mode.

## Project Structure
- `src/` - VHDL source files.
  - `top_equalizer.vhd` - Top level entity.
  - `vga_drawer.vhd` - VGA rendering logic.
  - `user_interface.vhd` - FSM and gain registers.
  - `debouncer.vhd` - Button debouncing logic.
  - `vga_sync.vhd` - VGA synchronization signal generator.
- `top_equalizer.qpf` - Quartus Project File.
- `top_equalizer.qsf` - Quartus Settings File (Pin assignments).
