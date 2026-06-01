-- =============================================================================
-- coeff_rom.vhd
-- ROM de coeficientes para el banco de 8 filtros IIR biquad pasa-banda.
-- Logica combinacional pura (sin reloj) - tabla de busqueda.
--
-- Formato de coeficientes: Q2.14 signed 16-bit
--   Valor 16384 = 1.0  (2^14)
--   Valor 0     = 0.0
--
-- FASE 2 - Coeficientes placeholder (pass-through):
--   b0 = 16384 (1.0),  b1 = 0,  b2 = 0,  a1 = 0,  a2 = 0
--   => y[n] = x[n]  (sin filtrado, solo para verificar la cadena de senial)
--
-- FASE 3 - Reemplazar con coeficientes calculados por calc_coefficients.py
--   Frecuencias centrales (Hz): 63, 125, 250, 500, 1000, 2000, 4000, 8000
--   Fs = 48000 Hz,  Q = 0.707 (Butterworth)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity coeff_rom is
    Port (
        band_idx : in  integer range 0 to 7;
        b0 : out signed(15 downto 0);
        b1 : out signed(15 downto 0);
        b2 : out signed(15 downto 0);
        a1 : out signed(15 downto 0);
        a2 : out signed(15 downto 0)
    );
end coeff_rom;

architecture Behavioral of coeff_rom is

    -- -------------------------------------------------------------------------
    -- Tipo de dato para un conjunto de coeficientes biquad (5 valores x 16 bits)
    -- Orden: (b0, b1, b2, a1, a2)  en formato Q2.14
    -- -------------------------------------------------------------------------
    type coeff_set_t is record
        c_b0 : signed(15 downto 0);
        c_b1 : signed(15 downto 0);
        c_b2 : signed(15 downto 0);
        c_a1 : signed(15 downto 0);
        c_a2 : signed(15 downto 0);
    end record;

    type coeff_array_t is array (0 to NUM_BANDS-1) of coeff_set_t;

    -- =========================================================================
    -- TABLA DE COEFICIENTES - FASE 3: Coeficientes reales calculados
    -- Generado por: scripts/calc_coefficients.py
    -- Fs = 48000 Hz  |  Q = 0.707 (Butterworth)  |  Formato Q2.14 (escala=16384)
    -- Todos los filtros verificados estables (polos dentro del circulo unitario)
    --
    -- Bandas:  0=63Hz  1=125Hz  2=250Hz  3=500Hz
    --          4=1kHz  5=2kHz   6=4kHz   7=8kHz
    -- =========================================================================
    constant COEFF_TABLE : coeff_array_t := (
        -- Banda 0:    63 Hz  (b0=    95, b1=   0, b2=    -95, a1=-32577, a2= 16194) [ESTABLE]
        (c_b0 => to_signed(     95, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(    -95, 16),
         c_a1 => to_signed( -32577, 16),
         c_a2 => to_signed(  16194, 16)),

        -- Banda 1:   125 Hz  (b0=   187, b1=   0, b2=   -187, a1=-32389, a2= 16009) [ESTABLE]
        (c_b0 => to_signed(    187, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -187, 16),
         c_a1 => to_signed( -32389, 16),
         c_a2 => to_signed(  16009, 16)),

        -- Banda 2:   250 Hz  (b0=   371, b1=   0, b2=   -371, a1=-32010, a2= 15643) [ESTABLE]
        (c_b0 => to_signed(    371, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -371, 16),
         c_a1 => to_signed( -32010, 16),
         c_a2 => to_signed(  15643, 16)),

        -- Banda 3:   500 Hz  (b0=   725, b1=   0, b2=   -725, a1=-31250, a2= 14933) [ESTABLE]
        (c_b0 => to_signed(    725, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -725, 16),
         c_a1 => to_signed( -31250, 16),
         c_a2 => to_signed(  14933, 16)),

        -- Banda 4:  1000 Hz  (b0=  1392, b1=   0, b2=  -1392, a1=-29728, a2= 13600) [ESTABLE]
        (c_b0 => to_signed(   1392, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -1392, 16),
         c_a1 => to_signed( -29728, 16),
         c_a2 => to_signed(  13600, 16)),

        -- Banda 5:  2000 Hz  (b0=  2585, b1=   0, b2=  -2585, a1=-26659, a2= 11215) [ESTABLE]
        (c_b0 => to_signed(   2585, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -2585, 16),
         c_a1 => to_signed( -26659, 16),
         c_a2 => to_signed(  11215, 16)),

        -- Banda 6:  4000 Hz  (b0=  4582, b1=   0, b2=  -4582, a1=-20442, a2=  7221) [ESTABLE]
        (c_b0 => to_signed(   4582, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -4582, 16),
         c_a1 => to_signed( -20442, 16),
         c_a2 => to_signed(   7221, 16)),

        -- Banda 7:  8000 Hz  (b0=  7825, b1=   0, b2=  -7825, a1= -8559, a2=   735) [ESTABLE]
        (c_b0 => to_signed(   7825, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -7825, 16),
         c_a1 => to_signed(  -8559, 16),
         c_a2 => to_signed(    735, 16))
    );

begin

    -- Logica combinacional pura: salidas determinadas directamente por band_idx
    b0 <= COEFF_TABLE(band_idx).c_b0;
    b1 <= COEFF_TABLE(band_idx).c_b1;
    b2 <= COEFF_TABLE(band_idx).c_b2;
    a1 <= COEFF_TABLE(band_idx).c_a1;
    a2 <= COEFF_TABLE(band_idx).c_a2;

end Behavioral;
