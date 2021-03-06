library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.numeric_std.all;
library work;
use work.zxinterfacepkg.all;


entity spi_interface is
  port (
    SCK_i                 : in std_logic;
    CSN_i                 : in std_logic;
    arst_i                : in std_logic;

    MOSI_i                : in std_logic;
    MISO_o                : out std_logic;

    pc_i                  : in std_logic_vector(15 downto 0);
  
    fifo_empty_i          : in std_logic;
    fifo_rd_o             : out std_logic;
    fifo_data_i           : in std_logic_vector(31 downto 0);

    vidmem_en_o           : out std_logic;
    vidmem_adr_o          : out std_logic_vector(12 downto 0);
    vidmem_data_i         : in std_logic_vector(7 downto 0);

    capmem_en_o           : out std_logic;
    capmem_adr_o          : out std_logic_vector(CAPTURE_MEMWIDTH_BITS-1 downto 0);
    capmem_data_i         : in std_logic_vector(35 downto 0);

    -- Synchronous to SCK_i
    capture_run_o         : out std_logic;
    capture_clr_o         : out std_logic;
    capture_cmp_o         : out std_logic;
    capture_len_i         : in std_logic_vector(CAPTURE_MEMWIDTH_BITS-1 downto 0);
    capture_trig_i        : in std_logic;
    capture_trig_mask_o   : out std_logic_vector(31 downto 0);
    capture_trig_val_o    : out std_logic_vector(31 downto 0);

    rom_en_o              : out std_logic;
    rom_we_o              : out std_logic;
    rom_di_o              : out std_logic_vector(7 downto 0);
    rom_addr_o            : out std_logic_vector(13 downto 0);

    rstfifo_o             : out std_logic;
    rstspect_o            : out std_logic;
    intenable_o           : out std_logic;
    capsyncen_o           : out std_logic;
    frameend_o            : out std_logic;

    vidmode_o             : out std_logic_vector(1 downto 0);
    ulahack_o             : out std_logic;

    forceromcs_trig_on_o  : out std_logic;
    forceromcs_trig_off_o : out std_logic;
    forceromonretn_trig_o : out std_logic; -- single tick, SPI sck
    forcenmi_trig_on_o    : out std_logic; -- single tick, SPI sck
    forcenmi_trig_off_o   : out std_logic; -- single tick, SPI sck
    -- Resource FIFO

    resfifo_reset_o       : out std_logic;
    resfifo_wr_o          : out std_logic;
    resfifo_write_o       : out std_logic_vector(7 downto 0);
    resfifo_full_i        : in std_logic_vector(3 downto 0);

    -- TAP player FIFO
    tapfifo_reset_o       : out std_logic;
    tapfifo_wr_o          : out std_logic;
    tapfifo_write_o       : out std_logic_vector(8 downto 0);
    tapfifo_full_i        : in std_logic;
    tapfifo_used_i        : in std_logic_vector(9 downto 0);
    tap_enable_o          : out std_logic;

    -- Command FIFO

    cmdfifo_reset_o       : out std_logic;
    cmdfifo_rd_o          : out std_logic;
    cmdfifo_read_i        : in std_logic_vector(7 downto 0);
    cmdfifo_empty_i       : in std_logic;
    cmdfifo_intack_o      : out std_logic; -- Interrupt acknowledge

    -- External RAM access
    extram_addr_o         : out std_logic_vector(31 downto 0);
    extram_dat_i          : in std_logic_vector(31 downto 0);
    extram_dat_o          : out std_logic_vector(31 downto 0);
    extram_req_o          : out std_logic;
    extram_we_o           : out std_logic;
    extram_valid_i        : in std_logic;

    -- USB access

    usb_rd_o              : out std_logic;
    usb_wr_o              : out std_logic;
    usb_addr_o            : out std_logic_vector(10 downto 0);
    usb_dat_o             : out std_logic_vector(7 downto 0);
    usb_dat_i             : in std_logic_vector(7 downto 0);
    usb_int_i             : in std_logic; -- USB interrupt

    -- Keyboard manipulation
    kbd_en_o              : out std_logic;
    kbd_force_press_o     : out std_logic_vector(39 downto 0); -- 40 keys.
    -- Joystick data
    joy_en_o              : out std_logic;
    joy_data_o            : out std_logic_vector(4 downto 0);
    -- Mouse
    mouse_en_o            : out std_logic;
    mouse_x_o             : out std_logic_vector(7 downto 0);
    mouse_y_o             : out std_logic_vector(7 downto 0);
    mouse_buttons_o       : out std_logic_vector(1 downto 0);
    volume_o              : out std_logic_vector(63 downto 0)
  );

