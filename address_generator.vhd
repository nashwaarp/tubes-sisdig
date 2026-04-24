library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ==========================================
-- SUB-ENTITY: Bit Reversal (10-bit)
-- ==========================================
entity bit_reversal is
    generic (ADDR_WIDTH: integer := 10);
    port (
        addr_in  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        addr_out : out std_logic_vector(ADDR_WIDTH-1 downto 0)
    );
end entity bit_reversal;

architecture RTL of bit_reversal is
begin
    process(addr_in)
    begin
        for i in 0 to ADDR_WIDTH-1 loop
            addr_out(i) <= addr_in(ADDR_WIDTH-1-i);
        end loop;
    end process;
end architecture RTL;

-- ==========================================
-- MAIN ENTITY: Address Generator (10-stage)
-- ==========================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity address_generator is
    generic (
        ADDR_WIDTH : integer := 10; -- Diubah untuk 1024-point
        N_STAGES   : integer := 10  -- log2(1024) = 10 stages
    );
    port (
        clk         : in  std_logic;
        rst_n       : in  std_logic; -- Menggunakan penamaan rst_n (active low)
        
        mode        : in  std_logic_vector(2 downto 0);
        stage       : in  std_logic_vector(3 downto 0); -- Butuh 4 bit untuk angka 0-9
        step        : in  std_logic_vector(8 downto 0); -- Butuh 9 bit untuk 512 operasi per stage
        addr_in     : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
        
        addr_read_a : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        addr_read_b : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        addr_write  : out std_logic_vector(ADDR_WIDTH-1 downto 0);
        
        -- Output tambahan untuk mengirim alamat memori ROM Twiddle Factor
        twiddle_addr: out std_logic_vector(8 downto 0) 
    );
end entity address_generator;

architecture RTL of address_generator is

    signal addr_br : std_logic_vector(ADDR_WIDTH-1 downto 0);
    
    -- Sinyal delay (Pipeline) untuk mencocokkan latensi Butterfly Unit
    signal addr_a_d1, addr_a_d2, addr_a_d3 : std_logic_vector(ADDR_WIDTH-1 downto 0);
    signal addr_b_d1, addr_b_d2, addr_b_d3 : std_logic_vector(ADDR_WIDTH-1 downto 0);

    -- Fungsi bawaan dari kode lamamu (algoritma pengalamatan Cooley-Tukey tetap sama, hanya beda lebar bit)
    function get_butterfly_addr(
        step_val  : unsigned;
        stage_val : integer;
        is_b      : boolean;
        width     : integer
    ) return std_logic_vector is
        variable result    : unsigned(width-1 downto 0);
        variable upper, lower, mask, shift_val : unsigned(width-1 downto 0);
        variable step_ext  : unsigned(width-1 downto 0); -- Variabel baru untuk penyesuaian ukuran
    begin
        step_ext := resize(step_val, width); -- Tarik step (9-bit) menjadi 10-bit
        
        if stage_val = 0 then 
            mask := (others => '0');
        else 
            mask := to_unsigned((2**stage_val) - 1, width);
        end if;
        
        lower := step_ext and mask;
        upper := (step_ext and not mask) sll 1;
        
        if is_b then
            shift_val := to_unsigned(1, width) sll stage_val;
            result := upper or shift_val or lower;
        else
            result := upper or lower;
        end if;
        
        return std_logic_vector(result);
    end function;

begin

    inst_bit_rev: entity work.bit_reversal
        generic map (ADDR_WIDTH => ADDR_WIDTH)
        port map (addr_in => addr_in, addr_out => addr_br);

    -- Proses Shift Register untuk Pipeline
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            addr_a_d1 <= (others => '0'); addr_a_d2 <= (others => '0'); addr_a_d3 <= (others => '0');
            addr_b_d1 <= (others => '0'); addr_b_d2 <= (others => '0'); addr_b_d3 <= (others => '0');
        elsif rising_edge(clk) then
            addr_a_d1 <= get_butterfly_addr(unsigned(step), to_integer(unsigned(stage)), false, ADDR_WIDTH);
            addr_a_d2 <= addr_a_d1;
            addr_a_d3 <= addr_a_d2;
            
            addr_b_d1 <= get_butterfly_addr(unsigned(step), to_integer(unsigned(stage)), true, ADDR_WIDTH);
            addr_b_d2 <= addr_b_d1;
            addr_b_d3 <= addr_b_d2;
        end if;
    end process;

    -- Kalkulasi alamat ROM untuk Twiddle Factor
    -- Di FFT Radix-2, indeks Twiddle bergantung pada stage dan step
    process(stage, step)
        variable shift_amt : integer;
        variable tw_index  : unsigned(8 downto 0);
    begin
        -- Menghitung k pada W_N^k. Semakin tinggi stage, loncatan indeks semakin kecil
        shift_amt := 9 - to_integer(unsigned(stage)); 
        tw_index := unsigned(step(8 downto 0)) sll shift_amt;
        twiddle_addr <= std_logic_vector(tw_index);
    end process;

    -- Logika Kombinasional Mode (Sama seperti sebelumnya)
    process(mode, addr_br, stage, step, addr_a_d3, addr_b_d3)
        variable addr_a_now : std_logic_vector(ADDR_WIDTH-1 downto 0);
        variable addr_b_now : std_logic_vector(ADDR_WIDTH-1 downto 0);
    begin
        addr_a_now := get_butterfly_addr(unsigned(step), to_integer(unsigned(stage)), false, ADDR_WIDTH);
        addr_b_now := get_butterfly_addr(unsigned(step), to_integer(unsigned(stage)), true, ADDR_WIDTH);

        case mode is
            when "001" => -- BIT REVERSAL (Loading dari UART)
                addr_read_a <= (others => '0');
                addr_read_b <= (others => '0');
                addr_write  <= addr_br;
                
            when "010" => -- READ STAGE (Kirim alamat ke RAM untuk dibaca Unit Butterfly)
                addr_read_a <= addr_a_now;
                addr_read_b <= addr_b_now;
                addr_write  <= (others => '0');
                
            when "011" => -- WRITE STAGE (Simpan hasil Butterfly kembali ke RAM menggunakan alamat yang di-delay)
                addr_read_a <= (others => '0');
                addr_read_b <= (others => '0');
                addr_write  <= addr_a_d3; 
                
            when others =>
                addr_read_a <= (others => '0');
                addr_read_b <= (others => '0');
                addr_write  <= (others => '0');
        end case;
    end process;

end architecture RTL;