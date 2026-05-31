library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

package equalizer_pkg is

    -- -------------------------------------------------------------------------
    -- Existing type (Fase 1 - NO modificar)
    -- -------------------------------------------------------------------------
    -- Type for the 8 gain values (8 bits each, representing 0-255)
    type gain_array_t is array (0 to 7) of unsigned(7 downto 0);

    -- -------------------------------------------------------------------------
    -- Constantes para el sistema de filtros IIR (Fase 2)
    -- -------------------------------------------------------------------------

    -- Numero de bandas del ecualizador
    constant NUM_BANDS : integer := 8;

    -- Bits fraccionarios del formato de coeficientes Q2.14
    -- Un coeficiente de valor 16384 representa 1.0
    constant FRAC_BITS : integer := 14;

    -- Valor 1.0 en formato Q2.14 (usado como coeficiente b0 placeholder)
    constant COEFF_ONE : signed(15 downto 0) := to_signed(16384, 16);

    -- Ancho de los registros de retroalimentacion (y_n1, y_n2) en iir_biquad
    -- 8 bits extra respecto a los 16 de audio para evitar limit cycles
    constant FEEDBACK_BITS : integer := 24;

end package;
