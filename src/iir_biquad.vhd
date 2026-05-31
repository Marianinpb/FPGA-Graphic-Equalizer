-- =============================================================================
-- iir_biquad.vhd
-- Filtro IIR de segundo orden (Biquad), Forma Directa I
-- Pipeline de 3 etapas para cumplir timing a 50 MHz
-- Registros de retroalimentacion en precision extendida (24-bit)
--   para evitar ciclos limite (limit cycles) en frecuencias bajas.
--
-- Ecuacion en diferencias:
--   y[n] = b0*x[n] + b1*x[n-1] + b2*x[n-2] - a1*y[n-1] - a2*y[n-2]
--
-- Formatos:
--   Coeficientes : Q2.14  signed 16-bit  (FRAC_BITS = 14)
--   Audio in/out : Q1.15  signed 16-bit
--   Retroalim.   : signed 24-bit  (8 bits de guarda)
--   Acumulador   : signed 42-bit
--
-- FSM: IDLE -> S1_MUL_X -> S2_MUL_Y -> S3_ACC -> IDLE
--   Latencia total: 3 ciclos de reloj (~60 ns @ 50 MHz)
--   Periodo de muestra: ~20.8 us @ 48 kHz  =>  margen de ~1039 ciclos
-- =============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity iir_biquad is
    Port (
        clk       : in  STD_LOGIC;
        reset     : in  STD_LOGIC;
        sample_en : in  STD_LOGIC;           -- Pulso activo 1 ciclo por muestra
        -- Coeficientes Q2.14 signed 16-bit
        b0 : in signed(15 downto 0);
        b1 : in signed(15 downto 0);
        b2 : in signed(15 downto 0);
        a1 : in signed(15 downto 0);
        a2 : in signed(15 downto 0);
        -- Audio
        x_in      : in  signed(15 downto 0); -- Entrada  Q1.15
        y_out     : out signed(15 downto 0); -- Salida   Q1.15
        valid_out : out STD_LOGIC            -- Pulso cuando y_out es valido
    );
end iir_biquad;

architecture Behavioral of iir_biquad is

    -- FSM
    type state_t is (IDLE, S1_MUL_X, S2_MUL_Y, S3_ACC);
    signal state : state_t := IDLE;

    -- Registros de retardo de ENTRADA (16 bits)
    signal x_n1 : signed(15 downto 0) := (others => '0');
    signal x_n2 : signed(15 downto 0) := (others => '0');

    -- Registros de RETROALIMENTACION en precision extendida (24 bits)
    -- Los 8 bits extra actuan como "guard bits" para evitar limit cycles
    signal y_n1 : signed(FEEDBACK_BITS-1 downto 0) := (others => '0');
    signal y_n2 : signed(FEEDBACK_BITS-1 downto 0) := (others => '0');

    -- Captura de la muestra actual al entrar a S1
    signal x_cur : signed(15 downto 0) := (others => '0');

    -- Productos registrados del pipeline:
    --   Etapa 1: b0*x[n], b1*x[n-1], b2*x[n-2]  =>  16x16 = 32 bits
    signal p_b0 : signed(31 downto 0) := (others => '0');
    signal p_b1 : signed(31 downto 0) := (others => '0');
    signal p_b2 : signed(31 downto 0) := (others => '0');

    --   Etapa 2: a1*y[n-1], a2*y[n-2]  =>  16x24 = 40 bits
    signal p_a1 : signed(39 downto 0) := (others => '0');
    signal p_a2 : signed(39 downto 0) := (others => '0');

    -- Acumulador  (42 bits = margen para sumar 5 productos de ancho mixto)
    signal acc : signed(41 downto 0) := (others => '0');

    -- Salida extendida antes de saturar
    signal y_ext : signed(FEEDBACK_BITS-1 downto 0) := (others => '0');

