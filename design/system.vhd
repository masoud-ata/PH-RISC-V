library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;


entity system is
    generic (
        PROGRAM_ADDRESS_WIDTH: natural := 10;
        DATA_ADDRESS_WIDTH: natural := 6;
        CPU_DATA_WIDTH: natural := 32
    );
    
    port (
        clk: in std_logic;
        reset_n: in std_logic;
        redundant: out std_logic      
    );
end system;

architecture structural of system is
    
    signal program_address: std_logic_vector(PROGRAM_ADDRESS_WIDTH-1 downto 0);
    signal program_data: std_logic_vector(INSTRUCTION_WIDTH-1 downto 0);
    
    signal data_write_en: std_logic;
    signal data_address: std_logic_vector(DATA_ADDRESS_WIDTH-1 downto 0);
    signal data_read: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal data_write: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);    

begin

    cpu: entity work.ph_risc_v 
        generic map (
            PROGRAM_ADDRESS_WIDTH => PROGRAM_ADDRESS_WIDTH,
            DATA_ADDRESS_WIDTH => DATA_ADDRESS_WIDTH,
            CPU_DATA_WIDTH => CPU_DATA_WIDTH,
            REGISTER_FILE_ADDRESS_WIDTH => 5
        )
        port map (
            clk => clk,
            reset_n => reset_n,
            program_read => program_data,
            pc => program_address,
            data_address => data_address,
            data_read => data_read,
            data_write_en => data_write_en,
            data_write => data_write
        );
    
    prog_mem: entity work.program_memory 
        generic map (
                ADDRESS_WIDTH => PROGRAM_ADDRESS_WIDTH,
                DATA_WIDTH => INSTRUCTION_WIDTH
            )    
        port map (
            clk => clk,
            write_en => '0',
            write_data => (others => '0'),
            address => program_address,
            read_data => program_data
        );

    data_mem: entity work.data_memory 
        generic map (
            ADDRESS_WIDTH => DATA_ADDRESS_WIDTH,
            DATA_WIDTH => CPU_DATA_WIDTH
        )
        port map (
            clk => clk,
            write_en => data_write_en,
            write_data => data_write,
            address => data_address,
            read_data => data_read
        );
    
    -- Just added to force the tools not to optimize away the logic
    process (clk)
        variable red: std_logic := '0';
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                red := '0';
            else
                for i in data_write'range loop
                    red := red or data_write(i);
                end loop;
            end if;            
            redundant <= red;
        end if;
    end process;
    
end structural;