LIBRARY ieee;
USE ieee.std_logic_1164.all;

ENTITY Regn IS
    GENERIC (
        N : INTEGER := 32
    );
    PORT (
        D : IN STD_LOGIC_VECTOR(N - 1 DOWNTO 0);
        Reset, Clk, En : IN STD_LOGIC;
        Q : OUT STD_LOGIC_VECTOR(N - 1 DOWNTO 0)
    );
END Regn;

ARCHITECTURE Behavior OF Regn IS
BEGIN

    PROCESS (Reset, Clk)
    BEGIN
        IF Reset = '1' THEN
            Q <= (OTHERS => '0');

        ELSIF rising_edge(Clk) THEN
            IF En = '1' THEN
                Q <= D;
            END IF;
        END IF;
    END PROCESS;

END Behavior;