begin

    -- -------------------------------------------------------------------------
    -- Pipeline de 3 etapas
    -- -------------------------------------------------------------------------
    process(clk, reset)
    begin
        if reset = '1' then
            state     <= IDLE;
            x_n1      <= (others => '0');
            x_n2      <= (others => '0');
            y_n1      <= (others => '0');
            y_n2      <= (others => '0');
            x_cur     <= (others => '0');
            p_b0      <= (others => '0');
            p_b1      <= (others => '0');
            p_b2      <= (others => '0');
            p_a1      <= (others => '0');
            p_a2      <= (others => '0');
            acc       <= (others => '0');
            y_ext     <= (others => '0');
            y_out     <= (others => '0');
            valid_out <= '0';

        elsif rising_edge(clk) then
            valid_out <= '0'; -- pulso de 1 ciclo, se activa solo en S3

            case state is

                -- -----------------------------------------------------------------
                when IDLE =>
                    if sample_en = '1' then
                        -- Capturar muestra actual y avanzar registros de entrada
                        x_cur <= x_in;
                        -- x_n1 y x_n2 se actualizan DESPUES de calcular (en S3)
                        state <= S1_MUL_X;
                    end if;

                -- -----------------------------------------------------------------
                -- Etapa 1: Multiplicaciones del camino de avance (feedforward)
                --   p_b0 = b0 * x[n]    (16x16 -> 32 bits)
                --   p_b1 = b1 * x[n-1]  (16x16 -> 32 bits)
                --   p_b2 = b2 * x[n-2]  (16x16 -> 32 bits)
                -- -----------------------------------------------------------------
                when S1_MUL_X =>
                    p_b0  <= b0 * x_cur;
                    p_b1  <= b1 * x_n1;
                    p_b2  <= b2 * x_n2;
                    state <= S2_MUL_Y;

                -- -----------------------------------------------------------------
                -- Etapa 2: Multiplicaciones del camino de retroalimentacion
                --   p_a1 = a1 * y[n-1]  (16x24 -> 40 bits)
                --   p_a2 = a2 * y[n-2]  (16x24 -> 40 bits)
                -- -----------------------------------------------------------------
                when S2_MUL_Y =>
                    p_a1  <= a1 * y_n1;
                    p_a2  <= a2 * y_n2;
                    state <= S3_ACC;

                -- -----------------------------------------------------------------
                -- Etapa 3: Acumulacion, desplazamiento, actualizacion y salida
                --   acc = p_b0 + p_b1 + p_b2 - p_a1 - p_a2
                --   (todos extendidos a 42 bits antes de sumar)
                --
                -- Desplazamiento: acc >> FRAC_BITS (= >>14) alinea Q2.14 con Q1.15
                --   Resultado: signed(27 downto 0) [42-14=28 bits significativos]
                --   Guardamos los 24 LSBs en y_n1 (precision extendida)
                --   Saturamos a 16 bits para y_out
                -- -----------------------------------------------------------------
                when S3_ACC =>
                    -- Extender todos los operandos a 42 bits con signo
                    acc <= resize(p_b0, 42)
                         + resize(p_b1, 42)
                         + resize(p_b2, 42)
                         - resize(p_a1, 42)
                         - resize(p_a2, 42);

                    -- Shift aritmetico a la derecha por FRAC_BITS (14)
                    -- acc tiene formato Q(2+2).(14+14) = Q4.28 tras la mult
                    -- >>14 => Q4.14, los bits [27:14] son la parte entera+frac Q1.15
                    -- Tomamos bits [27:0] del acc desplazado como y_ext (28 bits)
                    -- Guardamos 24 bits en y_n1 para la proxima iteracion
                    y_ext <= resize(shift_right(acc, FRAC_BITS), FEEDBACK_BITS);

                    -- Actualizar registros de retardo
                    x_n2 <= x_n1;
                    x_n1 <= x_cur;
                    y_n2 <= y_n1;
                    -- y_n1 recibe y_ext en el proximo ciclo (usa valor registrado)
                    y_n1 <= resize(shift_right(acc, FRAC_BITS), FEEDBACK_BITS);

                    -- Saturacion a 16 bits con signo (Q1.15)
                    -- El resultado util esta en acc[27:14] (desplazado >>14)
                    -- y_ext tiene 24 bits; si los bits [23:15] no son todos
                    -- iguales al bit de signo, hay overflow -> saturar
                    if shift_right(acc, FRAC_BITS) > to_signed(32767, 42) then
                        y_out <= to_signed(32767, 16);   -- +1.0 saturado
                    elsif shift_right(acc, FRAC_BITS) < to_signed(-32768, 42) then
                        y_out <= to_signed(-32768, 16);  -- -1.0 saturado
                    else
                        y_out <= resize(shift_right(acc, FRAC_BITS), 16);
                    end if;

                    valid_out <= '1';
                    state     <= IDLE;

            end case;
        end if;
    end process;

end Behavioral;
