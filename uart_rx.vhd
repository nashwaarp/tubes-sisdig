library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity uart_rx is
    Generic (
        CLKS_PER_BIT : integer := 54  -- 50MHz / 921600 Baud = 54
    );
    Port (
        clk         : in  STD_LOGIC;
        rst_n       : in  STD_LOGIC;
        rx_serial   : in  STD_LOGIC;
        rx_out      : out STD_LOGIC_VECTOR(7 downto 0);
        rx_done     : out STD_LOGIC
    );
end uart_rx;

architecture Behavioral of uart_rx is

    type rx_state_type is (IDLE, START_BIT, DATA_BITS, STOP_BIT);
    signal state : rx_state_type := IDLE;
    
    signal clk_count : integer range 0 to CLKS_PER_BIT-1 := 0;
    signal bit_index : integer range 0 to 7 := 0;
    signal rx_byte   : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

begin

    process(clk, rst_n)
    begin
        if rst_n = '0' then
            state     <= IDLE;
            rx_done   <= '0';
            clk_count <= 0;
            bit_index <= 0;
        elsif rising_edge(clk) then
            -- Default pulse
            rx_done <= '0';

            case state is
                when IDLE =>
                    clk_count <= 0;
                    bit_index <= 0;
                    if rx_serial = '0' then  -- Start bit terdeteksi (Logic 0)
                        state <= START_BIT;
                    end if;

                when START_BIT =>
                    if clk_count = (CLKS_PER_BIT - 1)/2 then
                        if rx_serial = '0' then -- Pastikan ini benar-benar start bit (bukan glitch)
                            clk_count <= 0;
                            state <= DATA_BITS;
                        else
                            state <= IDLE;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when DATA_BITS =>
                    if clk_count = CLKS_PER_BIT - 1 then
                        clk_count <= 0;
                        rx_byte(bit_index) <= rx_serial; -- Ambil data
                        
                        if bit_index < 7 then
                            bit_index <= bit_index + 1;
                        else
                            bit_index <= 0;
                            state <= STOP_BIT;
                        end if;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when STOP_BIT =>
                    if clk_count = CLKS_PER_BIT - 1 then
                        rx_done <= '1'; -- Kirim sinyal bahwa 1 byte siap
                        rx_out  <= rx_byte;
                        state   <= IDLE;
                    else
                        clk_count <= clk_count + 1;
                    end if;

                when others =>
                    state <= IDLE;
            end case;
        end if;
    end process;

end Behavioral;