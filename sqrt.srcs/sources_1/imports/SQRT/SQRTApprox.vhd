LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY SQRTApprox IS
    GENERIC (
        DATA_WIDTH : INTEGER := 32;
        FRAC_WIDTH : INTEGER := 16;
        ITER_MAX   : INTEGER := 32
    );
    PORT (
        Reset   : IN STD_LOGIC;
        CLK     : IN STD_LOGIC;
        Start_i : IN STD_LOGIC;

        A_i : IN STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

        SQRT_o  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        Error_o : OUT STD_LOGIC;
        Done_o  : OUT STD_LOGIC
    );
END SQRTApprox;

ARCHITECTURE STR OF SQRTApprox IS

    SIGNAL Load_A_s        : STD_LOGIC;
    SIGNAL Set_Error_s     : STD_LOGIC;
    SIGNAL Set_Zero_s      : STD_LOGIC;
    SIGNAL Norm_Low_s      : STD_LOGIC;
    SIGNAL Norm_High_s     : STD_LOGIC;
    SIGNAL Init_XY_s       : STD_LOGIC;
    SIGNAL Iter_Add_s      : STD_LOGIC;
    SIGNAL Iter_Sub_s      : STD_LOGIC;
    SIGNAL Gain_Correct_s  : STD_LOGIC;
    SIGNAL Scale_Correct_s : STD_LOGIC;

    SIGNAL A_Neg_s     : STD_LOGIC;
    SIGNAL A_Zero_s    : STD_LOGIC;
    SIGNAL A_Lt_Half_s : STD_LOGIC;
    SIGNAL A_Ge_Two_s  : STD_LOGIC;
    SIGNAL Y_Neg_s     : STD_LOGIC;
    SIGNAL Iter_Done_s : STD_LOGIC;

BEGIN

    Ctrl_Unit : ENTITY work.Controller
        PORT MAP (
            Reset   => Reset,
            CLK     => CLK,
            Start_i => Start_i,

            A_Neg     => A_Neg_s,
            A_Zero    => A_Zero_s,
            A_Lt_Half => A_Lt_Half_s,
            A_Ge_Two  => A_Ge_Two_s,
            Y_Neg     => Y_Neg_s,
            Iter_Done => Iter_Done_s,

            Load_A        => Load_A_s,
            Set_Error     => Set_Error_s,
            Set_Zero      => Set_Zero_s,
            Norm_Low      => Norm_Low_s,
            Norm_High     => Norm_High_s,
            Init_XY       => Init_XY_s,
            Iter_Add      => Iter_Add_s,
            Iter_Sub      => Iter_Sub_s,
            Gain_Correct  => Gain_Correct_s,
            Scale_Correct => Scale_Correct_s,

            Done_o => Done_o
        );

    Datapath_Unit : ENTITY work.Datapath
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_WIDTH => FRAC_WIDTH,
            ITER_MAX   => ITER_MAX
        )
        PORT MAP (
            Reset => Reset,
            CLK   => CLK,

            A_i => A_i,

            Load_A        => Load_A_s,
            Set_Error     => Set_Error_s,
            Set_Zero      => Set_Zero_s,
            Norm_Low      => Norm_Low_s,
            Norm_High     => Norm_High_s,
            Init_XY       => Init_XY_s,
            Iter_Add      => Iter_Add_s,
            Iter_Sub      => Iter_Sub_s,
            Gain_Correct  => Gain_Correct_s,
            Scale_Correct => Scale_Correct_s,

            A_Neg     => A_Neg_s,
            A_Zero    => A_Zero_s,
            A_Lt_Half => A_Lt_Half_s,
            A_Ge_Two  => A_Ge_Two_s,
            Y_Neg     => Y_Neg_s,
            Iter_Done => Iter_Done_s,

            Error_o => Error_o,
            SQRT_o  => SQRT_o
        );

END STR;
