library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fsm_controller is
    Port (
        clk             : in  STD_LOGIC;
        rst_n           : in  STD_LOGIC;
        
        -- Sinyal Status dari Modul Lain (Input)
        rx_data_ready   : in  STD_LOGIC; -- Dari UART RX (menandakan 1 byte siap)
        mag_done        : in  STD_LOGIC; -- Dari Magnitude Calculator
        tx_done         : in  STD_LOGIC; -- Dari UART TX (menandakan 1 byte selesai dikirim)
        
        -- Sinyal Kendali ke Modul Lain (Output)
        -- 1. Ke Address Generator
        addr_mode       : out STD_LOGIC_VECTOR(2 downto 0);
        stage_out       : out STD_LOGIC_VECTOR(3 downto 0); -- Stage 0-9
        step_out        : out STD_LOGIC_VECTOR(8 downto 0); -- Step 0-511
        addr_in         : out STD_LOGIC_VECTOR(9 downto 0); -- Index untuk Bit Reversal (0-1023)
        
        -- 2. Ke RAM & FIFO
        fifo_rd_en      : out STD_LOGIC;
        mem_we          : out STD_LOGIC;
        
        -- 3. Ke Butterfly Unit
        bf_en           : out STD_LOGIC;
        
        -- 4. Ke Magnitude Calculator
        mag_en          : out STD_LOGIC;
        
        -- 5. Ke UART TX
        tx_start        : out STD_LOGIC;
        
        -- Mux Control (Untuk memilih address RAM saat membaca/menulis)
        -- '0' = Address dari Generator (saat FFT), '1' = Address dari FSM (saat UART TX)
        addr_mux_sel    : out STD_LOGIC;
        fsm_read_addr   : out STD_LOGIC_VECTOR(9 downto 0) 
    );
end fsm_controller;

architecture RTL of fsm_controller is

    -- Definisi State Utama
    type state_type is (
        IDLE, 
        BURST_LOAD,      -- Menerima 1024 data dari UART ke RAM (via FIFO & Bit Reversal)
        FFT_COMPUTE,     -- Siklus utama FFT (Read RAM & hitung Butterfly)
        WAIT_BF_PIPELINE,-- Menunggu Butterfly selesai (Latensi 3 clock)
        UPDATE_MEM,      -- Menulis hasil Butterfly kembali ke RAM
        MAGNITUDE_CALC,  -- Menghitung Magnitudo dari hasil akhir
        SEND_DATA,       -- Mengirim data ke UART
        DONE_STATE
    );
    signal current_state, next_state : state_type;

    -- Counter Internal
    signal rx_cnt     : unsigned(9 downto 0) := (others => '0'); -- 0 to 1023
    signal stage_cnt  : unsigned(3 downto 0) := (others => '0'); -- 0 to 9
    signal step_cnt   : unsigned(8 downto 0) := (others => '0'); -- 0 to 511
    signal tx_cnt     : unsigned(9 downto 0) := (others => '0'); -- 0 to 1023
    
    -- Sub-state untuk transmisi UART TX (Mirip di top-level lamamu)
    signal tx_substate : integer range 0 to 3 := 0;

