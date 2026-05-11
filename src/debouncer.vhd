library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity debouncer is
    Generic (
        CLK_FREQ : integer := 50_000_000; -- 50 MHz
        DEBOUNCE_MS : integer := 10       -- 10 ms
    );
    Port ( 
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        btn_in : in STD_LOGIC;
        btn_stable : out STD_LOGIC;
        btn_pulse : out STD_LOGIC
    );
end debouncer;

architecture Behavioral of debouncer is
    constant MAX_COUNT : integer := (CLK_FREQ / 1000) * DEBOUNCE_MS;
    signal count : integer range 0 to MAX_COUNT := 0;
    signal sync_0, sync_1 : std_logic := '1'; -- Default high for active low keys
    signal stable_reg : std_logic := '1';
    signal stable_reg_d : std_logic := '1';
begin
    process(clk, reset)
    begin
        if reset = '1' then
            sync_0 <= '1';
            sync_1 <= '1';
            count <= 0;
            stable_reg <= '1';
            stable_reg_d <= '1';
        elsif rising_edge(clk) then
            -- Double synchronizer to avoid metastability
            sync_0 <= btn_in;
            sync_1 <= sync_0;
            
            stable_reg_d <= stable_reg; -- Delay by 1 clock cycle for edge detection
            
            if sync_1 = stable_reg then
                count <= 0;
            else
                if count = MAX_COUNT then
                    stable_reg <= sync_1;
                    count <= 0;
                else
                    count <= count + 1;
                end if;
            end if;
        end if;
    end process;
    
    btn_stable <= stable_reg;
    
    -- DE2-115 keys are active LOW. A "press" generates a falling edge.
    btn_pulse <= '1' when (stable_reg = '0' and stable_reg_d = '1') else '0';

end Behavioral;
