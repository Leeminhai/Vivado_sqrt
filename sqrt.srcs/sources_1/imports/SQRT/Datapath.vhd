LIBRARY ieee;
USE ieee.std_logic_1164.all;
USE ieee.numeric_std.all;

ENTITY Datapath IS
    GENERIC (
        DATA_WIDTH : INTEGER := 32; -- dữ liệu 32 bit
        FRAC_WIDTH : INTEGER := 16; -- 16 bit phần thập phân của Q16.16
        ITER_MAX   : INTEGER := 32  -- số vòng lặp CORDIC
    );
    PORT (
        Reset, CLK : IN STD_LOGIC;

        A_i : IN STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
-- nhóm tín hiệu điều khiển từ Controller sang Datapath:
        Load_A        : IN STD_LOGIC; -- nạp A_i vào A_reg
        Set_Error     : IN STD_LOGIC; -- báo lỗi đầu vào âm
        Set_Zero      : IN STD_LOGIC; -- báo lỗi đầu vào âm
        Norm_Low      : IN STD_LOGIC; -- chuẩn hóa khi A < 0.5
        Norm_High     : IN STD_LOGIC; -- chuẩn hóa khi A >= 2
        Init_XY       : IN STD_LOGIC; -- khởi tạo X, Y, i
        Iter_Add      : IN STD_LOGIC; -- vòng lặp khi Y < 0
        Iter_Sub      : IN STD_LOGIC; -- vòng lặp khi Y >= 0
        Gain_Correct  : IN STD_LOGIC; -- hiệu chỉnh gain
        Scale_Correct : IN STD_LOGIC; -- bù scale
-- nhóm tín hiệu trạng thái từ Datapath gửi về Controller:
        A_Neg     : OUT STD_LOGIC; -- A < 0
        A_Zero    : OUT STD_LOGIC; -- A = 0
        A_Lt_Half : OUT STD_LOGIC; -- A < 0.5
        A_Ge_Two  : OUT STD_LOGIC; -- A >= 2
        Y_Neg     : OUT STD_LOGIC; -- Y < 0
        Iter_Done : OUT STD_LOGIC; -- đủ số vòng lặp
-- dữ liệu đầu ra
        Error_o : OUT STD_LOGIC; -- báo lỗi đầu vào âm
        SQRT_o  : OUT STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0) -- kết quả 32-bit Q16.16
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
    -- Hang so hieu chinh gain CORDIC
    -- Sau vong lap CORDIC, gia tri X bi anh huong boi he so gain K.
    -- Voi thuat toan nay:
    --   K ~= 0.828159
    --   1 / K ~= 1.207497
    -- Doi 1/K sang Q16.16:
    --   1.207497 * 65536 ~= 79134
    -- Do do INV_K_Q16 = 79134.
    --------------------------------------------------------------------
    CONSTANT INV_K_Q16 : SIGNED(DATA_WIDTH - 1 DOWNTO 0) := TO_SIGNED(79134, DATA_WIDTH);
    --------------------------------------------------------------------
    -- Do rong cua thanh ghi scale va bo dem lap
    --
    -- SCALE_WIDTH = 6:
    --   scale can bieu dien ca gia tri duong va am.
    --   6 bit signed bieu dien duoc tu -32 den 31.
    --
    -- ITER_WIDTH = 6:
    --   can dem toi hon 32 vong lap.
    --   6 bit unsigned bieu dien duoc tu 0 den 63.
    --------------------------------------------------------------------
    CONSTANT SCALE_WIDTH : INTEGER := 6;
    CONSTANT ITER_WIDTH  : INTEGER := 6;
    --------------------------------------------------------------------
    -- Cac thanh ghi chinh cua Datapath:
    SIGNAL A_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Luu A_i sau khi nap va sau khi chuan hoa
    SIGNAL X_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Luu bien X cua thuat toan CORDIC
    SIGNAL Y_reg      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Luu bien Y cua thuat toan CORDIC
    SIGNAL Xcorr_reg  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Luu X sau khi hieu chinh gain
    SIGNAL Result_reg : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0); -- Luu ket qua cuoi cung SQRT_o

    SIGNAL Scale_reg  : STD_LOGIC_VECTOR(SCALE_WIDTH - 1 DOWNTO 0); -- Luu so lan chuan hoa A
    SIGNAL Iter_reg   : STD_LOGIC_VECTOR(ITER_WIDTH - 1 DOWNTO 0); -- Luu chi so vong lap i
    SIGNAL Error_reg  : STD_LOGIC_VECTOR(0 DOWNTO 0); -- Luu co bao loi
    --------------------------------------------------------------------
    -- Tin hieu dau vao cho cac thanh ghi
    -- Moi thanh ghi co mot tin hieu *_src lam du lieu D:
    SIGNAL A_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL X_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_src      : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Xcorr_src  : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Result_src : STD_LOGIC_VECTOR(DATA_WIDTH - 1 DOWNTO 0);

    SIGNAL Scale_src  : STD_LOGIC_VECTOR(SCALE_WIDTH - 1 DOWNTO 0);
    SIGNAL Iter_src   : STD_LOGIC_VECTOR(ITER_WIDTH - 1 DOWNTO 0);
    SIGNAL Error_src  : STD_LOGIC_VECTOR(0 DOWNTO 0);
    --------------------------------------------------------------------
    -- Tin hieu enable cho cac thanh ghi
    -- Khi *_ld = '1' tai canh len clock, thanh ghi tuong ung se nap du lieu moi:
    SIGNAL A_ld       : STD_LOGIC;
    SIGNAL X_ld       : STD_LOGIC;
    SIGNAL Y_ld       : STD_LOGIC;
    SIGNAL Xcorr_ld   : STD_LOGIC;
    SIGNAL Result_ld  : STD_LOGIC;
    SIGNAL Scale_ld   : STD_LOGIC;
    SIGNAL Iter_ld    : STD_LOGIC;
    SIGNAL Error_ld   : STD_LOGIC;
    --------------------------------------------------------------------
    -- Cac tin hieu dich bit trong vong lap CORDIC
    -- X_shift = X >> i = X / 2^i
    -- Y_shift = Y >> i = Y / 2^i
    SIGNAL X_shift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_shift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    --------------------------------------------------------------------
    -- Cac ket qua cong/tru tam thoi trong vong lap CORDIC:
    SIGNAL X_add_Yshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_add_Xshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL X_sub_Yshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    SIGNAL Y_sub_Xshift : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    --------------------------------------------------------------------
    -- Tin hieu dung cho buoc hieu chinh gain
    -- Gain_Product rong 64 bit vi nhan hai so 32 bit.
    -- Sau do dich phai FRAC_WIDTH bit de dua ve Q16.16.
    SIGNAL Gain_Product : SIGNED((2 * DATA_WIDTH) - 1 DOWNTO 0);
    SIGNAL Gain_Result  : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    --------------------------------------------------------------------
    -- Ket qua sau khi bu scale:
    SIGNAL Scaled_Result : SIGNED(DATA_WIDTH - 1 DOWNTO 0);

