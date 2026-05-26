LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY Regn IS
    GENERIC 
        N : INTEGER := 32 -- độ rộng thanh ghi
    );
    PORT (
        D : IN STD_LOGIC_VECTOR(N - 1 DOWNTO 0); -- dữ liệu đầu vào
        Reset, Clk, En : IN STD_LOGIC; -- dữ liệu đầu vào
        Q : OUT STD_LOGIC_VECTOR(N - 1 DOWNTO 0) -- dữ liệu đầu ra
    );
END Regn;

ARCHITECTURE Behavior OF Regn IS
BEGIN

    PROCESS (Reset, Clk) -- chương trình này chạy lại khi Reset hoặc Clk thay đổi
    BEGIN
        IF Reset = '1' THEN
            Q <= (OTHERS => '0'); -- Nếu reset bằng 1, Q về 0.

        ELSIF rising_edge(Clk) THEN
            IF En = '1' THEN
                Q <= D; -- Nếu enable bằng 1, nạp D vào Q,Nếu En = 0, thanh ghi giữ nguyên giá trị cũ.
            END IF;
        END IF;
    END PROCESS;

END Behavior;
