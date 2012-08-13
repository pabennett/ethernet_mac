--------------------------------------------------------------------------------
-- NETWORK SEND
-- Implements OSI layer 3.
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

entity network_send is
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
end network_send;

architecture RTL of network_send is

  -- Functions
  function log2(A: integer) return integer is
  begin
    for I in 1 to 30 loop  -- Works for up to 32 bit integers
      if(2**I > A) then return(I-1);  end if;
    end loop;
    return(30);
  end;

  type header_array is array (0 to 19) of std_logic_vector(7 downto 0);

  function get_header   ( version       : std_logic_vector(3 downto 0);
                          header_length : integer;
                          service_type  : std_logic_vector(7 downto 0);
                          data_length   : std_logic_vector(15 downto 0);
                          identification: std_logic_vector(15 downto 0);
                          flags         : std_logic_vector(2 downto 0);
                          fragment_offset : std_logic_vector(13 downto 0);
                          time_to_live  : std_logic_vector(7 downto 0);
                          protocol      : std_logic_vector(7 downto 0); 
                          source_ip     : std_logic_vector(31 downto 0);
                          destination_ip: std_logic_vector(31 downto 0)
  ) return header_array is
    variable data_length_int : integer := to_integer(unsigned(data_length));
    variable total_length : std_logic_vector(15 downto 0)
                          := std_logic_vector(to_unsigned(header_length + data_length_int,16));
    variable header     : header_array := 
                        (
                          version & std_logic_vector(to_unsigned(header_length,4)),
                          service_type,
                          total_length(15 downto 8),
                          total_length(7 downto 0),
                          identification(15 downto 8),
                          identification(7 downto 0),
                          flags & fragment_offset(13 downto 9),
                          fragment_offset(7 downto 0),
                          time_to_live,
                          protocol,
                          "00000000",
                          "00000000",
                          source_ip(31 downto 24),
                          source_ip(23 downto 16),
                          source_ip(15 downto 8),
                          source_ip(7 downto 0),
                          destination_ip(31 downto 24),
                          destination_ip(23 downto 16),
                          destination_ip(15 downto 8),
                          destination_ip(7 downto 0)
                         );
  begin
    return header;
  end get_header;   

  -- Header length always 20 bytes (5 * 32 bit words).
  constant HEADER_LENGTH  : integer := 5 * (32 / 8);

  type frame_send_states is (wait_for_frame, send_data);

  -- Frame send signals
  signal send_state                 : frame_send_states := wait_for_frame;
  signal tx_byte_count              : unsigned(15 downto 0) := (others => '0');
  signal tx_busy                    : std_logic := '0';
  signal tx_header                  : header_array := (others => (others => '0'));
  signal tx_byte                    : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_data_length             : std_logic_vector(15 downto 0) := (others => '0');
  -- Lower layer signals
  signal tx_frame_data_out          : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_byte_strobe             : std_logic := '0';
  signal tx_byte_acknowledge        : std_logic := '0';
  signal tx_frame_end               : std_logic := '0';
  signal tx_frame_valid             : std_logic := '0';
  signal tx_frame_new               : std_logic := '0';        
  -- Checksum calculation
  signal checksum                   : unsigned(15 downto 0) := (others => '0');
  signal checksum16                 : unsigned(16 downto 0) := (others => '0');
  signal checksum_word_count        : unsigned(log2(HEADER_LENGTH) - 1 downto 0)  := (others => '0');
  signal tx_calculating_checksum    : std_logic := '0';
  signal tx_new_checksum            : std_logic := '0';
  -- RAM signals
  signal tx_ram_data_in             : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_ram_address        : integer   := 0;
                   
