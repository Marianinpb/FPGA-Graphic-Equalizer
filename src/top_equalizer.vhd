library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.equalizer_pkg.all;

entity top_equalizer is
    Port (
        CLOCK_50 : in STD_LOGIC;
        KEY : in STD_LOGIC_VECTOR(3 downto 0); -- KEY(0) reset, KEY(1) sel, KEY(2) up, KEY(3) down
        SW : in STD_LOGIC_VECTOR(2 downto 0);  -- SW(2..0) for band selection

        -- VGA Outputs for DE2-115 (8-bit DAC)
        VGA_R : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_G : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_B : out STD_LOGIC_VECTOR(7 downto 0);
        VGA_HS : out STD_LOGIC;
        VGA_VS : out STD_LOGIC;
        VGA_CLK : out STD_LOGIC;
        VGA_BLANK_N : out STD_LOGIC;
        VGA_SYNC_N : out STD_LOGIC;

        -- Audio Codec WM8731 (I2C + I2S)
        I2C_SCLK    : out   STD_LOGIC;
        I2C_SDAT    : inout STD_LOGIC;
        AUD_XCK     : buffer STD_LOGIC;
        AUD_BCLK    : inout STD_LOGIC;
        AUD_ADCLRCK : out   STD_LOGIC;
        AUD_ADCDAT  : in    STD_LOGIC;
        AUD_DACLRCK : out   STD_LOGIC;
        AUD_DACDAT  : out   STD_LOGIC
    );
end top_equalizer;

architecture Structural of top_equalizer is

    -- -------------------------------------------------------------------------
    -- Signals for User Interface
    -- -------------------------------------------------------------------------
    signal reset : std_logic;
    signal btn_sel_pulse, btn_up_pulse, btn_dn_pulse : std_logic;
    signal gains : gain_array_t;
    signal selected_band : integer range 0 to 7;
    signal edit_mode : std_logic;

    -- -------------------------------------------------------------------------
    -- Signals for VGA
    -- -------------------------------------------------------------------------
    signal pixel_row, pixel_col : std_logic_vector(9 downto 0);
    signal video_on, pixel_clock_int : std_logic;
    signal draw_r, draw_g, draw_b : std_logic;
    signal sync_r, sync_g, sync_b : std_logic;

    -- -------------------------------------------------------------------------
    -- Signals for Audio Codec (WM8731)
    -- -------------------------------------------------------------------------
    signal Lin, Rin   : signed(15 downto 0);   -- ADC outputs (from codec)
    signal Lout, Rout : signed(15 downto 0);   -- DAC inputs  (to codec)
    signal Ldone, Rdone : std_logic;           -- "new sample ready" pulses

    -- -------------------------------------------------------------------------
    -- Signals for Filter Bank DSP
    -- -------------------------------------------------------------------------
    signal audio_out_eq : signed(15 downto 0); -- Equalized audio (left channel)
    signal filter_valid  : std_logic;           -- filter_bank output valid pulse

    -- -------------------------------------------------------------------------
    -- Sincronizador de Ldone: AUD_XCK (18.432 MHz) -> CLOCK_50 (50 MHz)
    -- Ldone es un pulso de ~54 ns en el dominio de AUD_XCK.
    -- Sin sincronizar, puede causar metaestabilidad en CLOCK_50.
    -- Usamos 2 flip-flops en cascada + detector de flanco ascendente.
    -- -------------------------------------------------------------------------
    signal Ldone_meta  : std_logic := '0';  -- 1er FF (puede ser metaestable)
    signal Ldone_sync  : std_logic := '0';  -- 2do FF (estable)
    signal Ldone_prev  : std_logic := '0';  -- Para detectar flanco
    signal Ldone_pulse : std_logic;         -- Pulso limpio de 1 ciclo CLOCK_50

    -- Muestra de audio capturada sincrona a CLOCK_50
    signal Lin_latched : signed(15 downto 0) := (others => '0');

    -- -------------------------------------------------------------------------
    -- Component declaration for VGA_SYNC (legacy component from resources)
    -- -------------------------------------------------------------------------
    component VGA_SYNC
        PORT( clock_50Mhz, red, green, blue : IN STD_LOGIC;
              red_out, green_out, blue_out, horiz_sync_out,
              vert_sync_out, video_on, pixel_clock : OUT STD_LOGIC;
              pixel_row, pixel_column: OUT STD_LOGIC_VECTOR(9 DOWNTO 0));
    end component;

