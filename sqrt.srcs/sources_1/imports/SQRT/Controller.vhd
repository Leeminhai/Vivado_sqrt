LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY Controller IS
    PORT (
        Reset, CLK : IN STD_LOGIC;
        Start_i    : IN STD_LOGIC;

        A_Neg     : IN STD_LOGIC;
        A_Zero    : IN STD_LOGIC;
        A_Lt_Half : IN STD_LOGIC;
        A_Ge_Two  : IN STD_LOGIC;
        Y_Neg     : IN STD_LOGIC;
        Iter_Done : IN STD_LOGIC;

        Load_A        : OUT STD_LOGIC;
        Set_Error     : OUT STD_LOGIC;
        Set_Zero      : OUT STD_LOGIC;
        Norm_Low      : OUT STD_LOGIC;
        Norm_High     : OUT STD_LOGIC;
        Init_XY       : OUT STD_LOGIC;
        Iter_Add      : OUT STD_LOGIC;
        Iter_Sub      : OUT STD_LOGIC;
        Gain_Correct  : OUT STD_LOGIC;
        Scale_Correct : OUT STD_LOGIC;

        Done_o : OUT STD_LOGIC
    );
END Controller;

ARCHITECTURE BEV OF Controller IS

    TYPE state_type IS (
        s0,   -- reset state
        s1,   -- wait start
        s2,   -- load input A
        s3,   -- check A < 0 or A = 0
        s4,   -- check normalization range
        s5,   -- normalize low: A = A * 4, scale = scale - 1
        s6,   -- normalize high: A = A / 4, scale = scale + 1
        s7,   -- init X, Y, i
        s8,   -- check iteration done
        s9,   -- CORDIC iteration when Y < 0, d = 1
        s10,  -- CORDIC iteration when Y >= 0, d = -1
        s11,  -- gain correction
        s12,  -- scale correction
        s13,  -- done
        s14   -- wait Start_i = 0
    );

    SIGNAL state : state_type;

BEGIN

    --------------------------------------------------------------------
    -- FSM state transition
    --------------------------------------------------------------------
    FSM : PROCESS (Reset, CLK)
    BEGIN
        IF Reset = '1' THEN
            state <= s0;

        ELSIF rising_edge(CLK) THEN

            CASE state IS

                WHEN s0 =>
                    state <= s1;

                WHEN s1 =>
                    IF Start_i = '1' THEN
                        state <= s2;
                    ELSE
                        state <= s1;
                    END IF;

                WHEN s2 =>
                    state <= s3;

                WHEN s3 =>
                    IF A_Neg = '1' THEN
                        state <= s13;
                    ELSIF A_Zero = '1' THEN
                        state <= s13;
                    ELSE
                        state <= s4;
                    END IF;

                WHEN s4 =>
                    IF A_Lt_Half = '1' THEN
                        state <= s5;
                    ELSIF A_Ge_Two = '1' THEN
                        state <= s6;
                    ELSE
                        state <= s7;
                    END IF;

                WHEN s5 =>
                    state <= s4;

                WHEN s6 =>
                    state <= s4;

                WHEN s7 =>
                    state <= s8;

                WHEN s8 =>
                    IF Iter_Done = '1' THEN
                        state <= s11;
                    ELSE
                        IF Y_Neg = '1' THEN
                            state <= s9;
                        ELSE
                            state <= s10;
                        END IF;
                    END IF;

                WHEN s9 =>
                    state <= s8;

                WHEN s10 =>
                    state <= s8;

                WHEN s11 =>
                    state <= s12;

                WHEN s12 =>
                    state <= s13;

                WHEN s13 =>
                    state <= s14;

                WHEN s14 =>
                    IF Start_i = '0' THEN
                        state <= s1;
                    ELSE
                        state <= s14;
                    END IF;

                WHEN OTHERS =>
                    state <= s0;

            END CASE;

        END IF;
    END PROCESS;

    --------------------------------------------------------------------
    -- FSM output logic
    --------------------------------------------------------------------
    Load_A        <= '1' WHEN state = s2 ELSE '0';

    Set_Error     <= '1' WHEN state = s3 AND A_Neg = '1' ELSE '0';

    Set_Zero      <= '1' WHEN state = s3 AND A_Zero = '1' ELSE '0';

    Norm_Low      <= '1' WHEN state = s5 ELSE '0';

    Norm_High     <= '1' WHEN state = s6 ELSE '0';

    Init_XY       <= '1' WHEN state = s7 ELSE '0';

    Iter_Add      <= '1' WHEN state = s9 ELSE '0';

    Iter_Sub      <= '1' WHEN state = s10 ELSE '0';

    Gain_Correct  <= '1' WHEN state = s11 ELSE '0';

    Scale_Correct <= '1' WHEN state = s12 ELSE '0';

    Done_o        <= '1' WHEN state = s13 ELSE '0';

END BEV;
