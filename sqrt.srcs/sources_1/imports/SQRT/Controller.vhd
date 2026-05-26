LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY Controller IS
    PORT (
        ----------------------------------------------------------------
        -- Tin hieu he thong
        Reset, CLK : IN STD_LOGIC; -- Reset va clock cua FSM
        Start_i    : IN STD_LOGIC; -- Tin hieu bat dau phep tinh
        ----------------------------------------------------------------
        -- Cac tin hieu trang thai nhan tu Datapath
        -- Controller dua vao cac co nay de quyet dinh chuyen trang thai
        A_Neg     : IN STD_LOGIC; -- = 1 neu A < 0
        A_Zero    : IN STD_LOGIC; -- = 1 neu A = 0
        A_Lt_Half : IN STD_LOGIC; -- = 1 neu A < 0.5
        A_Ge_Two  : IN STD_LOGIC; -- = 1 neu A >= 2.0
        Y_Neg     : IN STD_LOGIC; -- = 1 neu Y < 0
        Iter_Done : IN STD_LOGIC; -- = 1 neu da du so vong lap CORDIC
        ----------------------------------------------------------------
        -- Cac tin hieu dieu khien gui sang Datapath
        Load_A        : OUT STD_LOGIC; -- Cho phep nap A_i vao A_reg
        Set_Error     : OUT STD_LOGIC; -- Bao loi khi A_i la so am
        Set_Zero      : OUT STD_LOGIC; -- Xu ly truong hop A_i = 0
        Norm_Low      : OUT STD_LOGIC; -- Chuan hoa khi A < 0.5
        Norm_High     : OUT STD_LOGIC; -- Chuan hoa khi A >= 2.0
        Init_XY       : OUT STD_LOGIC; -- Khoi tao X, Y va bien dem i
        Iter_Add      : OUT STD_LOGIC; -- Cap nhat CORDIC theo nhanh cong
        Iter_Sub      : OUT STD_LOGIC; -- Cap nhat CORDIC theo nhanh tru
        Gain_Correct  : OUT STD_LOGIC; -- Hieu chinh he so gain CORDIC
        Scale_Correct : OUT STD_LOGIC; -- Bu lai scale sau khi chuan hoa
        ----------------------------------------------------------------
        -- Tin hieu bao hoan thanh
        Done_o : OUT STD_LOGIC
    );
END Controller;

-- Phan nay mo ta hanh vi cua FSM bang process va case state:
ARCHITECTURE BEV OF Controller IS

    ----------------------------------------------------------------
    -- Khai bao kieu du lieu state_type
    -- FSM gom cac trang thai s0 den s14.
    -- Moi state tuong ung voi mot buoc trong thuat toan SQRTApprox.
    TYPE state_type IS (
        s0,   -- trang thai sau khi reset
        s1,   -- wait Start_i = 1
        s2,   -- nap A_i vao thanh ghi A_reg
        s3,   -- check A < 0 or A = 0
        s4,   -- check A co nam trong [0.5, 2) khong?
        s5,   -- neu A < 0.5 thi A = A * 4, scale = scale - 1
        s6,   -- neu A >= 2 thi A = A / 4, scale = scale + 1
        s7,   -- khoi tao X = A + 0.25, Y = A - 0.25, i = 1
        s8,   -- kiem tra da lap du ITER_MAX chua
        s9,   -- dung khi Y < 0
        s10,  -- dung khi Y >= 0
        s11,  -- hieu chinh he so CORDIC gain
        s12,  -- bu lai he so scale do qua trinh chuan hoa
        s13,  -- bao phep tinh hoan thanh
        s14   -- wait Start_i = 0 de tranh chay lai lien tuc
    );

    ----------------------------------------------------------------
    -- Thanh ghi trang thai hien tai cua FSM
    SIGNAL state : state_type;

