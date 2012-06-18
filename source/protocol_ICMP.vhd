--------------------------------------------------------------------------------
-- PROTOCOL ICMP
-- Implements the internet control message protocol.
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

entity ICMP is
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
end ICMP;

architecture RTL of ICMP is

  type icmp_states is (wait_for_packet, read_type, read_header_byte);
  signal icmp_state             : icmp_states := wait_for_packet;
  signal icmp_echo_request      : std_logic := '0';
  signal icmp_rx_byte           : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_rx_byte_count     : integer range 0 to (MAX_PACKET_LENGTH - 1) := 0;
  signal icmp_data_length       : std_logic_vector(15 downto 0) := (others => '0');


  signal icmp_tx_new_data       : std_logic := '0';
  signal icmp_tx_data_length    : std_logic_vector(15 downto 0) := (others => '0');
  signal icmp_tx_source_ip      : std_logic_vector(31 downto 0) := (others => '0');
  signal icmp_tx_destination_ip : std_logic_vector(31 downto 0) := (others => '0');
  signal icmp_tx_protocol       : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_service_type   : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_identification : std_logic_vector(15 downto 0) := (others => '0');
  signal icmp_tx_time_to_live   : std_logic_vector(7 downto 0) := (others => '0');
  signal icmp_tx_flags          : std_logic_vector(2 downto 0) := (others => '0');
  --	 0          4          8         12          16         20         24         28          32
  --  0+----------+----------+----------+-----------+----------+----------+----------+-----------+
  --   |        Type         |         Code         |                  Checksum                  | 
  --   |                     |                      |                                            |
  -- 32+----------+----------+----------------------+-------+------------------------------------+
  --	 |                                                                                         |
  --	 =                                      Message Body                                       = 
  --   |           (For error messages, encapsulated portion of original IP datagram)            |         
  --   +---------------------+----------------------+-------+------------------------------------+

  -- This component only implements Echo Requests and Responses.


begin

  TX_NEW_DATA           <= icmp_tx_new_data;
  TX_DATA_LENGTH        <= icmp_tx_data_length;
  TX_SOURCE_IP          <= icmp_tx_source_ip;
  TX_DESTINATION_IP     <= icmp_tx_destination_ip; 
  TX_PROTOCOL           <= icmp_tx_protocol; 
  TX_SERVICE_TYPE       <= icmp_tx_service_type; 
  TX_IDENTIFICATION     <= icmp_tx_identification;
  TX_TIME_TO_LIVE       <= icmp_tx_time_to_live; 
  TX_FLAGS              <= icmp_tx_flags;  

  icmp_rx_byte      <= RAM_DATA_IN;
  RAM_READ_ADDRESS  <= icmp_rx_byte_count;
  ECHO_REQUEST      <= icmp_echo_request;

  ICMP_LISTEN : process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if RESET = '1' then
        icmp_echo_request               <= '0';
        icmp_rx_byte_count              <= 0;
        icmp_data_length                <= (others => '0');
        -- Network send layer signals
        icmp_tx_new_data                <= '0';
        icmp_tx_data_length             <= (others => '0');
        icmp_tx_source_ip               <= (others => '0');
        icmp_tx_destination_ip          <= (others => '0');
        icmp_tx_protocol                <= (others => '0');
        icmp_tx_service_type            <= (others => '0');
        icmp_tx_identification          <= (others => '0');
        icmp_tx_time_to_live            <= (others => '0');
        icmp_tx_flags                   <= (others => '0');
      else

        icmp_echo_request               <= '0';
        icmp_tx_new_data                <= '0';  

        case icmp_state is
          when wait_for_packet =>
            -- Wait for a new packet with the ICMP protocol.
            if NEW_DATA = '1' and PROTOCOL = ICMP_PROTOCOL then
              icmp_state                <= read_type;
              icmp_rx_byte_count        <= 0;
              icmp_tx_data_length       <= std_logic_vector(unsigned(DATA_LENGTH) - 1);
              icmp_tx_source_ip         <= CONST_DEVICE_IP_ADDRESS;
              icmp_tx_destination_ip    <= SOURCE_IP;
              icmp_tx_protocol          <= PROTOCOL;
              icmp_tx_service_type      <= (others => '0');
              icmp_tx_identification    <= (others => '0');
              icmp_tx_time_to_live      <= x"03";
              icmp_tx_flags             <= (others => '0');
              -- RAM addressable from 0, so minus 1 from length.
              icmp_data_length          <= std_logic_vector(unsigned(DATA_LENGTH) - 1);
            end if;
          when read_type =>
            if icmp_rx_byte /= x"04" then
              -- The ICMP type is not an echo request, abort.
              icmp_state                <= wait_for_packet;
              icmp_rx_byte_count        <= 0;
            else
              -- The ICMP type is an echo request.
              icmp_state                <= read_header_byte;
              icmp_rx_byte_count        <= icmp_rx_byte_count + 1;
              icmp_echo_request         <= '1';
              icmp_tx_new_data          <= '1';
            end if;
          when read_header_byte =>
            -- TODO: Implement ICMP response.
            -- TODO: for now, dont care about rest of data.
            --if icmp_rx_byte_count < unsigned(icmp_data_length) then
            --  icmp_state          <= read_header_byte;
            --  icmp_rx_byte_count  <= icmp_rx_byte_count + 1;
            --else
            --  icmp_state          <= wait_for_packet;
            --end if;
            icmp_state          <= wait_for_packet;
          when others =>
            icmp_state            <= wait_for_packet;
        end case;
      end if;
    end if;
  end process ICMP_LISTEN;
end RTL;
