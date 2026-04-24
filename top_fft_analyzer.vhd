library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity top_fft_analyzer is
    Port (
        -- Input utama dari Board Cyclone IV
        clk_50mhz : in  STD_LOGIC;
        rst_n     : in  STD_LOGIC;  -- Reset aktif rendah (Sesuai kesepakatan)
        
        -- Antarmuka Komunikasi PC via UART
        uart_rx   : in  STD_LOGIC;  -- Pin RX (Data dari Python)
        uart_tx   : out STD_LOGIC;  -- Pin TX (Data ke Python)
        
        -- Indikator Visual untuk Debugging
        led_idle  : out STD_LOGIC;  -- Menyala saat sistem IDLE
        led_done  : out STD_LOGIC   -- Pulse saat frame selesai terkirim
    );
end top_fft_analyzer;

architecture Structural of top_fft_analyzer is

    -- ========================================================================
    -- SINYAL INTERNAL (Penghubung Antar Modul)
    -- ========================================================================
    
    -- Sinyal Kendali dari FSM Controller
    signal fsm_addr_mode   : STD_LOGIC_VECTOR(2 downto 0);
    signal fsm_stage       : STD_LOGIC_VECTOR(3 downto 0);
    signal fsm_step        : STD_LOGIC_VECTOR(8 downto 0);
    signal fsm_addr_in     : STD_LOGIC_VECTOR(9 downto 0);
    signal fsm_fifo_rd_en  : STD_LOGIC;
    signal fsm_mem_we      : STD_LOGIC;
    signal fsm_bf_en       : STD_LOGIC;
    signal fsm_mag_en      : STD_LOGIC;
    signal fsm_tx_start    : STD_LOGIC;
    signal fsm_mux_sel     : STD_LOGIC;
    signal fsm_read_addr   : STD_LOGIC_VECTOR(9 downto 0);

    -- Sinyal dari UART RX & FIFO
    signal rx_byte_ready   : STD_LOGIC;
    signal rx_byte_data    : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_data_out   : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_empty      : STD_LOGIC;

    -- Sinyal dari Address Generator
    signal gen_addr_rd_a   : STD_LOGIC_VECTOR(9 downto 0);
    signal gen_addr_rd_b   : STD_LOGIC_VECTOR(9 downto 0);
    signal gen_addr_wr     : STD_LOGIC_VECTOR(9 downto 0);
    signal twiddle_idx     : STD_LOGIC_VECTOR(8 downto 0);

    -- Sinyal Memori RAM (Hasil MUX Alamat)
    signal ram_final_rd_a  : STD_LOGIC_VECTOR(9 downto 0);
    signal ram_final_wr_addr : STD_LOGIC_VECTOR(9 downto 0);
    signal ram_in_re       : STD_LOGIC_VECTOR(15 downto 0);
    signal ram_in_im       : STD_LOGIC_VECTOR(15 downto 0);
    signal ram_out_re_a    : STD_LOGIC_VECTOR(15 downto 0);
    signal ram_out_im_a    : STD_LOGIC_VECTOR(15 downto 0);
    signal ram_out_re_b    : STD_LOGIC_VECTOR(15 downto 0);
    signal ram_out_im_b    : STD_LOGIC_VECTOR(15 downto 0);

    -- Sinyal ROM Twiddle Factor
    signal rom_re_out      : STD_LOGIC_VECTOR(15 downto 0);
    signal rom_im_out      : STD_LOGIC_VECTOR(15 downto 0);

    -- Sinyal Butterfly Unit
    signal bf_re_a         : signed(15 downto 0);
    signal bf_im_a         : signed(15 downto 0);
    signal bf_re_b         : signed(15 downto 0);
    signal bf_im_b         : signed(15 downto 0);

    -- Sinyal Magnitude & UART TX
    signal mag_val_out     : STD_LOGIC_VECTOR(15 downto 0);
    signal mag_valid_sig   : STD_LOGIC;
    signal tx_byte_done    : STD_LOGIC;

