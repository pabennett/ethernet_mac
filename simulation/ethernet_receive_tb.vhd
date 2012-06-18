library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
library std;
use std.textio.all;

library work;
use work.all;

entity ethernet_receive_tb is

end ethernet_receive_tb;

architecture BEH of ethernet_receive_tb is  
    signal  s_reset, s_reset_n      : std_logic := '0';
    signal  s_clock                 : std_logic := '0';
    signal  MDIO_CLK                : std_logic := '0';      
    signal  data                    : std_logic_vector(3 downto 0) := X"A";
    signal  datavalid               : std_logic := '0';
    signal  datacount               : integer := 0;
    signal  s_uart_txd              : std_logic := '0';
    component message_gen is
      port (  -- General
              CLOCK_Y3            :   in      std_logic;
              USER_RESET          :   in      std_logic;    
              -- UART
              USB_RS232_RXD       :   in      std_logic;
              USB_RS232_TXD       :   out     std_logic;
              -- Ethernet
              ETH_MDC             :   out     std_logic;
              ETH_RX_CLK          :   in      std_logic;
              ETH_RX_D0           :   in      std_logic;
              ETH_RX_D1           :   in      std_logic;    
              ETH_RX_D2           :   in      std_logic;
              ETH_RX_D3           :   in      std_logic;
              ETH_RX_DV           :   in      std_logic
           );
    end component message_gen;


    type dataout is array (0 to 71) of std_logic_vector(7 downto 0);
       
    signal rxdv         : std_logic := '1';
    
    
    --for all : top use entity WORK.top;
begin
        
    ETHRX : message_gen
    port map(
            CLOCK_Y3            => s_clock,
            USER_RESET          => s_reset_n,  
            -- UART
            USB_RS232_RXD       => '0',
            USB_RS232_TXD       => s_uart_txd,
            -- Ethernet
            ETH_MDC             => MDIO_CLK,
            ETH_RX_CLK          => MDIO_CLK,
            ETH_RX_D0           => data(0),
            ETH_RX_D1           => data(1),
            ETH_RX_D2           => data(2),
            ETH_RX_D3           => data(3),
            ETH_RX_DV           => rxdv
    );
    
    s_reset <= '0', '1' after 100 NS;
    s_reset_n <= not s_reset;
    
    CLOCKGEN : process(s_clock)
    begin
        s_clock <= not s_clock after 5 NS;
    end process CLOCKGEN;
    
    DATAGEN : process(MDIO_CLK)
        variable currentbyte : std_logic_vector(7 downto 0);
        variable highnib, lownib : std_logic_vector(3 downto 0);
        variable sendlownib : boolean := FALSE;
        variable L                  : line;
        variable v_file_open        : boolean := FALSE;
        variable v_file_open_status : file_open_status;
        file     testfile           : text;
        variable first_call         : boolean := TRUE;    
        constant c_filepath         : string := "./simulation/source.txt";    
        variable done               : boolean := FALSE;
    begin
    
        if (not v_file_open) and first_call then
            file_open(v_file_open_status, testfile, c_filepath, read_mode);
            assert (v_file_open_status = open_ok)
            report "Failed to open settings file: " & c_filepath & " , aborting simulation." severity Failure;
            v_file_open := TRUE;
            rxdv        <= '1';
        else
            if falling_edge(MDIO_CLK) then
                if v_file_open then
                    if not endfile(testfile) then
                        if first_call then
                            sendlownib := TRUE;
                            readline(testfile, L);
                            hread(L, currentbyte);
                            lownib      := currentbyte(3 downto 0);
                            highnib     := currentbyte(7 downto 4);
                            first_call  := FALSE;
                        end if;
                        if sendlownib then
                            data       <= lownib;
                            sendlownib := FALSE;
                        else
                            data       <= highnib;
                            sendlownib := TRUE;
                            readline(testfile, L);
                            hread(L, currentbyte);
                            lownib      := currentbyte(3 downto 0);
                            highnib     := currentbyte(7 downto 4);
                        end if;
                    else
                        if not done and sendlownib then
                            data       <= lownib;
                            sendlownib := FALSE;
                        elsif not done then
                            data       <= highnib;
                            sendlownib := TRUE;
                            done        := TRUE;
                            lownib      := currentbyte(3 downto 0);
                            highnib     := currentbyte(7 downto 4);
                        else
                            rxdv            <= '0';
                            file_close(testfile);
                            v_file_open     := FALSE;
                            assert FALSE
                            report "End of test file reached." severity note;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process DATAGEN;
end BEH;
