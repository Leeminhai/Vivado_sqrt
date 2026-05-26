--------------------------------------------------------------------
--   - Nhan clock vi sai 200 MHz tu board AC701
--   - Dung IBUFDS de doi clock vi sai sang clock single-ended
--   - Dung clk_wiz_0 de tao clock 50 MHz
--   - Dung vio_0 de nhap Reset, Start_i, A_i qua JTAG
--   - Dua SQRT_o, Done_o, Error_o ve VIO de quan sat tren Hardware Manager
--------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.all;

--------------------------------------------------------------------
-- Thu vien UNISIM cua Xilinx
-- Can thiet khi dung primitive IBUFDS va cac IP/primitive cua Vivado
--------------------------------------------------------------------
LIBRARY unisim;
USE unisim.vcomponents.all;

--------------------------------------------------------------------
-- ENTITY SQRTApprox_vio_top
-- Top nay chi co 2 chan ngoai:
--   SYSCLK_P
--   SYSCLK_N
-- Day la cap clock vi sai 200 MHz tren board AC701.
-- Cac tin hieu A_i, Start_i, Reset, SQRT_o, Done_o, Error_o
-- khong dua ra chan FPGA truc tiep ma di qua VIO.
--------------------------------------------------------------------
ENTITY SQRTApprox_vio_top IS
    PORT (
        SYSCLK_P : IN STD_LOGIC; -- Clock vi sai chan P tu board AC701
        SYSCLK_N : IN STD_LOGIC  -- Clock vi sai chan N tu board AC701
    );
END SQRTApprox_vio_top;

--------------------------------------------------------------------
-- ARCHITECTURE STR
-- Kien truc ghep noi cac khoi:
--   1. IBUFDS
--   2. clk_wiz_0
--   3. vio_0
--   4. SQRTApprox core
--------------------------------------------------------------------
ARCHITECTURE STR OF SQRTApprox_vio_top IS

    --------------------------------------------------------------------
    -- Clock signals
    --------------------------------------------------------------------
    SIGNAL CLK_200M : STD_LOGIC; -- Clock 200 MHz sau khi qua IBUFDS
    SIGNAL CLK_50M  : STD_LOGIC; -- Clock 50 MHz sau khi qua Clocking Wizard
    SIGNAL locked_s : STD_LOGIC; -- = 1 khi Clocking Wizard da on dinh clock

    --------------------------------------------------------------------
    -- VIO control signals
    -- Day la cac tin hieu dieu khien do nguoi dung nhap tu VIO Dashboard.
    --------------------------------------------------------------------
    SIGNAL Reset_vio : STD_LOGIC;                     -- Reset nhap tu VIO
    SIGNAL Reset_s   : STD_LOGIC;                     -- Reset thuc su dua vao SQRTApprox
    SIGNAL Start_s   : STD_LOGIC;                     -- Start_i nhap tu VIO
    SIGNAL A_s       : STD_LOGIC_VECTOR(31 DOWNTO 0); -- A_i[31:0] nhap tu VIO

    --------------------------------------------------------------------
    -- SQRT output signals
    -- Day la cac tin hieu dau ra cua SQRTApprox core.
    -- Cac tin hieu nay duoc dua ve VIO de quan sat.
    --------------------------------------------------------------------
    SIGNAL SQRT_s    : STD_LOGIC_VECTOR(31 DOWNTO 0); -- Ket qua sqrt(A), Q16.16
    SIGNAL Done_s    : STD_LOGIC;                     -- Bao phep tinh hoan thanh
    SIGNAL Error_s   : STD_LOGIC;                     -- Bao loi neu A_i < 0

    --------------------------------------------------------------------
    -- VIO IP declaration
    -- vio_0 la IP duoc tao trong Vivado.
    -- No cho phep dieu khien va quan sat tin hieu noi bo FPGA qua JTAG.
    -- probe_in  : tin hieu tu FPGA dua ve PC de quan sat
    -- probe_out : tin hieu tu PC/VIO dua vao FPGA de dieu khien
    --------------------------------------------------------------------
    COMPONENT vio_0
        PORT (
            clk        : IN STD_LOGIC; -- Clock cap cho VIO

            ------------------------------------------------------------
            -- Tin hieu dua vao VIO de quan sat tren Hardware Manager
            probe_in0  : IN STD_LOGIC_VECTOR(31 DOWNTO 0); -- SQRT_s[31:0]
            probe_in1  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- Done_s
            probe_in2  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);  -- Error_s
            ------------------------------------------------------------
            -- Tin hieu dieu khien tu VIO dua vao FPGA
            probe_out0 : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);  -- Reset_vio
            probe_out1 : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);  -- Start_s
            probe_out2 : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)  -- A_s[31:0]
            ------------------------------------------------------------
        );
    END COMPONENT;

    --------------------------------------------------------------------
    -- Clocking Wizard IP declaration
    -- clk_wiz_0 la IP duoc tao trong Vivado.
    -- Nhiem vu: tao clock 50 MHz tu clock dau vao 200 MHz.
    --------------------------------------------------------------------
    COMPONENT clk_wiz_0
        PORT (
            clk_out1 : OUT STD_LOGIC; -- Clock dau ra 50 MHz
            reset    : IN  STD_LOGIC; -- Reset cho Clocking Wizard
            locked   : OUT STD_LOGIC; -- = 1 khi clock dau ra da on dinh
            clk_in1  : IN  STD_LOGIC  -- Clock dau vao 200 MHz
        );
    END COMPONENT;

