--------------------------------------------------------------------------------
-- DATA LINK SEND
-- Sends data to the ethernet PHY device.
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

entity data_link_send is
  Port 
  (
    CLOCK               :   in  std_logic;
    RESET               :   in  std_logic;
    -- PHY Signals
    ETH_TX_CLK          :   in  std_logic;
    ETH_TX_EN           :   out std_logic;
    ETH_TXD             :   out std_logic_vector(3 downto 0);
    -- Frame Control Signals
    FRAME_DATA_IN       :   in  std_logic_vector(7 downto 0);
    FRAME_DATA_IN_STB   :   in  std_logic;
    FRAME_DATA_IN_ACK   :   out std_logic;
    FRAME_END           :   in  std_logic;
    FRAME_VALID         :   in  std_logic;
    FRAME_NEW           :   in  std_logic;
    -- Frame Parameters
    DESTINATION_MAC     :   in  std_logic_vector(47 downto 0);
    DATAGRAM_SIZE       :   in  std_logic_vector(15 downto 0);
    ETHERTYPE           :   in  std_logic_vector(15 downto 0)
  );
end data_link_send;

architecture RTL of data_link_send is
  component CRC is
  Port 
    (  
      CLOCK               :   in  std_logic;
      RESET               :   in  std_logic;
      DATA                :   in  std_logic_vector(7 downto 0);
      LOAD_INIT           :   in  std_logic;
      CALC                :   in  std_logic;
      D_VALID             :   in  std_logic;
      CRC                 :   out std_logic_vector(7 downto 0);
      CRC_REG             :   out std_logic_vector(31 downto 0);
      CRC_VALID           :   out std_logic
    );
  end component CRC;

  type header_array is array (0 to 21) of std_logic_vector(7 downto 0);
  
  -- Function to assemble a header array
  -- Much easier to sequentially send header bytes this way.
  function get_header(tx_destination_mac : std_logic_vector;
                      tx_ethertype       : std_logic_vector)
                      return std_logic_vector is
  -- +---------------------------------------------------------------------+     
  -- |                    802.3 Ethernet Frame Structure                   |
  -- |                               Octets                                |
  -- |   7      1        6       6      (4)     2     46-1500   4      12  |
  -- |  (7)    (8)      (14)    (20)    (24)   (26)                        |
  -- +---------------------------------------------------------------------+
  -- | PRE   | SOF   | MAC D | MAC S | 802.1q| LEN   | PAY   | FCS   | IFG |
  -- +---------------------------------------------------------------------+
  -- Data is sent most significant byte first.
  -- Bytes are sent low nibble first (reason why SFD is backwards).
    constant header : header_array :=
    (
    -- Preamble (7 bytes).
    x"55",x"55",x"55",x"55",x"55",x"55",x"55",
    -- Start Frame Delimeter (1 byte).
    x"5D",
    -- Send the destination MAC (6 bytes).
    tx_destination_mac(47 downto 40),
    tx_destination_mac(39 downto 32),
    tx_destination_mac(31 downto 24),
    tx_destination_mac(23 downto 16),
    tx_destination_mac(15 downto 8),
    tx_destination_mac(7 downto 0),
    -- Send the source MAC (6 bytes).
    CONST_DEVICE_MAC_ADDRESS(47 downto 40),
    CONST_DEVICE_MAC_ADDRESS(39 downto 32),
    CONST_DEVICE_MAC_ADDRESS(31 downto 24),
    CONST_DEVICE_MAC_ADDRESS(23 downto 16),
    CONST_DEVICE_MAC_ADDRESS(15 downto 8),
    CONST_DEVICE_MAC_ADDRESS(7 downto 0),
    -- Send the ethertype (2 bytes).
    -- 0x0800 	Internet Protocol, Version 4 (IPv4)
    -- 0x0806 	Address Resolution Protocol (ARP)
    tx_ethertype(15 downto 8),
    tx_ethertype(7 downto 0)
    );

  begin
    return header;
  end get_header;

  -- Main SM Signals
  signal tx_header                : header_array := (others => (others => '0'));

  -- Upper layer signals
  signal tx_frame_data_ack        : std_logic := '0';

  -- PHY Signals
  signal tx_clock_tick            : std_logic := '0';
  signal tx_clock                 : std_logic := '0';
  signal tx_clock_reg             : std_logic := '0';
  signal tx_enable                : std_logic := '0';
  signal tx_data                  : std_logic_vector(3 downto 0) := (others => '0');

  signal tx_destination_mac       : std_logic_vector(47 downto 0) := (others => '0');
  signal tx_datagram_size         : std_logic_vector(15 downto 0) := (others => '0');
  signal tx_ethertype             : std_logic_vector(7 downto 0) := (others => '0');

  -- CRC
  signal  s_fcs_crc_data_in       : std_logic_vector(7 downto 0)  := (others => '0');
  signal  s_fcs_crc_load_init     : std_logic := '0';
  signal  s_fcs_crc_calc_en       : std_logic := '0';
  signal  s_fcs_crc_d_valid       : std_logic := '0';
  signal  s_crc_valid             : std_logic := '0';
  signal  s_crc_reg               : std_logic_vector(31 downto 0) := (others => '0');

