LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY Datapath IS
    GENERIC (
        DATA_WIDTH : INTEGER := 32;
        FRAC_WIDTH : INTEGER := 16;
        ITER_MAX   : INTEGER := 32
    );
    PORT (
        Reset, CLK : IN STD_LOGIC;

        A_i : IN STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

        Load_A        : IN STD_LOGIC;
        Set_Error     : IN STD_LOGIC;
        Set_Zero      : IN STD_LOGIC;
        Norm_Low      : IN STD_LOGIC;
        Norm_High     : IN STD_LOGIC;
        Init_XY       : IN STD_LOGIC;
        Iter_Add      : IN STD_LOGIC;
        Iter_Sub      : IN STD_LOGIC;
        Gain_Correct  : IN STD_LOGIC;
        Scale_Correct : IN STD_LOGIC;

        A_Neg     : OUT STD_LOGIC;
        A_Zero    : OUT STD_LOGIC;
        A_Lt_Half : OUT STD_LOGIC;
        A_Ge_Two  : OUT STD_LOGIC;
        Y_Neg     : OUT STD_LOGIC;
        Iter_Done : OUT STD_LOGIC;

        Error_o : OUT STD_LOGIC;
        SQRT_o  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0)
    );
END Datapath;

ARCHITECTURE STR OF Datapath IS

    --------------------------------------------------------------------
    -- Fixed-point Q16.16 constants
    -- 0.25 = 16384
    -- 0.5  = 32768
    -- 1.0  = 65536
    -- 2.0  = 131072
    --------------------------------------------------------------------
    CONSTANT Q_ZERO    : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(0, DATA_WIDTH);
    CONSTANT Q_HALF    : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(32768, DATA_WIDTH);
    CONSTANT Q_TWO     : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(131072, DATA_WIDTH);
    CONSTANT Q_QUARTER : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(16384, DATA_WIDTH);

    --------------------------------------------------------------------
    -- K = 0.828159
    -- sqrt(a) = x / K = x * (1 / K)
    -- 1 / K ? 1.207497
    -- Q16.16 value: 1.207497 * 65536 ? 79134
    --------------------------------------------------------------------
    CONSTANT INV_K_Q16 : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(79134, DATA_WIDTH);

    CONSTANT SCALE_WIDTH : INTEGER := 6;
    CONSTANT ITER_WIDTH  : INTEGER := 6;

    SIGNAL A_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL X_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Xcorr_reg  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Result_reg : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL Scale_reg  : STD_LOGIC_VECTOR(SCALE_WIDTH - 1 DOWNTO 0);
    SIGNAL Iter_reg   : STD_LOGIC_VECTOR(ITER_WIDTH - 1 DOWNTO 0);
    SIGNAL Error_reg  : STD_LOGIC_VECTOR(0 DOWNTO 0);

    SIGNAL A_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL X_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Xcorr_src  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Result_src : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL Scale_src  : STD_LOGIC_VECTOR(SCALE_WIDTH - 1 DOWNTO 0);
    SIGNAL Iter_src   : STD_LOGIC_VECTOR(ITER_WIDTH - 1 DOWNTO 0);
    SIGNAL Error_src  : STD_LOGIC_VECTOR(0 DOWNTO 0);

    SIGNAL A_ld       : STD_LOGIC;
    SIGNAL X_ld       : STD_LOGIC;
    SIGNAL Y_ld       : STD_LOGIC;
    SIGNAL Xcorr_ld   : STD_LOGIC;
    SIGNAL Result_ld  : STD_LOGIC;
    SIGNAL Scale_ld   : STD_LOGIC;
    SIGNAL Iter_ld    : STD_LOGIC;
    SIGNAL Error_ld   : STD_LOGIC;

    SIGNAL X_shift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_shift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL X_add_Yshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_add_Xshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL X_sub_Yshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_sub_Xshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL Gain_Product : SIGNED((2 * DATA_WIDTH) - 1 DOWNTO 0);
    SIGNAL Gain_Result  : SIGNED(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL Scaled_Result : SIGNED(DATA_WIDTH - 1 DOWNTO 0);

BEGIN

    --------------------------------------------------------------------
    -- Output assignment
    --------------------------------------------------------------------
    SQRT_o  <= Result_reg;
    Error_o <= Error_reg(0);

    --------------------------------------------------------------------
    -- Status flags sent to Controller
    --------------------------------------------------------------------
    A_Neg     <= '1' WHEN SIGNED(A_reg) < Q_ZERO ELSE '0';
    A_Zero    <= '1' WHEN SIGNED(A_reg) = Q_ZERO ELSE '0';
    A_Lt_Half <= '1' WHEN SIGNED(A_reg) < Q_HALF ELSE '0';
    A_Ge_Two  <= '1' WHEN SIGNED(A_reg) >= Q_TWO ELSE '0';
    Y_Neg     <= '1' WHEN SIGNED(Y_reg) < Q_ZERO ELSE '0';

    Iter_Done <= '1' WHEN TO_INTEGER(UNSIGNED(Iter_reg)) > ITER_MAX ELSE '0';

    --------------------------------------------------------------------
    -- Register enable signals
    --------------------------------------------------------------------
    A_ld      <= Load_A OR Norm_Low OR Norm_High;
    X_ld      <= Init_XY OR Iter_Add OR Iter_Sub;
    Y_ld      <= Init_XY OR Iter_Add OR Iter_Sub;
    Xcorr_ld  <= Gain_Correct;
    Result_ld <= Set_Error OR Set_Zero OR Scale_Correct;
    Scale_ld  <= Load_A OR Norm_Low OR Norm_High;
    Iter_ld   <= Init_XY OR Iter_Add OR Iter_Sub;
    Error_ld  <= Load_A OR Set_Error OR Set_Zero;

    --------------------------------------------------------------------
    -- A register input MUX
    -- Load_A    : A = A_i
    -- Norm_Low  : A = A * 4
    -- Norm_High : A = A / 4
    --------------------------------------------------------------------
    A_src <= A_i WHEN Load_A = '1' ELSE
             STD_LOGIC_VECTOR(SHIFT_LEFT(SIGNED(A_reg), 2)) WHEN Norm_Low = '1' ELSE
             STD_LOGIC_VECTOR(SHIFT_RIGHT(SIGNED(A_reg), 2));

    --------------------------------------------------------------------
    -- Scale register input MUX
    -- Load_A    : scale = 0
    -- Norm_Low  : scale = scale - 1
    -- Norm_High : scale = scale + 1
    --------------------------------------------------------------------
    Scale_src <= STD_LOGIC_VECTOR(TO_SIGNED(0, SCALE_WIDTH)) WHEN Load_A = '1' ELSE
                 STD_LOGIC_VECTOR(SIGNED(Scale_reg) - 1) WHEN Norm_Low = '1' ELSE
                 STD_LOGIC_VECTOR(SIGNED(Scale_reg) + 1);

    --------------------------------------------------------------------
    -- Iteration counter input MUX
    -- Init_XY : i = 1
    -- Iter    : i = i + 1
    --------------------------------------------------------------------
    Iter_src <= STD_LOGIC_VECTOR(TO_UNSIGNED(1, ITER_WIDTH)) WHEN Init_XY = '1' ELSE
                STD_LOGIC_VECTOR(UNSIGNED(Iter_reg) + 1);

    --------------------------------------------------------------------
    -- Error register input MUX
    --------------------------------------------------------------------
    Error_src <= "1" WHEN Set_Error = '1' ELSE "0";

    --------------------------------------------------------------------
    -- Shift operations: multiply by 2^(-i)
    --------------------------------------------------------------------
    X_shift <= SHIFT_RIGHT(SIGNED(X_reg), TO_INTEGER(UNSIGNED(Iter_reg)));
    Y_shift <= SHIFT_RIGHT(SIGNED(Y_reg), TO_INTEGER(UNSIGNED(Iter_reg)));

    --------------------------------------------------------------------
    -- CORDIC add/sub operations
    --------------------------------------------------------------------
    X_add_Yshift <= SIGNED(X_reg) + Y_shift;
    Y_add_Xshift <= SIGNED(Y_reg) + X_shift;

    X_sub_Yshift <= SIGNED(X_reg) - Y_shift;
    Y_sub_Xshift <= SIGNED(Y_reg) - X_shift;

    --------------------------------------------------------------------
    -- X register input MUX
    -- Init_XY  : X = A + 0.25
    -- Iter_Add : X = X + (Y >> i)
    -- Iter_Sub : X = X - (Y >> i)
    --------------------------------------------------------------------
    X_src <= STD_LOGIC_VECTOR(SIGNED(A_reg) + Q_QUARTER) WHEN Init_XY = '1' ELSE
             STD_LOGIC_VECTOR(X_add_Yshift) WHEN Iter_Add = '1' ELSE
             STD_LOGIC_VECTOR(X_sub_Yshift);

    --------------------------------------------------------------------
    -- Y register input MUX
    -- Init_XY  : Y = A - 0.25
    -- Iter_Add : Y = Y + (X >> i)
    -- Iter_Sub : Y = Y - (X >> i)
    --------------------------------------------------------------------
    Y_src <= STD_LOGIC_VECTOR(SIGNED(A_reg) - Q_QUARTER) WHEN Init_XY = '1' ELSE
             STD_LOGIC_VECTOR(Y_add_Xshift) WHEN Iter_Add = '1' ELSE
             STD_LOGIC_VECTOR(Y_sub_Xshift);

    --------------------------------------------------------------------
    -- Gain correction
    -- sqrt(A_norm) ~= X / K = X * INV_K
    --------------------------------------------------------------------
    Gain_Product <= SIGNED(X_reg) * INV_K_Q16;
    Gain_Result  <= RESIZE(SHIFT_RIGHT(Gain_Product, FRAC_WIDTH), DATA_WIDTH);
    Xcorr_src    <= STD_LOGIC_VECTOR(Gain_Result);

    --------------------------------------------------------------------
    -- Scale correction
    -- sqrt(A_original) = sqrt(A_norm) * 2^scale
    --------------------------------------------------------------------
    PROCESS (Xcorr_reg, Scale_reg)
        VARIABLE scale_int : INTEGER;
        VARIABLE temp      : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    BEGIN
        scale_int := TO_INTEGER(SIGNED(Scale_reg));
        temp := SIGNED(Xcorr_reg);

        IF scale_int > 0 THEN
            temp := SHIFT_LEFT(SIGNED(Xcorr_reg), scale_int);
        ELSIF scale_int < 0 THEN
            temp := SHIFT_RIGHT(SIGNED(Xcorr_reg), -scale_int);
        END IF;

        Scaled_Result <= temp;
    END PROCESS;

    --------------------------------------------------------------------
    -- Result input MUX
    --------------------------------------------------------------------
    Result_src <= (OTHERS => '0') WHEN Set_Error = '1' ELSE
                  (OTHERS => '0') WHEN Set_Zero = '1' ELSE
                  STD_LOGIC_VECTOR(Scaled_Result);

    --------------------------------------------------------------------
    -- Registers
    --------------------------------------------------------------------
    RegA : ENTITY work.Regn
        GENERIC MAP (N => DATA_WIDTH)
        PORT MAP (
            D     => A_src,
            Reset => Reset,
            Clk   => CLK,
            En    => A_ld,
            Q     => A_reg
        );

    RegX : ENTITY work.Regn
        GENERIC MAP (N => DATA_WIDTH)
        PORT MAP (
            D     => X_src,
            Reset => Reset,
            Clk   => CLK,
            En    => X_ld,
            Q     => X_reg
        );

    RegY : ENTITY work.Regn
        GENERIC MAP (N => DATA_WIDTH)
        PORT MAP (
            D     => Y_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Y_ld,
            Q     => Y_reg
        );

    RegXcorr : ENTITY work.Regn
        GENERIC MAP (N => DATA_WIDTH)
        PORT MAP (
            D     => Xcorr_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Xcorr_ld,
            Q     => Xcorr_reg
        );

    RegResult : ENTITY work.Regn
        GENERIC MAP (N => DATA_WIDTH)
        PORT MAP (
            D     => Result_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Result_ld,
            Q     => Result_reg
        );

    RegScale : ENTITY work.Regn
        GENERIC MAP (N => SCALE_WIDTH)
        PORT MAP (
            D     => Scale_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Scale_ld,
            Q     => Scale_reg
        );

    RegIter : ENTITY work.Regn
        GENERIC MAP (N => ITER_WIDTH)
        PORT MAP (
            D     => Iter_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Iter_ld,
            Q     => Iter_reg
        );

    RegError : ENTITY work.Regn
        GENERIC MAP (N => 1)
        PORT MAP (
            D     => Error_src,
            Reset => Reset,
            Clk   => CLK,
            En    => Error_ld,
            Q     => Error_reg
        );

END STR;
