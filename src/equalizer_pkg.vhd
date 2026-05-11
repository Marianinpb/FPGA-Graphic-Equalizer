library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package equalizer_pkg is
    -- Type for the 8 gain values (8 bits each, representing 0-255)
    type gain_array_t is array (0 to 7) of unsigned(7 downto 0);
end package;
