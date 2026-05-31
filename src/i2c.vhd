library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c is
   generic(
		clk_freq: integer := 50000000; --input clock 50MHz
		i2c_freq: integer := 20000     -- I2C 20KHz
	);
   port(
      clock 	: in std_logic;
      reset 	: in std_logic;
		done	 	: out std_logic;
      I2C_SCLK 	: out std_logic;
      I2C_SDAT 	: inout std_logic;
		SAMPLE_CTRL : in std_logic_vector(15 downto 0)
	);
end;

architecture initialization of I2C is
	signal	i2c_clk, i2c_end, sdo : std_logic;
	signal 	go : boolean;
	signal	ack : std_logic_vector(1 to 3);
	signal	num : unsigned(3 downto 0);
	signal	i2c_out : std_logic_vector(15 downto 0);
	
	constant address : std_logic_vector(7 downto 0) := X"34";	
	type codec is array (0 to 9) of std_logic_vector(15 downto 0);
	constant Audio_init: codec :=
         (	x"0015", -- SET_LIN_L//L-line, modernately high gain; max=1F
				x"0215", -- SET_LIN_R//R-line, modernately high gain; max=1F
				x"0475", -- SET_HEAD_L//L-phone out, medium volume; max=79
				x"0675", -- SET_HEAD_R//R-phone out, medium volume; max=79
				x"0812", -- A_PATH_CTRL//Line-> ADC, DAC on, no bypass
				x"0A06", -- D_PATH_CTRL//deemph to 48KHz
				x"0C00", -- POWER_ON//all on
				x"0E01", -- SET_FORMAT//MSB first, left justified, 16-bit
				x"1002", -- SAMPLE_CTRL(48KHz)//MSB first, left justified
				x"1201"  -- SET_ACTIVE//Activate
          );
	type statei2c is (s1, s2, s3, s4, s5);
	signal AUDIO : statei2c;
	
begin
	I2C_SDAT <= '0' when SDO='0' else 'Z';
   -----------------------------------------------	
	I2C_Clock_Gen: process(clock, reset) is
		variable count : integer range 0 to clk_freq / (2 * i2c_freq);
	begin
		if(reset = '1') then
			i2c_clk <= '0';	
			count := 0;		
		elsif(clock'event and clock = '1') then
			if(count < (clk_freq / (2 * i2c_freq)) - 1) then
				count := count + 1;
			else
				count := 0;
				i2c_clk <= not i2c_clk;
			end if;
		end if;
	end process;
   -----------------------------------------------	
   audio_config: process(i2c_clk, reset) is
	begin
	   if(reset = '1') then
			go <= false;
			num <= "0000";
			done <= '1';
			Audio <= s1;
	   elsif(i2c_clk'event and i2c_clk = '1') then
			case AUDIO is
				when  s1 => 
					go <= true;
					if(num = 8) then
						i2c_out <= SAMPLE_CTRL;
					else
						i2c_out <= Audio_init(to_integer(num));
					end if;
					Audio <= s2;
				when s2 =>
					if(i2c_end='1') then 
						go <= false; 
						Audio <= s3; 
					end if;
				when s3 =>
					if(ack = "000") then 
						Audio <= s4;
					else
						Audio <= s1;
					end if;
				when s4 =>
					num <= num + 1;
					Audio <= s5;
				when s5 =>
					if(num < 10) then
						Audio <= s1;
					else
						done <= '0';
					end if;
				when others =>
					Audio <= s1;
			end case;
	   end if;
	end process;   
   -----------------------------------------------
   -- The I2C transmitter/receiver
   -----------------------------------------------
   I2C_Port: process(i2c_clk, reset) is
		variable index : integer range 0 to 32;
   begin
		if(index <= 1 or index >= 31) then I2C_SCLK <= '1';
			elsif(index = 2 or index = 30) then I2C_SCLK <= '0';
				else I2C_SCLK <= not i2c_clk;	
		end if;	
			
      if(reset = '1') then
			SDO <= '1';
			i2c_end <= '0';
			ack <= "000";
			index := 0;
      elsif(i2c_clk'event and i2c_clk = '1') then
			if(go) then index := index + 1; else index := 0; end if;
			if(index = 0) then -- idle condition
				SDO <= '1';
				i2c_end <= '0';
				ack <= "000";
			elsif(index = 1) then
				SDO <= '0';
			elsif(index = 2) then
				null;
			elsif(index >= 3 and index <= 10) then
				SDO <= address(10-index);	--send address
			elsif(index = 11) then
				SDO <= '1';
			elsif(index = 12) then
				SDO <= i2c_out(15);		--send bit 15
				ack(1) <= I2C_SDAT;		--receive ack for byte1
			elsif(index >= 13 and index <= 19) then
				SDO <= i2c_out(27-index);	--send 2nd byte
			elsif(index = 20) then
				SDO <= '1';
			elsif(index = 21) then
				SDO <= i2c_out(7);		--send bit 7
				ack(2) <= I2C_SDAT;		--receive ack for byte2
			elsif(index >= 22 and index <= 28) then
				SDO <= i2c_out(28-index);	--send 3rd byte
			elsif(index = 29) then
				SDO <= '1';
			elsif(index = 30) then
				SDO <= '0';				
				ack(3) <= I2C_SDAT;		--receive ack for byte3
			elsif(index = 31) then
				null;
			elsif(index = 32) then
				SDO <= '1';				
				i2c_end <= '1';
			end if;
      end if;
   end process I2C_Port;
end  initialization;
