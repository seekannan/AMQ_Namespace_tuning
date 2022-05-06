CREATE OR REPLACE PROCEDURE  GEN_SQL_XP_OULTINE
( sql_id IN VARCHAR2,
  owner IN VARCHAR2,
  hint_text IN VARCHAR2,  
  stmt_id OUT VARCHAR2,
  Msg OUT VARCHAR2,
  debug IN BOOLEAN DEFAULT FALSE)
AUTHID CURRENT_USER
IS
 v_sqlid VARCHAR2(30) := sql_id;
 v_stmt_id VARCHAR2(30) ;
 cl_sql_text CLOB;
 cl_tmp CLOB  ;
 v_appnd_sql VARCHAR2(200) := 'Explain plan set statement_id=''';
 v_hint_text VARCHAR2(200) := hint_text;
 f_what VARCHAR2(10) :='SELECT ';
 v_owner VARCHAR2(128) := owner;
 v_replc_sql VARCHAR2(1000) ;
 v_sql VARCHAR2(4000) ;
 o_clob CLOB;
 l_sql PLS_INTEGER;
 l_what PLS_INTEGER;
 l_with PLS_INTEGER;
 n PLS_INTEGER;
 v_exc_owner VARCHAR2(128) ;
 v_flg VARCHAR2(20) ;
 v_cnt NUMBER := 0;
 v_PrgNm VARCHAR2(100) := 'GEN_SQL_XP_OULTINE';
 v_Msg VARCHAR2(1000) ;
 CURSOR c_val_owner_cache (c_sqlid VARCHAR2, c_owner VARCHAR2) IS
 SELECT  COUNT(1)
 FROM v$sql_plan
 WHERE sql_id=c_sqlid
 AND object_owner=c_owner
 AND timestamp=(SELECT MAX(timestamp) FROM v$sql_plan WHERE sql_id = c_sqlid )
 AND ROWNUM <2;
 CURSOR c_val_owner_awr (c_sqlid VARCHAR2, c_owner VARCHAR2) IS
 SELECT  COUNT(1)
 FROM dba_hist_sql_plan
 WHERE sql_id=c_sqlid
 AND object_owner=c_owner
 AND timestamp=(SELECT MAX(timestamp) FROM dba_hist_sql_plan WHERE sql_id = c_sqlid)
 AND ROWNUM <2;
 CURSOR c_getsqltxt_cache (c_sqlid VARCHAR2 ) IS
 SELECT sql_fulltext INTO cl_sql_text
 FROM v$sql
 WHERE sql_id=c_sqlid
 AND last_active_time=( select max(last_active_time) from v$sql where sql_id = v_sqlid)
 AND rownum <2;
 CURSOR c_getsqltxt_awr (c_sqlid VARCHAR2 ) IS
 SELECT sql_text INTO cl_sql_text
 FROM dba_hist_sqltext
 WHERE sql_id=c_sqlid
 AND rownum <2;
 e_owner_notfound EXCEPTION;
 e_sqlid_notfound EXCEPTION;
