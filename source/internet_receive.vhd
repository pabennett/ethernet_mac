--------------------------------------------------------------------------------
-- INTERNET RECEIVE
-- OSI Layer 3
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

entity internet_receive is
  Port
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
end internet_receive;

architecture RTL of internet_receive is

  function shift_in(slv : std_logic_vector; input : std_logic_vector) return std_logic_vector is
  -- Big Endian byte receiver helper function.
  -- Shift the slv left by the input bits.
  -- E.g: slv = x123456, input = x78
  -- returns: x345678
  begin
    return slv(slv'high - input'length downto 0) & input; 
  end shift_in;
  
  -- OSI LAYER 3 (IP NETWORK LAYER)
  -- IPv4 Datagram Header Format
  --  
  --	 0          4          8                      16      19  20         24                    31
  --  0+----------+----------+----------------------+---------------------------------------------+
  --   | Version  |  Header  |    Service Type      |        Total Length including header        |
  --	 |   (4)    |  Length  |     (ignored)        |                                             |
  -- 32+----------+----------+----------------------+-------+-------------------------------------+
  --	 |           Identification                   | Flags |       Fragment Offset               |
  --	 |                                            |       |                                     |
  -- 64+---------------------+----------------------+-------+-------------------------------------+
  --	 |    Time To Live     |       Protocol       |             Header Checksum                 |
  --	 |                     |                      |                                             |
  -- 96+---------------------+----------------------+---------------------------------------------+
  --   |                                   Source IP Address                                      |
  --	 |                                                                                          |
  --128+------------------------------------------------------------------------------------------+
  --	 |                                 Destination IP Address                                   |
  --	 |                                                                                          |
  --160+---------------------------------------------------------+--------------------------------+
  --	 |                         Options (if Header Len > 5)     |       Padding (If needed)      |
  --	 |                                                         |                                |
  --192+---------------------------------------------------------+--------------------------------+
  --	 |                                          Data                                            |
  --	 |                                                                                          |
  --	 +------------------------------------------------------------------------------------------+
  --	 |                                          Data (Contd.)                                   |
  --	 |                                                                                          |
  --	 +------------------------------------------------------------------------------------------+
  --                                           (Bits)
  signal IPV4_SERVICE_TYPE        : std_logic := '0';
  signal IPV4_TOTAL_LENGTH        : std_logic := '0';
  signal IPV4_IDENTIFICATION      : std_logic := '0';
  signal IPV4_FLAGS               : std_logic := '0';
  signal IPV4_FRAGMENT_OFFSET     : std_logic := '0';
  signal IPV4_TIME_TO_LIVE        : std_logic := '0';
  signal IPV4_PROTOCOL            : std_logic := '0';
  signal IPV4_CHECKSUM            : std_logic := '0';
  signal IPV4_SOURCE_IP           : std_logic := '0';
  signal IPV4_DESTINATION_IP      : std_logic := '0';
  -- Datagram Element Registers
  signal rx_datagram_length       : std_logic_vector(15 downto 0) := (others => '0');
  signal rx_identification        : std_logic_vector(15 downto 0) := (others => '0');
  signal rx_flags                 : std_logic_vector(2 downto 0) := (others => '0');
  signal rx_fragment_offset       : std_logic_vector(12 downto 0) := (others => '0');
  signal rx_time_to_live          : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_protocol              : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_checksum              : std_logic_vector(15 downto 0) := (others => '0');
  signal rx_source_IP             : std_logic_vector(31 downto 0) := (others => '0');
  signal rx_destination_IP        : std_logic_vector(31 downto 0) := (others => '0');
  -- Datagram Flags
  signal new_datagram             : std_logic := '0';
  signal valid_datagram           : std_logic := '0';
  -- Incoming Datalink Layer Signals
  signal rx_byte                  : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_byte_count            : unsigned(15 downto 0) := (others => '0'); 
  signal rx_header_length         : unsigned(5 downto 0) := (others => '0');  
  signal rx_byte_strobe           : std_logic := '0';      
  signal rx_frame_end             : std_logic := '0';
  signal rx_start_of_frame        : std_logic := '0';
  signal rx_frame_valid           : std_logic := '0';
  -- Outgoing upper layer signals
  signal rx_data_out              : std_logic_vector(7 downto 0) := (others => '0');
  signal rx_data_out_strobe       : std_logic := '0';
  signal rx_ram_write_address     : unsigned(15 downto 0) := (others => '0');
  signal rx_data_length           : unsigned(15 downto 0) := (others => '0');
  -- Checksum Signals
  signal rx_new_checksum_byte     : std_logic := '0';
  signal checksum                 : unsigned(15 downto 0) := (others => '0');
  signal checksum16               : unsigned(16 downto 0) := (others => '0');
  signal checksum_lsb             : unsigned(7 downto 0) := (others => '0');
  signal set_checksum_msb         : std_logic := '0';
  signal rx_new_checksum          : std_logic := '0';

  type frame_receive_state is     (wait_for_frame, 
                                   get_header_length,
                                   receive_frame_byte, 
                                   store_data_byte, 
                                   store_header_byte
                                   );
  signal receive_state            : frame_receive_state := wait_for_frame;
