library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity top_equalizer is
    Port (
        CLOCK_50 : in STD_LOGIC;
        KEY : in STD_LOGIC_VECTOR(3 downto 0); -- KEY(0) reset, KEY(1) sel, KEY(2) up, KEY(3) down
        SW : in STD_LOGIC_VECTOR(2 downto 0);  -- SW(2..0) for band selection
        
        -- VGA Outputs for DE2-115 (8-bit DAC)
        VGA_R : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_G : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_B : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_HS : out STD_LOGIC;
        VGA_VS : out STD_LOGIC;
        VGA_CLK : out STD_LOGIC;
        VGA_BLANK_N : out STD_LOGIC;
        VGA_SYNC_N : out STD_LOGIC
    );
end top_equalizer;

architecture Structural of top_equalizer is
    
    -- Signals for User Interface
    signal reset : std_logic;
    signal btn_sel_pulse, btn_up_pulse, btn_dn_pulse : std_logic;
    signal gains : gain_array_t;
    signal selected_band : integer range 0 to 7;
    signal edit_mode : std_logic;
    
    -- Signals for VGA
    signal pixel_row, pixel_col : std_logic_vector(9 downto 0);
    signal video_on, pixel_clock_int : std_logic;
    signal draw_r, draw_g, draw_b : std_logic;
    signal sync_r, sync_g, sync_b : std_logic;

    -- Component declaration for VGA_SYNC
    component VGA_SYNC
        PORT( clock_50Mhz, red, green, blue : IN STD_LOGIC;
              red_out, green_out, blue_out, horiz_sync_out, 
              vert_sync_out, video_on, pixel_clock : OUT STD_LOGIC;
              pixel_row, pixel_column: OUT STD_LOGIC_VECTOR(9 DOWNTO 0));
    end component;
    
begin
    -- Assign reset (KEY0 is active low, so we invert it for active high reset inside)
    reset <= not KEY(0);
    
    -- Debouncers for buttons
    deb_sel: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(1), btn_pulse => btn_sel_pulse);
        
    deb_up: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(2), btn_pulse => btn_up_pulse);
        
    deb_dn: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(3), btn_pulse => btn_dn_pulse);

    -- User Interface Logic
    ui_inst: entity work.user_interface
        port map(
            clk => CLOCK_50,
            reset => reset,
            btn_sel_pulse => btn_sel_pulse,
            btn_up_pulse => btn_up_pulse,
            btn_dn_pulse => btn_dn_pulse,
            sw_band => SW(2 downto 0),
            gains_out => gains,
            selected_band_out => selected_band,
            edit_mode_out => edit_mode
        );

    -- VGA Drawer Logic
    drawer_inst: entity work.vga_drawer
        port map(
            clk => pixel_clock_int, -- Draw using pixel clock
            pixel_row => pixel_row,
            pixel_col => pixel_col,
            video_on => video_on,
            gains_in => gains,
            selected_band => selected_band,
            edit_mode => edit_mode,
            red => draw_r,
            green => draw_g,
            blue => draw_b
        );

    -- VGA Sync Generator (from resources)
    sync_inst: VGA_SYNC
        port map(
            clock_50Mhz => CLOCK_50,
            red => draw_r,
            green => draw_g,
            blue => draw_b,
            red_out => sync_r,
            green_out => sync_g,
            blue_out => sync_b,
            horiz_sync_out => VGA_HS,
            vert_sync_out => VGA_VS,
            video_on => video_on,
            pixel_clock => pixel_clock_int,
            pixel_row => pixel_row,
            pixel_column => pixel_col
        );

    -- Map 1-bit sync output to 8-bit DE2-115 VGA outputs
    VGA_R <= (others => '1') when sync_r = '1' else (others => '0');
    VGA_G <= (others => '1') when sync_g = '1' else (others => '0');
    VGA_B <= (others => '1') when sync_b = '1' else (others => '0');
    
    VGA_CLK <= pixel_clock_int;
    VGA_BLANK_N <= video_on;
    VGA_SYNC_N <= '0'; -- SYNC is on green, usually 0 for modern VGA

end Structural;
