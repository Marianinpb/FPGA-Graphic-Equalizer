library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity user_interface is
    Port ( 
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        btn_sel_pulse : in STD_LOGIC;
        btn_up_pulse : in STD_LOGIC;
        btn_dn_pulse : in STD_LOGIC;
        sw_band : in STD_LOGIC_VECTOR(2 downto 0);
        gains_out : out gain_array_t;
        selected_band_out : out integer range 0 to 7;
        edit_mode_out : out STD_LOGIC
    );
end user_interface;

architecture Behavioral of user_interface is
    type state_type is (IDLE, EDIT);
    signal state : state_type := IDLE;
    signal gains : gain_array_t := (others => to_unsigned(128, 8)); -- Start at mid gain
    signal sel_idx : integer range 0 to 7 := 0;
    constant STEP : unsigned(7 downto 0) := to_unsigned(8, 8);
begin
    process(clk, reset)
    begin
        if reset = '1' then
            state <= IDLE;
            gains <= (others => to_unsigned(128, 8));
            sel_idx <= 0;
        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    if btn_sel_pulse = '1' then
                        state <= EDIT;
                        sel_idx <= to_integer(unsigned(sw_band));
                    end if;
                    
                when EDIT =>
                    if btn_sel_pulse = '1' then
                        state <= IDLE;
                    else
                        if btn_up_pulse = '1' then
                            if gains(sel_idx) <= 255 - STEP then
                                gains(sel_idx) <= gains(sel_idx) + STEP;
                            else
                                gains(sel_idx) <= to_unsigned(255, 8);
                            end if;
                        elsif btn_dn_pulse = '1' then
                            if gains(sel_idx) >= STEP then
                                gains(sel_idx) <= gains(sel_idx) - STEP;
                            else
                                gains(sel_idx) <= to_unsigned(0, 8);
                            end if;
                        end if;
                    end if;
            end case;
        end if;
    end process;
    
    gains_out <= gains;
    edit_mode_out <= '1' when state = EDIT else '0';
    -- While idle, show the band the switches are pointing to. While editing, lock to the selected band.
    selected_band_out <= sel_idx when state = EDIT else to_integer(unsigned(sw_band));
    
end Behavioral;
