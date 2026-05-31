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
    -- Audio Codec WM8731 (Fase 2 - nuevo)
    -- Configura el codec via I2C al arrancar y maneja el flujo I2S.
    -- Genera Lin/Rin (ADC) y consume Lout/Rout (DAC).
    -- Ldone/Rdone son pulsos de 1 ciclo que indican "nueva muestra lista".
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
    -- Banco de Filtros IIR (Fase 2 - nuevo)
    -- Ldone del codec sirve como sample_en (nuevo sample cada ~20.8 us @ 48kHz).
    -- Procesa el canal izquierdo (Lin). La salida ecualizada se envia a ambos
    -- canales del DAC (mono).
    -- =========================================================================
    fb_inst: entity work.filter_bank
        port map(
            clk       => CLOCK_50,
            reset     => reset,
            sample_en => Ldone,         -- Pulse from codec: new sample available
            audio_in  => Lin,           -- Left channel from ADC
            gains     => gains,         -- 8-band gains from user interface
            audio_out => audio_out_eq,  -- Equalized output
            valid_out => filter_valid
        );

    -- =========================================================================
    -- Conectar salida del ecualizador al DAC
    -- Proceso registrado para evitar latches y mantener la sincronia con el
    -- protocolo I2S del codec (Lout/Rout deben ser estables hasta el siguiente
    -- Ldone/Rdone).
    -- =========================================================================
    process(CLOCK_50, reset)
    begin
        if reset = '1' then
            Lout <= (others => '0');
            Rout <= (others => '0');
        elsif rising_edge(CLOCK_50) then
            if filter_valid = '1' then
                Lout <= audio_out_eq;   -- Canal izquierdo ecualizado
                Rout <= audio_out_eq;   -- Canal derecho = mismo (mono)
            end if;
        end if;
    end process;

end Structural;
