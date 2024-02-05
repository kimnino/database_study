SET GLOBAL log_bin_trust_function_creators = 1;
-- log_bin_trust_function_creators 옵션은 MySQL이 function, trigger 생성에 대한 제약을 강제할 수 있는 기능

CREATE FUNCTION  GET_NAME (
    V_PLAYER_ID INTEGER
) RETURNS VARCHAR(20)
BEGIN
   DECLARE NAME_TITLE VARCHAR(20);
   SELECT P.NAME INTO NAME_TITLE FROM PLAYER P WHERE player_id = V_PLAYER_ID;
   RETURN NAME_TITLE;
END