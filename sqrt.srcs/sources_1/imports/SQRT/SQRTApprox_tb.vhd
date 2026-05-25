LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
USE ieee.math_real.all;

ENTITY SQRTApprox_tb IS
END SQRTApprox_tb;

ARCHITECTURE BEV OF SQRTApprox_tb IS

    CONSTANT DATA_WIDTH : INTEGER := 32;
    CONSTANT FRAC_WIDTH : INTEGER := 16;
    CONSTANT ITER_MAX   : INTEGER := 32;

    CONSTANT SCALE_REAL : REAL := 65536.0;

    SIGNAL Reset   : STD_LOGIC := '0';
    SIGNAL CLK     : STD_LOGIC := '0';
    SIGNAL Start_i : STD_LOGIC := '0';

    SIGNAL A_i     : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SQRT_o  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Error_o : STD_LOGIC;
    SIGNAL Done_o  : STD_LOGIC;

BEGIN

    --------------------------------------------------------------------
    -- Unit Under Test
    --------------------------------------------------------------------
    UUT : ENTITY work.SQRTApprox
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_WIDTH => FRAC_WIDTH,
            ITER_MAX   => ITER_MAX
        )
        PORT MAP (
            Reset   => Reset,
            CLK     => CLK,
            Start_i => Start_i,

            A_i => A_i,

            SQRT_o  => SQRT_o,
            Error_o => Error_o,
            Done_o  => Done_o
        );

    --------------------------------------------------------------------
    -- Clock generation: period = 20 ns
    --------------------------------------------------------------------
    CLK <= NOT CLK AFTER 10 ns;

    --------------------------------------------------------------------
    -- Test process
    --------------------------------------------------------------------
    Stimulus : PROCESS

        PROCEDURE Run_Test (
            CONSTANT a_real : IN REAL
        ) IS
            VARIABLE input_int   : INTEGER;
            VARIABLE result_int  : INTEGER;
            VARIABLE cordic_real : REAL;
            VARIABLE math_real_v : REAL;
            VARIABLE error_real  : REAL;
        BEGIN

            ------------------------------------------------------------
            -- Convert real input to Q16.16 fixed-point
            ------------------------------------------------------------
            input_int := INTEGER(a_real * SCALE_REAL);

            A_i <= STD_LOGIC_VECTOR(TO_SIGNED(input_int, DATA_WIDTH));

            ------------------------------------------------------------
            -- Start pulse
            ------------------------------------------------------------
            Start_i <= '1';
            WAIT UNTIL rising_edge(CLK);
            Start_i <= '0';

            ------------------------------------------------------------
            -- Wait until calculation finishes
            ------------------------------------------------------------
            WAIT UNTIL Done_o = '1';
            WAIT UNTIL rising_edge(CLK);

            ------------------------------------------------------------
            -- Convert output Q16.16 to real
            ------------------------------------------------------------
            result_int  := TO_INTEGER(SIGNED(SQRT_o));
            cordic_real := REAL(result_int) / SCALE_REAL;
            math_real_v := sqrt(a_real);

            IF cordic_real >= math_real_v THEN
                error_real := cordic_real - math_real_v;
            ELSE
                error_real := math_real_v - cordic_real;
            END IF;

            ------------------------------------------------------------
            -- Print result to Transcript
            ------------------------------------------------------------
            REPORT "sqrt(" & REAL'IMAGE(a_real) & ") : CORDIC = " &
                   REAL'IMAGE(cordic_real) &
                   ", math = " &
                   REAL'IMAGE(math_real_v) &
                   ", sai so = " &
                   REAL'IMAGE(error_real);

            WAIT FOR 100 ns;

        END PROCEDURE;

    BEGIN

        ----------------------------------------------------------------
        -- Reset
        ----------------------------------------------------------------
        Reset   <= '1';
        Start_i <= '0';
        A_i     <= (OTHERS => '0');

        WAIT FOR 40 ns;

        Reset <= '0';

        WAIT FOR 40 ns;

        ----------------------------------------------------------------
        -- Test cases
        ----------------------------------------------------------------
        Run_Test(0.0);
        Run_Test(0.25);
        Run_Test(0.5);
        Run_Test(1.0);
        Run_Test(2.0);
        Run_Test(3.0);
        Run_Test(4.0);
        Run_Test(9.0);
        Run_Test(16.0);
        Run_Test(100.0);
        Run_Test(0.1);
        Run_Test(12345.6789);

        ----------------------------------------------------------------
        -- Negative input test: sqrt(-1.0)
        ----------------------------------------------------------------
        A_i <= STD_LOGIC_VECTOR(TO_SIGNED(-65536, DATA_WIDTH));

        Start_i <= '1';
        WAIT UNTIL rising_edge(CLK);
        Start_i <= '0';

        WAIT UNTIL Done_o = '1';
        WAIT UNTIL rising_edge(CLK);

        REPORT "sqrt(-1.0) : Error_o = " & STD_LOGIC'IMAGE(Error_o);

        ASSERT Error_o = '1'
            REPORT "Negative input test failed: Error_o should be 1"
            SEVERITY ERROR;

        REPORT "All SQRTApprox test cases finished.";

        WAIT;

    END PROCESS;

END BEV;