begin

    -- =========================================================================
    -- Reset: KEY(0) active-low => active-high reset inside
    -- =========================================================================
    reset <= not KEY(0);

    -- =========================================================================
    -- Debouncers for buttons (Fase 1 - sin cambios)
    -- =========================================================================
    deb_sel: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(1), btn_pulse => btn_sel_pulse);

    deb_up: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(2), btn_pulse => btn_up_pulse);

    deb_dn: entity work.debouncer
        port map(clk => CLOCK_50, reset => reset, btn_in => KEY(3), btn_pulse => btn_dn_pulse);

    -- =========================================================================
    -- User Interface FSM (Fase 1 - sin cambios)
    -- =========================================================================
    ui_inst: entity work.user_interface
        port map(
            clk            => CLOCK_50,
            reset          => reset,
            btn_sel_pulse  => btn_sel_pulse,
            btn_up_pulse   => btn_up_pulse,
            btn_dn_pulse   => btn_dn_pulse,
            sw_band        => SW(2 downto 0),
            gains_out      => gains,
            selected_band_out => selected_band,
            edit_mode_out  => edit_mode
        );

    -- =========================================================================
    -- VGA Drawer (Fase 1 - sin cambios)
    -- =========================================================================
    drawer_inst: entity work.vga_drawer
        port map(
            clk          => pixel_clock_int,
            pixel_row    => pixel_row,
            pixel_col    => pixel_col,
            video_on     => video_on,
            gains_in     => gains,
            selected_band => selected_band,
            edit_mode    => edit_mode,
            red          => draw_r,
            green        => draw_g,
            blue         => draw_b
        );

    -- =========================================================================
    -- VGA Sync Generator (Fase 1 - sin cambios)
    -- =========================================================================
    sync_inst: VGA_SYNC
        port map(
            clock_50Mhz    => CLOCK_50,
            red            => draw_r,
            green          => draw_g,
            blue           => draw_b,
            red_out        => sync_r,
            green_out      => sync_g,
            blue_out       => sync_b,
            horiz_sync_out => VGA_HS,
            vert_sync_out  => VGA_VS,
            video_on       => video_on,
            pixel_clock    => pixel_clock_int,
            pixel_row      => pixel_row,
            pixel_column   => pixel_col
        );

    -- Map 1-bit sync outputs to 8-bit DE2-115 VGA bus
    VGA_R <= (others => '1') when sync_r = '1' else (others => '0');
    VGA_G <= (others => '1') when sync_g = '1' else (others => '0');
    VGA_B <= (others => '1') when sync_b = '1' else (others => '0');

    VGA_CLK     <= pixel_clock_int;
    VGA_BLANK_N <= video_on;
    VGA_SYNC_N  <= '0';

    -- =========================================================================
    -- Audio Codec WM8731 (Fase 2)
    -- Configura el codec via I2C al arrancar y maneja el flujo I2S.
    -- Genera Lin/Rin (ADC) y consume Lout/Rout (DAC).
    -- Ldone/Rdone son pulsos de 1 ciclo (AUD_XCK) que indican "nueva muestra".
    -- El AudioPLL interno genera 18.432 MHz (AUD_XCK) desde los 50 MHz.
    -- =========================================================================
    audio_inst: entity work.Audio
        generic map (SAMPLE_RATE => 48)  -- 48 kHz
        port map(
            clock       => CLOCK_50,
            reset       => reset,
            AUD_XCK     => AUD_XCK,
            I2C_SCLK    => I2C_SCLK,
            I2C_SDAT    => I2C_SDAT,
            AUD_BCLK    => AUD_BCLK,
            AUD_DACLRCK => AUD_DACLRCK,
            AUD_ADCLRCK => AUD_ADCLRCK,
            AUD_ADCDAT  => AUD_ADCDAT,
            AUD_DACDAT  => AUD_DACDAT,
            Rin         => Rin,
            Lin         => Lin,
            Rout        => Rout,
            Lout        => Lout,
            Rdone       => Rdone,
            Ldone       => Ldone
        );

    -- =========================================================================
    -- Sincronizador de Ldone: AUD_XCK -> CLOCK_50
    -- 2 flip-flops en cascada + detector de flanco ascendente
    -- Genera Ldone_pulse: pulso limpio de exactamente 1 ciclo de CLOCK_50
    -- =========================================================================
    process(CLOCK_50, reset)
    begin
        if reset = '1' then
            Ldone_meta  <= '0';
            Ldone_sync  <= '0';
            Ldone_prev  <= '0';
            Lin_latched <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            -- Cadena de sincronizacion de 2 FF
            Ldone_meta <= Ldone;
            Ldone_sync <= Ldone_meta;
            Ldone_prev <= Ldone_sync;
            -- Capturar Lin cuando detectamos el flanco de Ldone
            -- Lin viene del dominio AUD_XCK pero ya esta estable cuando Ldone sube
            if Ldone_sync = '1' and Ldone_prev = '0' then
                Lin_latched <= Lin;
            end if;
        end if;
    end process;

    -- Pulso de 1 ciclo en flanco ascendente de Ldone_sync
    Ldone_pulse <= Ldone_sync and (not Ldone_prev);

    -- =========================================================================
    -- Banco de Filtros IIR (Fase 2/3)
    -- Usa Ldone_pulse (sincronizado a CLOCK_50) como sample_en.
    -- Usa Lin_latched (capturado sincrono a CLOCK_50) como entrada de audio.
    -- =========================================================================
    fb_inst: entity work.filter_bank
        port map(
            clk       => CLOCK_50,
            reset     => reset,
            sample_en => Ldone_pulse,     -- Pulso sincronizado a CLOCK_50
            audio_in  => Lin_latched,     -- Audio capturado sincrono
            gains     => gains,
            audio_out => audio_out_eq,
            valid_out => filter_valid
        );

    -- =========================================================================
    -- Conectar salida del ecualizador al DAC
    -- Proceso registrado: Lout/Rout se mantienen estables hasta el siguiente
    -- filter_valid, lo cual ocurre ~7 ciclos de CLOCK_50 despues de Ldone.
    -- Audio.vhd lee Lout bit por bit durante el siguiente periodo LRCK
    -- (~20.8 us despues), asi que Lout tiene tiempo de sobra para estabilizarse.
    -- =========================================================================
    process(CLOCK_50, reset)
    begin
        if reset = '1' then
            Lout <= (others => '0');
            Rout <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if filter_valid = '1' then
                Lout <= audio_out_eq;
                Rout <= audio_out_eq;
            end if;
        end if;
    end process;

end Structural;
