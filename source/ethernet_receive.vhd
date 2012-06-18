--------------------------------------------------------------------------------
-- ETHERNET RECEIVE
-- Receives data from the ethernet PHY device.
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

entity ethernet_receive is
    Port 
    (
      CLOCK               :   in  std_logic;
      RESET               :   in  std_logic;
      -- PHY Signals
      ETH_RX_CLK          :   in  std_logic;
      ETH_RX_DV           :   in  std_logic;
      ETH_RXD             :   in  std_logic_vector(3 downto 0);
      -- Control Signals
      FRAME_DATA_OUT      :   out std_logic_vector(7 downto 0);
      FRAME_DATA_OUT_STB  :   out std_logic;
      FRAME_END           :   out std_logic;
      FRAME_VALID         :   out std_logic;
      FRAME_NEW           :   out std_logic
    );
end ethernet_receive;

architecture RTL of ethernet_receive is

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

  -- Global constants
  constant c_device_mac               : std_logic_vector(47 downto 0) := x"00aa0062c609";
  -- The lengths and positions within the frame of each element of interest
  -- Values are in octets (bytes).
  constant c_eth_mac_dest_len         : positive := 6;
  constant c_eth_mac_dest_loc         : positive := c_eth_mac_dest_len;
  constant c_eth_mac_src_len          : positive := 6;
  constant c_eth_mac_src_loc          : positive := c_eth_mac_dest_loc + c_eth_mac_src_len;
  constant c_eth_ethertype_len        : positive := 2;    
  constant c_eth_ethertype_loc        : positive := c_eth_mac_src_loc + c_eth_ethertype_len;
                 
  type    eth_receive_states is (wait_for_frame, get_low_nibble, get_high_nibble, check_preamble, process_byte, invalid_frame, do_crc_check);
  signal  eth_receive_state : eth_receive_states := wait_for_frame;                                                   

  signal  int_eth_rx_clk_reg,       
          int_eth_rx_clk,
          int_eth_rx_dv_reg,
          int_eth_rx_dv,
          eth_clk_tick            : std_logic := '0';
  signal  int_eth_rxd_reg,
          int_eth_rxd             : std_logic_vector(3 downto 0)  := (others => '0');
          
  -- Ethernet Receiver State Machine Signals
  signal  rx_preamble_seen        : std_logic := '0'; --Asserted when the SFD has been seen (0xA followed by 0xB) 
  signal  rx_byte_count           : unsigned (10 downto 0)        := (others => '0'); -- Goes up to 1542.
  signal  rx_mac_src,
          rx_mac_dest             : std_logic_vector(47 downto 0) := (others => '0');
  signal  rx_ethertype            : std_logic_vector(15 downto 0) := (others => '0'); 
  signal  rx_byte                 : std_logic_vector(7 downto 0)  := (others => '0');   

  -- Upper Layer Signals
  signal  rx_end_of_frame         : std_logic := '0';
  signal  rx_frame_valid          : std_logic := '0';
  signal  rx_start_of_frame       : std_logic := '0';
  signal  rx_frame_data_out       : std_logic_vector(7 downto 0) := (others => '0');
  signal  rx_frame_data_stb       : std_logic := '0';

  -- CRC
  signal  s_fcs_crc_data_in       : std_logic_vector(7 downto 0)  := (others => '0');
  signal  s_fcs_crc_load_init     : std_logic := '0';
  signal  s_fcs_crc_calc_en       : std_logic := '0';
  signal  s_fcs_crc_d_valid       : std_logic := '0';
  signal  s_crc_valid             : std_logic := '0';
  signal  s_crc_reg               : std_logic_vector(31 downto 0) := (others => '0');       
