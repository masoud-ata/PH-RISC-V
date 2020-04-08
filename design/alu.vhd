library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;


entity alu is
    generic(DATA_WIDTH: integer := 32);

    port(
        control: in std_logic_vector(2 downto 0);
        left_operand: in std_logic_vector(DATA_WIDTH-1 downto 0);
        right_operand: in std_logic_vector(DATA_WIDTH-1 downto 0);
        zero: out std_logic;
        result: out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end alu;

architecture behavioral of alu is

    signal alu_result: std_logic_vector(DATA_WIDTH-1 downto 0);

begin

    process(control, left_operand, right_operand)
    begin
        case control is
            when "000" => 
                alu_result <= left_operand and right_operand;
            when "001" => 
                alu_result <= left_operand or right_operand;
            when "010" =>
                alu_result <= std_logic_vector(signed(left_operand) + signed(right_operand));
            when "110" => 
                alu_result <= std_logic_vector(signed(left_operand) - signed(right_operand));
            when others => 
                alu_result <= left_operand and right_operand;
        end case;
    end process;

    result <= alu_result;
    zero <= '1' when signed(alu_result) = 0 else '0';

end behavioral;