begin

  -- Datalink layer signals
  FRAME_DATA_OUT        <= tx_frame_data_out;
  FRAME_DATA_OUT_STB    <= tx_byte_strobe;
  tx_byte_acknowledge   <= FRAME_DATA_OUT_ACK;
  FRAME_END             <= tx_frame_end;
  FRAME_VALID           <= tx_frame_valid;
  FRAME_NEW             <= tx_frame_new;
  -- Upper layer signals.
  BUSY                  <= tx_busy;
  -- RAM interface
  tx_ram_data_in        <= RAM_DATA_IN;
  RAM_READ_ADDRESS      <= tx_ram_address;

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


  FRAME_SEND  : process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if RESET = '1' then
        tx_byte_count             <= (others => '0');
        tx_frame_data_out         <= (others => '0');
        tx_byte_strobe  <= '0';
        tx_frame_end              <= '0';
        tx_frame_valid            <= '0';
        tx_frame_new              <= '0';
        tx_busy                   <= '0';
        tx_header                 <= (others => (others => '0'));
        tx_ram_address            <= 0;
        tx_data_length            <= (others => '0');
      else
        tx_frame_new              <= '0';
        if tx_byte_acknowledge = '1' then
          tx_byte_strobe            <= '0';
        end if;
        tx_new_checksum           <= '0';
        case send_state is
          when wait_for_frame =>
            if NEW_DATA = '1' then
              -- A new packet is waiting to be sent.
              -- Get the packet parameters.
              send_state          <= send_data;
              tx_byte_count       <= (others => '0');
              tx_frame_new        <= '1';
              tx_busy             <= '1';
              tx_ram_address      <= 0;
              tx_data_length      <= DATA_LENGTH;
              -------------------------------------------------------------
              -- Construct the frame header into array format to make
              -- it easy to read later.
              -------------------------------------------------------------
              tx_header           <= get_header
                                    (x"4",
                                     HEADER_LENGTH,
                                     SERVICE_TYPE,
                                     DATA_LENGTH,
                                     IDENTIFICATION,
                                     FLAGS,
                                     "00000000000000",
                                     TIME_TO_LIVE,
                                     PROTOCOL,
                                     SOURCE_IP,
                                     DESTINATION_IP
                                    );
              -------------------------------------------------------------
              -- Tell the checksum generator to create a new checksum 
              -- The checksum is produced in 180ns, just in time to
              -- insert the result into the correct position in the frame.
              -------------------------------------------------------------
              tx_new_checksum     <= '1'; 
            end if;
          when send_data =>
            if tx_byte_strobe = '0' then
              if tx_byte_count < HEADER_LENGTH then
                if tx_byte_count = 9 then
                  -- Send the checksum MSB.
                  tx_byte           <= std_logic_vector(checksum(15 downto 8));
                elsif tx_byte_count = 10 then
                  -- Send the checksum LSB.
                  tx_byte           <= std_logic_vector(checksum(7 downto 0));
                else
                  -- Send header bytes.
                  tx_byte           <= tx_header(to_integer(tx_byte_count));
                end if;
                tx_byte_count       <= tx_byte_count + 1;
                tx_byte_strobe      <= '1';
              elsif tx_byte_count - HEADER_LENGTH < to_integer(unsigned(tx_data_length)) then
                -- Send data bytes
                tx_byte             <= tx_ram_data_in;
                tx_ram_address      <= tx_ram_address + 1; 
              else
                -- We're done sending the frame, tell the lower layer.
                tx_frame_end        <= '1';
                tx_frame_valid      <= '1';
                tx_busy             <= '0';
                send_state          <= wait_for_frame;
              end if;
            end if;
          when others =>
            send_state              <= wait_for_frame;
          end case;           
      end if;
    end if;
  end process FRAME_SEND;

  -----------------------------------------------------------------
  -- The header checksum process produces the 16 bit checksum
  -- for the header 10 clock cycles after the assertion of
  -- the tx_new_checksum signal. 
  -- It reads 16 bits of the header at a time (10 * 16bits/clock)
  -----------------------------------------------------------------
  -- Add in the carry for ones complement addition.
  checksum <= checksum16(15 downto 0) + ("000000000000000" & checksum16(16));
  -----------------------------------------------------------------
  HEADER_CHECKSUM : process (CLOCK)
  begin
    if rising_edge(CLOCK) then
      if RESET = '1' then
        tx_calculating_checksum   <= '0';
        checksum16                <= (others => '0');
        checksum_word_count       <= (others => '0');
      else
        if tx_new_checksum = '1' and tx_calculating_checksum = '0' then
          tx_calculating_checksum <= '1';
          checksum16              <= (others => '0');
          checksum_word_count     <= (others => '0');
        elsif tx_calculating_checksum = '1' and checksum_word_count < HEADER_LENGTH then
          checksum16              <= ('0' & checksum) + 
                                     ('0' & unsigned(tx_header(to_integer(checksum_word_count))));
          checksum_word_count     <= checksum_word_count + 1;
        else
          tx_calculating_checksum <= '0';
        end if;
      end if;
    end if;
  end process HEADER_CHECKSUM;
end RTL;