begin
  ---Port signal mapping--------------------------------------
  ---Control Signals------------------------------------------
  rx_byte             <= FRAME_DATA_OUT;
  rx_byte_strobe      <= FRAME_DATA_OUT_STB;  
  rx_frame_end        <= FRAME_END;       
  rx_frame_valid      <= FRAME_VALID;   

  rx_start_of_frame   <= FRAME_NEW;   
  ---Upper layer signals--------------------------------------
  NEW_DATA            <= new_datagram;
  DATA_VALID          <= valid_datagram;
  DATA_LENGTH         <= std_logic_vector(rx_data_length);
  SOURCE_IP_OUT       <= rx_source_IP;
  DESTINATION_IP_OUT  <= rx_destination_IP;
  PROTOCOL_OUT        <= rx_protocol;
  RAM_DATA_OUT        <= rx_data_out;
  RAM_WRITE_ENABLE    <= rx_data_out_strobe;
  RAM_WRITE_ADDRESS   <= to_integer(rx_ram_write_address);
  CHECKSUM_OUT        <= rx_checksum;
  ------------------------------------------------------------ 
   
  -- FRAME RECEIVE SM   
  FRAME_RECEIVE : process (CLOCK)
  begin
    -- NOTE: Descriptions of header elements in this section are copied
    -- from: http://www.tcpipguide.com/free/t_IPDatagramGeneralFormat.htm
    if rising_edge(CLOCK) then
      if RESET =  '1' then
        receive_state                   <= wait_for_frame;
        rx_identification               <= (others => '0');
        rx_flags                        <= (others => '0');
        rx_fragment_offset              <= (others => '0');
        rx_time_to_live                 <= (others => '0');
        rx_protocol                     <= (others => '0');
        rx_datagram_length              <= (others => '0');
        rx_checksum                     <= (others => '0');
        rx_source_IP                    <= (others => '0');
        rx_destination_IP               <= (others => '0');
        rx_byte_count                   <= (others => '0'); 
        new_datagram                    <= '0';
        valid_datagram                  <= '0';
        rx_data_out                     <= (others => '0');
        rx_data_out_strobe              <= '0';
        rx_ram_write_address            <= (others => '0');
        rx_data_length                  <= (others => '0');
        rx_new_checksum_byte            <= '0';
        rx_new_checksum                 <= '0';
      else
        new_datagram                    <= '0';
        valid_datagram                  <= '0';
        rx_data_out_strobe              <= '0';
        rx_new_checksum_byte            <= '0';
        rx_new_checksum                 <= '0';
        -- Case for each element of the IPv4 datagram.
        case receive_state is
          when wait_for_frame =>
            -- Is this the start of a new frame?
            if rx_start_of_frame = '1' then
              rx_identification         <= (others => '0');
              rx_flags                  <= (others => '0');
              rx_fragment_offset        <= (others => '0');
              rx_time_to_live           <= (others => '0');
              rx_protocol               <= (others => '0');
              rx_datagram_length        <= (others => '0');
              rx_checksum               <= (others => '0');
              rx_source_IP              <= (others => '0');
              rx_destination_IP         <= (others => '0');
              rx_data_out               <= (others => '0');
              rx_ram_write_address      <= (others => '0');
              new_datagram              <= '0';
              valid_datagram            <= '0';
              receive_state             <= get_header_length;
              rx_data_length            <= (others => '0');
              rx_new_checksum           <= '1';
            end if;
          when get_header_length =>
            ------------------------------------------------------------
            -- The first byte of the header is available and has 
            -- the following elements:
            -- Version (3:0) and Header Length (8:4)
            ------------------------------------------------------------
            --VERSION:--------------------------------------------------
            -- Identifies the version of IP used to generate the
            -- datagram. For IPv4, this is of course the number 4. The
            -- purpose of this field is to ensure compatibility between
            -- devices that may be running different versions of IP.                
            ------------------------------------------------------------ 
            --HEADER LENGTH:--------------------------------------------
            -- Specifies the length of the IP header, in 32-bit words. 
            -- This includes the length of any options fields and
            -- padding. The normal value of this field when no options
            -- are used is 5 (5 32-bit words = 5*4 = 20 bytes). Contrast
            -- to the longer Total Length field below.                  
            ------------------------------------------------------------
            if rx_byte_strobe = '1' then
              if rx_byte(7 downto 4) /= X"4" then
                -- This isnt an IPv4 Datagram, ignore it.
                receive_state           <= wait_for_Frame;
              else
                -- The header length is given in 32bit words and
                -- needs converting to bytes (multiply by 4).
                rx_new_checksum_byte    <= '1';
                rx_header_length        <= unsigned(rx_byte(3 downto 0) & "00");
                receive_state           <= receive_frame_byte;
                rx_byte_count           <= to_unsigned(1,rx_byte_count'length);  
              end if;
            end if;
          when receive_frame_byte =>
            ------------------------------------------------------------
            -- Receiving frame bytes.
            ------------------------------------------------------------
            -- Are we receiving header bytes?
            if rx_byte_count < rx_header_length then
              -- Still receiving header bytes.
              if rx_byte_strobe = '1' then
                receive_state           <= store_header_byte;
                rx_byte_count           <= rx_byte_count + 1;
              end if;
            else
              -- All bytes of the header have been received
              -- Start receiving data.
              -- TODO:
              -- Need to implement IP checks and Fragmentation Checks
              -- Currently receives and processes ALL frames.
              rx_data_length            <= unsigned(rx_datagram_length) - rx_header_length;
              if rx_byte_count < unsigned(rx_datagram_length) then
                -- Still receiving data bytes.
                if rx_byte_strobe = '1' then
                  receive_state         <= store_data_byte;
                  rx_byte_count         <= rx_byte_count + 1;
                  rx_ram_write_address  <= rx_byte_count - unsigned(rx_header_length);
                end if;
              elsif rx_byte_count > to_unsigned(MAX_PACKET_LENGTH, rx_byte_count'length) then
                -- The frame length is over 9000, cannot deal with it.
                receive_state           <= wait_for_frame;
                new_datagram            <= '1';
              elsif rx_frame_valid = '1' and rx_frame_end = '1' and checksum = x"FFFF" then
                -- End of valid frame.
                receive_state           <= wait_for_frame;
                valid_datagram          <= '1';
                new_datagram            <= '1';
                
              elsif rx_frame_end = '1' then
                -- End of invalid frame.
                receive_state           <= wait_for_frame;
                new_datagram            <= '1';
              else
                -- Wait for flags.
              end if;
            end if;                
          when store_data_byte =>
            ------------------------------------------------------------
            -- The data to be transmitted in the datagram, either an
            -- entire higher-layer message or a fragment of one.
            ------------------------------------------------------------
            -- TODO: For now just pass the data up.
            receive_state               <= receive_frame_byte;
            rx_data_out_strobe          <= '1';
            rx_data_out                 <= rx_byte;
          when store_header_byte =>
            receive_state               <= receive_frame_byte;
            rx_new_checksum_byte        <= '1';
            ------------------------------------------------------------
            -- Store the header byte in the appropriate register.
            -- Pass the header byte to the CRC process.
            ------------------------------------------------------------
            if IPV4_SERVICE_TYPE = '1' then
              ------------------------------------------------------------
              -- A field designed to carry information to provide quality
              -- of service features, such as prioritized delivery, for
              -- IP datagrams.
              --------------------## This is ignored ! ##-----------------
              ----------------------## 1 Byte Long ##---------------------
            elsif IPV4_TOTAL_LENGTH = '1' then
              ------------------------------------------------------------
              -- Specifies the total length of the IP datagram, in bytes.
              -- Since this field is 16 bits wide, the maximum length of
              -- an IP datagram is 65,535 bytes, though most are much 
              -- smaller. 
              --------------------## 2 bytes long ##----------------------

              rx_datagram_length        <= shift_in(rx_datagram_length, rx_byte);

            elsif IPV4_IDENTIFICATION = '1' then
              ------------------------------------------------------------
              -- This field contains a 16-bit value that is common to each
              -- of the fragments belonging to a particular message; for
              -- datagrams originally sent unfragmented it is still filled
              -- in, so it can be used if the datagram must be fragmented
              -- by a router during delivery. 
              --------------------## This is ignored ! ##-----------------
              --------------------## 2 bytes long ##----------------------

              rx_identification         <= shift_in(rx_identification, rx_byte);

            elsif IPV4_FLAGS = '1' then
              ------------------------------------------------------------
              -- BIT 0 : Reserved, ignored.
              -- BIT 1 : DF
              -- Dont Fragment: When set to 1, specifies that the
              -- datagram should not be fragmented. SInce the
              -- fragmentation process is generally 'invisible' to
              -- higher layers, most protocols don't care about this
              -- and don't set this flag. It is, however, used for testing
              -- the maximum transmission unit (MTU) of a link.
              -- BIT 2 : MF
              -- More Fragments: When set to 0, indicates the last
              -- fragment in a mesage; when set to 1, indicates that
              -- more fragments are yet to come in the fragmented
              -- message. If no fragmentation is used for a message
              -- then of course there is only one 'fragment' and this
              -- flag is 0. If fragmentation is used, all fragments
              -- but the last set this flag to 1, so the recipient 
              -- knows when all fragments have been sent.
              --
              -- NOTE: Includes most significant 5 bits of fragment offset
              --------------------## This is ignored ! ##-----------------
              ----------------------## 3 bits Long ##---------------------

              rx_flags                  <= rx_byte(7 downto 5);

            elsif IPV4_FRAGMENT_OFFSET = '1' then
              ------------------------------------------------------------
              -- When fragmentation of a message occurs, this field 
              -- specifies the offset, or position, in the overall message
              -- where the data in this fragment goes. It is specified in
              -- units of 8 bytes (64 bits). The first fragment has an
              -- offset of 0.
              --------------------## This is ignored ! ##-----------------
              ----------------------## 1 Byte Long ##---------------------
            elsif IPV4_TIME_TO_LIVE = '1' then
              ------------------------------------------------------------
              -- Specifies how long the datagram is allowed to 'live' on
              -- the network, in terms of router hops. Each router
              -- decrements the value of the TTL field (reduces it by one)
              -- prior to transmitting it. If the TTL field drops to zero,
              -- the datagram is assumed to have taken too long a route and
              -- is discarded.
              --------------------## This is ignored ! ##-----------------
              ----------------------## 1 Byte Long ##---------------------

              rx_time_to_live           <= rx_byte;

            elsif IPV4_PROTOCOL = '1' then
              ------------------------------------------------------------
              -- Identifies the higher-layer protocol (generally either
              -- a transport layer protocol or encapsulated network 
              -- layer protocol) carried in the datagram.
              --------------------## This is ignored ! ##-----------------
              ----------------------## 1 Byte Long ##---------------------

              rx_protocol               <= rx_byte;

            elsif IPV4_CHECKSUM = '1' then
              ------------------------------------------------------------
              -- A checksum computed over the header to provide basic
              -- protection against corruption in transmission. This is
              -- not the more complex CRC code typically used by data link
              -- layer technologies such as Ethernet; it's just a 16-bit
              -- checksum. It is calculated by dividing the header bytes
              -- into words (a word is two bytes) and then adding them
              -- together. The data is not checksummed, only the header.
              -- At each hop the device receiving the datagram does the
              -- same checksum calculation and on a mismatch, discards
              -- the datagram as damaged.
              ----------------------## 2 Bytes Long ##--------------------

              rx_checksum               <= shift_in(rx_checksum, rx_byte);

            elsif IPV4_SOURCE_IP = '1' then
              ------------------------------------------------------------
              -- The 32-bit IP address of the originator of the datagram.
              -- Note that even though intermediate devices such as
              -- routers may handle the datagram, they do not normally put
              -- their address into this field-it is always the device
              -- that originally sent the datagram.
              ----------------------## 4 Bytes Long ##--------------------

              rx_source_IP              <= shift_in(rx_source_IP, rx_byte);

            elsif IPV4_DESTINATION_IP = '1' then
              ------------------------------------------------------------
              -- The 32-bit IP address of the intended recipient of the
              -- datagram. Again, even though devices such as routers may
              -- be the intermediate targets of the datagram, this field
              -- is always for the ultimate destination.
              ----------------------## 4 Bytes Long ##--------------------

              rx_destination_IP         <= shift_in(rx_destination_IP, rx_byte);

            else
              ------------------------------------------------------------
              -- Options and Padding are ignored in this implementation.
              ------------------------------------------------------------
            end if;
          when others =>
        end case;
      end if;
    end if;
  end process FRAME_RECEIVE;

  -- Add in the carry for ones complement addition.
  checksum <= checksum16(15 downto 0) + ("000000000000000" & checksum16(16));

  HEADER_CHECKSUM : process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if RESET = '1' then
        checksum16                <= (others => '0');
        set_checksum_msb          <= '0';
        checksum_lsb              <= (others => '0');
      else
        if rx_new_checksum = '1' then
          checksum16              <= (others => '0');
          set_checksum_msb        <= '0';
          checksum_lsb            <= (others => '0');
        else
          if rx_new_checksum_byte = '1' and set_checksum_msb = '0' then
            checksum_lsb          <= unsigned(rx_byte);
            set_checksum_msb      <= '1';
          elsif rx_new_checksum_byte = '1' and set_checksum_msb = '1' then
            checksum16            <= ('0' & checksum) + ('0' & unsigned(rx_byte) & checksum_lsb);
            set_checksum_msb      <= '0';    
          end if;
        end if;
      end if;
    end if;
  end process HEADER_CHECKSUM;

  HEADER_IDENTIFIER : process (rx_byte_count)
  begin
    IPV4_SERVICE_TYPE           <= '0';
    IPV4_TOTAL_LENGTH           <= '0';
    IPV4_IDENTIFICATION         <= '0';
    IPV4_FLAGS                  <= '0';
    IPV4_FRAGMENT_OFFSET        <= '0';
    IPV4_TIME_TO_LIVE           <= '0';
    IPV4_PROTOCOL               <= '0';
    IPV4_CHECKSUM               <= '0';
    IPV4_SOURCE_IP              <= '0';
    IPV4_DESTINATION_IP         <= '0';
    if rx_byte_count <= 2 then
      IPV4_SERVICE_TYPE         <= '1';
    elsif rx_byte_count <= 4 then
      IPV4_TOTAL_LENGTH         <= '1';
    elsif rx_byte_count <= 6 then
      IPV4_IDENTIFICATION       <= '1';
    elsif rx_byte_count = 7 then
      IPV4_FLAGS                <= '1';
    elsif rx_byte_count = 8 then
      IPV4_FRAGMENT_OFFSET      <= '1';
    elsif rx_byte_count = 9 then
      IPV4_TIME_TO_LIVE         <= '1';
    elsif rx_byte_count = 10 then
      IPV4_PROTOCOL             <= '1';
    elsif rx_byte_count <= 12 then
      IPV4_CHECKSUM             <= '1';
    elsif rx_byte_count <= 16 then
      IPV4_SOURCE_IP            <= '1';
    elsif rx_byte_count <= 20 then
      IPV4_DESTINATION_IP       <= '1';
    end if;
  end process HEADER_IDENTIFIER;
end RTL;
