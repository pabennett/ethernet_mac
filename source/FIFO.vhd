--------------------------------------------------------------------------------
-- FIFO
-- Generic FIFO implemented in block RAM.
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

entity FIFO is
  Generic 
  ( 
    width : POSITIVE;
    depth : POSITIVE
  );
  Port 
  ( 
    clock        :   in  STD_LOGIC;
    reset        :   in  STD_LOGIC;
    data_in      :   in  STD_LOGIC_VECTOR (width - 1 downto 0);
    data_out     :   out STD_LOGIC_VECTOR (width - 1 downto 0);
    data_in_stb  :   in  STD_LOGIC;
    data_out_stb :   out STD_LOGIC;
    data_in_ack  :   out STD_LOGIC;
    data_out_ack :   in  STD_LOGIC
  );
end FIFO;

architecture RTL of FIFO is

    function log2(A: integer) return integer is
    begin
      for I in 1 to 30 loop  -- Works for up to 32 bit integers
        if(2**I > A) then return(I-1);  end if;
      end loop;
      return(30);
    end;

    function get_fifo_level(write_pointer   : UNSIGNED;
                            read_pointer    : UNSIGNED;
                            depth           : POSITIVE
                            ) return INTEGER is
    begin
        if write_pointer > read_pointer then
            return to_integer(write_pointer - read_pointer);
        elsif write_pointer = read_pointer then
            return 0;
        else
            return ((depth) - to_integer(read_pointer)) + to_integer(write_pointer);
        end if;
    end function get_fifo_level;

    type    memory is array (0 to depth - 1) of STD_LOGIC_VECTOR(width - 1 downto 0);
    signal  fifo_memory     : memory := (others => (others => '0'));
    signal  read_pointer,
            write_pointer   : UNSIGNED (log2(depth) downto 0) := (others => '0');
    signal  s_data_out_stb  : STD_LOGIC := '0';
    signal  s_data_in_ack   : STD_LOGIC := '0';
begin    

    data_out_stb    <= s_data_out_stb;
    data_in_ack     <= s_data_in_ack;
    
    FIFO_LOGIC : process (clock, reset)
    begin
        if rising_edge(clock) then
            if reset = '1' then
                write_pointer       <= (others => '0');
                read_pointer        <= (others => '0');
                s_data_out_stb      <= '0';
                data_out            <= (others => '0');
                s_data_in_ack         <= '0';                
            else
                s_data_in_ack         <= '0';
                if data_in_stb = '1' and 
                   get_fifo_level (write_pointer, read_pointer, depth) /= depth - 1 and
                   s_data_in_ack = '0' then
                    fifo_memory(to_integer(write_pointer))   
                                    <= data_in;
                    if write_pointer = depth - 1 then
                        write_pointer <= (others => '0');
                    else
                        write_pointer <= write_pointer + 1;
                    end if;
                    s_data_in_ack     <= '1';
                end if;
                
                if s_data_out_stb = '0' and get_fifo_level (write_pointer, read_pointer, depth) > 0 then
                    data_out        <= fifo_memory(to_integer(read_pointer));
                    s_data_out_stb  <= '1';
                    if read_pointer = depth - 1 then
                        read_pointer <= (others => '0');
                    else
                        read_pointer <= read_pointer + 1;
                    end if;
                elsif s_data_out_stb = '1' and data_out_ack = '1' then
                    s_data_out_stb  <= '0';
                end if;
            end if;
        end if;
    end process FIFO_LOGIC;    
end RTL;
