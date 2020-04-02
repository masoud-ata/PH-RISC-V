library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common.all;


entity risc_v is    
    generic(
        PROGRAM_ADDRESS_WIDTH: natural := 6;
        DATA_ADDRESS_WIDTH: natural := 6;
        CPU_DATA_WIDTH: natural := 32;
        REGISTER_FILE_ADDRESS_WIDTH: natural := 5
    );
    
    port(
        clk: in std_logic;
        reset_n: in std_logic;
        program_read: in std_logic_vector(INSTRUCTION_WIDTH-1 downto 0);
        pc: out std_logic_vector(PROGRAM_ADDRESS_WIDTH-1 downto 0);
        data_address: out std_logic_vector(DATA_ADDRESS_WIDTH-1 downto 0);
        data_read: in std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        data_write_en: out std_logic;
        data_write: out std_logic_vector(CPU_DATA_WIDTH-1 downto 0) 
    );        
end risc_v;

architecture behavioral of risc_v is

    type forward_control_type is record
        ex_forward_mux_left_operand: std_logic_vector(1 downto 0);
        ex_forward_mux_right_operand: std_logic_vector(1 downto 0);
        id_forward_mux_r1: boolean;
        id_forward_mux_r2: boolean;          
    end record;
    
    type instruction_type is record
        funct7: std_logic_vector(6 downto 0);
        rs2: std_logic_vector(4 downto 0);
        rs1: std_logic_vector(4 downto 0);
        funct3: std_logic_vector(2 downto 0);
        rd: std_logic_vector(4 downto 0);
        opcode: std_logic_vector(6 downto 0);
    end record;    

    type if_id_type is record 
        pc: std_logic_vector(PROGRAM_ADDRESS_WIDTH-1 downto 0);
        instruction: instruction_type;
    end record;
    
    type id_ex_type is record
        control_alu_op: std_logic_vector(1 downto 0);
        control_alu_src: std_logic;
        control_mem_read: std_logic;
        control_mem_write: std_logic;
        control_reg_write: std_logic;
        control_mem_to_reg: std_logic;
        register_file_data1: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        register_file_data2: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        sign_extended_immediate: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        alu_control: std_logic_vector(3 downto 0);
        register_file_rs1: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
        register_file_rs2: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
        register_file_rd: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
    end record;
    
    type ex_mem_type is record
        control_mem_read: std_logic;
        control_mem_write: std_logic;
        control_reg_write: std_logic;
        control_mem_to_reg: std_logic;    
        alu_result: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        register_file_data2: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        register_file_rd: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
    end record;
    
    type mem_wb_type is record
        control_reg_write: std_logic;
        control_mem_to_reg: std_logic;      
        memory_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        alu_result: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
        register_file_rd: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
    end record;
    
    constant FORWARD_NONE: std_logic_vector(1 downto 0) := "00";
    constant FORWARD_EX_MEM: std_logic_vector(1 downto 0) := "01";
    constant FORWARD_MEM_WB: std_logic_vector(1 downto 0) := "10";
        
    function generate_immediate(instruction: instruction_type) return std_logic_vector is
        type inst_t is (I, S, SB);
        variable inst_type: inst_t;
        variable sign_extended_immediate: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    begin
        if (instruction.opcode(6) = '0' and instruction.opcode(5) = '0') then
            inst_type := I;
        elsif (instruction.opcode(6) = '0' and instruction.opcode(5) = '1') then  
            inst_type := S;  
        else
            inst_type := SB; 
        end if;
            
        if (inst_type = I) then
            sign_extended_immediate := 
                std_logic_vector(resize(signed(instruction.funct7 & instruction.rs2), sign_extended_immediate'length));
        elsif (inst_type = S) then
            sign_extended_immediate := 
                std_logic_vector(resize(signed(instruction.funct7 & instruction.rd), sign_extended_immediate'length));
        else
            sign_extended_immediate := 
                std_logic_vector(resize(signed((
                    instruction.funct7(6) & instruction.rd(0) & 
                    instruction.funct7(5 downto 0) & instruction.rd(4 downto 1))), sign_extended_immediate'length
                ));
        end if;   
        
        return sign_extended_immediate; 
    end;
    
    function control_forwarding(
        ex_mem_reg_write: std_logic;
        ex_mem_rd: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0); 
        mem_wb_reg_write: std_logic;
        mem_wb_rd: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
        if_id_rs1: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0); 
        if_id_rs2: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0); 
        id_ex_rs1: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0);
        id_ex_rs2: std_logic_vector(REGISTER_FILE_ADDRESS_WIDTH-1 downto 0)    
    ) return forward_control_type is
        variable ex_mem_writes_back: boolean;
        variable ex_mem_reg_rd_not_x0: boolean;
        variable mem_wb_writes_back: boolean;
        variable mem_wb_reg_rd_not_x0: boolean; 
        variable forward_control: forward_control_type;              
    begin
        forward_control.ex_forward_mux_left_operand := FORWARD_NONE;
        forward_control.ex_forward_mux_right_operand := FORWARD_NONE;
        forward_control.id_forward_mux_r1 := false;
        forward_control.id_forward_mux_r2 := false;
        
        ex_mem_writes_back := (ex_mem_reg_write = '1');
        ex_mem_reg_rd_not_x0 := (ex_mem_rd /= std_logic_vector(to_unsigned(0, ex_mem_rd'length)));
        mem_wb_writes_back := (mem_wb_reg_write = '1');
        mem_wb_reg_rd_not_x0 := (mem_wb_rd /= std_logic_vector(to_unsigned(0, mem_wb_rd'length)));

        -- forward to id (since register file is sync with clock and wb can't write in time for RF to read the right value)
        if mem_wb_writes_back and mem_wb_reg_rd_not_x0 then
            if mem_wb_rd = if_id_rs1 then
                forward_control.id_forward_mux_r1 := true;
            end if;     
            if mem_wb_rd = if_id_rs2 then
                forward_control.id_forward_mux_r2 := true;
            end if; 
        end if; 
            
        -- forward to ex           
        if ex_mem_writes_back and ex_mem_reg_rd_not_x0 then
            if ex_mem_rd = id_ex_rs1 then
                forward_control.ex_forward_mux_left_operand := FORWARD_EX_MEM;
            end if;
            if ex_mem_rd = id_ex_rs2 then
                forward_control.ex_forward_mux_right_operand := FORWARD_EX_MEM;
            end if;
        elsif mem_wb_writes_back and mem_wb_reg_rd_not_x0 then
            if mem_wb_rd = id_ex_rs1 then
                forward_control.ex_forward_mux_left_operand := FORWARD_MEM_WB;
            end if;
            if mem_wb_rd = id_ex_rs2 then
                forward_control.ex_forward_mux_right_operand := FORWARD_MEM_WB;
            end if;                         
        end if;
        
        return forward_control;
    end;    
        
    signal pc_reg, pc_next: std_logic_vector(PROGRAM_ADDRESS_WIDTH-1 downto 0);
    
    signal if_id_reg, if_id_next: if_id_type;
    signal id_ex_reg, id_ex_next: id_ex_type;
    signal ex_mem_reg, ex_mem_next: ex_mem_type;
    signal mem_wb_reg, mem_wb_next: mem_wb_type;
    
    -- ID stage
    signal id_sign_extended_immediate: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal id_sign_extended_immediate_shifted_1: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal id_branch_address: std_logic_vector(PROGRAM_ADDRESS_WIDTH-1 downto 0);
    signal id_register_file_read1_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal id_register_file_read2_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal id_r1_equals_r2: std_logic;
    signal id_read1_final_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal id_read2_final_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);

    signal id_control_alu_op: std_logic_vector(1 downto 0);
    signal id_control_alu_src: std_logic;
    signal id_control_mem_read: std_logic;
    signal id_control_mem_write: std_logic;
    signal id_control_reg_write: std_logic;
    signal id_control_mem_to_reg: std_logic; 
    signal id_control_is_branch: std_logic;   
    signal id_control_branch_taken: std_logic;
    
    signal id_forward_mux_r1: boolean;
    signal id_forward_mux_r2: boolean;
        
    -- EX stage    
    signal ex_alu_zero: std_logic;
    signal ex_alu_result: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);    
    signal ex_alu_left_operand: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal ex_alu_right_operand: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    signal ex_alu_control: std_logic_vector(2 downto 0);
    signal ex_read2_final_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    
    signal ex_forward_mux_left_operand: std_logic_vector(1 downto 0);
    signal ex_forward_mux_right_operand: std_logic_vector(1 downto 0);

    -- WB stage
    signal wb_register_file_write_data: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);

    -- control
    signal pc_src: std_logic;
    signal forward_controls: forward_control_type;
       
begin

    registers: process (clk) is
    begin
        if rising_edge(clk) then
            if reset_n = '0' then
                pc_reg <= (others => '0');
                if_id_reg <= (instruction => (others => (others => '0')), others => (others => '0'));               
                id_ex_reg <= ("00", '0', '0', '0', '0', '0', others => (others => '0'));
                ex_mem_reg <= ('0', '0', '0', '0',others => (others => '0'));
                mem_wb_reg <= ('0', '0', others => (others => '0'));
            else
                pc_reg <= pc_next;
                if_id_reg <= if_id_next;
                id_ex_reg <= id_ex_next;
                ex_mem_reg <= ex_mem_next;
                mem_wb_reg <= mem_wb_next;
            end if;
        end if;
    end process registers;
 
    reg_file: entity work.register_file 
        generic map (
            DATA_WIDTH => CPU_DATA_WIDTH,
            ADDRESS_WIDTH => REGISTER_FILE_ADDRESS_WIDTH
        )
        port map (
            clk => clk,
            reset_n => reset_n,
            write_en => mem_wb_reg.control_reg_write,
            read1_id => if_id_reg.instruction.rs1,
            read2_id => if_id_reg.instruction.rs2,
            write_id => mem_wb_reg.register_file_rd,
            write_data => wb_register_file_write_data,
            read1_data => id_register_file_read1_data,
            read2_data => id_register_file_read2_data
        );
    
    alu_unit: entity work.alu 
        port map (
            control => ex_alu_control,
            left_operand => ex_alu_left_operand,
            right_operand => ex_alu_right_operand,
            zero => ex_alu_zero,
            result => ex_alu_result
        );

    next_pc_logic: process (pc_reg, id_branch_address, pc_src) is
    begin
        if pc_src = '0' then
            pc_next <= std_logic_vector(unsigned(pc_reg) + 4);
        else 
            pc_next <= id_branch_address;
        end if;
    end process next_pc_logic;
    
    id_sign_extended_immediate <= generate_immediate(if_id_reg.instruction);
    
    control_unit: process (if_id_reg.instruction.opcode) is
        constant R_FORMAT: std_logic_vector(6 downto 0) := "0110011";
        constant ADDI: std_logic_vector(6 downto 0) := "0010011";
        constant LOAD: std_logic_vector(6 downto 0) := "0000011";
        constant STORE: std_logic_vector(6 downto 0) := "0100011";
        constant BEQ: std_logic_vector(6 downto 0) := "1100011";
    begin
        id_control_alu_op <= "00";
        id_control_alu_src <= '0';
        id_control_mem_read <= '0';
        id_control_mem_write <= '0';
        id_control_reg_write <= '0';
        id_control_mem_to_reg <= '0';
        id_control_is_branch <= '0';
        
        if if_id_reg.instruction.opcode = R_FORMAT then
            id_control_alu_op <= "10";
            id_control_reg_write <= '1';
        elsif if_id_reg.instruction.opcode = ADDI then
            id_control_alu_op <= "10";
            id_control_reg_write <= '1';
            id_control_alu_src <= '1';
        elsif if_id_reg.instruction.opcode = LOAD then
            id_control_alu_src <= '1';
            id_control_mem_read <= '1';
            id_control_reg_write <= '1';
            id_control_mem_to_reg <= '1';
        elsif if_id_reg.instruction.opcode = STORE then
            id_control_alu_src <= '1';
            id_control_mem_write <= '1';
        elsif if_id_reg.instruction.opcode = BEQ then
            id_control_alu_op <= "01"; 
            id_control_is_branch <= '1';          
        end if;
    end process control_unit;   

    alu_control: process (id_ex_reg.alu_control, id_ex_reg.control_alu_op) is
        constant ALU_AND: std_logic_vector(2 downto 0) := "000";
        constant ALU_OR: std_logic_vector(2 downto 0) := "001";
        constant ALU_ADD: std_logic_vector(2 downto 0) := "010";
        constant ALU_SUB: std_logic_vector(2 downto 0) := "110";
    begin    
        ex_alu_control <= ALU_AND;
             
        if id_ex_reg.control_alu_op = "00" then
            ex_alu_control <= ALU_ADD;
        elsif id_ex_reg.control_alu_op = "01" then
            ex_alu_control <= ALU_SUB;
        elsif id_ex_reg.alu_control = "0000" then
            ex_alu_control <= ALU_ADD;
        elsif id_ex_reg.alu_control = "1000" then
            ex_alu_control <= ALU_SUB;       
        elsif id_ex_reg.alu_control = "0111" then
            ex_alu_control <= ALU_AND;
        elsif id_ex_reg.alu_control = "0110" then
            ex_alu_control <= ALU_OR;                                     
        end if;
    end process alu_control;
    
    forward_controls <= control_forwarding(
        ex_mem_reg_write => ex_mem_reg.control_reg_write,
        ex_mem_rd => ex_mem_reg.register_file_rd,
        mem_wb_reg_write => mem_wb_reg.control_reg_write,
        mem_wb_rd => mem_wb_reg.register_file_rd,
        if_id_rs1 => if_id_reg.instruction.rs1,
        if_id_rs2 => if_id_reg.instruction.rs2,
        id_ex_rs1 => id_ex_reg.register_file_rs1,
        id_ex_rs2 => id_ex_reg.register_file_rs2
    );
    ex_forward_mux_left_operand <= forward_controls.ex_forward_mux_left_operand;
    ex_forward_mux_right_operand <= forward_controls.ex_forward_mux_right_operand;
    id_forward_mux_r1 <= forward_controls.id_forward_mux_r1;
    id_forward_mux_r2 <= forward_controls.id_forward_mux_r2;    

    alu_and_forwarding_left_mux: process (
        ex_forward_mux_left_operand, id_ex_reg.register_file_data1, 
        ex_mem_reg.alu_result, wb_register_file_write_data) 
    begin
        ex_alu_left_operand <= (others => '0');
        
        if ex_forward_mux_left_operand = FORWARD_NONE then
            ex_alu_left_operand <= id_ex_reg.register_file_data1;
        elsif ex_forward_mux_left_operand = FORWARD_EX_MEM then
            ex_alu_left_operand <= ex_mem_reg.alu_result;
        elsif ex_forward_mux_left_operand = FORWARD_MEM_WB then
            ex_alu_left_operand <= wb_register_file_write_data;         
        end if;  
    end process alu_and_forwarding_left_mux;

    alu_and_forwarding_right_mux: process (
        ex_forward_mux_right_operand, id_ex_reg.control_alu_src, id_ex_reg.register_file_data2, 
        ex_mem_reg.alu_result, id_ex_reg.sign_extended_immediate, wb_register_file_write_data
    ) 
        variable mux_1: std_logic_vector(CPU_DATA_WIDTH-1 downto 0);
    begin
        ex_alu_right_operand <= (others => '0');
        mux_1 := (others => '0');
        
        if ex_forward_mux_right_operand = FORWARD_NONE then
            mux_1 := id_ex_reg.register_file_data2;
        elsif ex_forward_mux_right_operand = FORWARD_EX_MEM then
            mux_1 := ex_mem_reg.alu_result;
        elsif ex_forward_mux_right_operand = FORWARD_MEM_WB then
            mux_1 := wb_register_file_write_data;            
        end if; 
        
        if id_ex_reg.control_alu_src = '0' then        
            ex_alu_right_operand <= mux_1;
        else 
            ex_alu_right_operand <= id_ex_reg.sign_extended_immediate; 
        end if;
        
        ex_read2_final_data <= mux_1;
    end process alu_and_forwarding_right_mux;
    
    id_read1_final_data <= wb_register_file_write_data when id_forward_mux_r1 else id_register_file_read1_data;
    id_read2_final_data <= wb_register_file_write_data when id_forward_mux_r2 else id_register_file_read2_data;
    
    -- Pipeline registers next state logic
    if_id_next <= (
        pc => pc_reg, 
        instruction => (
            program_read(31 downto 25), program_read(24 downto 20), program_read(19 downto 15), 
            program_read(14 downto 12), program_read(11 downto 7), program_read(6 downto 0)
        )
    );

    id_ex_next <= (
        control_alu_op => id_control_alu_op,
        control_alu_src => id_control_alu_src,
        control_mem_read => id_control_mem_read,
        control_mem_write => id_control_mem_write,
        control_reg_write => id_control_reg_write,
        control_mem_to_reg => id_control_mem_to_reg,
        register_file_data1 => id_read1_final_data, 
        register_file_data2 => id_read2_final_data, 
        sign_extended_immediate => id_sign_extended_immediate, 
        alu_control => if_id_reg.instruction.funct7(5) & if_id_reg.instruction.funct3, 
        register_file_rs1 => if_id_reg.instruction.rs1,
        register_file_rs2 => if_id_reg.instruction.rs2,
        register_file_rd => if_id_reg.instruction.rd
    );
 
    ex_mem_next <= (
        control_mem_read => id_ex_reg.control_mem_read, 
        control_mem_write => id_ex_reg.control_mem_write, 
        control_reg_write => id_ex_reg.control_reg_write, 
        control_mem_to_reg => id_ex_reg.control_mem_to_reg,
        alu_result => ex_alu_result, 
        register_file_data2 => ex_read2_final_data, 
        register_file_rd => id_ex_reg.register_file_rd
    );
        
    mem_wb_next <= (
        control_reg_write => ex_mem_reg.control_reg_write,
        control_mem_to_reg => ex_mem_reg.control_mem_to_reg,
        memory_data => data_read, 
        alu_result => ex_mem_reg.alu_result,
        register_file_rd => ex_mem_reg.register_file_rd
    );
  
    id_sign_extended_immediate_shifted_1 <= id_sign_extended_immediate(CPU_DATA_WIDTH-2 downto 0) & '0';
    
    id_branch_address <= std_logic_vector(signed(if_id_reg.pc) + signed(id_sign_extended_immediate_shifted_1(PROGRAM_ADDRESS_WIDTH-1 downto 0)));
    
    id_r1_equals_r2 <= '1' when (id_read1_final_data = id_read2_final_data) else '0';
    id_control_branch_taken <= id_control_is_branch and id_r1_equals_r2;
      
    wb_register_file_write_data <= mem_wb_reg.alu_result when mem_wb_reg.control_mem_to_reg = '0' else mem_wb_reg.memory_data;
    
    --controls
    pc_src <= id_control_branch_taken;
    
    pc <= pc_reg;     
    data_address <= ex_mem_reg.alu_result(DATA_ADDRESS_WIDTH-1 downto 0);    
    data_write <= ex_mem_reg.register_file_data2;  
    data_write_en <= ex_mem_reg.control_mem_write;  
    
end behavioral;
