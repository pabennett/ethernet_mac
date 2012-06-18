--------------------------------------------------------------------------------
-- UART
-- Wrapper for the UART core.
--           
-- @author         Peter A Bennett
-- @copyright      (c) 2012 Peter A Bennett
-- @version        $Rev: 2 $
-- @lastrevision   $Date: 2012-03-11 15:19:25 +0000 (Sun, 11 Mar 2012) $
-- @license        LGPL      
-- @email          pab850@googlemail.com
-- @contact        www.bytebash.com
--
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity UART is
    Generic 
    (
            BAUD_RATE               : positive;
            CLOCK_FREQUENCY         : positive;
            TX_FIFO_DEPTH           : positive;
            RX_FIFO_DEPTH           : positive
    );
    Port 
    (  -- General
            CLOCK                   :   in      std_logic;
            RESET                   :   in      std_logic;    
            TX_FIFO_DATA_IN         :   in      std_logic_vector(7 downto 0);
            TX_FIFO_DATA_IN_STB     :   in      std_logic;
            TX_FIFO_DATA_IN_ACK     :   out     std_logic;
            RX_FIFO_DATA_OUT        :   out     std_logic_vector(7 downto 0);
            RX_FIFO_DATA_OUT_STB    :   out     std_logic;
            RX_FIFO_DATA_OUT_ACK    :   in      std_logic;
            RX                      :   in      std_logic;
            TX                      :   out     std_logic
    );
end UART;

architecture RTL of UART is
    -- Component Declarations
    component UART_core is
        Generic (
                BAUD_RATE           : positive;
                CLOCK_FREQUENCY     : positive
            );
        Port (  -- General
                CLOCK100M           :   in      std_logic;
                RESET               :   in      std_logic;    
                DATA_STREAM_IN      :   in      std_logic_vector(7 downto 0);
                DATA_STREAM_IN_STB  :   in      std_logic;
                DATA_STREAM_IN_ACK  :   out     std_logic;
                DATA_STREAM_OUT     :   out     std_logic_vector(7 downto 0);
                DATA_STREAM_OUT_STB :   out     std_logic;
                DATA_STREAM_OUT_ACK :   in      std_logic;
                TX                  :   out     std_logic;
                RX                  :   in      std_logic
             );
    end component UART_core;
    
    component FIFO is
        generic(
            width : integer;
            depth : integer
        );
        port(  CLOCK        :   in  std_logic;
               RESET        :   in  std_logic;
               DATA_IN      :   in  std_logic_vector (width - 1 downto 0);
               DATA_OUT     :   out std_logic_vector (width - 1 downto 0);
               DATA_IN_STB  :   in  std_logic;
               DATA_OUT_STB :   out std_logic;
               DATA_IN_ACK  :   out std_logic;
               DATA_OUT_ACK :   in  std_logic
        );
    end component FIFO;

    -- FIFO signals
    signal tx_fifo_data_out         : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_fifo_data_out_stb     : std_logic := '0';
    signal tx_fifo_data_out_ack     : std_logic := '0';
    signal rx_fifo_data_in          : std_logic_vector(7 downto 0) := (others => '0');
    signal rx_fifo_data_in_stb      : std_logic := '0';
    signal rx_fifo_data_in_ack      : std_logic := '0';
        
begin

    UART_inst1 : UART_core
    generic map (
            BAUD_RATE           => BAUD_RATE,
            CLOCK_FREQUENCY     => CLOCK_FREQUENCY
    )
    port map    (  -- General
            CLOCK100M           => CLOCK,
            RESET               => RESET,
            DATA_STREAM_IN      => tx_fifo_data_out,
            DATA_STREAM_IN_STB  => tx_fifo_data_out_stb,
            DATA_STREAM_IN_ACK  => tx_fifo_data_out_ack,
            DATA_STREAM_OUT     => rx_fifo_data_in,
            DATA_STREAM_OUT_STB => rx_fifo_data_in_stb,
            DATA_STREAM_OUT_ACK => rx_fifo_data_in_ack,
            TX                  => TX,
            RX                  => RX
    );
    
    TX_FIFO : FIFO generic map(
      width => 8,
      depth => TX_FIFO_DEPTH
    )
    port map(  CLOCK    =>  CLOCK,
           RESET        =>  RESET,
           DATA_IN      =>  TX_FIFO_DATA_IN,
           DATA_OUT     =>  tx_fifo_data_out,
           DATA_IN_STB  =>  TX_FIFO_DATA_IN_STB,
           DATA_OUT_STB =>  tx_fifo_data_out_stb,
           DATA_IN_ACK  =>  TX_FIFO_DATA_IN_ACK,
           DATA_OUT_ACK =>  tx_fifo_data_out_ack
    );     

    RX_FIFO : FIFO generic map(
      width => 8,
      depth => RX_FIFO_DEPTH
    )
    port map(  CLOCK    =>  CLOCK,
           RESET        =>  RESET,
           DATA_IN      =>  rx_fifo_data_in,
           DATA_OUT     =>  RX_FIFO_DATA_OUT,
           DATA_IN_STB  =>  rx_fifo_data_in_stb,
           DATA_OUT_STB =>  RX_FIFO_DATA_OUT_STB,
           DATA_IN_ACK  =>  rx_fifo_data_in_ack,
           DATA_OUT_ACK =>  RX_FIFO_DATA_OUT_ACK
    );   
            
end RTL;
