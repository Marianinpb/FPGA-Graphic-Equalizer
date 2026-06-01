-- =============================================================================
-- filter_bank.vhd
-- Banco de 8 filtros IIR biquad pasa-banda en paralelo + mezclador con ganancia
--
-- Arquitectura:
--   1. coeff_rom  -> coeficientes Q2.14 para cada banda
--   2. 8x iir_biquad (en paralelo via generate) -> 8 seniales filtradas
--   3. Pipeline de post-procesamiento (FSM de 2 etapas):
--      Etapa GAIN: filt_out[i] * gain[i] >> 7  -> scaled_out[i]
--      Etapa MIX:  suma de los 8 scaled_out + saturacion -> audio_out
--   4. Saturacion del resultado final a signed 16-bit
--
-- La FSM garantiza que la etapa de ganancia COMPLETA antes de que el mixer lea,
-- evitando la condicion de carrera del diseno anterior donde el mixer leia
-- valores de ganancia obsoletos (del sample anterior o inicializados a cero).
--
-- Latencia total: 5 ciclos de CLOCK_50 (3 biquad + 1 gain + 1 mix)
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
    -- Arrays de seniales internas para conectar las 8 instancias de iir_biquad
    -- -------------------------------------------------------------------------
    type audio_array_t is array (0 to NUM_BANDS-1) of signed(15 downto 0);

    -- Coeficientes de la ROM (una fila por banda)
    signal rom_b0, rom_b1, rom_b2, rom_a1, rom_a2 : audio_array_t;

    -- Salidas de los 8 filtros biquad
    signal filt_out   : audio_array_t;
    signal filt_valid : std_logic_vector(NUM_BANDS-1 downto 0);

    -- Salidas escaladas por ganancia: signed(24 downto 0) = 25 bits
    type scaled_array_t is array (0 to NUM_BANDS-1) of signed(24 downto 0);
    signal scaled_out : scaled_array_t;

    -- FSM de post-procesamiento
    type post_state_t is (POST_IDLE, POST_GAIN, POST_MIX);
    signal post_state : post_state_t := POST_IDLE;

begin

    -- =========================================================================
    -- Instancias de coeff_rom: una por banda (logica combinacional)
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
    -- Pipeline de post-procesamiento: Ganancia + Mezcla
    --
    -- FSM de 3 estados:
    --   POST_IDLE: Espera filt_valid(0) = '1'
    --   POST_GAIN: Calcula scaled_out[i] = filt_out[i] * gain[i] >> 7
    --              (los valores se registran en scaled_out, disponibles en el
    --               proximo ciclo)
    --   POST_MIX:  Lee scaled_out (ya estable), suma los 8 canales, satura
    --              y emite audio_out + valid_out = '1'
    --
    -- Esto garantiza que scaled_out se calcula y registra ANTES de que el
    -- mixer lo lea, eliminando la condicion de carrera del diseno anterior.
    -- =========================================================================
    process(clk, reset)
        variable prod     : signed(24 downto 0);
        variable gain_s   : signed(8 downto 0);
        variable acc_v    : signed(26 downto 0);
    begin
        if reset = '1' then
            post_state <= POST_IDLE;
            audio_out  <= (others => '0');
            valid_out  <= '0';
            for i in 0 to NUM_BANDS-1 loop
                scaled_out(i) <= (others => '0');
            end loop;

        elsif rising_edge(clk) then
            valid_out <= '0';  -- pulso de 1 ciclo

            case post_state is

                -- =============================================================
                when POST_IDLE =>
                    if filt_valid(0) = '1' then
                        post_state <= POST_GAIN;
                    end if;

                -- =============================================================
                -- Etapa GAIN: calcula ganancia para las 8 bandas
                -- gain[i] es unsigned 8-bit:  0=silencio, 128=unitaria, 255=~x2
                -- scaled[i] = filt_out[i] * gain[i] >> 7
                -- =============================================================
                when POST_GAIN =>
                    for i in 0 to NUM_BANDS-1 loop
                        -- Extender ganancia unsigned 8-bit a signed 9-bit
                        gain_s := signed(resize(gains(i), 9));
                        -- Multiplicar: 16-bit * 9-bit = 25-bit signed
                        prod := filt_out(i) * gain_s;
                        -- Desplazar >>7 para normalizar (128 -> x1.0)
                        prod := shift_right(prod, 7);
                        -- Registrar resultado
                        scaled_out(i) <= prod;
                    end loop;
                    post_state <= POST_MIX;

                -- =============================================================
                -- Etapa MIX: suma los 8 canales y satura a 16-bit
                -- scaled_out ya esta estable (registrado en POST_GAIN)
                -- =============================================================
                when POST_MIX =>
                    acc_v := resize(scaled_out(0), 27)
                           + resize(scaled_out(1), 27)
                           + resize(scaled_out(2), 27)
                           + resize(scaled_out(3), 27)
                           + resize(scaled_out(4), 27)
                           + resize(scaled_out(5), 27)
                           + resize(scaled_out(6), 27)
                           + resize(scaled_out(7), 27);

                    -- Saturacion a 16-bit signed
                    if acc_v > to_signed(32767, 27) then
                        audio_out <= to_signed(32767, 16);
                    elsif acc_v < to_signed(-32768, 27) then
                        audio_out <= to_signed(-32768, 16);
                    else
                        audio_out <= resize(acc_v, 16);
                    end if;

                    valid_out  <= '1';
                    post_state <= POST_IDLE;

            end case;
        end if;
    end process;

end Behavioral;
