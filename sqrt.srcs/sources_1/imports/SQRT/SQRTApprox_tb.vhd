--------------------------------------------------------------------
-- Nhiem vu:
--   - Tao clock va reset cho mach
--   - Dua nhieu gia tri A_i vao khoi SQRTApprox
--   - Phat xung Start_i de bat dau tinh toan
--   - Cho Done_o = 1 de biet phep tinh da xong
--   - Chuyen ket qua SQRT_o tu Q16.16 ve so thuc
--   - So sanh ket qua CORDIC voi ham sqrt() cua math_real
--   - In ket qua ra cua so Transcript cua ModelSim/Vivado

LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;
USE ieee.math_real.all;

--------------------------------------------------------------------
-- ENTITY SQRTApprox_tb
-- Testbench khong co cong vao/ra.
-- Ly do: testbench la moi truong mo phong, tu no tao tin hieu
-- dau vao va quan sat tin hieu dau ra cua UUT.
--------------------------------------------------------------------
ENTITY SQRTApprox_tb IS
END SQRTApprox_tb;
--------------------------------------------------------------------
-- ARCHITECTURE BEV
-- BEV viet tat cua Behavioral.
-- Phan nay mo ta hanh vi testbench bang cac process.
--------------------------------------------------------------------
ARCHITECTURE BEV OF SQRTApprox_tb IS

    ----------------------------------------------------------------
    -- Cac hang so cau hinh giong voi thiet ke SQRTApprox
    CONSTANT DATA_WIDTH : INTEGER := 32; -- Do rong du lieu 32 bit
    CONSTANT FRAC_WIDTH : INTEGER := 16; -- Q16.16 co 16 bit phan thap phan
    CONSTANT ITER_MAX   : INTEGER := 32; -- So vong lap CORDIC
    ----------------------------------------------------------------
    -- SCALE_REAL = 2^16 = 65536
    -- Dung de chuyen doi giua:
    --   So thuc real  <->  so fixed-point Q16.16
    -- Vi du:
    --   1.0  * 65536 = 65536  = 0x00010000
    --   0.25 * 65536 = 16384  = 0x00004000
    ----------------------------------------------------------------
    CONSTANT SCALE_REAL : REAL := 65536.0;
    ----------------------------------------------------------------
    -- Cac tin hieu testbench tao ra de dua vao UUT
    SIGNAL Reset   : STD_LOGIC := '0'; -- Reset muc cao
    SIGNAL CLK     : STD_LOGIC := '0'; -- Clock mo phong
    SIGNAL Start_i : STD_LOGIC := '0'; -- Tin hieu bat dau phep tinh
    ----------------------------------------------------------------
    -- Tin hieu du lieu vao/ra cua UUT
    SIGNAL A_i     : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) := (OTHERS => '0');
    SIGNAL SQRT_o  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Error_o : STD_LOGIC;
    SIGNAL Done_o  : STD_LOGIC;

