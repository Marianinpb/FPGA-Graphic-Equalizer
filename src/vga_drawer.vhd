library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity vga_drawer is
    Port (
        clk : in STD_LOGIC;
        pixel_row : in STD_LOGIC_VECTOR(9 downto 0);
        pixel_col : in STD_LOGIC_VECTOR(9 downto 0);
        video_on : in STD_LOGIC;
        gains_in : in gain_array_t;
        selected_band : in integer range 0 to 7;
        edit_mode : in STD_LOGIC;
        red : out STD_LOGIC;
        green : out STD_LOGIC;
        blue : out STD_LOGIC
    );
end vga_drawer;

architecture Behavioral of vga_drawer is
    -- Screen dimensions
    constant MAX_X : integer := 640;
    constant MAX_Y : integer := 480;
    
    -- Bar layout parameters
    constant BAR_WIDTH : integer := 40;
    constant BAR_SPACING : integer := 20;
    constant TOTAL_BAR_WIDTH : integer := 8 * BAR_WIDTH + 7 * BAR_SPACING; -- 320 + 140 = 460
    constant START_X : integer := (MAX_X - TOTAL_BAR_WIDTH) / 2; -- (640 - 460) / 2 = 90
    constant BASE_Y : integer := 400; -- Bottom of the bars
    
begin
    process(clk)
        variable p_x : integer;
        variable p_y : integer;
        variable bar_idx : integer;
        variable in_bar_x : boolean;
        variable bar_height : integer;
    begin
        if rising_edge(clk) then
            if video_on = '1' then
                p_x := to_integer(unsigned(pixel_col));
                p_y := to_integer(unsigned(pixel_row));
                
                -- Default background: Black
                red <= '0';
                green <= '0';
                blue <= '0';
                
                in_bar_x := false;
                bar_idx := 0;
                
                -- Check if pixel is within the horizontal range of any bar
                for i in 0 to 7 loop
                    if (p_x >= START_X + i * (BAR_WIDTH + BAR_SPACING)) and 
                       (p_x < START_X + i * (BAR_WIDTH + BAR_SPACING) + BAR_WIDTH) then
                        in_bar_x := true;
                        bar_idx := i;
                    end if;
                end loop;
                
                if in_bar_x then
                    -- Calculate bar height based on gain (0-255).
                    bar_height := to_integer(gains_in(bar_idx));
                    
                    -- Check if pixel is within the vertical range of the bar
                    -- Bar goes from (BASE_Y - bar_height) down to BASE_Y.
                    if (p_y <= BASE_Y) and (p_y >= BASE_Y - bar_height) then
                        
                        -- Determine color
                        if bar_idx = selected_band then
                            if edit_mode = '1' then
                                -- Yellow when editing
                                red <= '1';
                                green <= '1';
                                blue <= '0';
                            else
                                -- Red when selected but not editing
                                red <= '1';
                                green <= '0';
                                blue <= '0';
                            end if;
                        else
                            -- Cyan for other bars
                            red <= '0';
                            green <= '1';
                            blue <= '1';
                        end if;
                        
                    end if;
                end if;
                
                -- Draw a base line
                if (p_y = BASE_Y + 1) and (p_x >= START_X - 10) and (p_x <= START_X + TOTAL_BAR_WIDTH + 10) then
                    red <= '1';
                    green <= '1';
                    blue <= '1';
                end if;
                
            else
                red <= '0';
                green <= '0';
                blue <= '0';
            end if;
        end if;
    end process;

end Behavioral;