BEGIN
 /* Get current schema detail to revert to */
 select SYS_CONTEXT('USERENV','CURRENT_SCHEMA') into v_exc_owner from dual ;
 v_Msg := 'Get Current schema user: '|| v_exc_owner || ' to revert to post execution';
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 /* Get SQL TEXT for sql_id */
 v_flg := 'CACHE' ;
 OPEN c_getsqltxt_cache(v_sqlid);
 FETCH c_getsqltxt_cache into cl_sql_text;
 v_Msg := 'Get SQL text for sql_id : '|| v_sqlid || ' from CACHE';
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF c_getsqltxt_cache%NOTFOUND THEN
    v_flg := 'AWR' ;
    OPEN c_getsqltxt_awr(v_sqlid);
    FETCH c_getsqltxt_awr into cl_sql_text;
    v_Msg := 'Get SQL text for sql_id : '|| v_sqlid || ' from AWR';
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    IF c_getsqltxt_awr%NOTFOUND THEN
       RAISE e_sqlid_notfound ;
    END IF;
 END IF;
 /* Validate owner */
 IF v_flg = 'CACHE' THEN
    OPEN c_val_owner_cache(v_sqlid, v_owner);
    FETCH c_val_owner_cache into v_cnt;
    v_Msg := 'Validate if sql '|| v_sqlid ||' ran on schema: '|| v_owner || ' from CACHE';
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
 ELSIF v_flg = 'AWR' THEN
    OPEN c_val_owner_awr(v_sqlid, v_owner);
    FETCH c_val_owner_awr into v_cnt;
    v_Msg := 'Validate if sql '|| v_sqlid ||' ran on schema: '|| v_owner || ' from AWR';
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
 END IF;
 IF v_cnt=0 THEN
    RAISE e_owner_notfound ;
 END IF;
 /* Prepare SQL statement for execution plan */
 v_Msg := 'Prepare sql_id : '|| v_sqlid ||' for explain plan';
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 v_stmt_id := v_sqlid ;
 v_appnd_sql := v_appnd_sql || v_stmt_id || ''' into plan_table for ' ;
 cl_tmp := v_appnd_sql ;
 dbms_lob.append(cl_tmp,cl_sql_text) ;
 cl_sql_text :=cl_tmp;
 n := NVL( DBMS_LOB.INSTR(cl_sql_text,f_what,1,1),0 );
 l_sql  :=DBMS_LOB.GETLENGTH( cl_sql_text) ;
 l_what :=LENGTH( f_what );
 v_replc_sql :=f_what ||'/*+ ' ||v_hint_text || ' */ ';
 cl_tmp := v_replc_sql ;
 l_with :=DBMS_LOB.GETLENGTH( cl_tmp) ;
 IF debug  THEN
    INSERT INTO prog_debug_interim_op (Prog_Nm,sql_id,sql_text) VALUES (v_PrgNm, v_sqlid, cl_sql_text );
	COMMIT;
 END IF;
 --dbms_output.put_line(l_sql || ',' || l_with || ',' || n) ;
 DBMS_LOB.CREATETEMPORARY( o_clob, FALSE );
 IF n > 0 THEN
    IF n > 1 THEN
       DBMS_LOB.COPY( o_clob, cl_sql_text, n-1, 1, 1 );
    END IF;
    IF debug  THEN
       INSERT INTO prog_debug_interim_op (Prog_Nm,sql_id,sql_text) VALUES (v_PrgNm, v_sqlid, o_clob );
    END IF;
    IF l_with > 0 THEN
       DBMS_LOB.APPEND( o_clob, cl_tmp );
    END IF;
    IF n + l_what <= l_sql THEN
       DBMS_LOB.COPY( o_clob, cl_sql_text, l_sql - n - l_what + 1, n + l_with, n + l_what );
    END IF;
 END IF;
 IF debug  THEN
    INSERT INTO prog_debug_interim_op (Prog_Nm,sql_id,sql_text) VALUES (v_PrgNm, v_sqlid, o_clob );
	COMMIT;
 END iF;
 /* Generate explain plan for SQL statement */
 v_Msg := 'Generate Explain plan for sql_id : '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 v_sql:='alter session set current_schema='||v_owner ;
 execute immediate (v_sql);
 dbms_output.put_line(v_sql) ;
 v_sql := 'delete from plan_table where statement_id= '''|| v_stmt_id ||'''' ;
 execute immediate (v_sql);
 dbms_output.put_line(v_sql) ;
 stmt_id :='';
 execute immediate (o_clob) ;
 dbms_output.put_line(DBMS_LOB.SUBSTR(o_clob,1000,1)) ;
 v_flg := 'get_stmnt_id';
 dbms_output.put_line(v_flg);
 select distinct statement_id into v_stmt_id from plan_table where plan_id=  ( select max(plan_id) from plan_table )  ;
 dbms_output.put_line(v_stmt_id);
 /* Change current_schema back to */
 v_Msg := 'Change current_schema back to owner : '|| v_exc_owner ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 v_sql:='alter session set current_schema='||v_exc_owner ;
 execute immediate (v_sql);
 v_Msg := 'Outline Generate for sql_id: '|| v_sqlid ||' in plan_table.' ;
 dbms_output.put_line(' ');
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 dbms_output.put_line(' ');
 write_log( v_PrgNm, v_Msg, debug) ;
 stmt_id := v_stmt_id ;
 Msg := v_PrgNm || ':' ||v_Msg ;
EXCEPTION
   WHEN e_owner_notfound THEN
    v_Msg := 'ERROR: Owner: '|| v_owner ||' not found in AWR /CACHE for sql_id : '||v_sqlid ;
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
    v_sql:='alter session set current_schema='||v_exc_owner ;
    execute immediate (v_sql);
    Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN e_sqlid_notfound THEN
    v_Msg := 'ERROR: SQL text for sql_id: '||v_sqlid||' not found in AWR /CACHE.' ;
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
    v_sql:='alter session set current_schema='||v_exc_owner ;
    execute immediate (v_sql);
    Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN no_data_found THEN
    dbms_output.put_line(' ');
    IF v_flg = 'get_stmnt_id' THEN
       v_Msg := 'ERROR: Retreving statement_id  from PLAN_TABLE ';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
    END IF;
    dbms_output.put_line(' ');
	Msg := v_PrgNm || ':' ||v_Msg ; 
   WHEN OTHERS THEN
    v_Msg := 'ERROR: as encountered - '||SQLCODE||' -ERROR- '||SQLERRM ;
    write_log( v_PrgNm, v_Msg, debug) ;
    v_sql:='alter session set current_schema='||v_exc_owner ;
    execute immediate (v_sql);
    Msg := v_PrgNm || ':' ||v_Msg ;
    RAISE_APPLICATION_ERROR(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END GEN_SQL_XP_OULTINE;
/