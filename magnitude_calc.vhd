library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity magnitude_calc is
    Generic (
        DATA_WIDTH : integer := 16
    );
    Port (
        clk         : in  STD_LOGIC;
        rst_n       : in  STD_LOGIC;
        valid_in    : in  STD_LOGIC;  -- Sinyal trigger dari FSM saat data Re & Im siap
        
        -- Input dari RAM (Hasil akhir FFT)
        data_re     : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        data_im     : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        
        -- Output menuju UART Transmitter
        mag_out     : out STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        valid_out   : out STD_LOGIC   -- Sinyal penanda magnitudo sudah selesai dihitung
    );
end magnitude_calc;

architecture RTL of magnitude_calc is

    -- Sinyal internal untuk proses aritmatika
    signal re_signed, im_signed : signed(DATA_WIDTH-1 downto 0);
    signal abs_re, abs_im       : unsigned(DATA_WIDTH-1 downto 0);
    signal max_val, min_val     : unsigned(DATA_WIDTH-1 downto 0);
    signal min_shr2, min_shr3   : unsigned(DATA_WIDTH-1 downto 0);
    signal sum_mag              : unsigned(DATA_WIDTH-1 downto 0);

begin

    -- ========================================================================
    -- PROSES KOMBINASIONAL (Rangkaian logika dasar)
    -- ========================================================================
    
    -- 1. Konversi tipe data
    re_signed <= signed(data_re);
    im_signed <= signed(data_im);

    -- 2. Dapatkan nilai absolut (Mutlak)
    abs_re <= unsigned(abs(re_signed));
    abs_im <= unsigned(abs(im_signed));

    -- 3. Tentukan mana yang lebih besar (Max) dan lebih kecil (Min)
    max_val <= abs_re when abs_re > abs_im else abs_im;
    min_val <= abs_im when abs_re > abs_im else abs_re;

    -- 4. Shift right (Pembagian untuk mendapatkan 0.375 * Min)
    min_shr2 <= shift_right(min_val, 2); -- min_val / 4
    min_shr3 <= shift_right(min_val, 3); -- min_val / 8

    -- 5. Jumlahkan semuanya: Max + (Min/4) + (Min/8)
    sum_mag <= max_val + min_shr2 + min_shr3;


    -- ========================================================================
    -- PROSES SEKUENSIAL (Register / D-Flip Flop penyimpan hasil)
    -- ========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            mag_out   <= (others => '0');
            valid_out <= '0';
        elsif rising_edge(clk) then
            -- Meneruskan sinyal valid (Pipeline delay 1 clock cycle)
            valid_out <= valid_in;
            
            -- Jika input valid, simpan hasil jumlahan ke output
            if valid_in = '1' then
                mag_out <= std_logic_vector(sum_mag);
            end if;
        end if;
    end process;

end RTL;