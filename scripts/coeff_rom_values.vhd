-- =============================================================================
-- FRAGMENTO PARA REEMPLAZAR EN: src/coeff_rom.vhd
-- Sustituir el bloque 'constant COEFF_TABLE' con el siguiente contenido.
--
-- Generado por: scripts/calc_coefficients.py
-- Fs = 48000 Hz  |  Q = 0.707  |  Formato Q2.14 (escala = 16384)
-- Bandas (Hz): [63, 125, 250, 500, 1000, 2000, 4000, 8000]
-- =============================================================================

    constant COEFF_TABLE : coeff_array_t := (
        -- Banda 0:    63 Hz  (b0=     95, b1=      0, b2=    -95, a1= -32577, a2=  16194)  [ESTABLE]
        (c_b0 => to_signed(     95, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(    -95, 16),
         c_a1 => to_signed( -32577, 16),
         c_a2 => to_signed(  16194, 16)),

        -- Banda 1:   125 Hz  (b0=    187, b1=      0, b2=   -187, a1= -32389, a2=  16009)  [ESTABLE]
        (c_b0 => to_signed(    187, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -187, 16),
         c_a1 => to_signed( -32389, 16),
         c_a2 => to_signed(  16009, 16)),

        -- Banda 2:   250 Hz  (b0=    371, b1=      0, b2=   -371, a1= -32010, a2=  15643)  [ESTABLE]
        (c_b0 => to_signed(    371, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -371, 16),
         c_a1 => to_signed( -32010, 16),
         c_a2 => to_signed(  15643, 16)),

        -- Banda 3:   500 Hz  (b0=    725, b1=      0, b2=   -725, a1= -31250, a2=  14933)  [ESTABLE]
        (c_b0 => to_signed(    725, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(   -725, 16),
         c_a1 => to_signed( -31250, 16),
         c_a2 => to_signed(  14933, 16)),

        -- Banda 4:  1000 Hz  (b0=   1392, b1=      0, b2=  -1392, a1= -29728, a2=  13600)  [ESTABLE]
        (c_b0 => to_signed(   1392, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -1392, 16),
         c_a1 => to_signed( -29728, 16),
         c_a2 => to_signed(  13600, 16)),

        -- Banda 5:  2000 Hz  (b0=   2585, b1=      0, b2=  -2585, a1= -26659, a2=  11215)  [ESTABLE]
        (c_b0 => to_signed(   2585, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -2585, 16),
         c_a1 => to_signed( -26659, 16),
         c_a2 => to_signed(  11215, 16)),

        -- Banda 6:  4000 Hz  (b0=   4582, b1=      0, b2=  -4582, a1= -20442, a2=   7221)  [ESTABLE]
        (c_b0 => to_signed(   4582, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -4582, 16),
         c_a1 => to_signed( -20442, 16),
         c_a2 => to_signed(   7221, 16)),

        -- Banda 7:  8000 Hz  (b0=   7825, b1=      0, b2=  -7825, a1=  -8559, a2=    735)  [ESTABLE]
        (c_b0 => to_signed(   7825, 16),
         c_b1 => to_signed(      0, 16),
         c_b2 => to_signed(  -7825, 16),
         c_a1 => to_signed(  -8559, 16),
         c_a2 => to_signed(    735, 16))

    );