BEGIN

    --------------------------------------------------------------------
    -- Process nay mo ta cach FSM chuyen trang thai.
    -- Reset duoc xu ly khong dong bo vi Reset nam trong sensitivity list
    -- va duoc kiem tra truoc rising_edge(CLK).
    -- Khi Reset = 1:
    --   state <= s0
    -- Khi co canh len CLK:
    --   FSM chuyen trang thai tuy theo state hien tai va cac tin hieu
    --   trang thai nhan tu Datapath.
    FSM : PROCESS (Reset, CLK)
    BEGIN
        ----------------------------------------------------------------
        -- Neu Reset = 1, dua FSM ve trang thai reset s0
        ----------------------------------------------------------------
        IF Reset = '1' THEN
            state <= s0;
        ----------------------------------------------------------------
        -- Neu khong reset, FSM chi chuyen trang thai tai canh len clock
        ELSIF rising_edge(CLK) THEN
        ----------------------------------------------------------------
            CASE state IS
                ----------------------------------------------------------------
                -- s0: Reset state
                -- Sau khi reset xong, FSM chuyen sang s1 de cho Start_i.
                WHEN s0 =>
                    state <= s1;
                ----------------------------------------------------------------
                -- s1: Wait start
                -- FSM dung o day cho den khi Start_i = 1.
                -- Neu Start_i = 1 thi bat dau phep tinh va sang s2.
                WHEN s1 =>
                    IF Start_i = '1' THEN
                        state <= s2;
                    ELSE
                        state <= s1;
                    END IF;
                ------------------------------------------------------------
                -- s2: Load input A
                -- state nay thi Controller se bat Load_A = 1.
                -- Datapath se nap A_i vao A_reg tai canh clock.
                -- Sau do FSM sang s3 de kiem tra A.
                WHEN s2 =>
                    state <= s3;
                ------------------------------------------------------------
                -- Kiem tra hai truong hop dac biet:
                --   1. A < 0  : khong tinh sqrt, bat Error
                --   2. A = 0  : ket qua sqrt = 0
                -- Neu gap mot trong hai truong hop nay thi sang done.
                -- Neu A hop le thi sang s4 de chuan hoa.
                WHEN s3 =>
                    IF A_Neg = '1' THEN
                        state <= s13;
                    ELSIF A_Zero = '1' THEN
                        state <= s13;
                    ELSE
                        state <= s4;
                    END IF;
                ------------------------------------------------------------
                -- Muc tieu la dua A ve khoang [0.5, 2).
                -- Neu A < 0.5:
                --   sang s5 de nhan A voi 4 va giam scale
                -- Neu A >= 2:
                --   sang s6 de chia A cho 4 va tang scale
                -- Neu A da nam trong [0.5, 2):
                --   sang s7 de khoi tao X, Y, i
                WHEN s4 =>
                    IF A_Lt_Half = '1' THEN
                        state <= s5;
                    ELSIF A_Ge_Two = '1' THEN
                        state <= s6;
                    ELSE
                        state <= s7;
                    END IF;
                ------------------------------------------------------------
                -- s5: Normalize low
                -- Controller bat Norm_Low = 1.
                -- Datapath thuc hien:
                --   A = A << 2  tuong duong A = A * 4
                --   scale = scale - 1
                -- Sau do quay ve s4 de kiem tra lai.
                WHEN s5 =>
                    state <= s4;
                ------------------------------------------------------------
                -- s6: Normalize high
                -- Controller bat Norm_High = 1.
                -- Datapath thuc hien:
                --   A = A >> 2  tuong duong A = A / 4
                --   scale = scale + 1
                -- Sau do quay ve s4 de kiem tra lai.
                WHEN s6 =>
                    state <= s4;
                ------------------------------------------------------------
                -- s7: Init X, Y, i
                -- Controller bat Init_XY = 1.
                -- Datapath thuc hien:
                --   X = A + 0.25
                --   Y = A - 0.25
                --   i = 1
                -- Sau do sang s8 de bat dau vong lap CORDIC.
                WHEN s7 =>
                    state <= s8;
                ------------------------------------------------------------
                -- s8: Check iteration
                -- Neu Iter_Done = 1, nghia la da lap du so vong CORDIC,
                -- FSM sang s11 de hieu chinh gain.
                -- Neu chua xong, FSM kiem tra dau cua Y:
                --   Y < 0  -> sang s9, dung nhanh cong
                --   Y >= 0 -> sang s10, dung nhanh tru
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
                ------------------------------------------------------------
                -- s9: CORDIC add iteration
                -- Controller bat Iter_Add = 1.
                -- Datapath cap nhat:
                --   X = X + (Y >> i)
                --   Y = Y + (X >> i)
                --   i = i + 1
                -- Sau do quay ve s8 de kiem tra tiep.
                WHEN s9 =>
                    state <= s8;
                ------------------------------------------------------------
                -- s10: CORDIC sub iteration
                -- Controller bat Iter_Sub = 1.
                -- Datapath cap nhat:
                --   X = X - (Y >> i)
                --   Y = Y - (X >> i)
                --   i = i + 1
                -- Sau do quay ve s8 de kiem tra tiep.
                WHEN s10 =>
                    state <= s8;
                ------------------------------------------------------------
                -- s11: Gain correction
                -- Controller bat Gain_Correct = 1.
                -- Datapath nhan X voi INV_K_Q16 de bu he so gain CORDIC.
                -- Sau do sang s12.
                WHEN s11 =>
                    state <= s12;
                ------------------------------------------------------------
                -- s12: Scale correction
                -- Controller bat Scale_Correct = 1.
                -- Datapath bu lai scale da tao ra trong buoc chuan hoa.
                -- Sau do sang s13 de bao done.
                WHEN s12 =>
                    state <= s13;
                ------------------------------------------------------------
                -- s13: Done
                -- Controller bat Done_o = 1.
                -- Trang thai nay bao rang SQRT_o va Error_o da hop le.
                -- Sau do sang s14 de cho Start_i ha xuong 0.
                WHEN s13 =>
                    state <= s14;
                ------------------------------------------------------------
                -- s14: Wait Start_i = 0
                -- Day la trang thai handshake.
                -- Neu Start_i van giu bang 1, FSM dung o s14.
                -- Khi Start_i = 0, FSM moi quay ve s1 de san sang phep tinh moi.
                WHEN s14 =>
                    IF Start_i = '0' THEN
                        state <= s1;
                    ELSE
                        state <= s14;
                    END IF;
                ------------------------------------------------------------
                -- Neu vi ly do nao do state bi loi, dua ve s0
                WHEN OTHERS =>
                    state <= s0;
                ------------------------------------------------------------
            END CASE;
        END IF;
    END PROCESS;

    --------------------------------------------------------------------
    -- FSM output logic
    -- Phan nay tao cac tin hieu dieu khien dua tren state hien tai.
    -- Moi tin hieu chi duoc bat len '1' o mot state tuong ung.
    -- Phan lon output chi phu thuoc vao state nen co tinh Moore.
    -- Rieng Set_Error va Set_Zero phu thuoc them A_Neg/A_Zero,
    -- nen co tinh Mealy.
    Load_A        <= '1' WHEN state = s2 ELSE '0'; -- Yeu cau Datapath nap A_i vao A_reg tai s2

    Set_Error     <= '1' WHEN state = s3 AND A_Neg = '1' ELSE '0';  -- Set_Error = 1 khi dang o s3 va A_Neg = 1,truong hop am

    Set_Zero      <= '1' WHEN state = s3 AND A_Zero = '1' ELSE '0'; -- Set_Zero = 1 khi dang o s3 va A_Zero = 1, truong hop = 0

    Norm_Low      <= '1' WHEN state = s5 ELSE '0'; -- Datapath thuc hien A = A * 4, scale = scale - 1 tai s5

    Norm_High     <= '1' WHEN state = s6 ELSE '0'; -- Datapath thuc hien A = A / 4, scale = scale + 1 tai s6

    Init_XY       <= '1' WHEN state = s7 ELSE '0'; -- Datapath khoi tao X, Y va i tai s7

    Iter_Add      <= '1' WHEN state = s9 ELSE '0';  -- Datapath cap nhat X/Y theo nhanh cong cua CORDIC tai s9, dung khi Y < 0

    Iter_Sub      <= '1' WHEN state = s10 ELSE '0'; -- Datapath cap nhat X/Y theo nhanh tru cua CORDIC TAI S10, dung khi Y >= 0 

    Gain_Correct  <= '1' WHEN state = s11 ELSE '0'; -- Datapath thuc hien hieu chinh he so gain CORDIC tai s11

    Scale_Correct <= '1' WHEN state = s12 ELSE '0'; -- Datapath bu lai he so scale sau khi chuan hoa A tai s12

    Done_o        <= '1' WHEN state = s13 ELSE '0'; -- Bao phep tinh da hoan thanh, output da hop le tai s13

END BEV;
