CREATE OR REPLACE PROCEDURE write_log (Prg_Name VARCHAR2 , Message VARCHAR2 , Debug_Flag BOOLEAN)
AS 
   PRAGMA AUTONOMOUS_TRANSACTION;
   v_tblNm VARCHAR2(100) :='prog_debug_log' ;
BEGIN
   IF Debug_Flag THEN
     INSERT INTO prog_debug_log (prog_name,prog_stage) VALUES (Prg_Name, Message) ;
	 COMMIT;
   ELSE
     NULL;
   END IF;
EXCEPTION
   WHEN OTHERS THEN
     DBMS_OUTPUT.PUT_LINE(' ');
     DBMS_OUTPUT.PUT_LINE('ERROR: error occured in writing log in to '|| v_tblNm ||' table') ;
     DBMS_OUTPUT.PUT_LINE(' ');
     RAISE_APPLICATION_ERROR(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM); 
END write_log;
/