end entity spi_interface;

architecture beh of spi_interface is

  signal txdat_s      : std_logic_vector(7 downto 0);
  signal txload_s     : std_logic;
  signal txready_s    : std_logic;
  signal txden_s      : std_logic;
  
  signal dat_s        : std_logic_vector(7 downto 0);
  signal dat_valid_s  : std_logic;
  signal wordindex_r  : unsigned(1 downto 0);
  signal wordindex2_r : unsigned(2 downto 0);

  signal vid_addr_r   : unsigned(12 downto 0);
  signal flags_r      : std_logic_vector(15 downto 0);
  signal capmem_adr_r : unsigned(CAPTURE_MEMWIDTH_BITS-1 downto 0);

  constant NUMREGS32  : natural := 8;

  subtype reg32_type is std_logic_vector(31 downto 0);
  type regs32_type is array(0 to NUMREGS32-1) of reg32_type;

  signal regs32_r       : regs32_type;
  signal tempreg_r      : std_logic_vector(23 downto 0);
  signal current_reg_r  : natural range 0 to NUMREGS32-1;
  signal pc_latch_r     : std_logic_vector(7 downto 0);

  type state_type is (
    IDLE,
    UNKNOWN,
    READID,
    READSTATUS,
    READDATA,
    RDVIDMEM1,
    RDVIDMEM2,
    RDVIDMEM,
    READCAPTURE,
    READCAPSTATUS,
    SETFLAGS1,
    SETFLAGS2,
    SETFLAGS3,
    SETREG32_INDEX,
    SETREG32_1,
    SETREG32_2,
    SETREG32_3,
    SETREG32_4,
    WRITEROM1,
    WRITEROM2,
    WRITEROM,
    WRRESFIFO,
    WRTAPFIFO,
    RDTAPFIFOUSAGE,
    READFIFOCMDDATA,
    RDPC1,
    EXTRAMADDR1,
    EXTRAMADDR2,
    EXTRAMADDR3,
    EXTRAMDATA,
    USBADDR1,
    USBADDR2,
    USBREADDATA,
    USBWRITEDATA
  );

  signal state_r      : state_type;

  signal frame_end_r  : std_logic;
  signal rom_addr_r    : unsigned(13 downto 0);


  signal capture_len_sync_s   : std_logic_vector(CAPTURE_MEMWIDTH_BITS-1 downto 0);
  signal capture_trig_sync_s  : std_logic;

  signal wreg_en_r        : std_logic;
  signal tapfifo_used_lsb_r : std_logic_vector(7 downto 0);

  signal extram_addr_r  : std_logic_vector(23 downto 0);
  signal extram_req_r   : std_logic := '0'; -- FIxme: needs areset
  signal extram_we_r    : std_logic := '0';
  signal extram_wdata_r : std_logic_vector(7 downto 0);

  --signal usb_addr_r     : std_logic_vector(15 downto 0);
  signal usb_addr_wr_r  : std_logic_vector(15 downto 0);
  signal usb_rd_r       : std_logic := '0'; -- FIxme: needs areset
--  signal usb_wr_r       : std_logic := '0'; -- FIxme: needs areset
  signal usb_is_write_r : std_logic;
  signal tapcmd_r       : std_logic;

