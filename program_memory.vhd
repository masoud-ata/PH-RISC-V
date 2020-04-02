library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;


entity program_memory is
    generic (
        ADDRESS_WIDTH: natural := 6;
        DATA_WIDTH: natural := 32
    );
    
    port (
        clk: in std_logic;
        write_en: in std_logic;
        write_data: in std_logic_vector(DATA_WIDTH-1 downto 0);
        address: in std_logic_vector(ADDRESS_WIDTH-1 downto 0);
        read_data : out std_logic_vector(DATA_WIDTH-1 downto 0)
    );
end program_memory;

architecture behavioral of program_memory is

    constant MEMORY_DEPTH: natural := 2 ** ADDRESS_WIDTH;

    type ram_type is array (0 to MEMORY_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
    
    impure function initRAM(filename: in string) return ram_type is
        FILE ram_file: text is in filename;
        variable ram_file_line: line;
        variable instruction: bit_vector(DATA_WIDTH-1 downto 0);
        variable ram: ram_type := (others => (others => '0'));
    begin
        for i in ram_type'range loop
            if(not endfile(ram_file)) then
                readline(ram_file, ram_file_line);            
                read(ram_file_line, instruction);
                ram(i) := to_stdlogicvector((instruction));
            end if;
        end loop;        
        return ram;        
    end function;
    
    signal ram: ram_type := initRAM("instruction_mem.mem");
    
    alias word_address: std_logic_vector(ADDRESS_WIDTH-3 downto 0) is address(ADDRESS_WIDTH-1 downto 2);

begin

    instruction_ram: process (clk) is
    begin
        if rising_edge(clk) then
            if write_en = '1' then
                ram(to_integer(unsigned(word_address))) <= write_data;
            end if;
        end if;
    end process instruction_ram;

    read_data <= ram(to_integer(unsigned(word_address)));

end behavioral;
