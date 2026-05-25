LIBRARY ieee;
USE ieee.std_logic_1164.all;

LIBRARY unisim;
USE unisim.vcomponents.all;

ENTITY SQRTApprox_vio_top IS
    PORT (
        SYSCLK_P : IN STD_LOGIC;
        SYSCLK_N : IN STD_LOGIC
    );
END SQRTApprox_vio_top;

ARCHITECTURE STR OF SQRTApprox_vio_top IS

    --------------------------------------------------------------------
    -- Clock signals
    --------------------------------------------------------------------
    SIGNAL CLK_200M : STD_LOGIC;
    SIGNAL CLK_50M  : STD_LOGIC;
    SIGNAL locked_s : STD_LOGIC;

    --------------------------------------------------------------------
    -- VIO control signals
    --------------------------------------------------------------------
    SIGNAL Reset_vio : STD_LOGIC;
    SIGNAL Reset_s   : STD_LOGIC;
    SIGNAL Start_s   : STD_LOGIC;
    SIGNAL A_s       : STD_LOGIC_VECTOR(31 DOWNTO 0);

    --------------------------------------------------------------------
    -- SQRT output signals
    --------------------------------------------------------------------
    SIGNAL SQRT_s    : STD_LOGIC_VECTOR(31 DOWNTO 0);
    SIGNAL Done_s    : STD_LOGIC;
    SIGNAL Error_s   : STD_LOGIC;

    --------------------------------------------------------------------
    -- VIO IP declaration
    --------------------------------------------------------------------
    COMPONENT vio_0
        PORT (
            clk        : IN STD_LOGIC;

            probe_in0  : IN STD_LOGIC_VECTOR(31 DOWNTO 0);
            probe_in1  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);
            probe_in2  : IN STD_LOGIC_VECTOR(0 DOWNTO 0);

            probe_out0 : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            probe_out1 : OUT STD_LOGIC_VECTOR(0 DOWNTO 0);
            probe_out2 : OUT STD_LOGIC_VECTOR(31 DOWNTO 0)
        );
    END COMPONENT;

    --------------------------------------------------------------------
    -- Clocking Wizard IP declaration
    --------------------------------------------------------------------
    COMPONENT clk_wiz_0
        PORT (
            clk_out1 : OUT STD_LOGIC;
            reset    : IN  STD_LOGIC;
            locked   : OUT STD_LOGIC;
            clk_in1  : IN  STD_LOGIC
        );
    END COMPONENT;

BEGIN

    --------------------------------------------------------------------
    -- 1. Convert AC701 differential 200 MHz clock to single-ended clock
    --------------------------------------------------------------------
    clk_ibufds_inst : IBUFDS
        GENERIC MAP (
            IOSTANDARD => "LVDS_25"
        )
        PORT MAP (
            I  => SYSCLK_P,
            IB => SYSCLK_N,
            O  => CLK_200M
        );

    --------------------------------------------------------------------
    -- 2. Clocking Wizard: 200 MHz -> 50 MHz
    --------------------------------------------------------------------
    clk_wiz_inst : clk_wiz_0
        PORT MAP (
            clk_out1 => CLK_50M,
            reset    => '0',
            locked   => locked_s,
            clk_in1  => CLK_200M
        );

    --------------------------------------------------------------------
    -- 3. Reset logic
    -- Reset_s = reset t? VIO ho?c clock chýa locked
    --------------------------------------------------------------------
    Reset_s <= Reset_vio OR (NOT locked_s);

    --------------------------------------------------------------------
    -- 4. VIO runs at 50 MHz
    --------------------------------------------------------------------
    vio_inst : vio_0
        PORT MAP (
            clk => CLK_50M,

            probe_in0    => SQRT_s,
            probe_in1(0) => Done_s,
            probe_in2(0) => Error_s,

            probe_out0(0) => Reset_vio,
            probe_out1(0) => Start_s,
            probe_out2    => A_s
        );

    --------------------------------------------------------------------
    -- 5. SQRTApprox core also runs at 50 MHz
    --------------------------------------------------------------------
    sqrt_core : ENTITY work.SQRTApprox
        GENERIC MAP (
            DATA_WIDTH => 32,
            FRAC_WIDTH => 16,
            ITER_MAX   => 32
        )
        PORT MAP (
            Reset   => Reset_s,
            CLK     => CLK_50M,
            Start_i => Start_s,

            A_i => A_s,

            SQRT_o  => SQRT_s,
            Error_o => Error_s,
            Done_o  => Done_s
        );

END STR;