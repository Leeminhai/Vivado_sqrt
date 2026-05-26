LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY SQRTApprox IS
    GENERIC (

        DATA_WIDTH : INTEGER := 32; -- do rong du lieu
        FRAC_WIDTH : INTEGER := 16; -- so bit phan thap phan trong dinh dang Q16.16
        ITER_MAX   : INTEGER := 32 -- so vong lap CORDIC
    );

    PORT (
        ----------------------------------------------------------------
        -- Tin hieu he thong
        ----------------------------------------------------------------
        Reset   : IN STD_LOGIC;  -- Reset muc cao
        CLK     : IN STD_LOGIC;  -- Clock he thong
        Start_i : IN STD_LOGIC;  -- Tin hieu bat dau tinh toan

        ----------------------------------------------------------------
        -- Du lieu dau vao
        -- A_i la so fixed-point Q16.16, rong DATA_WIDTH bit.
        A_i : IN STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
        ----------------------------------------------------------------
        -- Du lieu dau ra
        ----------------------------------------------------------------
        SQRT_o  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Ket qua sqrt(A_i), Q16.16
        Error_o : OUT STD_LOGIC;                                -- Bao loi neu A_i < 0
        Done_o  : OUT STD_LOGIC                                 -- Bao phep tinh da hoan thanh
        ----------------------------------------------------------------
    );
END SQRTApprox;

--------------------------------------------------------------------
-- Kien truc nay khong tinh toan truc tiep, ma chi ghep hai khoi:
--   1. Controller
--   2. Datapath
ARCHITECTURE STR OF SQRTApprox IS

    ----------------------------------------------------------------
    -- Nhom tin hieu dieu khien tu Controller sang Datapath
    -- Cac tin hieu nay duoc Controller tao ra de yeu cau Datapath
    -- thuc hien tung buoc cua thuat toan.
    SIGNAL Load_A_s        : STD_LOGIC; -- Yeu cau Datapath nap A_i vao A_reg
    SIGNAL Set_Error_s     : STD_LOGIC; -- Yeu cau Datapath bat co loi
    SIGNAL Set_Zero_s      : STD_LOGIC; -- Yeu cau Datapath gan ket qua bang 0
    SIGNAL Norm_Low_s      : STD_LOGIC; -- Yeu cau chuan hoa khi A < 0.5
    SIGNAL Norm_High_s     : STD_LOGIC; -- Yeu cau chuan hoa khi A >= 2
    SIGNAL Init_XY_s       : STD_LOGIC; -- Yeu cau khoi tao X, Y va i
    SIGNAL Iter_Add_s      : STD_LOGIC; -- Yeu cau cap nhat CORDIC theo nhanh cong
    SIGNAL Iter_Sub_s      : STD_LOGIC; -- Yeu cau cap nhat CORDIC theo nhanh tru
    SIGNAL Gain_Correct_s  : STD_LOGIC; -- Yeu cau hieu chinh gain CORDIC
    SIGNAL Scale_Correct_s : STD_LOGIC; -- Yeu cau bu lai scale sau chuan hoa

    ----------------------------------------------------------------
    -- Nhom tin hieu trang thai tu Datapath gui ve Controller
    -- Datapath tao cac co trang thai nay de Controller biet
    -- nen chuyen sang state nao tiep theo.
    SIGNAL A_Neg_s     : STD_LOGIC; -- = 1 neu A < 0
    SIGNAL A_Zero_s    : STD_LOGIC; -- = 1 neu A = 0
    SIGNAL A_Lt_Half_s : STD_LOGIC; -- = 1 neu A < 0.5
    SIGNAL A_Ge_Two_s  : STD_LOGIC; -- = 1 neu A >= 2.0
    SIGNAL Y_Neg_s     : STD_LOGIC; -- = 1 neu Y < 0
    SIGNAL Iter_Done_s : STD_LOGIC; -- = 1 neu da lap du ITER_MAX vong
    --------------------------------------------------------------------
BEGIN

    --------------------------------------------------------------------
    -- Controller la FSM dieu khien toan bo thuat toan.
    -- Controller nhan:
    --   - Reset, CLK, Start_i
    --   - Cac co trang thai tu Datapath
    -- Controller xuat:
    --   - Cac tin hieu dieu khien sang Datapath
    --   - Done_o bao phep tinh hoan thanh
    Ctrl_Unit : ENTITY work.Controller
        PORT MAP (
            ------------------------------------------------------------
            -- Tin hieu he thong
            ------------------------------------------------------------
            Reset   => Reset,
            CLK     => CLK,
            Start_i => Start_i,

            ------------------------------------------------------------
            -- Tin hieu trang thai nhan tu Datapath
            ------------------------------------------------------------
            A_Neg     => A_Neg_s,
            A_Zero    => A_Zero_s,
            A_Lt_Half => A_Lt_Half_s,
            A_Ge_Two  => A_Ge_Two_s,
            Y_Neg     => Y_Neg_s,
            Iter_Done => Iter_Done_s,

            ------------------------------------------------------------
            -- Tin hieu dieu khien gui sang Datapath
            ------------------------------------------------------------
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

            ------------------------------------------------------------
            -- Tin hieu bao hoan thanh dua ra ngoai top
            ------------------------------------------------------------
            Done_o => Done_o
        );

    --------------------------------------------------------------------
    -- Datapath thuc hien:
    --   - Nap A_i
    --   - Kiem tra A am, A bang 0, A < 0.5, A >= 2
    --   - Chuan hoa A
    --   - Khoi tao X, Y
    --   - Lap CORDIC
    --   - Hieu chinh gain
    --   - Bu scale
    --   - Tao SQRT_o va Error_o
    --------------------------------------------------------------------
    Datapath_Unit : ENTITY work.Datapath
        GENERIC MAP (
            ------------------------------------------------------------
            -- Truyen cac tham so tu SQRTApprox xuong Datapath
            ------------------------------------------------------------
            DATA_WIDTH => DATA_WIDTH,
            FRAC_WIDTH => FRAC_WIDTH,
            ITER_MAX   => ITER_MAX
        )
        PORT MAP (
            ------------------------------------------------------------
            -- Tin hieu he thong
            ------------------------------------------------------------
            Reset => Reset,
            CLK   => CLK,

            ------------------------------------------------------------
            -- Du lieu dau vao
            ------------------------------------------------------------
            A_i => A_i,

            ------------------------------------------------------------
            -- Tin hieu dieu khien nhan tu Controller
            ------------------------------------------------------------
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

            ------------------------------------------------------------
            -- Tin hieu trang thai gui ve Controller
            ------------------------------------------------------------
            A_Neg     => A_Neg_s,
            A_Zero    => A_Zero_s,
            A_Lt_Half => A_Lt_Half_s,
            A_Ge_Two  => A_Ge_Two_s,
            Y_Neg     => Y_Neg_s,
            Iter_Done => Iter_Done_s,

            ------------------------------------------------------------
            -- Ket qua dau ra cua loi SQRTApprox
            ------------------------------------------------------------
            Error_o => Error_o,
            SQRT_o  => SQRT_o
        );

END STR;