BEGIN

    --------------------------------------------------------------------
    -- Gan dau ra cua Datapath
    -- SQRT_o lay truc tiep tu Result_reg.
    -- Error_o lay bit duy nhat cua Error_reg.
    SQRT_o  <= Result_reg;
    Error_o <= Error_reg(0);

    --------------------------------------------------------------------
    -- Tao cac co trang thai gui ve Controller
    -- Cac tin hieu nay giup Controller biet nen chuyen sang
    -- trang thai nao tiep theo trong FSM.
    A_Neg     <= '1' WHEN SIGNED(A_reg) < Q_ZERO ELSE '0'; -- Kiem tra A co am khong
    A_Zero    <= '1' WHEN SIGNED(A_reg) = Q_ZERO ELSE '0'; -- Kiem tra A co bang 0 khong
    A_Lt_Half <= '1' WHEN SIGNED(A_reg) < Q_HALF ELSE '0'; -- Kiem tra A < 0.5
    A_Ge_Two  <= '1' WHEN SIGNED(A_reg) >= Q_TWO ELSE '0'; -- Kiem tra A >= 2
    Y_Neg     <= '1' WHEN SIGNED(Y_reg) < Q_ZERO ELSE '0'; -- Kiem tra Y < 0
    --------------------------------------------------------------------
    -- Khi Iter_reg > ITER_MAX, nghia la da thuc hien du so vong lap.
    -- Iter_reg duoc khoi tao = 1 va tang sau moi lan lap.
    Iter_Done <= '1' WHEN TO_INTEGER(UNSIGNED(Iter_reg)) > ITER_MAX ELSE '0';
    --------------------------------------------------------------------
    -- Tao tin hieu enable cho cac thanh ghi
    -- Controller chi bat cac tin hieu dieu khien trong tung trang thai.
    -- Datapath gom cac tin hieu do lai thanh enable cho tung thanh ghi.
    A_ld      <= Load_A OR Norm_Low OR Norm_High;        -- A_reg duoc ghi khi nap A hoac chuan hoa
    X_ld      <= Init_XY OR Iter_Add OR Iter_Sub;        -- X_reg duoc ghi khi khoi tao hoac lap CORDIC
    Y_ld      <= Init_XY OR Iter_Add OR Iter_Sub;        -- Y_reg duoc ghi khi khoi tao hoac lap CORDIC
    Xcorr_ld  <= Gain_Correct;                           -- Xcorr_reg chi ghi o buoc hieu chinh gain
    Result_ld <= Set_Error OR Set_Zero OR Scale_Correct; -- Result_reg ghi khi loi, A=0, hoac sau bu scale
    Scale_ld  <= Load_A OR Norm_Low OR Norm_High;        -- Scale_reg reset khi load A va cap nhat khi chuan hoa
    Iter_ld   <= Init_XY OR Iter_Add OR Iter_Sub;        -- Iter_reg set ve 1 khi init va tang khi lap
    Error_ld  <= Load_A OR Set_Error OR Set_Zero;        -- Error_reg reset khi load A, set khi co loi

    --------------------------------------------------------------------
    -- MUX dau vao cho A_reg
    -- Load_A = 1:
    --   A_src = A_i, nap gia tri dau vao vao A_reg.
    -- Norm_Low = 1:
    --   A_src = A_reg << 2 = A_reg * 4.
    --   Dung khi A < 0.5.
    -- Nguoc lai:
    --   A_src = A_reg >> 2 = A_reg / 4.
    --   Truong hop nay tuong ung Norm_High, dung khi A >= 2.
    --------------------------------------------------------------------
    A_src <= A_i WHEN Load_A = '1' ELSE
             STD_LOGIC_VECTOR(SHIFT_LEFT(SIGNED(A_reg), 2)) WHEN Norm_Low = '1' ELSE
             STD_LOGIC_VECTOR(SHIFT_RIGHT(SIGNED(A_reg), 2));

   --------------------------------------------------------------------
    -- MUX dau vao cho Scale_reg
    -- scale dung de ghi nho viec da nhan/chia A bao nhieu lan trong
    -- qua trinh chuan hoa.
    -- Load_A:
    --   scale = 0.
    -- Norm_Low:
    --   A = A * 4 nen sqrt(A_goc) = sqrt(A_chuan_hoa) / 2.
    --   Vi vay scale = scale - 1.
    -- Norm_High:
    --   A = A / 4 nen sqrt(A_goc) = sqrt(A_chuan_hoa) * 2.
    --   Vi vay scale = scale + 1.
    --------------------------------------------------------------------
    Scale_src <= STD_LOGIC_VECTOR(TO_SIGNED(0, SCALE_WIDTH)) WHEN Load_A = '1' ELSE
                 STD_LOGIC_VECTOR(SIGNED(Scale_reg) - 1) WHEN Norm_Low = '1' ELSE
                 STD_LOGIC_VECTOR(SIGNED(Scale_reg) + 1);

    --------------------------------------------------------------------
    -- MUX dau vao cho Iter_reg
    -- Init_XY:
    --   i = 1, bat dau lap CORDIC tu buoc i = 1.
    -- Iter_Add hoac Iter_Sub:
    --   i = i + 1 sau moi vong lap.
    Iter_src <= STD_LOGIC_VECTOR(TO_UNSIGNED(1, ITER_WIDTH)) WHEN Init_XY = '1' ELSE
                STD_LOGIC_VECTOR(UNSIGNED(Iter_reg) + 1);
    --------------------------------------------------------------------
    -- MUX dau vao cho Error_reg
    -- Neu Set_Error = 1 thi ghi Error_reg = 1.
    -- Cac truong hop con lai ghi Error_reg = 0.
    -- Khi Load_A = 1, Error_ld cung bang 1 nen co loi se duoc xoa
    -- truoc khi bat dau phep tinh moi.
    Error_src <= "1" WHEN Set_Error = '1' ELSE "0";
    --------------------------------------------------------------------
    -- Tinh cac gia tri dich phai dung trong CORDIC
    -- SHIFT_RIGHT tren kieu SIGNED la dich phai so hoc,
    -- giu dung dau cua so co dau.
    -- TO_INTEGER(UNSIGNED(Iter_reg)) chuyen Iter_reg tu vector bit
    -- sang so nguyen de lam so bit can dich.
    X_shift <= SHIFT_RIGHT(SIGNED(X_reg), TO_INTEGER(UNSIGNED(Iter_reg)));
    Y_shift <= SHIFT_RIGHT(SIGNED(Y_reg), TO_INTEGER(UNSIGNED(Iter_reg)));

    --------------------------------------------------------------------
    -- Tinh truoc cac kha nang cap nhat X va Y trong vong lap CORDIC
    -- Khi Y < 0:
    --   X_new = X + (Y >> i)
    --   Y_new = Y + (X >> i)
    -- Khi Y >= 0:
    --   X_new = X - (Y >> i)
    --   Y_new = Y - (X >> i)

    X_add_Yshift <= SIGNED(X_reg) + Y_shift;
    Y_add_Xshift <= SIGNED(Y_reg) + X_shift;

    X_sub_Yshift <= SIGNED(X_reg) - Y_shift;
    Y_sub_Xshift <= SIGNED(Y_reg) - X_shift;

    --------------------------------------------------------------------
    -- MUX dau vao cho X_reg
    -- Init_XY:
    --   X = A + 0.25.
    -- Iter_Add:
    --   X = X + (Y >> i).
    -- Iter_Sub:
    --   X = X - (Y >> i).
    X_src <= STD_LOGIC_VECTOR(SIGNED(A_reg) + Q_QUARTER) WHEN Init_XY = '1' ELSE
             STD_LOGIC_VECTOR(X_add_Yshift) WHEN Iter_Add = '1' ELSE
             STD_LOGIC_VECTOR(X_sub_Yshift);
    --------------------------------------------------------------------
    -- MUX dau vao cho Y_reg
    -- Init_XY:
    --   Y = A - 0.25.
    -- Iter_Add:
    --   Y = Y + (X >> i).
    -- Iter_Sub:
    --   Y = Y - (X >> i).
    Y_src <= STD_LOGIC_VECTOR(SIGNED(A_reg) - Q_QUARTER) WHEN Init_XY = '1' ELSE
             STD_LOGIC_VECTOR(Y_add_Xshift) WHEN Iter_Add = '1' ELSE
             STD_LOGIC_VECTOR(Y_sub_Xshift);
    --------------------------------------------------------------------
    -- Hieu chinh gain CORDIC
    -- X_reg la Q16.16.
    -- INV_K_Q16 cung la Q16.16.
    -- Khi nhan:
    --   Q16.16 * Q16.16 = Q32.32
    -- Vi vay can dich phai FRAC_WIDTH = 16 bit de dua ket qua
    -- ve lai dang Q16.16.
    Gain_Product <= SIGNED(X_reg) * INV_K_Q16;
    Gain_Result  <= RESIZE(SHIFT_RIGHT(Gain_Product, FRAC_WIDTH), DATA_WIDTH);
    Xcorr_src    <= STD_LOGIC_VECTOR(Gain_Result);
    --------------------------------------------------------------------
    -- Bu scale sau khi da tinh sqrt(A_norm)
    -- Quan he:
    --   sqrt(A_original) = sqrt(A_normalized) * 2^scale
    -- Neu scale > 0:
    --   Dich trai scale bit, tuong duong nhan 2^scale.
    -- Neu scale < 0:
    --   Dich phai -scale bit, tuong duong chia 2^(-scale).
    -- Neu scale = 0:
    --   Giu nguyen Xcorr_reg.
    -- PROCESS nay la mach to hop, vi khong co rising_edge(CLK).
    PROCESS (Xcorr_reg, Scale_reg)
        VARIABLE scale_int : INTEGER;
        VARIABLE temp      : SIGNED(DATA_WIDTH - 1 DOWNTO 0);
    BEGIN
    -- Chuyen Scale_reg tu vector signed sang integer de dung lam so bit dich
        scale_int := TO_INTEGER(SIGNED(Scale_reg));
    -- Mac dinh ket qua bang X da hieu chinh gain
        temp := SIGNED(Xcorr_reg);
    -- Neu scale duong thi nhan them 2^scale
        IF scale_int > 0 THEN
            temp := SHIFT_LEFT(SIGNED(Xcorr_reg), scale_int);
    -- Neu scale am thi chia cho 2^(-scale)
        ELSIF scale_int < 0 THEN
            temp := SHIFT_RIGHT(SIGNED(Xcorr_reg), -scale_int);
        END IF;
    -- Gan ket qua sau bu scale ra tin hieu Scaled_Result
        Scaled_Result <= temp;
    END PROCESS;

    --------------------------------------------------------------------
    -- MUX dau vao cho Result_reg
    -- Set_Error:
    --   Dau vao am, khong tinh sqrt, ket qua dat ve 0.
    -- Set_Zero:
    --   Dau vao = 0, sqrt(0) = 0.
    -- Scale_Correct:
    --   Ghi ket qua sau khi bu scale.
    Result_src <= (OTHERS => '0') WHEN Set_Error = '1' ELSE
                  (OTHERS => '0') WHEN Set_Zero = '1' ELSE
                  STD_LOGIC_VECTOR(Scaled_Result);

    --------------------------------------------------------------------
    -- Cac thanh ghi cua Datapath
    -- Tat ca deu dung entity Regn trong file regn.vhd.
    -- Regn la thanh ghi generic N-bit:
    --   D     : du lieu dau vao
    --   Q     : du lieu dau ra
    --   En    : cho phep ghi
    --   Reset : reset ve 0
    --   Clk   : clock
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