begin

    -- ========================================================================
    -- PROSES 1: Update State & Counter (Sekuensial)
    -- ========================================================================
    process(clk, rst_n)
    begin
        if rst_n = '0' then
            current_state <= IDLE;
            rx_cnt        <= (others => '0');
            stage_cnt     <= (others => '0');
            step_cnt      <= (others => '0');
            tx_cnt        <= (others => '0');
            tx_substate   <= 0;
        elsif rising_edge(clk) then
            current_state <= next_state;
            
            -- Logika Counter Berdasarkan State Saat Ini
            case current_state is
                when IDLE =>
                    rx_cnt    <= (others => '0');
                    stage_cnt <= (others => '0');
                    step_cnt  <= (others => '0');
                    tx_cnt    <= (others => '0');
                    tx_substate <= 0;

                when BURST_LOAD =>
                    -- Setiap kali data ready, counter naik
                    if rx_data_ready = '1' then
                        rx_cnt <= rx_cnt + 1;
                    end if;

                when UPDATE_MEM =>
                    -- Selesai 1 siklus Butterfly, naikkan step
                    if step_cnt = 511 then
                        step_cnt <= (others => '0');
                        stage_cnt <= stage_cnt + 1;
                    else
                        step_cnt <= step_cnt + 1;
                    end if;

                when SEND_DATA =>
                    -- State Machine mini untuk transmisi UART per byte
                    if tx_cnt < 1024 then
                        case tx_substate is
                            when 0 => 
                                tx_substate <= 1; -- Tunggu latensi RAM read (1 clock)
                            when 1 =>
                                -- Mag Calculator butuh 1 clock lagi untuk menghitung
                                tx_substate <= 2; 
                            when 2 =>
                                -- Memicu pengiriman UART
                                tx_substate <= 3;
                            when 3 =>
                                -- Tunggu sinyal tx_done dari modul UART TX
                                if tx_done = '1' then
                                    tx_cnt <= tx_cnt + 1;
                                    tx_substate <= 0;
                                end if;
                        end case;
                    end if;

                when others =>
                    null;
            end case;
        end if;
    end process;


    -- ========================================================================
    -- PROSES 2: Logika Transisi State (Kombinasional)
    -- ========================================================================
    process(current_state, rx_cnt, stage_cnt, step_cnt, tx_cnt)
    begin
        next_state <= current_state; 
        
        case current_state is
            when IDLE =>
                -- Mulai jika ada data masuk (Ini asumsi sistem langsung aktif saat ada data)
                -- Dalam praktiknya, mungkin butuh kondisi rx_data_ready = '1' di sini
                next_state <= BURST_LOAD;

            when BURST_LOAD =>
                if rx_cnt = 1023 then -- 1024 data (0-1023)
                    next_state <= FFT_COMPUTE;
                end if;

            when FFT_COMPUTE =>
                next_state <= WAIT_BF_PIPELINE;

            when WAIT_BF_PIPELINE =>
                -- Karena pipeline Butterfly kita 3 clock cycle,
                -- kita asumsikan setelah FFT_COMPUTE, ia butuh 1-2 siklus tambahan sebelum update
                -- Untuk sederhananya di draf ini, kita langsung pindah (nanti disesuaikan dengan valid_out Butterfly)
                next_state <= UPDATE_MEM;

            when UPDATE_MEM =>
                if stage_cnt = 10 and step_cnt = 0 then
                    -- Semua 10 stage selesai (0-9)
                    next_state <= SEND_DATA; 
                    -- Catatan: FSM ini melompat langsung ke SEND_DATA, 
                    -- karena komputasi Magnitude dilakukan on-the-fly saat membaca RAM untuk UART
                else
                    next_state <= FFT_COMPUTE;
                end if;

            when SEND_DATA =>
                if tx_cnt = 1024 then
                    next_state <= DONE_STATE;
                end if;

            when DONE_STATE =>
                next_state <= IDLE;

            when others =>
                next_state <= IDLE;
        end case;
    end process;


    -- ========================================================================
    -- PROSES 3: Sinyal Output Kendali (Kombinasional)
    -- ========================================================================
    process(current_state, rx_data_ready, stage_cnt, step_cnt, rx_cnt, tx_cnt, tx_substate)
    begin
        -- Nilai Default untuk mencegah Latch
        addr_mode    <= "000";
        fifo_rd_en   <= '0';
        mem_we       <= '0';
        bf_en        <= '0';
        mag_en       <= '0';
        tx_start     <= '0';
        addr_mux_sel <= '0';
        
        -- Teruskan nilai counter ke Address Generator
        stage_out <= std_logic_vector(stage_cnt);
        step_out  <= std_logic_vector(step_cnt);
        addr_in   <= std_logic_vector(rx_cnt);
        fsm_read_addr <= std_logic_vector(tx_cnt);

        case current_state is
            when BURST_LOAD =>
                addr_mode <= "001"; -- Mode Bit Reversal
                if rx_data_ready = '1' then
                    fifo_rd_en <= '1';
                    mem_we     <= '1';
                end if;

            when FFT_COMPUTE =>
                addr_mode <= "010"; -- Mode Read RAM
                bf_en     <= '1';   -- Aktifkan Butterfly

            when WAIT_BF_PIPELINE =>
                addr_mode <= "011"; -- Mode Persiapan Tulis

            when UPDATE_MEM =>
                addr_mode <= "011"; -- Mode Tulis RAM
                mem_we    <= '1';

            when SEND_DATA =>
                addr_mux_sel <= '1'; -- Ambil alih kendali alamat RAM dari Address Generator
                
                -- tx_substate 0: FSM mengatur alamat (fsm_read_addr <= tx_cnt)
                -- tx_substate 1: RAM mengeluarkan data Real & Imag
                if tx_substate = 1 then
                    mag_en <= '1'; -- Picu kalkulator magnitudo
                end if;
                -- tx_substate 2: Kalkulator selesai, trigger pengiriman UART
                if tx_substate = 2 then
                    tx_start <= '1';
                end if;

            when others =>
                null;
        end case;
    end process;

end RTL;