begin

    -- ========================================================================
    -- LOGIKA PEMILIHAN JALUR (MULTIPLEXER)
    -- ========================================================================
    
    -- 1. Alamat Baca Port A: Digunakan Address Gen (saat FFT) atau FSM (saat Kirim UART)
    ram_final_rd_a <= fsm_read_addr when fsm_mux_sel = '1' else gen_addr_rd_a;

    -- 2. Data Input RAM: Audio mentah (saat Load) atau Hasil Butterfly (saat FFT)
    ram_in_re <= std_logic_vector(resize(signed(fifo_data_out), 16)) when fsm_addr_mode = "001" else 
             std_logic_vector(bf_re_a);
                 
    ram_in_im <= (others => '0') when fsm_addr_mode = "001" else 
                 std_logic_vector(bf_im_a);

    -- ========================================================================
    -- INSTANSIASI BLOK KENDALI & KOMUNIKASI
    -- ========================================================================

    inst_fsm: entity work.fsm_controller
        port map (
            clk             => clk_50mhz,
            rst_n           => rst_n,
            rx_data_ready   => rx_byte_ready,
            mag_done        => mag_valid_sig,
            tx_done         => tx_byte_done,
            addr_mode       => fsm_addr_mode,
            stage_out       => fsm_stage,
            step_out        => fsm_step,
            addr_in         => fsm_addr_in,
            fifo_rd_en      => fsm_fifo_rd_en,
            mem_we          => fsm_mem_we,
            bf_en           => fsm_bf_en,
            mag_en          => fsm_mag_en,
            tx_start        => fsm_tx_start,
            addr_mux_sel    => fsm_mux_sel,
            fsm_read_addr   => fsm_read_addr
        );

    inst_rx: entity work.uart_rx
        generic map (CLKS_PER_BIT => 54) -- 921600 Baud
        port map (
            clk       => clk_50mhz,
            rst_n     => rst_n,
            rx_serial => uart_rx,
            rx_out    => rx_byte_data,
            rx_done   => rx_byte_ready
        );

    inst_tx: entity work.uart_tx
        generic map (BAUD_RATE => 921600)
        port map (
            clk      => clk_50mhz,
            rst_n    => rst_n,
            tx_data  => mag_val_out(7 downto 0), -- Ambil 8-bit sesuai spek Python
            tx_start => fsm_tx_start,
            tx       => uart_tx,
            tx_ready => open,
            tx_done  => tx_byte_done
        );

    -- ========================================================================
    -- INSTANSIASI BLOK DATAPATH & ARITMATIKA
    -- ========================================================================

    inst_addr_gen: entity work.address_generator
        port map (
            clk          => clk_50mhz,
            rst_n        => rst_n,
            mode         => fsm_addr_mode,
            stage        => fsm_stage,
            step         => fsm_step,
            addr_in      => fsm_addr_in,
            addr_read_a  => gen_addr_rd_a,
            addr_read_b  => gen_addr_rd_b,
            addr_write   => gen_addr_wr,
            twiddle_addr => twiddle_idx
        );

    inst_bf: entity work.butterfly_unit
        port map (
            clk        => clk_50mhz,
            rst_n      => rst_n, -- Sudah seragam active-low
            enable     => fsm_bf_en,
            A_real     => signed(ram_out_re_a),
            A_imag     => signed(ram_out_im_a),
            B_real     => signed(ram_out_re_b),
            B_imag     => signed(ram_out_im_b),
            W_real     => signed(rom_re_out),
            W_imag     => signed(rom_im_out),
            A_out_real => bf_re_a,
            A_out_imag => bf_im_a,
            B_out_real => bf_re_b,
            B_out_imag => bf_im_b,
            valid_out  => open
        );

    inst_mag: entity work.magnitude_calc
        port map (
            clk       => clk_50mhz,
            rst_n     => rst_n,
            valid_in  => fsm_mag_en,
            data_re   => ram_out_re_a,
            data_im   => ram_out_im_a,
            mag_out   => mag_val_out,
            valid_out => mag_valid_sig
        );

   -- ========================================================================
    -- INSTANSIASI IP CORES 
    -- ========================================================================
    
    inst_fifo : entity work.my_fifo_ip 
        port map (
            clock => clk_50mhz,
            data  => rx_byte_data,
            rdreq => fsm_fifo_rd_en,
            wrreq => rx_byte_ready,
            empty => fifo_empty,
            q     => fifo_data_out
        );

    -- Pakai IP RAM yang sama untuk Real dan Imajiner
    inst_ram_re : entity work.my_ram_ip 
        port map (
            clock     => clk_50mhz,
            data      => ram_in_re,
            rdaddress => ram_final_rd_a,
            wraddress => gen_addr_wr,
            wren      => fsm_mem_we,
            q         => ram_out_re_a
        );

    inst_ram_im : entity work.my_ram_ip 
        port map (
            clock     => clk_50mhz,
            data      => ram_in_im,
            rdaddress => ram_final_rd_a,
            wraddress => gen_addr_wr,
            wren      => fsm_mem_we,
            q         => ram_out_im_a
        );

    -- ROM: 1-PORT untuk Twiddle Real
    inst_rom_twiddle_re : entity work.my_rom_twiddle_re_ip 
        port map (
            clock   => clk_50mhz,
            address => twiddle_idx,
            q       => rom_re_out
        );

    -- ROM: 1-PORT untuk Twiddle Imajiner
    inst_rom_twiddle_im : entity work.my_rom_twiddle_im_ip 
        port map (
            clock   => clk_50mhz,
            address => twiddle_idx,
            q       => rom_im_out
        );

    -- LED Indikator
    led_idle <= '1' when fsm_addr_mode = "000" else '0';
    led_done <= tx_byte_done;

end Structural;