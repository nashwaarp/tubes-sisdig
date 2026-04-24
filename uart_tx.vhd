library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_tx is
    Generic (
        CLK_FREQ   : integer := 50_000_000; -- 50 MHz
        BAUD_RATE  : integer := 921600;     -- Menggunakan baud rate tinggi untuk visualisasi real-time
        DATA_WIDTH : integer := 8           -- Mengirim per 1 byte
    );
    Port (
        clk        : in  STD_LOGIC;
        rst_n      : in  STD_LOGIC;
        
        tx_data    : in  STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0);
        tx_start   : in  STD_LOGIC; -- Sinyal trigger dari FSM
        
        tx         : out STD_LOGIC; -- Pin fisik TX ke PC
        tx_ready   : out STD_LOGIC; -- '1' jika siap menerima data baru
        tx_done    : out STD_LOGIC  -- Pulse '1' saat 1 byte selesai dikirim
    );
end uart_tx;

architecture RTL of uart_tx is

    constant CLKS_PER_BIT : integer := CLK_FREQ / BAUD_RATE;
    
    type state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : state_type := IDLE;
    
    signal baud_counter : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_counter  : integer range 0 to DATA_WIDTH-1 := 0;
    signal tx_shift_reg : STD_LOGIC_VECTOR(DATA_WIDTH-1 downto 0) := (others => '0');

begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state        <= IDLE;
            baud_counter <= 0;
            bit_counter  <= 0;
            tx_shift_reg <= (others => '0');
            tx_done      <= '0';
        elsif rising_edge(clk) then
            tx_done <= '0'; -- Default value agar menjadi pulse

            case state is
                when IDLE =>
                    baud_counter <= 0;
                    bit_counter  <= 0;
                    if tx_start = '1' then
                        tx_shift_reg <= tx_data;
                        state        <= START_BIT;
                    end if;

                when START_BIT =>
                    if baud_counter < CLKS_PER_BIT - 1 then
                        baud_counter <= baud_counter + 1;
                    else
                        baud_counter <= 0;
                        state        <= DATA_BITS;
                    end if;

                when DATA_BITS =>
                    if baud_counter < CLKS_PER_BIT - 1 then
                        baud_counter <= baud_counter + 1;
                    else
                        baud_counter <= 0;
                        tx_shift_reg <= '0' & tx_shift_reg(DATA_WIDTH-1 downto 1);
                        
                        if bit_counter < DATA_WIDTH - 1 then
                            bit_counter <= bit_counter + 1;
                        else
                            bit_counter <= 0;
                            state       <= STOP_BIT;
                        end if;
                    end if;

                when STOP_BIT =>
                    if baud_counter < CLKS_PER_BIT - 1 then
                        baud_counter <= baud_counter + 1;
                    else
                        tx_done <= '1'; -- Kirim sinyal selesai ke FSM
                        state   <= IDLE;
                    end if;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

    -- Output Kombinasional
    tx <= '0' when state = START_BIT else
          tx_shift_reg(0) when state = DATA_BITS else 
          '1';
          
    tx_ready <= '1' when state = IDLE else '0';

end RTL;