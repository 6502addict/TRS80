library IEEE;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all; 

entity kbd_matrix is
    Port ( 
        clk            : in  std_logic;  
        reset_n        : in  std_logic;
        scan_code      : in  std_logic_vector(9 downto 0);
        scan_strobe_n  : in  std_logic;
        cs_n           : in  std_logic;
        rd_n           : in  std_logic;
        address        : in  std_logic_vector(7 downto 0);
        data_out       : out std_logic;
        reset_out      : out std_logic := '0'
    );

end entity;

architecture Behavioral of kbd_matrix is


signal matrix            : std_logic_vector(63 downto 0) := (others => '1');     -- mo5 kbd matrice (active low)


begin


    kbd_data <= matrix(to_integer(unsigned(kbd_address));

    process(reset_n, clk)
        variable key_shift     : std_logic;
        variable is_shift_key  : boolean;
        variable matrix_idx    : integer;
		  variable remapped_code : std_logic_vector(8 downto 0);
	begin
		if reset_n = '0' or mode /= last_mode then
			last_mode        <= mode;
			prev_strobe      <= '1'; 
			kbd_state        <= KBD_IDLE;
			shift_on         <= '0';
			acc_on           <= '0';
			matrix           <= (others => '1');
			all_keys         <= (others => ('0', '0', '0'));
         delay_counter    <= 0;
         prev_shift_state <= '1';
		   ctrl_pressed     <= '0';
		   alt_pressed      <= '0';
		   del_pressed      <= '0';
			reset_out        <= '0';
		elsif falling_edge(clk) then
			prev_strobe <= escan_strobe_n;
			if prev_strobe = '1' and escan_strobe_n = '0' then
				if (escan_code(8 downto 0) = PS2_LEFT_CTRL) or (escan_code(8 downto 0) = PS2_RIGHT_CTRL) then
					ctrl_pressed <= not escan_code(9);
				elsif (escan_code(8 downto 0) = PS2_LEFT_ALT) or (escan_code(8 downto 0) = PS2_RIGHT_ALT) then
					alt_pressed <= not escan_code(9);
				elsif (escan_code(8 downto 0) = PS2_DELETE) then
					del_pressed <=  not escan_code(9);
				end if;			
			end if;
			if ctrl_pressed = '1' and alt_pressed = '1' and del_pressed = '1' then
				reset_out <= '1';
			else
				reset_out <= '0';
			end if;			
			
			if prev_strobe = '1' and escan_strobe_n = '0' then
				remapped_code := escan_code(8 downto 0);
				if escan_code(8 downto 0) = PS2_ESCAPE then
					acc_pending <= not escan_code(9);
					kbd_state <= KBD_END;
				end if;

				if alt_pressed = '1' and mode = "01" then
					case escan_code(8 downto 0) is
						when PS2_3  => remapped_code := PS2_ALT_3;
						when PS2_7  => remapped_code := PS2_ALT_7;
						when PS2_9  => remapped_code := PS2_ALT_9;
						when PS2_0  => remapped_code := PS2_ALT_0;
						when others =>	null;
					end case;
				end if;
--				if acc_pending ='1' then
--					case escan_code(8 downto 0) is
--						when PS2_6  => remapped_code := PS2_2;
--						when PS2_7  => remapped_code := PS2_2;
--						when PS2_8  => remapped_code := PS2_APOSTROPHE;
--						when PS2_9  => remapped_code := PS2_9;
--						when PS2_0  => remapped_code := PS2_0;
--						when others =>	null;
--					end case;
--				end if;
			end if;

			case kbd_state is 
				when KBD_IDLE => 
					 if prev_strobe = '1' and escan_strobe_n = '0' then
						  key_action <= escan_code(9); -- Save make/break flag
						  is_shift_key := (escan_code(8 downto 0) = PS2_LEFT_SHIFT) or 
												(escan_code(8 downto 0) = PS2_RIGHT_SHIFT);
						  if is_shift_key then
								case escan_code(9) is
									 when '0' => shift_on <= '1'; -- Key pressed
									 when '1' => shift_on <= '0'; -- Key released
									 when others => null;
								end case;
						  end if;
						  if escan_code(9) = '0' then  -- Make code
								all_keys(build_index('0', remapped_code(8 downto 0))).active <= '1';
								all_keys(build_index('0', remapped_code(8 downto 0))).shift <= shift_on;
								all_keys(build_index('0', remapped_code(8 downto 0))).accent <= acc_on;  -- Store accent state
								if acc_pending = '1' then
									kbd_index <= build_index('0', remapped_code(8 downto 0));
								else
									kbd_index <= build_index(shift_on, remapped_code(8 downto 0));
								end if;
						  else  -- Break code
								key_shift := all_keys(build_index('0', remapped_code(8 downto 0))).shift;
								all_keys(build_index('0', remapped_code(8 downto 0))).active <= '0';
								if acc_pending = '1' then
									kbd_index <= build_index('0', remapped_code(8 downto 0));	
								else 
									kbd_index <= build_index(key_shift, remapped_code(8 downto 0));	
								end if;
						  end if;
									 
						  kbd_state <= KBD_FETCH;
					 end if;
					
				when KBD_FETCH =>			
					current_key_addr <= kbd_output(5 downto 0);
					shift_mode       <= kbd_output(6);
					acc_mode         <= kbd_output(7);
					kbd_state        <= KBD_PROCESS;
				
				when KBD_PROCESS =>
					if kbd_output = NULL_KEY then
						 kbd_state <= KBD_END;
					else
						 if current_key_addr = MO5_SHIFT then
							  matrix(to_integer(unsigned(current_key_addr))) <= key_action;
							  kbd_state <= KBD_END;
						 elsif acc_mode = '1' and key_action = '0' then
							  kbd_state <= KBD_ACC_SET;
						 elsif acc_mode = '1' and key_action = '1' then
							  matrix(to_integer(unsigned(current_key_addr))) <= key_action;
							  acc_on <= '0';
							  kbd_state <= KBD_END;
						 elsif matrix(to_integer(unsigned(MO5_SHIFT))) = not shift_mode then
							  matrix(to_integer(unsigned(current_key_addr))) <= key_action;
							  kbd_state <= KBD_END;
						 else
							  kbd_state <= KBD_SHIFT_PREPARE;
						 end if;
					end if;

            when KBD_SHIFT_PREPARE =>
               prev_shift_state <= matrix(to_integer(unsigned(MO5_SHIFT)));
               matrix(to_integer(unsigned(MO5_SHIFT))) <= not shift_mode;
               delay_counter <= 20000;
               kbd_state <= KBD_SHIFT_DELAY;
                
            when KBD_SHIFT_DELAY =>
               if delay_counter > 0 then
						delay_counter <= delay_counter - 1;
               else
                  kbd_state <= KBD_KEY_SET;
               end if;
                
            when KBD_KEY_SET =>
               matrix(to_integer(unsigned(current_key_addr))) <= key_action;
					delay_counter <= 20000;
               kbd_state <= KBD_KEY_HOLD;
                
            when KBD_KEY_HOLD =>
               if delay_counter > 0 then
						delay_counter <= delay_counter - 1;
               else
                  matrix(to_integer(unsigned(MO5_SHIFT))) <= prev_shift_state;
                  kbd_state <= KBD_END;
               end if;

				when KBD_ACC_SET =>    
					matrix(to_integer(unsigned(MO5_ACC))) <= '0';  -- Active low, so set to 0
					delay_counter <= 20000;
					kbd_state <= KBD_ACC_SET_DELAY;
								
				when KBD_ACC_SET_DELAY =>
					if delay_counter > 0 then
						delay_counter <= delay_counter - 1;
					else
						delay_counter <= 20000;  -- Reset the counter for the next delay
						kbd_state <= KBD_ACC_RELEASE;
					end if;

				when KBD_ACC_RELEASE =>
					matrix(to_integer(unsigned(MO5_ACC))) <= '1';  -- Release the accent key
					if delay_counter > 0 then
						delay_counter <= delay_counter - 1;
					else
						delay_counter <= 20000;  -- Reset the counter for the next delay
						kbd_state <= KBD_ACC_KEY_SET;
                    end if;
                                
                when KBD_ACC_KEY_SET =>
                    matrix(to_integer(unsigned(current_key_addr))) <= key_action;
                    delay_counter <= 20000;
                    kbd_state <= KBD_ACC_KEY_HOLD;
                                
                when KBD_ACC_KEY_HOLD =>
                    if delay_counter > 0 then
                        delay_counter <= delay_counter - 1;
                    else
                        kbd_state <= KBD_END;
                    end if;
                    
                when KBD_END =>
                    -- wait for rising edge of escan_strobe
                    -- then move to KBD_IDLE;
                    if prev_strobe = '0' and escan_strobe_n = '1' then
                        kbd_state <= KBD_IDLE;
                    end if;
                    
            when others =>
                    kbd_state <= KBD_IDLE;
        end case;
    end if;
    end process;

end Behavioral;




 