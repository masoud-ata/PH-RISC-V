library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity testbench is

end testbench;

architecture Behavioral of testbench is

    component system is
        port(
            clk: in std_logic;
            reset_n: in std_logic
        );
    end component;

    signal clk: std_logic := '0';
    signal reset_n: std_logic := '0';

begin

    sys: system port map(
        clk => clk,
        reset_n => reset_n 
    );
    
    clk <= not clk after 10ns;
    reset_n <= '1' after 35ns;

end Behavioral;