begin
    
  FRAME_DATA_OUT          <= rx_frame_data_out;
  FRAME_DATA_OUT_STB      <= rx_frame_data_stb;
  FRAME_END               <= rx_end_of_frame;
  FRAME_VALID             <= rx_frame_valid;
  FRAME_NEW               <= rx_start_of_frame;
    
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
    
  -- Deglitch the PHY inputs with double registers.
  -- 25MHz -> 100Mhz Domain Crossing.
  -- Also generates a ETH_CLK tick.
  DEGLITCHING : process (CLOCK)
  begin
    if rising_edge (CLOCK) then
      if RESET = '1' then
        int_eth_rx_clk_reg  <= '0';
        int_eth_rx_clk      <= '0';
        int_eth_rx_dv_reg   <= '0';
        int_eth_rx_dv       <= '0';
        int_eth_rxd_reg     <= (others => '0');
        int_eth_rxd         <= (others => '0');
        eth_clk_tick        <= '0';
      else
        int_eth_rx_clk_reg  <= ETH_RX_CLK;
        int_eth_rx_clk      <= int_eth_rx_clk_reg;
        int_eth_rx_dv_reg   <= ETH_RX_DV;
        int_eth_rx_dv       <= int_eth_rx_dv_reg;
        int_eth_rxd_reg     <= ETH_RXD;
        int_eth_rxd         <= int_eth_rxd_reg;
        -- Generate the ETH_RX_CLK tick
        if int_eth_rx_clk = '0' and int_eth_rx_clk_reg = '1' then
          eth_clk_tick    <= '1';
        else
          eth_clk_tick    <= '0';
        end if;
      end if;
    end if;
  end process DEGLITCHING;

    -- OSI LAYER 2 (DATALINK LAYER)        
    --                      802.3 Ethernet Frame Structure
    --     7      1        6       6      (4)     2     46-1500   4      12       Octets
    -- +-----------------------------------------------------------------------+
    -- | PRE   | SOF   | MAC D | MAC S | 802.1q| LEN   | PAY   | FCS   | IFG   |
    -- +-----------------------------------------------------------------------+
    -- |               |<------------64-1522 octets------------------->|       |
    -- |<--------------------72-1530 octets--------------------------->|       |
    -- |<--------------------------84-1542 octets----------------------------->|
    
    ETH_RECEIVE_SM  : process (CLOCK)
    begin
        if rising_edge (CLOCK) then
            if RESET = '1' then
                rx_byte                             <= (others => '0');
                eth_receive_state                   <= wait_for_frame;
                rx_preamble_seen                    <= '0';
                rx_byte_count                       <= (others => '0');
                rx_end_of_frame                     <= '0';
                rx_start_of_frame                   <= '0';
                rx_frame_valid                      <= '0';
                rx_mac_src                          <= (others => '0');
                rx_mac_dest                         <= (others => '0');
                rx_ethertype                        <= (others => '0');
                s_fcs_crc_data_in                   <= (others => '0');
                s_fcs_crc_load_init                 <= '0';
                s_fcs_crc_d_valid                   <= '0';
                s_fcs_crc_calc_en                   <= '0';
                rx_frame_data_stb                   <= '0';
                rx_frame_data_out                   <= (others => '0');
            else
                            
                s_fcs_crc_load_init                 <= '0';
                s_fcs_crc_d_valid                   <= '0';
                rx_start_of_frame                   <= '0';
                rx_frame_data_stb                   <= '0';
            
                case eth_receive_state is
                    when wait_for_frame =>
                        -- Wait until RXDV is asserted (beginning of frame)
                        if int_eth_rx_dv = '1' then
                            rx_byte                 <= (others => '0');
                            rx_byte_count           <= (others => '0');
                            rx_preamble_seen        <= '0';
                            eth_receive_state       <= get_low_nibble;
                            rx_end_of_frame         <= '0';
                            rx_start_of_frame       <= '1';
                            rx_frame_valid          <= '0';
                            -- Initialise CRC generator
                            s_fcs_crc_load_init     <= '1';
                            s_fcs_crc_calc_en       <= '0';
                        end if;
                    when get_low_nibble =>
                        if eth_clk_tick = '1' and int_eth_rx_dv = '1' then
                            rx_byte(3 downto 0)     <= int_eth_rxd;
                            eth_receive_state       <= get_high_nibble;
                        elsif eth_clk_tick = '1' then
                            -- If RX DV is low then this is the end of the frame.
                            -- Check the CRC here.
                            eth_receive_state       <= wait_for_frame;
                            if s_crc_valid = '1' then
                                rx_end_of_frame     <= '1';
                                rx_frame_valid      <= '1';
                            else
                                rx_end_of_frame     <= '1';
                                rx_frame_valid      <= '0';
                            end if;                            
                        end if;
                    when get_high_nibble =>
                        if eth_clk_tick = '1' and rx_preamble_seen = '1' then
                            rx_byte(7 downto 4)     <= int_eth_rxd;
                            eth_receive_state       <= process_byte;
                            s_fcs_crc_calc_en       <= '1';
                        elsif eth_clk_tick = '1' and rx_preamble_seen = '0' then
                            rx_byte(7 downto 4)     <= int_eth_rxd;
                            eth_receive_state       <= check_preamble;
                        end if;
                    when check_preamble =>
                        -- This is the SFD
                        -- Bytes sent low nibble first, so the D is received last.
                        if rx_byte = x"D5" then
                            rx_preamble_seen        <= '1';
                        end if;
                        eth_receive_state           <= get_low_nibble;
                    when process_byte =>
                        -- Process Byte deals with the entire ethernet frame.
                        -- A byte counter determines where in the frame we currently are.
                        rx_byte_count               <= rx_byte_count + 1;
                        eth_receive_state           <= get_low_nibble;
                        s_fcs_crc_d_valid           <= '1';
                        s_fcs_crc_data_in           <= rx_byte;
                        if rx_byte_count < c_eth_mac_dest_loc then
                            -- receiving MAC dest
                            rx_mac_dest             <= rx_mac_dest(rx_mac_dest'high - 8 downto 0) & rx_byte; 
                        elsif rx_byte_count < c_eth_mac_src_loc then
                            -- receiving MAC src
                            rx_mac_src              <= rx_mac_src(rx_mac_src'high - 8 downto 0) & rx_byte; 
                        elsif rx_byte_count < c_eth_ethertype_loc then
                            -- Receiving Ethertype or Length
                            -- Could also be receiving an IEEE 802.1Q Tag
                            -- but ignore this for now.
                            -- 0x0800 indicates an IPv4 frame.                            
                            -- 0x0806 indicates an ARP frame.
                            -- 0x8100 indicates an IEEE 802.1Q. 
                            -- 0x86DD indicates an IPv6 frame.
                            rx_ethertype            <= rx_ethertype(rx_ethertype'high - 8 downto 0) & rx_byte; 
                            
                        else 
                            -- receiving payload and crc
                            -- Start sending data to upper layer
                            rx_frame_data_stb       <= '1';
                            rx_frame_data_out       <= rx_byte;

                        end if;
                    when invalid_frame =>
                        -- Ignore this transmission until RXDV goes low.
                        if int_eth_rx_dv = '0' then
                            -- Signal to the upper layer that the frame has ended.
                            rx_end_of_frame         <= '1';
                            eth_receive_state       <= wait_for_frame;
                        end if;
                    when others =>
                        eth_receive_state           <= wait_for_frame;
                end case;                  
            end if;
        end if;
    end process ETH_RECEIVE_SM;
end RTL;
