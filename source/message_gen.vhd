--------------------------------------------------------------------------------
-- MESSAGE GEN  
-- A wrapper class for testing. Will be removed.
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

library work;
use work.ethernet_constants.all;

entity MESSAGE_GEN is
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
end MESSAGE_GEN;

architecture RTL of MESSAGE_GEN is
  -- Functions
  function log2(A: integer) return integer is
  begin
    for I in 1 to 30 loop  -- Works for up to 32 bit integers
      if(2**I > A) then return(I-1);  end if;
    end loop;
    return(30);
  end;

  -- Component Declarations
  component UART is
    generic 
    (
      BAUD_RATE             : positive;
      CLOCK_FREQUENCY       : positive;
      TX_FIFO_DEPTH         : positive;
      RX_FIFO_DEPTH         : positive
    );
    port 
    (  -- General
      CLOCK                 :   in      std_logic;
      RESET                 :   in      std_logic;    
      TX_FIFO_DATA_IN       :   in      std_logic_vector(7 downto 0);
      TX_FIFO_DATA_IN_STB   :   in      std_logic;
      TX_FIFO_DATA_IN_ACK   :   out     std_logic;
      RX_FIFO_DATA_OUT      :   out     std_logic_vector(7 downto 0);
      RX_FIFO_DATA_OUT_STB  :   out     std_logic;
      RX_FIFO_DATA_OUT_ACK  :   in      std_logic;
      RX                    :   in      std_logic;
      TX                    :   out     std_logic
    );
  end component UART;

  component ethernet_receive is
    port 
    (  
      CLOCK                 :   in  std_logic;
      RESET                 :   in  std_logic;
      -- PHY Signals
      ETH_RX_CLK            :   in  std_logic;
      ETH_RX_DV             :   in  std_logic;
      ETH_RXD               :   in  std_logic_vector(3 downto 0);
      -- Control Signals
      FRAME_DATA_OUT        :   out std_logic_vector(7 downto 0);
      FRAME_DATA_OUT_STB    :   out std_logic;
      FRAME_END             :   out std_logic;
      FRAME_VALID           :   out std_logic;
      FRAME_NEW             :   out std_logic
    );
  end component ethernet_receive;

  component internet_receive is
    port
    (
      CLOCK                 :   in std_logic;
      RESET                 :   in std_logic;
      -- Datalink layer signals
      FRAME_DATA_OUT        :   in std_logic_vector(7 downto 0);
      FRAME_DATA_OUT_STB    :   in std_logic;
      FRAME_END             :   in std_logic;
      FRAME_VALID           :   in std_logic;
      FRAME_NEW             :   in std_logic;
      -- Signals to upper layer.
      NEW_DATA              :   out std_logic;
      DATA_VALID            :   out std_logic;
      DATA_LENGTH           :   out std_logic_vector(15 downto 0);
      SOURCE_IP_OUT         :   out std_logic_vector(31 downto 0);
      DESTINATION_IP_OUT    :   out std_logic_vector(31 downto 0);
      PROTOCOL_OUT          :   out std_logic_vector(7 downto 0);
      CHECKSUM_OUT          :   out std_logic_vector(15 downto 0);
      -- RAM interface
      RAM_DATA_OUT          :   out std_logic_vector(7 downto 0);
      RAM_WRITE_ADDRESS     :   out integer range 0 to (MAX_PACKET_LENGTH - 1);
      RAM_WRITE_ENABLE      :   out std_logic
    );
  end component internet_receive;

  component RAM is
    generic
    (
      WIDTH                 : positive;
      DEPTH                 : positive
    );
    port
    (
      CLOCK                 : in   std_logic;
      DATA_IN               : in   std_logic_vector (7 downto 0);
      WRITE_ADDRESS         : in   integer range 0 to MAX_PACKET_LENGTH - 1;
      READ_ADDRESS          : in   integer range 0 to MAX_PACKET_LENGTH - 1;
      WRITE_ENABLE          : in   std_logic;
      DATA_OUT              : out  std_logic_vector (7 downto 0)
    );
  end component RAM;

  component ICMP is
    port
    (
      CLOCK                 :   in std_logic;
      RESET                 :   in std_logic;
      -- Control signals
      NEW_DATA              :   in std_logic;
      DATA_VALID            :   in std_logic;
      DATA_LENGTH           :   in std_logic_vector(15 downto 0);
      SOURCE_IP             :   in std_logic_vector(31 downto 0);
      PROTOCOL              :   in std_logic_vector(7 downto 0);
      -- Network Send Layer Signals
      TX_NEW_DATA           :   out std_logic;
      TX_DATA_LENGTH        :   out std_logic_vector(15 downto 0);
      TX_SOURCE_IP          :   out std_logic_vector(31 downto 0);
      TX_DESTINATION_IP     :   out std_logic_vector(31 downto 0);
      TX_PROTOCOL           :   out std_logic_vector(7 downto 0);
      TX_SERVICE_TYPE       :   out std_logic_vector(7 downto 0);
      TX_IDENTIFICATION     :   out std_logic_vector(15 downto 0);
      TX_TIME_TO_LIVE       :   out std_logic_vector(7 downto 0);
      TX_FLAGS              :   out std_logic_vector(2 downto 0);
      -- RAM interface
      RAM_DATA_IN           :   in std_logic_vector(7 downto 0);
      RAM_READ_ADDRESS      :   out integer range 0 to (MAX_PACKET_LENGTH - 1);
      -- Misc
      ECHO_REQUEST          :   out std_logic
    );
  end component ICMP;

  component network_send is
    port
    (
      CLOCK                 :   in std_logic;
      RESET                 :   in std_logic;
      -- Datalink layer signals
      FRAME_DATA_OUT        :   out std_logic_vector(7 downto 0);
      FRAME_DATA_OUT_STB    :   out std_logic;
      FRAME_DATA_OUT_ACK    :   in  std_logic;
      FRAME_END             :   out std_logic;
      FRAME_VALID           :   out std_logic;
      FRAME_NEW             :   out std_logic;
      -- Upper layer signals.
      BUSY                  :   out std_logic;
      NEW_DATA              :   in std_logic;
      DATA_LENGTH           :   in std_logic_vector(15 downto 0);
      SOURCE_IP             :   in std_logic_vector(31 downto 0);
      DESTINATION_IP        :   in std_logic_vector(31 downto 0);
      PROTOCOL              :   in std_logic_vector(7 downto 0);
      SERVICE_TYPE          :   in std_logic_vector(7 downto 0);
      IDENTIFICATION        :   in std_logic_vector(15 downto 0);
      TIME_TO_LIVE          :   in std_logic_vector(7 downto 0);
      FLAGS                 :   in std_logic_vector(2 downto 0);
      -- RAM interface
      RAM_DATA_IN           :   in std_logic_vector(7 downto 0);
      RAM_READ_ADDRESS      :   out integer range 0 to (MAX_PACKET_LENGTH - 1)
    );
  end component network_send;
    
  signal CLOCK                          : std_logic := '0';

  signal reset_d0, reset                : std_logic := '0';
  signal uart_rxd_d0                    : std_logic := '0';
  signal uart_rxd                       : std_logic := '0';
  signal uart_txd_d0                    : std_logic := '0';
  signal uart_txd                       : std_logic := '0';
  signal eth_rx_clk_d0                  : std_logic := '0';
  signal eth_rx_clk_d1                  : std_logic := '0';
  signal eth_rxdv_d0                    : std_logic := '0';
  signal eth_rxdv                       : std_logic := '0';
  signal eth_rxd_d0                     : std_logic_vector (3 downto 0) := (others => '0');  
  signal eth_rxd                        : std_logic_vector (3 downto 0) := (others => '0');

  signal ethernet_frame_data_out        : std_logic_vector(7 downto 0) := (others => '0');
  signal ethernet_frame_data_out_stb    : std_logic := '0';
  signal ethernet_frame_end             : std_logic := '0';
  signal ethernet_frame_valid           : std_logic := '0';
  signal ethernet_frame_end_old         : std_logic := '0';
  signal ethernet_frame_new             : std_logic := '0';

  signal internet_new_data              : std_logic := '0';
  signal internet_data_valid            : std_logic := '0';
  signal internet_data_length           : std_logic_vector(15 downto 0) := (others => '0');
  signal internet_source_IP             : std_logic_vector(31 downto 0) := (others => '0');
  signal internet_destination_IP        : std_logic_vector(31 downto 0) := (others => '0');
  signal internet_protocol              : std_logic_vector(7 downto 0) := (others => '0');
  signal internet_checksum              : std_logic_vector(15 downto 0) := (others => '0');
          
  signal uart_tx_fifo_data_in           : std_logic_vector (7 downto 0) := (others => '0');
  signal uart_tx_fifo_data_in_stb       : std_logic := '0';
  signal uart_tx_fifo_data_in_ack       : std_logic := '0';
  signal uart_rx_fifo_data_in           : std_logic_vector (7 downto 0) := (others => '0');
  signal uart_rx_fifo_data_in_stb       : std_logic := '0';
  signal uart_rx_fifo_data_in_ack       : std_logic := '0';

  signal network_send_frame_data_out    : std_logic_vector(7 downto 0) := (others => '0');
  signal network_send_data_out_strobe   : std_logic := '0';
  signal network_send_data_out_ack      : std_logic := '0';
  signal network_send_frame_end         : std_logic := '0';
  signal network_send_frame_valid       : std_logic := '0';
  signal network_send_frame_new         : std_logic := '0';
  -- Upper layer signals.
  signal network_send_busy              : std_logic := '0';
  signal network_send_new_data          : std_logic := '0';
  signal network_send_data_length       : std_logic_vector(15 downto 0) := (others => '0');
  signal network_send_source_IP         : std_logic_vector(31 downto 0) := (others => '0');
  signal network_send_destination_IP    : std_logic_vector(31 downto 0) := (others => '0');
  signal network_send_protocol          : std_logic_vector(7 downto 0) := (others => '0');
  signal network_send_service_type      : std_logic_vector(7 downto 0) := (others => '0');
  signal network_send_identification    : std_logic_vector(15 downto 0) := (others => '0');
  signal network_send_time_to_live      : std_logic_vector(7 downto 0) := (others => '0');
  signal network_send_flags             : std_logic_vector(2 downto 0) := (others => '0');
  -- RAM interface
  signal network_send_ram_data_in       : std_logic_vector(7 downto 0) := (others => '0');
  signal network_send_ram_read_address  : integer range 0 to (MAX_PACKET_LENGTH - 1) := 0;

  signal icmp_ping_request              : std_logic := '0';

  signal packet_ram_data_in             : std_logic_vector(7 downto 0) := (others => '0');
  signal packet_ram_data_out            : std_logic_vector(7 downto 0) := (others => '0');
  signal packet_ram_write_address       : integer range 0 to (MAX_PACKET_LENGTH - 1) := 0;
  signal packet_ram_read_address        : integer range 0 to (MAX_PACKET_LENGTH - 1) := 0;
  signal packet_ram_write_enable        : std_logic := '0';

  signal icmp_tx_new_data               : std_logic := '0';
  signal icmp_tx_data_length            : std_logic_vector(15 downto 0) := (others => '0');
  signal icmp_tx_source_ip              : std_logic_vector(31 downto 0) := (others => '0');
  signal icmp_tx_destination_ip         : std_logic_vector(31 downto 0) := (others => '0');
  signal icmp_tx_protocol               : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_service_type           : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_identification         : std_logic_vector(15 downto 0) := (others => '0');
  signal icmp_tx_time_to_live           : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_flags                  : std_logic_vector(2 downto 0) := (others => '0');
  signal icmp_ram_read_address          : integer range 0 to (MAX_PACKET_LENGTH - 1) := 0;

  -- Message Sender Signals
  type message_states is                (idle, 
                                        send_new_frame_message, 
                                        send_configured_message,
                                        send_ping_request_message,
                                        send_LF,
                                        send_CR);

  signal message_sender_state           : message_states := idle;
  signal message_sender_source_IP       : std_logic_vector(31 downto 0);
  signal message_sender_dest_IP         : std_logic_vector(31 downto 0);
  signal message_sender_data_length     : std_logic_vector(15 downto 0);
  signal message_index                  : positive := 1;

  -- MDIO Clock
  constant c_mdio_clk_divider_val       : integer := ((100000000 / 25000000) / 2) - 1;
  constant c_mdio_divider               : unsigned (log2(c_mdio_clk_divider_val) downto 0) 
                                        := to_unsigned(c_mdio_clk_divider_val,log2(c_mdio_clk_divider_val) + 1);
  signal s_mdio_clk                     : std_logic := '0';

  signal mdio_clk_counter               : unsigned (c_mdio_divider'length - 1 downto 0) := (others => '0');

  -- Messages
  constant MSG_CONFIGURED               : string := "FPGA configured, listening for packets..." & CR & LF;
  constant MSG_NEW_FRAME                : string := "Internet layer received a new IP datagram..." & CR & LF;
  constant MSG_IP_SOURCE                : string := "Source IP: " & CR & LF;
  constant MSG_IP_DEST                  : string := "Destination IP: " & CR & LF;
  constant MSG_DATA_LENGTH              : string := "Data length: " & CR & LF;
  constant MSG_ETH_NEW_FRAME            : string := "Ethernet layer processing new frame..." & CR & LF;
  constant MSG_ETH_FRAME_END            : string := "Ethernet layer finished processing new frame." & CR & LF;
  constant MSG_ETH_PING_REQUEST         : string := "Ping request received from: " & CR & LF;

  signal MSG_IP_SOURCE_ADDRESS          : string(1 to 11) := "00.00.00.00";
  signal MSG_IP_DESTINATION_ADDRESS     : string(1 to 11) := "00.00.00.00";

  signal internet_new_data_latch        : std_logic := '0';
  signal ethernet_frame_start_latch     : std_logic := '0';
  signal ethernet_frame_end_latch       : std_logic := '0';
  signal icmp_ping_request_latch        : std_logic := '0';

begin

  CLOCK       <= CLOCK_Y3;

  DEGLITCHER : process (CLOCK)
  begin
      if rising_edge(CLOCK) then
          reset_d0        <= USER_RESET;
          reset           <= reset_d0;
          uart_rxd_d0     <= USB_RS232_RXD;
          uart_rxd        <= uart_rxd_d0;
          uart_txd_d0     <= uart_txd;
          USB_RS232_TXD   <= uart_txd_d0;
          eth_rx_clk_d0   <= ETH_RX_CLK;
          eth_rx_clk_d1   <= eth_rx_clk_d0;
          eth_rxd_d0      <= ETH_RX_D3 & ETH_RX_D2 & ETH_RX_D1 & ETH_RX_D0;
          eth_rxd         <= eth_rxd_d0;
          eth_rxdv_d0     <= ETH_RX_DV;
          eth_rxdv        <= eth_rxdv_d0;
      end if;
  end process DEGLITCHER;

  -- Generate a 25MHz MDIO CLOCK.
  MDIO_CLOCK_GEN   : process (CLOCK)
  begin
      if rising_edge (CLOCK) then
          if mdio_clk_counter = c_mdio_divider then
              mdio_clk_counter    <= (others => '0');
              s_mdio_clk          <= not s_mdio_clk;
          else
              mdio_clk_counter    <= mdio_clk_counter + 1;
          end if;
      end if;
  end process MDIO_CLOCK_GEN;

  ETH_MDC            <= s_mdio_clk;

  UART_inst1 : UART
  generic map 
  (
    BAUD_RATE               => 115200,
    CLOCK_FREQUENCY         => 100000000,
    TX_FIFO_DEPTH           => 1023,
    RX_FIFO_DEPTH           => 1023
  )
  port map 
  (
    CLOCK                   => CLOCK,
    RESET                   => reset,   
    TX_FIFO_DATA_IN         => uart_tx_fifo_data_in,
    TX_FIFO_DATA_IN_STB     => uart_tx_fifo_data_in_stb,
    TX_FIFO_DATA_IN_ACK     => uart_tx_fifo_data_in_ack,
    RX_FIFO_DATA_OUT        => open,
    RX_FIFO_DATA_OUT_STB    => open,
    RX_FIFO_DATA_OUT_ACK    => '0',
    RX                      => uart_rxd,
    TX                      => uart_txd
  );

  ETHERNET_RX : ethernet_receive
  port map    
  (  
    CLOCK                   => CLOCK,
    RESET                   => reset,
    -- PHY Signals
    ETH_RX_CLK              => eth_rx_clk_d1,
    ETH_RX_DV               => eth_rxdv,
    ETH_RXD                 => eth_rxd,
    -- Control Signals
    FRAME_DATA_OUT          => ethernet_frame_data_out,
    FRAME_DATA_OUT_STB      => ethernet_frame_data_out_stb,
    FRAME_END               => ethernet_frame_end,
    FRAME_VALID             => ethernet_frame_valid,
    FRAME_NEW               => ethernet_frame_new
  );   

  INTERNET_RX : internet_receive
  port map
  (
    CLOCK                   => CLOCK,
    RESET                   => reset,
    -- Datalink layer signals
    FRAME_DATA_OUT          => ethernet_frame_data_out,
    FRAME_DATA_OUT_STB      => ethernet_frame_data_out_stb,
    FRAME_END               => ethernet_frame_end,
    FRAME_VALID             => ethernet_frame_valid,
    FRAME_NEW               => ethernet_frame_new,
    -- Signals to upper layer.
    NEW_DATA                => internet_new_data,
    DATA_VALID              => internet_data_valid,
    DATA_LENGTH             => internet_data_length,
    SOURCE_IP_OUT           => internet_source_IP,
    DESTINATION_IP_OUT      => internet_destination_IP,
    PROTOCOL_OUT            => internet_protocol,
    CHECKSUM_OUT            => internet_checksum,
    -- RAM interface
    RAM_DATA_OUT            => packet_ram_data_in,
    RAM_WRITE_ADDRESS       => packet_ram_write_address,
    RAM_WRITE_ENABLE        => packet_ram_write_enable
  );

  -- RAM
  -- RAM to store packet (can hold jumbo frame of up to 9000 bytes)
  -- Can only hold 1 packet at a time.
  PACKET_RAM : RAM
  generic map
  (
    WIDTH                   => 8,
    DEPTH                   => MAX_PACKET_LENGTH - 1
  )
  port map
  (
    CLOCK                   => CLOCK,
    DATA_IN                 => packet_ram_data_in,
    WRITE_ADDRESS           => packet_ram_write_address,
    READ_ADDRESS            => packet_ram_read_address, 
    WRITE_ENABLE            => packet_ram_write_enable,
    DATA_OUT                => packet_ram_data_out
  );

  ICMP_PROTOCOL : ICMP
  port map
  (
    CLOCK                   => CLOCK,               
    RESET                   => reset, 
    -- Lower layer signals
    NEW_DATA                => internet_new_data,
    DATA_VALID              => internet_data_valid, 
    DATA_LENGTH             => internet_data_length,
    SOURCE_IP               => internet_source_IP,
    PROTOCOL                => internet_protocol,
    -- Misc
    ECHO_REQUEST            => icmp_ping_request,
    -- Network Send Layer Signals
    TX_NEW_DATA             => icmp_tx_new_data,
    TX_DATA_LENGTH          => icmp_tx_data_length,
    TX_SOURCE_IP            => icmp_tx_source_ip,
    TX_DESTINATION_IP       => icmp_tx_destination_ip,
    TX_PROTOCOL             => icmp_tx_protocol,
    TX_SERVICE_TYPE         => icmp_tx_service_type,
    TX_IDENTIFICATION       => icmp_tx_identification,
    TX_TIME_TO_LIVE         => icmp_tx_time_to_live,
    TX_FLAGS                => icmp_tx_flags,
    -- RAM interface
    RAM_DATA_IN             => packet_ram_data_out,
    RAM_READ_ADDRESS        => packet_ram_read_address
  );

  INTERNET_SEND : NETWORK_SEND
  port map
  (
    CLOCK                   => CLOCK,
    RESET                   => reset,
    -- Datalink layer signals
    FRAME_DATA_OUT          =>  network_send_frame_data_out,
    FRAME_DATA_OUT_STB      =>  network_send_data_out_strobe,
    FRAME_DATA_OUT_ACK      =>  network_send_data_out_ack,
    FRAME_END               =>  network_send_frame_end,
    FRAME_VALID             =>  network_send_frame_valid,
    FRAME_NEW               =>  network_send_frame_new,
    -- Upper layer signals.
    BUSY                    =>  network_send_busy,
    NEW_DATA                =>  network_send_new_data,
    DATA_LENGTH             =>  network_send_data_length,
    SOURCE_IP               =>  network_send_source_IP,
    DESTINATION_IP          =>  network_send_destination_IP,
    PROTOCOL                =>  network_send_protocol,
    SERVICE_TYPE            =>  network_send_service_type,
    IDENTIFICATION          =>  network_send_identification,
    TIME_TO_LIVE            =>  network_send_time_to_live,
    FLAGS                   =>  network_send_flags,
    -- RAM interface
    RAM_DATA_IN             =>  network_send_ram_data_in,
    RAM_READ_ADDRESS        =>  network_send_ram_read_address
  );

  MESSAGE_SENDER : process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if reset = '1' then
        uart_tx_fifo_data_in              <= (others => '0');
        uart_tx_fifo_data_in_stb          <= '0';
        message_sender_state              <= send_configured_message;
        message_sender_source_IP          <= (others => '0');
        message_sender_dest_IP            <= (others => '0');
        message_sender_data_length        <= (others => '0');
        message_index                     <= 1;
      else
        ethernet_frame_end_old            <= ethernet_frame_end;
        if uart_tx_fifo_data_in_ack = '1' then
          uart_tx_fifo_data_in_stb        <= '0';
        end if;
        -- Latch message send triggers.
        if internet_new_data = '1' then
          internet_new_data_latch         <= '1';
        end if;
        if eth_rxdv = '0' and eth_rxdv_d0 = '1' then
          ethernet_frame_start_latch      <= '1';
        end if;
        if ethernet_frame_end = '1' and ethernet_frame_end_old = '0' then
          ethernet_frame_end_latch        <= '1';
        end if;
        if icmp_ping_request = '1' then
          icmp_ping_request_latch         <= '1';
        end if;
        -- Wait for a new internet frame, then send messages.
        case message_sender_state is
          when idle =>
            -- Wait for internet frame.
            if icmp_ping_request_latch = '1' then
              message_sender_state        <= send_ping_request_message;
              message_sender_source_IP    <= internet_source_IP;
              message_index               <= 1;
              icmp_ping_request_latch     <= '0';
            elsif internet_new_data_latch = '1' then
              message_sender_state        <= send_new_frame_message;
              -- Latch the internet signals.
              message_index               <= 1;
              internet_new_data_latch     <= '0';
            end if;
          when send_new_frame_message =>
            if message_index <= MSG_NEW_FRAME'length then
              if uart_tx_fifo_data_in_stb = '0' then
                uart_tx_fifo_data_in_stb  <= '1';
                uart_tx_fifo_data_in      <= std_logic_vector(to_unsigned(character'pos(MSG_NEW_FRAME(message_index)),8));
                message_index             <= message_index + 1;
              end if;
            else
              message_index               <= 1;
              message_sender_state        <= idle;
            end if;
          when send_configured_message =>
            if message_index <= MSG_CONFIGURED'length then
              if uart_tx_fifo_data_in_stb = '0' then
                uart_tx_fifo_data_in_stb  <= '1';
                uart_tx_fifo_data_in      <= std_logic_vector(to_unsigned(character'pos(MSG_CONFIGURED(message_index)),8));
                message_index             <= message_index + 1;
              end if;
            else
              message_sender_state        <= idle;
            end if;
          when send_ping_request_message =>
            if message_index <= MSG_ETH_PING_REQUEST'length then
              if uart_tx_fifo_data_in_stb = '0' then
                uart_tx_fifo_data_in_stb  <= '1';
                uart_tx_fifo_data_in      <= std_logic_vector(to_unsigned(character'pos(MSG_ETH_PING_REQUEST(message_index)),8));
                message_index             <= message_index + 1;
              end if;
            else
              message_sender_state        <= idle;
            end if;
          when send_LF =>
            if uart_tx_fifo_data_in_stb = '0' then
              -- Send new line character and go to next state.
              uart_tx_fifo_data_in_stb  <= '1';
              uart_tx_fifo_data_in      <= x"0A";
              message_index             <= 1;
              message_sender_state      <= send_CR;
            end if;
          when send_CR =>
            if uart_tx_fifo_data_in_stb = '0' then
              -- Send new line character and go to next state.
              uart_tx_fifo_data_in_stb  <= '1';
              uart_tx_fifo_data_in      <= x"0D";
              message_index             <= 1;
              message_sender_state      <= idle;
            end if;
          when others =>
            message_sender_state        <= idle;
        end case;
      end if;
    end if;
  end process MESSAGE_SENDER;
end RTL;
