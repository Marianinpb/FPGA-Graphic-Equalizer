library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity Audio is
   generic(
      SAMPLE_RATE	:  natural := 48 -- in KHz
   );
	port(	
		clock 	: in std_logic;
		reset 	: in std_logic;
		AUD_XCK 	: buffer std_logic;
		I2C_SCLK 	: out std_logic;
		I2C_SDAT 	: inout std_logic;
		AUD_BCLK 	: buffer std_logic;
		AUD_DACLRCK : out std_logic;
		AUD_ADCLRCK : out std_logic;
		AUD_ADCDAT 	: in std_logic;
		AUD_DACDAT 	: out std_logic;
		Rin, Lin 	: out signed(15 downto 0);
		Rout, Lout	: in signed(15 downto 0);
		Rdone, Ldone: out std_logic
		);
end;

architecture WM8731 OF Audio IS
	type state is (wait1, wait2, left1, left2, left3, left4, left5,
						right1, right2, right3, right4, right5);
	signal RCV : state;
	
	constant word_count	: natural := 18432 / (2 * SAMPLE_RATE);
	constant bit_count 	: natural := word_count / (2 * 16);
	signal SAMPLE_CTRL	: std_logic_vector(15 downto 0);
	signal word_range	: natural;
	signal bit_range : natural;
	
	signal done : std_logic;
	signal lrck : std_logic;
	
begin
	assert (SAMPLE_RATE = 8 or SAMPLE_RATE = 32 or
				SAMPLE_RATE = 48 or SAMPLE_RATE = 96)
      report "The selected sample rate was not supported."
	severity error;
	
	SAMPLE_CTRL <= 	x"100E" when SAMPLE_RATE = 8 else
							x"101A" when SAMPLE_RATE = 32 else
							x"101E" when SAMPLE_RATE = 96 else
							x"1002";	--default 48KHz
	
	word_range <= 	word_count * 2 when SAMPLE_RATE = 96 else
				word_count;
						
	bit_range <= 	bit_count * 2 when SAMPLE_RATE = 96 else
				bit_count;
						
	I2C_controller: entity work.I2C port map(
      clock => clock,
      reset => reset,
		done => done,
      I2C_SCLK => I2C_SCLK,
      I2C_SDAT => I2C_SDAT,
		SAMPLE_CTRL => SAMPLE_CTRL
   	);
	
	AUD_DACLRCK <= lrck;
	AUD_ADCLRCK <= lrck;
	-------------------------------------------------
	--The bit clock (BCLK) and left/right clock (LRCK) 
	-------------------------------------------------      
	Aud_Bclock: process(AUD_XCK, reset) is
		variable bcount : integer range 0 to bit_count * 2;
		variable wcount : integer range 0 to word_count * 2;
	begin
		if(reset = '1') then
			AUD_BCLK <= '0';
			LRCK <= '1';
			bcount := 0;
			wcount := 0;
		elsif(AUD_XCK'event and AUD_XCK = '1') then
			if(bcount >= bit_range - 1) then
				bcount := 0;
				AUD_BCLK <= not AUD_BCLK;
			else
				bcount := bcount + 1;
			end if;
			if(wcount >= word_range - 1) then
				wcount := 0;
				LRCK <= not LRCK;
			else
				wcount := wcount + 1;
			end if;			
		end if;
	end process;
 	-------------------------------------------------------------
	-- Send Audio data Rout and Lout to DAC via AUD_DACDAT
	-- Receive audio data from ADC; AUD_ADCDAT --> Rin and Lin.
	--------------------------------------------------------------
	Aud_RCV_XMT: process(AUD_XCK, reset)
		variable k: integer range 0 to 15;
	begin
		if(reset = '1') then			
			k := 0;
			RCV <= wait1;
			Rdone <= '0';
			Ldone <= '0';	
		elsif(AUD_XCK'event AND AUD_XCK = '1') then
			case RCV is
				when wait1 =>	
					if(LRCK='0') then RCV <= wait2; end if;
				when wait2 =>	
					Rdone <= '0';
					if(LRCK='1') then RCV <= left1; end if;
				when left1 =>
					if(AUD_BCLK='0') then RCV <= left2; end if;
					AUD_DACDAT <= Lout(15-k);
				when left2 =>
					if(AUD_BCLK='1') then 
						RCV <= left3;	
						Lin(15-k) <= AUD_ADCDAT;
					end if;
				when left3 =>
					k := k+1;
					RCV <= left4;
				when left4 =>
					if(k = 0) then
						RCV <= left5;
					else 
						RCV <= left1; 
					end if;
				when left5 =>
					Ldone <= '1';
					RCV <= right1;
		------------------------------------------------ 		
				when right1 =>
					if(AUD_BCLK='0') then RCV <= right2; end if;
					AUD_DACDAT <= Rout(15-k);
					Ldone <= '0';
				when right2 =>
					if(AUD_BCLK='1') then 
						RCV <= right3; 
						Rin(15-k) <= AUD_ADCDAT;
					end if;
				when right3 =>
					k := k+1;	
					RCV <= right4;
				when right4 =>
					if(k = 0) then 
						RCV <= right5; 
					else 
						RCV <= right1;
					end if;	
				when right5 =>
					Rdone <= '1';
					RCV <= wait2;						
				when OTHERS =>
					RCV <= wait1;
			end case;
		end if;		
	end process;
----------------------------------------------
	Audio_PLL : entity work.AudioPLL port map(
      inclk0 => clock,
      areset => done,	-- reset until I2C initialization is done
      c0 => AUD_XCK		-- ~18.432MHz
   );
end architecture WM8731;
