--------------------------------------------------------------------------------
-- ETHERNET CONSTANTS
-- Constants used by the ethernet MAC.
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

package ethernet_constants is
  constant CONST_DEVICE_MAC_ADDRESS : std_logic_vector(47 downto 0) := x"112233445566";
  constant CONST_DEVICE_IP_ADDRESS  : std_logic_vector(31 downto 0) := x"C0A80116"; --192.168.1.16
  constant MAX_PACKET_LENGTH        : integer := 1500;
  constant ICMP_PROTOCOL            : std_logic_vector(7 downto 0) := x"11";
end ethernet_constants;