BEGIN

    --------------------------------------------------------------------
    -- Testbench se ket noi cac tin hieu Reset, CLK, Start_i, A_i
    -- vao UUT va quan sat SQRT_o, Error_o, Done_o.
    UUT : ENTITY work.SQRTApprox
        GENERIC MAP (
            DATA_WIDTH => DATA_WIDTH,
            FRAC_WIDTH => FRAC_WIDTH,
            ITER_MAX   => ITER_MAX
        )
        PORT MAP (
            ------------------------------------------------------------
            -- Tin hieu dieu khien
            ------------------------------------------------------------
            Reset   => Reset,
            CLK     => CLK,
            Start_i => Start_i,

            ------------------------------------------------------------
            -- Du lieu dau vao
            ------------------------------------------------------------
            A_i => A_i,

            ------------------------------------------------------------
            -- Ket qua dau ra
            ------------------------------------------------------------
            SQRT_o  => SQRT_o,
            Error_o => Error_o,
            Done_o  => Done_o
        );

    --------------------------------------------------------------------
    -- Clock generation
    -- Tao clock dao trang thai moi 10 ns.
    -- CLK = 0 -> sau 10 ns thanh 1
    -- CLK = 1 -> sau 10 ns thanh 0
    -- Vay chu ky clock la:
    --   10 ns + 10 ns = 20 ns
    -- Tan so clock tuong ung:
    --   f = 1 / 20 ns = 50 MHz
    --------------------------------------------------------------------
    CLK <= NOT CLK AFTER 10 ns;
    --------------------------------------------------------------------
    -- Test process
    -- Process nay thuc hien toan bo qua trinh test:
    --   1. Reset mach
    --   2. Goi procedure Run_Test voi nhieu gia tri dau vao
    --   3. Test truong hop dau vao am
    --   4. In thong bao ket thuc
    Stimulus : PROCESS
        ----------------------------------------------------------------
        -- Moi lan goi Run_Test(x), testbench se:
        --   - Chuyen x tu REAL sang Q16.16
        --   - Dua vao A_i
        --   - Phat xung Start_i
        --   - Cho Done_o = 1
        --   - Doc SQRT_o
        --   - Chuyen SQRT_o tu Q16.16 ve REAL
        --   - So sanh voi sqrt(x) cua thu vien math_real
        --   - In ket qua ra Transcript
        ----------------------------------------------------------------
        PROCEDURE Run_Test (
            CONSTANT a_real : IN REAL
        ) IS
            ------------------------------------------------------------
            -- Bien cuc bo chi dung ben trong procedure
            VARIABLE input_int   : INTEGER; -- Gia tri a_real sau khi doi sang Q16.16 dang integer
            VARIABLE result_int  : INTEGER; -- Gia tri SQRT_o sau khi doi sang integer
            VARIABLE cordic_real : REAL;    -- Ket qua cua mach CORDIC sau khi doi ve REAL
            VARIABLE math_real_v : REAL;    -- Ket qua chuan tinh bang sqrt() cua math_real
            VARIABLE error_real  : REAL;    -- Sai so tuyet doi giua CORDIC va math_real

        BEGIN

            ------------------------------------------------------------
            -- Convert real input to Q16.16 fixed-point
            -- Cong thuc:
            --   fixed_value = real_value * 2^16
            -- Vi du:
            --   a_real = 1.0
            --   input_int = 1.0 * 65536 = 65536 = 0x00010000
            ------------------------------------------------------------
            input_int := INTEGER(a_real * SCALE_REAL);

            ------------------------------------------------------------
            -- Dua gia tri input_int vao A_i
            -- TO_SIGNED(input_int, DATA_WIDTH):
            --   chuyen integer thanh so signed DATA_WIDTH bit
            -- STD_LOGIC_VECTOR(...):
            --   ep kieu sang std_logic_vector de phu hop voi port A_i
            ------------------------------------------------------------
            A_i <= STD_LOGIC_VECTOR(TO_SIGNED(input_int, DATA_WIDTH));
            ------------------------------------------------------------
            -- Start pulse
            -- Start_i duoc dua len 1 trong mot chu ky clock de bao
            -- cho Controller bat dau phep tinh.
            ------------------------------------------------------------
            Start_i <= '1';
            ------------------------------------------------------------
            -- Cho den canh len tiep theo cua clock.
            -- Tai canh len nay, FSM se nhan Start_i = 1.
            ------------------------------------------------------------
            WAIT UNTIL rising_edge(CLK);
            ------------------------------------------------------------
            -- Dua Start_i ve 0.
            -- Viec nay giup tao xung Start ngan va tranh viec FSM
            -- chay lai lien tuc sau khi Done.
            Start_i <= '0';
            ------------------------------------------------------------
            -- Cho den khi UUT bao Done_o = 1.
            -- Luc nay ket qua SQRT_o da hop le.
            WAIT UNTIL Done_o = '1';
            ------------------------------------------------------------
            -- Cho them mot canh clock de ket qua on dinh hon khi in/log.
            WAIT UNTIL rising_edge(CLK);
            ------------------------------------------------------------
            -- Convert output Q16.16 to real
            -- SQRT_o la std_logic_vector 32 bit.
            -- Can ep kieu sang SIGNED roi doi thanh INTEGER.
            result_int := TO_INTEGER(SIGNED(SQRT_o));
            ------------------------------------------------------------
            -- Doi ket qua fixed-point ve so thuc.
            -- Cong thuc:
            --   real_value = fixed_value / 2^16
            cordic_real := REAL(result_int) / SCALE_REAL;
            ------------------------------------------------------------
            -- Tinh ket qua chuan bang ham sqrt() trong ieee.math_real.
            -- Ham nay chi dung trong testbench, khong dung cho synthesis.
            math_real_v := sqrt(a_real);
            ------------------------------------------------------------
            -- Tinh sai so tuyet doi:
            --   error = |cordic_real - math_real_v|
            IF cordic_real >= math_real_v THEN
                error_real := cordic_real - math_real_v;
            ELSE
                error_real := math_real_v - cordic_real;
            END IF;
            ------------------------------------------------------------
            -- Print result to Transcript
            -- REPORT se in chuoi thong bao ra cua so Transcript.
            -- REAL'IMAGE(x):
            --   chuyen gia tri REAL thanh chuoi ky tu de in ra.
            REPORT "sqrt(" & REAL'IMAGE(a_real) & ") : CORDIC = " &
                   REAL'IMAGE(cordic_real) &
                   ", math = " &
                   REAL'IMAGE(math_real_v) &
                   ", sai so = " &
                   REAL'IMAGE(error_real);
            ------------------------------------------------------------
            -- Cho 100 ns truoc khi chay test case tiep theo.
            -- Muc dich la tach cac test case tren waveform cho de nhin.
            WAIT FOR 100 ns;

        END PROCEDURE;

    BEGIN
        ----------------------------------------------------------------
        -- Reset
        -- Dua Reset len 1 de xoa trang thai FSM va cac thanh ghitrong Datapath.
        ----------------------------------------------------------------
        Reset   <= '1';
        Start_i <= '0';
        A_i     <= (OTHERS => '0');
        ----------------------------------------------------------------
        -- Giu reset trong 40 ns, tuong duong 2 chu ky clock 20 ns.
        WAIT FOR 40 ns;
        ----------------------------------------------------------------
        -- Ha reset xuong 0 de mach bat dau san sang nhan Start_i.
        Reset <= '0';
        ----------------------------------------------------------------
        -- Cho them 40 ns de mach on dinh sau reset.
        ----------------------------------------------------------------
        WAIT FOR 40 ns;
        ----------------------------------------------------------------
        -- Test cases
        -- Moi dong Run_Test(x) se test sqrt(x).
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
        -- -1.0 trong Q16.16:
        --   -1.0 * 65536 = -65536
        -- Khi dua gia tri am vao, mach phai:
        --   Error_o = 1
        --   Done_o  = 1
        --   SQRT_o  = 0
        ----------------------------------------------------------------
        A_i <= STD_LOGIC_VECTOR(TO_SIGNED(-65536, DATA_WIDTH));
        ----------------------------------------------------------------
        -- Phat xung Start_i de bat dau test dau vao am
        Start_i <= '1';
        WAIT UNTIL rising_edge(CLK);
        Start_i <= '0';
        ----------------------------------------------------------------
        -- Cho den khi mach bao Done_o = 1
        WAIT UNTIL Done_o = '1';
        WAIT UNTIL rising_edge(CLK);
        ----------------------------------------------------------------
        -- In gia tri Error_o ra Transcript
        REPORT "sqrt(-1.0) : Error_o = " & STD_LOGIC'IMAGE(Error_o);
        ----------------------------------------------------------------
        -- ASSERT dung de tu dong kiem tra ket qua.
        -- Neu Error_o khong bang 1, simulation se bao loi voi muc ERROR.
        -- Neu Error_o = 1, cau lenh ASSERT khong bao loi.
        ASSERT Error_o = '1'
            REPORT "Negative input test failed: Error_o should be 1"
            SEVERITY ERROR;
        ----------------------------------------------------------------
        -- Thong bao da chay xong tat ca test case
        REPORT "All SQRTApprox test cases finished.";
        ----------------------------------------------------------------
        -- WAIT khong dieu kien:
        -- Dung testbench tai day, khong cho process lap lai.
        WAIT;
    END PROCESS;

END BEV;
