CREATE OR REPLACE PROCEDURE GET_TOP_AMQ_SQL ( days NUMBER)
AUTHID CURRENT_USER
IS
 v_days NUMBER := days ;
 CURSOR c_get_sqlid (c_days NUMBER) 
 IS
 SELECT sql_id 
 FROM sqlmon.pypl_topq_sql_profile@sqlmon_perfmon
 WHERE ( instance_name, host_name) = ( SELECT instance_name , host_name FROM v$instance )
 AND statday BETWEEN SYSDATE - c_days AND SYSDATE 
 AND sql_text like '%AMQ%'
 AND sql_text not like '%DECLARE%' ; 
BEGIN
 FOR sqlrec in c_get_sqlid (v_days)
 LOOP
  BEGIN
   INSERT INTO amq_sql_tuning (sql_id) VALUES (sqlrec.sql_id);
   COMMIT;
  EXCEPTION
   WHEN DUP_VAL_ON_INDEX THEN
    dbms_output.put_line ('sql_id: '|| sqlrec.sql_id ||' already in amq_sql_tuning table' ) ;
	CONTINUE;
  END;
 END LOOP;
END GET_TOP_AMQ_SQL;
/