-- =============================================================================
-- filter_bank.vhd
-- Banco de 8 filtros IIR biquad pasa-banda en paralelo + mezclador con ganancia
--
-- Arquitectura:
--   1. coeff_rom  -> coeficientes Q2.14 para cada banda
--   2. 8x iir_biquad (en paralelo via generate) -> 8 seniales filtradas
--   3. Aplicacion de ganancia: filtered[i] * gain[i] >> 7
--      (gain en rango 0-255, valor 128 = ganancia unitaria)
--   4. Inversion de polaridad en bandas alternas para suavizar valles de fase
--      (controlada por constante INVERT_ALT_BANDS)
--   5. Suma de las 8 seniales escaladas -> acumulador 27-bit
--   6. Saturacion del resultado final a signed 16-bit
--
-- Latencia: 3 ciclos de reloj (determinada por iir_biquad)
-- Throughput: 1 muestra por ciclo de sample_en (48 kHz)
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity filter_bank is
    Port (
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        sample_en : in  STD_LOGIC;              -- Pulso Ldone del codec WM8731
        audio_in  : in  signed(15 downto 0);    -- Del ADC (Lin del codec)
        gains     : in  gain_array_t;           -- 8 ganancias 8-bit (0-255, 128=unitaria)
        audio_out : out signed(15 downto 0);    -- Al DAC (Lout del codec)
        valid_out : out STD_LOGIC               -- Pulso cuando audio_out es valido
    );
end filter_bank;

architecture Behavioral of filter_bank is

    -- -------------------------------------------------------------------------
    -- Inversion de polaridad en bandas alternas para suavizar valles de fase.
    -- Cambiar a false para deshabilitar (util para comparacion en el reporte).
    -- -------------------------------------------------------------------------
    constant INVERT_ALT_BANDS : boolean := true;

    -- -------------------------------------------------------------------------
    -- Arrays de seniales internas para conectar las 8 instancias de iir_biquad
    -- -------------------------------------------------------------------------
    type audio_array_t is array (0 to NUM_BANDS-1) of signed(15 downto 0);

    -- Coeficientes de la ROM (una fila por banda)
    signal rom_b0, rom_b1, rom_b2, rom_a1, rom_a2 : audio_array_t;

    -- Salidas de los 8 filtros biquad
    signal filt_out   : audio_array_t;
    signal filt_valid : std_logic_vector(NUM_BANDS-1 downto 0);

    -- Salidas escaladas por ganancia (24-bit: 16+8 bits de ganancia)
    -- Con margen de signo: signed(24 downto 0)
    type scaled_array_t is array (0 to NUM_BANDS-1) of signed(24 downto 0);
    signal scaled_out : scaled_array_t;

    -- Acumulador del mezclador:
    -- 8 terminos de 25 bits -> maximo 8*32767 = 262136 -> necesita log2(262136)+1 = 19 bits
    -- Usamos 27 bits para tener margen generoso
    signal mix_acc : signed(26 downto 0) := (others => '0');

begin

    -- =========================================================================
    -- Instancias de coeff_rom: una por banda (logica combinacional)
    -- Nota: se podria usar una sola ROM con band_idx variable, pero instanciar
    -- 8 en paralelo da acceso simultaneo sin latencia de multiplexacion.
    -- =========================================================================
    gen_roms: for i in 0 to NUM_BANDS-1 generate
        coeff_inst: entity work.coeff_rom
            port map (
                band_idx => i,
                b0 => rom_b0(i),
                b1 => rom_b1(i),
                b2 => rom_b2(i),
                a1 => rom_a1(i),
                a2 => rom_a2(i)
            );
    end generate;

    -- =========================================================================
    -- Instancias de iir_biquad: 8 filtros en paralelo
    -- Todos reciben la misma muestra de entrada y el mismo sample_en
    -- =========================================================================
    gen_filters: for i in 0 to NUM_BANDS-1 generate
        biquad_inst: entity work.iir_biquad
            port map (
                clk       => clk,
                reset     => reset,
                sample_en => sample_en,
                b0        => rom_b0(i),
                b1        => rom_b1(i),
                b2        => rom_b2(i),
                a1        => rom_a1(i),
                a2        => rom_a2(i),
                x_in      => audio_in,
                y_out     => filt_out(i),
                valid_out => filt_valid(i)
            );
    end generate;

    -- =========================================================================
    -- Etapa de ganancia e inversion de polaridad
    -- gain[i] es unsigned 8-bit:
    --   0   = silencio
    --   128 = ganancia unitaria (x1.0)
    --   255 = ~x2.0
    --
    -- scaled[i] = filt_out[i] * gain[i] >> 7
    --   filt_out: signed 16-bit
    --   gain:     unsigned 8-bit, extendido a signed 9-bit para la mult
    --   producto: signed 25-bit (16+9)
    --   >>7: normaliza para que gain=128 => factor 1.0
    -- =========================================================================
    gen_gain: for i in 0 to NUM_BANDS-1 generate
        process(clk, reset)
            variable prod : signed(24 downto 0);
            variable gain_s : signed(8 downto 0);
        begin
            if reset = '1' then
                scaled_out(i) <= (others => '0');
            elsif rising_edge(clk) then
                -- Extender ganancia unsigned 8-bit a signed 9-bit (siempre positiva)
                gain_s := signed(resize(gains(i), 9));
                -- Multiplicar: 16-bit * 9-bit = 25-bit signed
                prod := filt_out(i) * gain_s;
                -- Desplazar >>7 para normalizar (128 -> x1.0)
                prod := shift_right(prod, 7);
                -- Inversion de polaridad en bandas impares (1, 3, 5, 7)
                if INVERT_ALT_BANDS and (i mod 2 = 1) then
                    scaled_out(i) <= -prod;
                else
                    scaled_out(i) <= prod;
                end if;
            end if;
        end process;
    end generate;

    -- =========================================================================
    -- Mezclador: suma de los 8 canales escalados
    -- valid_out se sincroniza con filt_valid(0) (todos validos al mismo tiempo
    -- ya que todos reciben el mismo sample_en y tienen la misma latencia)
    -- =========================================================================
    process(clk, reset)
        variable acc_v : signed(26 downto 0);
    begin
        if reset = '1' then
            mix_acc   <= (others => '0');
            audio_out <= (others => '0');
            valid_out <= '0';
        elsif rising_edge(clk) then
            valid_out <= '0';

            -- La suma ocurre 1 ciclo despues de que la etapa de ganancia registra
            -- sus resultados, los cuales se calculan en el ciclo donde valid=1.
            -- Se usa filt_valid(0) como trigger (todos los canales son identicos).
            if filt_valid(0) = '1' then
                -- Sumar los 8 canales en un acumulador de 27 bits
                acc_v := resize(scaled_out(0), 27)
                       + resize(scaled_out(1), 27)
                       + resize(scaled_out(2), 27)
                       + resize(scaled_out(3), 27)
                       + resize(scaled_out(4), 27)
                       + resize(scaled_out(5), 27)
                       + resize(scaled_out(6), 27)
                       + resize(scaled_out(7), 27);

                mix_acc <= acc_v;

                -- Saturacion a 16-bit signed
                if acc_v > to_signed(32767, 27) then
                    audio_out <= to_signed(32767, 16);
                elsif acc_v < to_signed(-32768, 27) then
                    audio_out <= to_signed(-32768, 16);
                else
                    audio_out <= resize(acc_v, 16);
                end if;

                valid_out <= '1';
            end if;
        end if;
    end process;

end Behavioral;