begin

  len_sync: entity work.syncv generic map (RESET => '0', WIDTH => CAPTURE_MEMWIDTH_BITS )
      port map ( clk_i => SCK_i, arst_i => arst_i, din_i => capture_len_i, dout_o => capture_len_sync_s );
  trig_sync: entity work.sync generic map (RESET => '0')
      port map ( clk_i => SCK_i, arst_i => arst_i, din_i => capture_trig_i, dout_o => capture_trig_sync_s );


  vidmem_adr_o <= std_logic_vector(vid_addr_r);
  capmem_adr_o <= std_logic_vector(capmem_adr_r);
  capture_trig_val_o  <= regs32_r(1);
  capture_trig_mask_o <= regs32_r(0);
  frameend_o <= frame_end_r;

  spi_inst: entity work.qspi_slave
  port map (
    SCK_i         => SCK_i,
    CSN_i         => CSN_i,
    --D_io          => D_io,
    MOSI_i        => MOSI_i,
    MISO_o        => MISO_o,
    txdat_i       => txdat_s,
    txload_i      => txload_s,
    txready_o     => txready_s,
    txden_i       => txden_s,
    qen_i         => '0',

    dat_o         => dat_s,
    dat_valid_o   => dat_valid_s
  );

  process(SCK_i, arst_i)
  begin
    if arst_i='1' then

      flags_r               <= (others => '0');
      resfifo_reset_o       <= '0';
      forceromonretn_trig_o <= '0';
      forceromcs_trig_on_o  <= '0';
      forceromcs_trig_off_o <= '0';
      forcenmi_trig_on_o    <= '0';
      forcenmi_trig_off_o   <= '0';
      cmdfifo_intack_o      <= '0';
      cmdfifo_reset_o       <= '0';
    elsif rising_edge(SCK_i) then

      resfifo_reset_o       <= '0';
      forceromonretn_trig_o <= '0';
      forceromcs_trig_on_o  <= '0';
      forceromcs_trig_off_o <= '0';
      forcenmi_trig_on_o    <= '0';
      forcenmi_trig_off_o   <= '0';
      cmdfifo_intack_o      <= '0';
      cmdfifo_reset_o       <= '0';

      if state_r=SETFLAGS1 then
        if dat_valid_s='1' then
          flags_r(7 downto 0) <= dat_s;
        end if;
      elsif state_r=SETFLAGS2 then
        if dat_valid_s='1' then
          resfifo_reset_o       <= dat_s(0);
          forceromonretn_trig_o <= dat_s(1);
          forceromcs_trig_on_o  <= dat_s(2);
          forceromcs_trig_off_o <= dat_s(3);
          -- Command FIFO interrupt acknowledge
          cmdfifo_intack_o      <= dat_s(4);
          cmdfifo_reset_o       <= dat_s(5);
          forcenmi_trig_on_o    <= dat_s(6);
          forcenmi_trig_off_o   <= dat_s(7); -- this might not be necessary.
        end if;
      elsif state_r=SETFLAGS3 then
        if dat_valid_s='1' then
          flags_r(15 downto 8) <= dat_s;
        end if;
      end if;

    end if;
  end process;

  rstfifo_o     <= flags_r(0);
  rstspect_o    <= flags_r(1);
  capture_clr_o <= flags_r(2);
  capture_run_o <= flags_r(3);
  capture_cmp_o <= flags_r(4); -- Compress
  intenable_o   <= flags_r(5); -- Interrupt enable
  capsyncen_o   <= flags_r(6); -- Capture sync

  ulahack_o     <= flags_r(8); --
  tapfifo_reset_o<=flags_r(9); --
  tap_enable_o  <= flags_r(10); --

  vidmode_o(0)     <= flags_r(11); --
  vidmode_o(1)     <= flags_r(12); --

  --forceromcs_o  <= flags_r(7);


  rom_en_o <= '1' when state_r=WRITEROM else '0';
  rom_we_o <= dat_valid_s;
  rom_di_o <= dat_s;
  rom_addr_o <= std_logic_vector(rom_addr_r);

  resfifo_wr_o      <= '1' when state_r=WRRESFIFO and dat_valid_s='1' else '0';
  resfifo_write_o   <= dat_s;

  tapfifo_wr_o      <= '1' when state_r=WRTAPFIFO and dat_valid_s='1' else '0';
  tapfifo_write_o(7 downto 0)   <= dat_s;
  tapfifo_write_o(8) <= tapcmd_r;

  usb_rd_o          <= usb_rd_r;--'1' when state_r=USBREADDATA and dat_valid_s='1' else '0';

  usb_wr_o          <= '1' when state_r=USBWRITEDATA and dat_valid_s='1' else '0';


  usb_dat_o         <= dat_s;

  process(SCK_i, CSN_i, arst_i)
    variable caplen_v:  std_logic_vector(31 downto 0);
  begin
    if CSN_i='1' then
      state_r       <= IDLE;
      txden_s       <= '0';
      txload_s      <= '0';
      fifo_rd_o     <= '0';
      cmdfifo_rd_o  <= '0';
      vidmem_en_o   <= '0';
      frame_end_r   <= '0';
      capmem_adr_r  <= (others=>'0');
      wreg_en_r     <= '0';
      usb_rd_r      <= '0';
      --usb_wr_r      <= '0';

    elsif rising_edge(SCK_i) then

      fifo_rd_o     <= '0';
      cmdfifo_rd_o  <= '0';
      capmem_en_o   <= '0';
      usb_rd_r      <= '0';