begin
        
  FCS_CRC : CRC 
  port map(
    CLOCK           => CLOCK,
    RESET           => RESET,
    DATA            => s_fcs_crc_data_in,
    LOAD_INIT       => s_fcs_crc_load_init,
    CALC            => s_fcs_crc_calc_en,
    D_VALID         => s_fcs_crc_d_valid,
    CRC             => open,
    CRC_REG         => s_crc_reg,
    CRC_VALID       => s_crc_valid
  );

  ETH_TXD           <= tx_data;
  ETH_TX_EN         <= tx_enable;
  FRAME_DATA_IN_ACK <= tx_frame_data_ack;

  -- Deglitch the PHY inputs with double registers.
  -- 25MHz -> 100Mhz Domain Crossing.
  -- Also generates a ETH_CLK tick.
  TX_CLOCK_TICKS : process (CLOCK)
  begin
    if rising_edge (CLOCK) then
      if RESET = '1' then
        tx_clock_tick       <= '0';
        tx_clock            <= '0';
        tx_clock_reg        <= '0';
      else
        tx_clock            <= ETH_TX_CLK;
        tx_clock_reg        <= tx_clock;
        -- Generate the TX clock tick.
        if tx_clock = '0' and tx_clock_reg = '1' then
          tx_clock_tick     <= '1';
        else
          tx_clock_tick     <= '0';
        end if;
      end if;
    end if;
  end process TX_CLOCK_TICKS;
  
  -- OSI LAYER 2 (DATALINK LAYER)        
  --                      802.3 Ethernet Frame Structure
  --     7      1        6       6      (4)     2     46-1500   4      12       Octets
  -- +-----------------------------------------------------------------------+
  -- | PRE   | SOF   | MAC D | MAC S | 802.1q| LEN   | PAY   | FCS   | IFG   |
  -- +-----------------------------------------------------------------------+
  -- |               |<------------64-1522 octets------------------->|       |
  -- |<--------------------72-1530 octets--------------------------->|       |
  -- |<--------------------------84-1542 octets----------------------------->|
  -- |               |<--------------CRC GEN ACTIVE--------->|

  ETH_SEND_SM : process (CLOCK)
  begin
    if rising_edge (CLOCK) then
      if RESET = '1' then
        tx_state                    <= wait_for_frame;
        tx_header                   <= (others => (others => '0'));
        tx_frame_size               <= (others => '0');
        s_fcs_crc_calc_en           <= '0';
        tx_enable                   <= '0';
      else

        -- Clear the CRC data valid signal
        s_fcs_crc_d_valid           <= '0';
        s_fcs_crc_calc_en           <= '0';

        tx_frame_data_ack           <= '1';

        case tx_state is
          when wait_for_frame =>
            -----------------------------------------------------------------
            -- Wait for a new frame to be available from the network send layer
            -- Send ethernet frame bytes when a new frame request is received
            -----------------------------------------------------------------
            if FRAME_NEW = '1' then
              tx_header             <= get_header(DESTINATION_MAC, ETHERTYPE);
              tx_frame_size         <= DATAGRAM_SIZE;
              tx_state              <= get_next_header_byte;
            end if;                 
          when send_low_nibble =>
            if tx_clock_tick = '1' then
              tx_data               <= tx_byte(3 downto 0);
              tx_state              <= send_high_nibble;
            end if;
          when send_high_nibble =>
            if tx_clock_tick = '1' then
              tx_data               <= tx_byte(7 downto 4);
              tx_byte_count         <= tx_byte_count + 1;
              if tx_byte_count < 21 then
                -------------------------------------------------------------
                -- If there are header bytes left to send, get the next one.
                -- Header bytes are stored in the tx_header register
                -------------------------------------------------------------
                tx_state            <= get_next_header_byte;
              elsif tx_byte_count < tx_frame_size then
                -------------------------------------------------------------
                -- We have send the header bytes and still have databytes
                -- to send. Wait for the byte strobe from the network send
                -- layer to receive payload bytes.
                -------------------------------------------------------------
                tx_state            <= get_next_data_byte;
              elsif tx_byte_count < tx_frame_size + 4 then
                -------------------------------------------------------------
                -- Send the 4 CRC bytes
                -- CRC bytes are obtained by strobing d_valid with calc low.
                -- calc is high for the first CRC byte.
                -------------------------------------------------------------
                tx_state            <= get_next_data_byte;
                s_fcs_crc_calc_en   <= '0';
              else
                -------------------------------------------------------------
                -- Transmission of the frame is complete.
                -------------------------------------------------------------
              end if;
            end if;
          when get_next_header_byte =>
            -- Get the header byte and prepare to send it to PHY.
            tx_byte                 <= tx_header(tx_byte_count);
            tx_state                <= send_low_nibble;
            -- Send the byte to the CRC
            s_fcs_crc_data_in       <= tx_byte;
            s_fcs_crc_d_valid       <= '1';
          when get_next_data_byte =>
            -- Get the next data byte from the layer above.
            -- NOTE: if the data is not presented in time this is a failure.
            if FRAME_DATA_IN_STB = '1' then
              tx_byte               <= FRAME_DATA_IN;
              tx_state              <= send_low_nibble;
              tx_frame_data_ack     <= '1';
              -- Send the byte to the CRC
              s_fcs_crc_data_in       <= tx_byte;
              s_fcs_crc_d_valid       <= '1';
              assert tx_clock_tick = '0'
                report "Catastrophic failure, frame data was not ready in time. Null byte transmitted."
                severity failure;
            end if;
          when get_crc_byte =>
            -- Get CRC byte to send.
            tx_byte                 <= s_fcs_crc;
            -- Prepare the next CRC byte.
            s_fcs_crc_d_valid       <= '1';
          when others =>
            tx_state                <= wait_for_frame;
        end case;
      end if;
    end if;
  end process ETH_SEND_SM;   
end RTL;
