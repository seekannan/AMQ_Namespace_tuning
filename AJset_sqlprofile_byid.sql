CREATE OR REPLACE PROCEDURE SET_SQLPROFILE_BYID
(sql_id IN VARCHAR2,
 stmnt_id IN VARCHAR2,
 profile_name IN OUT VARCHAR2,
 category IN VARCHAR2 DEFAULT 'DEFAULT',
 force_matching IN BOOLEAN DEFAULT TRUE,
 Msg OUT VARCHAR2,
 debug IN BOOLEAN DEFAULT FALSE
)
 AUTHID CURRENT_USER
IS
 v_sqlid VARCHAR2(30) := sql_id;
 v_stmt_id VARCHAR2(30) := stmnt_id;
 v_profile_name VARCHAR2(50) ;
 v_category VARCHAR2(20) := category;
 v_fmatch BOOLEAN := force_matching;
 cl_sql_text CLOB;
 ar_profile_hints sys.sqlprof_attr;
 v_cnt NUMBER;
 CURSOR c_chk_plntbl (c_stmtid VARCHAR2) IS
 SELECT COUNT(1) FROM plan_table
 WHERE statement_id = c_stmtid
 AND other_xml is not null;
 CURSOR c_getoutline (c_stmtid VARCHAR2) IS
 SELECT
 extractvalue(value(d), '/hint') AS outline_hints
 FROM
 xmltable('/*/outline_data/hint'
 passing (
 SELECT
 xmltype(other_xml) as xmlval
 FROM
 plan_table
 WHERE
 statement_id = c_stmtid
 AND other_xml IS NOT NULL
 )
 ) d;
 v_PrgNm VARCHAR2(100) := 'SET_SQLPROFILE_BYID';
 v_Msg VARCHAR2(1000) ;	 
 CURSOR c_getsqltxt_cache (c_sqlid VARCHAR2 ) IS
 SELECT sql_fulltext INTO cl_sql_text
 FROM v$sql
 WHERE sql_id=c_sqlid
 AND last_active_time=( SELECT MAX(last_active_time) FROM v$sql WHERE sql_id = v_sqlid)
 AND ROWNUM <2;
 CURSOR c_getsqltxt_awr (c_sqlid VARCHAR2 ) IS
 SELECT sql_text INTO cl_sql_text
 FROM dba_hist_sqltext
 WHERE sql_id=c_sqlid
 AND ROWNUM <2;
 e_planid_notfound EXCEPTION;
 e_sqlid_notfound EXCEPTION;
BEGIN
 IF v_profile_name IS NULL THEN
    v_profile_name := 'PROF_'|| v_sqlid ||'_BYAUTOTUN' ;
 ELSIF v_profile_name IS NOT NULL THEN
    v_profile_name := profile_name;
	profile_name := '';
 END IF;
 /* Get Outline hint for sql_id*/  
 OPEN c_chk_plntbl (v_stmt_id) ;
 FETCH c_chk_plntbl INTO v_cnt;
 CLOSE c_chk_plntbl;
 IF v_cnt > 0 THEN
    v_Msg := 'Get Outline hint for statement_id: '|| v_stmt_id ;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    OPEN c_getoutline (v_stmt_id) ;
    FETCH c_getoutline BULK COLLECT INTO ar_profile_hints;
	CLOSE c_getoutline ;
 ELSE
    RAISE e_planid_notfound ;
 END IF;      
 /* Get sql text for sql_id */   
 OPEN c_getsqltxt_cache(v_sqlid);
 FETCH c_getsqltxt_cache into cl_sql_text;
 v_Msg := 'Get sql text for sql_id: '|| v_sqlid || ' cache. ' ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF c_getsqltxt_cache%NOTFOUND THEN
    OPEN c_getsqltxt_awr(v_sqlid);
    FETCH c_getsqltxt_awr into cl_sql_text;	
    v_Msg := 'Get sql text for sql_id: '|| v_sqlid || ' AWR. ' ;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    IF c_getsqltxt_awr%NOTFOUND THEN
       RAISE e_sqlid_notfound ;
    END IF;
 END IF;
 CLOSE c_getsqltxt_cache;
 IF c_getsqltxt_awr%ISOPEN THEN
    CLOSE c_getsqltxt_awr;
 END IF;   
 /* Create or update profile for sql_id */   
 v_Msg := 'Create or update  profile for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 dbms_sqltune.import_sql_profile(
 sql_text => cl_sql_text,
 profile => ar_profile_hints,
 category => v_category,
 name => v_profile_name,
 force_match => v_fmatch,
 replace => true
 );
 v_Msg := 'SQL Profile '||v_profile_name||' created.' ;
 write_log( v_PrgNm, v_Msg, debug) ;
 profile_name := v_profile_name ;
 Msg := v_PrgNm || ':' ||v_Msg ;
 dbms_output.put_line(' ');
 dbms_output.put_line('SQL Profile '||v_profile_name||' created.');
 dbms_output.put_line(' Validate sql_id :'||v_sqlid||' execution plan using @show_plan.');
 dbms_output.put_line(' ');   
EXCEPTION
   WHEN e_planid_notfound THEN
    v_Msg :='ERROR: Stetement id : '||v_stmt_id||' provided not found in PLAN_TABLE';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
	dbms_output.put_line(' ');
	write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN e_sqlid_notfound THEN
    v_Msg :='ERROR: SQL TEXT for sql_id: '||v_sqlid||' not found in AWR/CACHE.';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
	dbms_output.put_line(' ');
	write_log( v_PrgNm, v_Msg, debug) ;
	CLOSE c_getsqltxt_cache;
	CLOSE c_getsqltxt_awr;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN OTHERS THEN
    v_Msg := 'ERROR: as encountered - '||SQLCODE||' -ERROR- '||SQLERRM ;
    write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;	
    RAISE_APPLICATION_ERROR(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END SET_SQLPROFILE_BYID;
/