BEGIN

    --------------------------------------------------------------------
    -- 1. Convert AC701 differential 200 MHz clock to single-ended clock
    -- Board AC701 cung cap clock he thong dang vi sai:
    --   SYSCLK_P va SYSCLK_N
    -- Primitive IBUFDS cua Xilinx dung de bien cap clock vi sai
    -- thanh tin hieu clock mot dau CLK_200M.
    --------------------------------------------------------------------
    clk_ibufds_inst : IBUFDS
        GENERIC MAP (
            IOSTANDARD => "LVDS_25" -- Chuan dien ap vi sai LVDS 2.5V
        )
        PORT MAP (
            I  => SYSCLK_P, -- Dau vao clock vi sai P
            IB => SYSCLK_N, -- Dau vao clock vi sai N
            O  => CLK_200M  -- Clock 200 MHz single-ended dau ra
        );

    --------------------------------------------------------------------
    -- 2. Clocking Wizard: 200 MHz -> 50 MHz
    -- Core SQRTApprox ban dau co the khong dat timing o 200 MHz.
    -- Vi vay dung clk_wiz_0 de ha clock xuong 50 MHz.
    -- CLK_50M duoc cap cho ca:
    --   - vio_0
    --   - SQRTApprox core
    clk_wiz_inst : clk_wiz_0
        PORT MAP (
            clk_out1 => CLK_50M,  -- Clock 50 MHz dau ra
            reset    => '0',      -- Khong reset Clocking Wizard
            locked   => locked_s, -- Bao clock 50 MHz da on dinh
            clk_in1  => CLK_200M  -- Clock 200 MHz dau vao
        );

    --------------------------------------------------------------------
    -- 3. Reset logic
    -- Reset_s la reset thuc su dua vao SQRTApprox core.
    -- Reset_s = 1 khi:
    --   - Nguoi dung bat Reset_vio tren VIO
    --   - Hoac Clocking Wizard chua locked
    -- Muc dich:
    --   Neu clock 50 MHz chua on dinh thi core van bi reset,
    --   tranh cho FSM/Datapath chay sai luc bat dau.
    --------------------------------------------------------------------
    Reset_s <= Reset_vio OR (NOT locked_s);

    --------------------------------------------------------------------
    -- 4. VIO instance
    -- VIO chay cung clock 50 MHz voi SQRTApprox core.
    -- Cac probe input:
    --   probe_in0 = SQRT_s
    --   probe_in1 = Done_s
    --   probe_in2 = Error_s
    -- Cac probe output:
    --   probe_out0 = Reset_vio
    --   probe_out1 = Start_s
    --   probe_out2 = A_s
    --------------------------------------------------------------------
    vio_inst : vio_0
        PORT MAP (
            ------------------------------------------------------------
            -- Clock cho VIO
            ------------------------------------------------------------
            clk => CLK_50M,
            ------------------------------------------------------------
            -- Dua ket qua tu SQRTApprox ve VIO de quan sat
            probe_in0    => SQRT_s,
            probe_in1(0) => Done_s,
            probe_in2(0) => Error_s,
            ------------------------------------------------------------
            -- Dua tin hieu dieu khien tu VIO vao SQRTApprox
            probe_out0(0) => Reset_vio,
            probe_out1(0) => Start_s,
            probe_out2    => A_s
        );

    --------------------------------------------------------------------
    -- 5. SQRTApprox core instance
    -- Day la loi tinh can bac hai that su.
    -- Core nhan:
    --   - Reset_s
    --   - CLK_50M
    --   - Start_s
    --   - A_s
    -- Core xuat:
    --   - SQRT_s
    --   - Error_s
    --   - Done_s
    -- Cac ket qua nay duoc dua ve VIO de quan sat tren Hardware Manager.
    --------------------------------------------------------------------
    sqrt_core : ENTITY work.SQRTApprox
        GENERIC MAP (
            DATA_WIDTH => 32, -- Du lieu 32 bit
            FRAC_WIDTH => 16, -- Q16.16 co 16 bit phan thap phan
            ITER_MAX   => 32  -- So vong lap CORDIC
        )
        PORT MAP (
            ------------------------------------------------------------
            -- Tin hieu dieu khien
            ------------------------------------------------------------
            Reset   => Reset_s,
            CLK     => CLK_50M,
            Start_i => Start_s,

            ------------------------------------------------------------
            -- Du lieu dau vao tu VIO
            ------------------------------------------------------------
            A_i => A_s,

            ------------------------------------------------------------
            -- Ket qua dua ve VIO
            ------------------------------------------------------------
            SQRT_o  => SQRT_s,
            Error_o => Error_s,
            Done_o  => Done_s
        );

END STR;