--      usb_wr_r      <= '0';

      case state_r is
        when IDLE =>
          capmem_adr_r <= (others => '0');

          if dat_valid_s='1' then
            case dat_s is
              when x"DE" => -- Read status
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00" & cmdfifo_empty_i & resfifo_full_i & fifo_empty_i;
                state_r <= READSTATUS;

              when x"DF" => -- Read video memory
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                state_r <= RDVIDMEM1;

              when x"40" => -- Read last PC
                pc_latch_r <= pc_i(7 downto 0);
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= pc_i(15 downto 8);
                state_r <= RDPC1;

              when x"50" => -- Read external RAM
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                extram_we_r <= '0';
                state_r <= EXTRAMADDR1;

              when x"51" => -- Write external RAM
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                extram_we_r <= '1';
                state_r <= EXTRAMADDR1;

              when x"60" => -- USB read
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                usb_is_write_r <= '0';
                state_r <= USBADDR1;

              when x"61" => -- USB write
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                usb_is_write_r <= '1';
                state_r <= USBADDR1;


              when x"E0" => -- Read capture memory
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                capmem_en_o <= '1'; -- Address should be zero.
                wordindex2_r <= "000";
                --capmem_adr_r <= capmem_adr_r + 1;
                state_r <= READCAPTURE;

              when x"E2" => -- Read capture status
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                wordindex_r <= "00";
                state_r <= READCAPSTATUS;

              when x"E1" => -- Write ROM contents
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                --capmem_en_o <= '1'; -- Address should be zero.
                --wordindex2_r <= "000";
                rom_addr_r <= (others => '0');
                state_r <= WRITEROM1;

              when x"E3" => -- Write Resource FIFO contents
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                state_r <= WRRESFIFO;

              when x"E4" => -- Write TAP FIFO contents
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                state_r <= WRTAPFIFO;
                tapcmd_r <= '0';

              when x"E6" => -- Write TAP command FIFO contents
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                state_r <= WRTAPFIFO;
                tapcmd_r <= '1';

              when x"E5" => -- Get TAP FIFO usage
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= tapfifo_full_i & "00000" & tapfifo_used_i(9 downto 8);
                txdat_s <= "000000" & tapfifo_used_i(9 downto 8);
                tapfifo_used_lsb_r <= tapfifo_used_i(7 downto 0);
                state_r <= RDTAPFIFOUSAGE;

              when x"EC" => -- Set flags
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                state_r <= SETFLAGS1;

              when x"ED" | x"EE" => -- Set/get regs 32
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                wreg_en_r <= dat_s(0);
                state_r <= SETREG32_INDEX;

              when x"EF" => -- Mark end of frame
                txden_s <= '1';
                txload_s <= '1';
                txdat_s <= "00000000";
                frame_end_r <= '1';

              when x"FC" => -- Read data
                txden_s <= '1';
                txload_s <= '1';
                wordindex_r <= "00";
                if fifo_empty_i='1' then
                  txdat_s <= x"FF";
                  state_r <= UNKNOWN;
                else
                  txdat_s <= x"FE";
                  state_r <= READDATA;
                end if;

              when x"FB" => -- Read FIFO command data
                txden_s     <= '1';
                txload_s    <= '1';
                wordindex_r <= "00";
                if cmdfifo_empty_i='1' then
                  txdat_s   <= x"FF";
                  state_r   <= UNKNOWN;
                else
                  txdat_s   <= x"FE";
                  state_r   <= READFIFOCMDDATA;
                end if;

              when x"9E" | x"9F" => -- Read ID
                txden_s <= '1';
                txload_s <= '1';
                wordindex_r <= "00";
                txdat_s <= x"A5";
                state_r <= READID;
                
              when others =>
                -- Unknown command
                state_r <= UNKNOWN;
            end case;
          end if;

        when RDPC1 =>
          txden_s <= '1';
          txload_s <= '1';
          txdat_s <= pc_latch_r;
          if dat_valid_s='1' then
            state_r <= UNKNOWN;
          end if;

        when RDTAPFIFOUSAGE =>
          txden_s <= '1';
          txload_s <= '1';
          txdat_s <= tapfifo_used_lsb_r;
          if dat_valid_s='1' then
            state_r <= UNKNOWN;
          end if;

        when SETREG32_INDEX =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            current_reg_r <= to_integer(unsigned(dat_s));
            state_r <= SETREG32_1;
          end if;

        when SETREG32_1 =>
          txload_s <= '1';
          txden_s <= '1';
          txdat_s <= regs32_r(current_reg_r)(31 downto 24);
          if dat_valid_s='1' then
            if wreg_en_r='1' then
              --regs32_r(current_reg_r)(31 downto 24) <= dat_s;
              tempreg_r(23 downto 16) <= dat_s;
            end if;
            state_r <= SETREG32_2;
          end if;

        when SETREG32_2 =>
          txload_s <= '1';
          txden_s <= '1';
          txdat_s <= regs32_r(current_reg_r)(23 downto 16);
          if dat_valid_s='1' then
            if wreg_en_r='1' then
              --regs32_r(current_reg_r)(23 downto 16) <= dat_s;
              tempreg_r(15 downto 8) <= dat_s;
            end if;
            state_r <= SETREG32_3;
          end if;

        when SETREG32_3 =>
          txload_s <= '1';
          txden_s <= '1';
          txdat_s <= regs32_r(current_reg_r)(15 downto 8);
          if dat_valid_s='1' then
            if wreg_en_r='1' then
              tempreg_r(7 downto 0) <= dat_s;
            end if;
            state_r <= SETREG32_4;
          end if;

        when SETREG32_4 =>
          txload_s <= '1';
          txden_s <= '1';
          txdat_s <= regs32_r(current_reg_r)(7 downto 0);
          if dat_valid_s='1' then
            if wreg_en_r='1' then
              regs32_r(current_reg_r) <= tempreg_r & dat_s;
            end if;
            state_r <= UNKNOWN;
          end if;

        when WRITEROM1 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            rom_addr_r(13 downto 8) <= unsigned(dat_s(5 downto 0));
            state_r <= WRITEROM2;
          end if;

        when WRITEROM2 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            rom_addr_r(7 downto 0) <= unsigned(dat_s);
            state_r <= WRITEROM;
          end if;

        when WRITEROM =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            rom_addr_r <= rom_addr_r + 1;
          end if;

        when WRRESFIFO =>
        when WRTAPFIFO =>
          
        when READSTATUS =>
          txload_s <= '1';
          txden_s <= '1';

        when RDVIDMEM1 =>
          if dat_valid_s='1' then
            vid_addr_r(12 downto 8) <= unsigned(dat_s(4 downto 0));
            state_r <= RDVIDMEM2;
          end if;

        when RDVIDMEM2 =>
          if dat_valid_s='1' then
            vid_addr_r(7 downto 0) <= unsigned(dat_s);
            state_r <= RDVIDMEM;
            vidmem_en_o <= '1';
          end if;

        when RDVIDMEM =>

          if dat_valid_s='1' then
            txden_s <= '1';
            txload_s <= '1';
            txdat_s <= vidmem_data_i;
            vid_addr_r <= vid_addr_r + 1;
            --if vid_addr_r=x"1B00" then
              -- Mark end of framebuffer.
            --  framecmplt_r <= '1';
            --end if;
          end if;

        when SETFLAGS1 =>

          if dat_valid_s='1' then
            state_r <= SETFLAGS2;
          end if;

        when SETFLAGS2 =>
          
          if dat_valid_s='1' then
            state_r <= SETFLAGS3;
          end if;

        when SETFLAGS3 =>
          
          if dat_valid_s='1' then
            state_r <= UNKNOWN;
          end if;


        when READDATA =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            wordindex_r <= wordindex_r + 1;
          end if;
          case wordindex_r is
            when "11" => txdat_s <= fifo_data_i(7 downto 0);
            when "10" => txdat_s <= fifo_data_i(15 downto 8);
            when "01" => txdat_s <= fifo_data_i(23 downto 16);
            when "00" => txdat_s <= fifo_empty_i & fifo_data_i(30 downto 24);
            when others =>
          end case;

          if wordindex_r="11" and txready_s='1' then
            fifo_rd_o <= '1';
          end if;

        when READFIFOCMDDATA =>
          txload_s  <= '1';
          txden_s   <= '1';
          txdat_s   <= cmdfifo_read_i;

          if dat_valid_s ='1' then -- TBD: shall we use dat_valid_s?
            cmdfifo_rd_o <= '1';
          end if;

        when READCAPSTATUS =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            wordindex_r <= wordindex_r + 1;
          end if;

          caplen_v(31) := capture_trig_sync_s;
          caplen_v(30 downto CAPTURE_MEMWIDTH_BITS) := (others => '0');
          caplen_v(CAPTURE_MEMWIDTH_BITS-1 downto 0)  := capture_len_sync_s;

          case wordindex_r is
            when "11" => txdat_s <= caplen_v(7 downto 0);
            when "10" => txdat_s <= caplen_v(15 downto 8);
            when "01" => txdat_s <= caplen_v(23 downto 16);
            when "00" => txdat_s <= caplen_v(31 downto 24);
            when others =>
          end case;

          if wordindex_r="11" and txready_s='1' then
            fifo_rd_o <= '1';
          end if;

        when READCAPTURE =>
          txload_s <= '1';
          txden_s <= '1';
          capmem_en_o <= '0';

          if dat_valid_s='1' then
            if wordindex2_r = "100" then
              wordindex2_r <= "000";
            else
              wordindex2_r <= wordindex2_r + 1;
            end if;
          end if;
          case wordindex2_r is
            when "100" => txdat_s <= capmem_data_i(7 downto 0);
            when "011" => txdat_s <= capmem_data_i(15 downto 8);
            when "010" => txdat_s <= capmem_data_i(23 downto 16);
            when "001" => txdat_s <= capmem_data_i(31 downto 24);
            when "000" => txdat_s <= "0000" & capmem_data_i(35 downto 32);

            when others =>
          end case;

          if wordindex2_r="100" and dat_valid_s='1' then
            capmem_en_o <= '1';
            capmem_adr_r <= capmem_adr_r + 1;
          end if;

        when READID =>
          txload_s <= '1';
          txden_s <= '1';
          if txready_s='1' then
            wordindex_r <= wordindex_r + 1;
          end if;
          case wordindex_r is
            when "00" => txdat_s <= FPGAID0;
            when "01" => txdat_s <= FPGAID1;
            when "10" => txdat_s <= FPGAID2;
            when "11" =>
              txdat_s <= (others => '0');

              if SCREENCAP_ENABLED  then txdat_s(0) <= '1'; end if;
              if ROM_ENABLED        then txdat_s(1) <= '1'; end if;
              if CAPTURE_ENABLED    then txdat_s(2) <= '1'; end if;

            when others =>
          end case;

        when EXTRAMADDR1 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            extram_addr_r(23 downto 16) <= dat_s;
            state_r <= EXTRAMADDR2;
          end if;

        when EXTRAMADDR2 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            extram_addr_r(15 downto 8) <= dat_s;
            state_r <= EXTRAMADDR3;
          end if;

        when EXTRAMADDR3 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            extram_addr_r(7 downto 0) <= dat_s;
            -- Request
            if extram_we_r='0' then
              extram_req_r <= not extram_req_r;
            end if;
            state_r <= EXTRAMDATA;
          end if;

        when EXTRAMDATA =>
          txload_s <= '1';
          txden_s <= '1';
          txdat_s <= extram_dat_i(7 downto 0);


          if dat_valid_s='1' then
            --extram_addr_r(7 downto 0) <= dat_i;
            extram_wdata_r <= dat_s;
            -- Request
            extram_req_r <= not extram_req_r;
            state_r <= EXTRAMDATA;
          end if;
          if extram_valid_i='1' then
            extram_addr_r <= std_logic_vector(unsigned(extram_addr_r) + 1);
          end if;

        when USBADDR1 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            --usb_addr_r(15 downto 8) <= dat_s;
            usb_addr_wr_r(15 downto 8) <= dat_s;--usb_addr_r(15 downto 8);
            state_r <= USBADDR2;
          end if;

        when USBADDR2 =>
          txload_s <= '1';
          txden_s <= '1';
          if dat_valid_s='1' then
            --usb_addr_r(7 downto 0) <= dat_s;
            --usb_addr_wr_r(8 downto 8) <= dat_s; --usb_addr_r(15 downto 8);
            usb_addr_wr_r(7 downto 0) <= dat_s;
            if usb_is_write_r='1' then
              state_r <= USBWRITEDATA;
            else
              state_r <= USBREADDATA;
              usb_rd_r <= '1';
            end if;
          end if;

        when USBREADDATA =>
          txload_s <= '1';
          txden_s   <= '1';
          txdat_s   <= usb_dat_i;
          if dat_valid_s='1' then
            usb_rd_r <= '1';
            state_r <= USBREADDATA;
            --usb_addr_r <= usb_addr_wr_r;
            usb_addr_wr_r <= std_logic_vector(unsigned(usb_addr_wr_r) +1);
          end if;

        when USBWRITEDATA =>
          txload_s <= '1';
          txden_s   <= '1';
          txdat_s   <= usb_dat_i;
          if dat_valid_s='1' then
            --usb_wr_r <= '1';
            --usb_addr_r <= usb_addr_wr_r;
            usb_addr_wr_r <= std_logic_vector(unsigned(usb_addr_wr_r) +1);
          end if;

        when UNKNOWN =>
          -- Leave TXDEN.

        when others =>
          txload_s <= '0';
          txden_s <= '0';
      end case;
    end if;
  end process;

  extram_addr_o(23 downto 0) <= extram_addr_r;
  extram_addr_o(31 downto 24) <= (others => '0');
  extram_req_o          <= extram_req_r;
  extram_dat_o(7 downto 0)           <= extram_wdata_r;
  extram_dat_o(31 downto 8)          <= (others => '0');
  extram_we_o           <= extram_we_r;

  usb_addr_o            <= usb_addr_wr_r(10 downto 0);


  kbd_en_o              <= regs32_r(2)(0);
  joy_en_o              <= regs32_r(2)(1);
  mouse_en_o            <= regs32_r(2)(2);

  kbd_force_press_o     <= regs32_r(4)(7 downto 0) & regs32_r(3);

  -- Joystick and mouse data

  mouse_x_o             <= regs32_r(5)(7 downto 0);
  mouse_y_o             <= regs32_r(5)(15 downto 8);
  mouse_buttons_o       <= regs32_r(5)(17 downto 16);
  joy_data_o            <= regs32_r(5)(22 downto 18);

  -- Volumes
  volume_o              <= regs32_r(7) & regs32_r(6);

end beh;
