CREATE OR REPLACE PROCEDURE AMQ_GENERATE_HINT
( sql_id IN VARCHAR2,
  plan_hash_value IN NUMBER,
  obj_owner IN VARCHAR2,
  tbl_name IN VARCHAR2,
  sqldetails_tab IN tab_sqldetail_type,
  hint_text OUT VARCHAR2,
  conf_score OUT NUMBER,
  hint_flg OUT BOOLEAN,
  Msg OUT VARCHAR2,
  debug IN BOOLEAN DEFAULT FALSE
)
AUTHID CURRENT_USER
IS
 v_sqlid VARCHAR2(30) := sql_id;
 v_plan_hash_value NUMBER := plan_hash_value;
 v_obj_owner VARCHAR2(100) := obj_owner;
 v_bind_cnt NUMBER;
 v_chk_cnt NUMBER :=0 ;
 v_chk_filterCr VARCHAR2(100) ;
 v_conf_scr NUMBER := 0;
 v_tabNm VARCHAR2(128) := tbl_name;
 v_idxNm VARCHAR2(30);
 v_objAlias VARCHAR2(261);
 v_hint VARCHAR2(500) ;
 v_flg VARCHAR2(100) ;
 v_tblIn VARCHAR2(50) :='AMQ%';
 v_hint_flg BOOLEAN :=FALSE;
 v_PrgNm VARCHAR2(100) := 'AMQ_GENERATE_HINT';
 v_Msg VARCHAR2(1000) ;
 v_dqtime_cnt NUMBER;
 cl_sql_text CLOB;
 cl_subsql_txt  CLOB;
 cl_psubsql_txt  CLOB;
 v_lsql NUMBER;
 v_lsubsql  NUMBER ;
 v_lpsubsql  NUMBER ;
 f_what VARCHAR2(10) :='DQ_TIME' ;
 l_offset NUMBER;
 l_ioffset NUMBER;
 v_exit_flg BOOLEAN;
 CURSOR c_getsqltxt_cache (c_sqlid VARCHAR2 ) IS
 SELECT upper(sql_fulltext) INTO cl_sql_text
 FROM v$sql
 WHERE sql_id=c_sqlid
 AND last_active_time=( SELECT MAX(last_active_time) FROM v$sql WHERE sql_id = v_sqlid)
 AND ROWNUM <2;
 CURSOR c_getsqltxt_awr (c_sqlid VARCHAR2 ) IS
 SELECT upper(sql_text) INTO cl_sql_text
 FROM dba_hist_sqltext
 WHERE sql_id=c_sqlid
 AND ROWNUM <2;
 CURSOR c_get_sqlbind_cache(c_sqlid VARCHAR2) IS
 SELECT AVG(bind_count) , AVG(dqtime_count) FROM
 (SELECT last_captured , COUNT(name) AS bind_count , SUM(dq_time) as dqtime_count FROM
  (SELECT last_captured , name , (CASE WHEN  name IN (':DQ_TIME',':DQ_TIME2') THEN 1 ELSE 0 END) as dq_time
   FROM v$sql_bind_capture WHERE  sql_id= c_sqlid AND was_captured='YES')
  GROUP BY last_captured );
 CURSOR c_get_sqlbind_awr(c_sqlid VARCHAR2) IS
 SELECT AVG(bind_count) , AVG(dqtime_count) FROM
 (SELECT last_captured , COUNT(name) AS bind_count , SUM(dq_time) as dqtime_count FROM
  (SELECT last_captured , name , (CASE WHEN  name IN (':DQ_TIME',':DQ_TIME2') THEN 1 ELSE 0 END) as dq_time
   FROM dba_hist_sqlbind WHERE  sql_id= c_sqlid AND was_captured='YES')
  GROUP BY last_captured );
 dqtime_not_in_pred EXCEPTION;
 no_filter_criteria EXCEPTION;
 table_not_amq EXCEPTION;
 sqlid_notfound EXCEPTION;
BEGIN
 /* Verify if it is AMQ table_name */
 v_Msg := 'Verify table name starts with AMQ';
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF v_tabNm NOT LIKE v_tblIn  THEN
    RAISE table_not_amq;
 END IF;
 /* Get sql text for sql_id from CACHE */
 OPEN c_getsqltxt_cache(v_sqlid);
 FETCH c_getsqltxt_cache into cl_sql_text;
 v_Msg := 'Get sql text for sql_id: '|| v_sqlid || ' cache. ' ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF c_getsqltxt_cache%NOTFOUND THEN
    /* Get sql text for sql_id from AWR */
    OPEN c_getsqltxt_awr(v_sqlid);
    FETCH c_getsqltxt_awr into cl_sql_text;
    v_Msg := 'Get sql text for sql_id: '|| v_sqlid || ' AWR. ' ;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    IF c_getsqltxt_awr%NOTFOUND THEN
       RAISE sqlid_notfound ;
    END IF;
 END IF;
 CLOSE c_getsqltxt_cache;
 IF c_getsqltxt_awr%ISOPEN THEN
    CLOSE c_getsqltxt_awr;
 END IF;
 /* Check for predicate */
 v_Msg := 'Check if sql_id: '|| v_sqlid || ' has predicate clause' ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 v_lsql := DBMS_LOB.GETLENGTH(cl_sql_text);
 l_offset := DBMS_LOB.INSTR(cl_sql_text,'WHERE',1,1);
 IF l_offset = 0 THEN
    RAISE no_filter_criteria;
 END IF;
 /* Gather predicate details from sql */
 v_Msg := 'Gather predicate details for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF DBMS_LOB.INSTR(cl_sql_text,'GROUP BY', l_offset,1) > 0 THEN
    v_lsubsql  := DBMS_LOB.INSTR(cl_sql_text,'GROUP BY', 1,1) - l_offset;
 ELSIF DBMS_LOB.INSTR(cl_sql_text,'ORDER BY', l_offset,1) > 0 THEN
    v_lsubsql  := DBMS_LOB.INSTR(cl_sql_text,'ORDER BY', 1,1) - l_offset;
 ELSE
    v_lsubsql  := v_lsql - l_offset;
 END IF;
 IF v_lsubsql  > 32765 THEN
    v_lpsubsql  := 32765 ;
    dbms_lob.createtemporary(cl_subsql_txt , FALSE);
    l_ioffset := l_offset;
    LOOP
     dbms_output.put_line( ' total sub-string length: '|| v_lsubsql  ) ;
     dbms_output.put_line( 'offset: '|| l_offset || ' part-sub-string length: '|| v_lpsubsql );
     cl_psubsql_txt  := DBMS_LOB.SUBSTR(cl_sql_text, v_lpsubsql , l_offset);
     dbms_lob.append(cl_subsql_txt ,cl_psubsql_txt ) ;
     IF v_exit_flg THEN
        EXIT;
     END IF;
     l_offset := v_lpsubsql  + l_offset;
     IF v_lsubsql - l_offset + l_ioffset> 32765 THEN
            v_lpsubsql  := 32765 ;
     ELSE
        v_lpsubsql  :=  v_lsubsql  - l_offset + l_ioffset;
                v_exit_flg := TRUE ;
     END IF;
    END LOOP;
 ELSE
    dbms_output.put_line( ' total sub-string length: '|| v_lsubsql );
    dbms_output.put_line( 'offset: '|| l_offset );
    cl_subsql_txt  := DBMS_LOB.SUBSTR(cl_sql_text,v_lsubsql ,l_offset );
 END IF;
 IF DEBUG THEN
    INSERT INTO prog_debug_interim_op (Prog_Nm,sql_id,sql_text) VALUES (v_PrgNm, v_sqlid, cl_subsql_txt );
    COMMIT;
 END IF;
 /* Check if DQ_TIME column is used in filter predicate */
 v_Msg := 'Check if DQ_TIME column is used in filter predicate for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF DBMS_LOB.INSTR(cl_subsql_txt ,f_what)=0 THEN
    RAISE dqtime_not_in_pred ;
 END IF;
 /* Get DQ_TIME column filter criteria */
 v_Msg := 'Get DQ_TIME column filter criteria for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 cl_sql_text := cl_subsql_txt ;
 v_lsql := DBMS_LOB.GETLENGTH(cl_sql_text);
 l_offset := DBMS_LOB.INSTR(cl_sql_text,f_what,1,1);
 v_lpsubsql := DBMS_LOB.INSTR(cl_sql_text,'AND',l_offset,1) ;
 v_lpsubsql := v_lpsubsql + length('AND') + 1 - l_offset ;
 dbms_output.put_line( ' part sub-string length: '|| v_lpsubsql  ) ;
 dbms_output.put_line( 'offset: '|| l_offset );
 cl_psubsql_txt  := DBMS_LOB.SUBSTR(cl_sql_text, v_lpsubsql , l_offset );
 IF DEBUG THEN
    INSERT INTO prog_debug_interim_op (Prog_Nm,sql_id,sql_text) VALUES (v_PrgNm, v_sqlid, cl_psubsql_txt );
    COMMIT;
 END IF;
 /* Check if DQ_TIME filter criteria has upper,lower limits */
 v_Msg := 'Check if DQ_TIME filter criteria has upper,lower limits for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 IF DBMS_LOB.INSTR(cl_psubsql_txt ,'BETWEEN',1,1)>0 THEN
    v_chk_filterCr := 'U-L_limit' ;
        v_conf_scr := 60 ;
        dbms_output.put_line( 'DQ_TIME filter criteria has '|| v_chk_filterCr || ' Setting confidence score: ' || v_conf_scr );
 ELSE
        v_chk_filterCr := 'Undefined_limit' ;
        v_conf_scr := 20 ;
        dbms_output.put_line( 'Validate DQ_TIME filter criteria has '|| v_chk_filterCr || ' Setting confidence score: ' || v_conf_scr );
 END IF;
 /* Get Bind variable count */
 v_Msg := 'Get avg count of Bind values passed for sql_id: '|| v_sqlid;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 OPEN c_get_sqlbind_cache (v_sqlid);
 FETCH c_get_sqlbind_cache INTO v_bind_cnt,v_dqtime_cnt;
 IF c_get_sqlbind_cache%NOTFOUND THEN
    OPEN c_get_sqlbind_awr (v_sqlid);
    FETCH c_get_sqlbind_awr INTO v_bind_cnt,v_dqtime_cnt;
    IF c_get_sqlbind_awr%NOTFOUND THEN
           v_Msg := 'Bind values not captured for sql_id: '|| v_sqlid;
           dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
           write_log( v_PrgNm, v_Msg, debug) ;
    END IF;
 END IF;
 CLOSE c_get_sqlbind_cache ;
 IF c_get_sqlbind_awr%ISOPEN THEN
    CLOSE c_get_sqlbind_awr;
 END IF;
 IF v_bind_cnt > 6 AND v_bind_cnt < 15 THEN
    v_conf_scr := v_conf_scr + 15 ;
 ELSIF v_bind_cnt >= 15 THEN
     v_conf_scr := v_conf_scr + 30 ;
 END IF;
 /* Get DQ_TIME index for the table*/
 v_Msg := 'Get DQTIME index name for the table: '|| v_tabNm;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 v_flg := 'get_dq_idx' ;
 SELECT index_name INTO v_idxNm FROM dba_ind_columns
 WHERE table_name = v_tabNm
 AND table_owner = v_obj_owner
 AND column_name = UPPER('DQ_TIME')
 AND column_position=1;
 /* Get Table alias and generate hint */
 v_Msg := 'Get table alias from sql stmmnt: '|| v_sqlid ||' and table: '||v_tabNm;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 SELECT NVL(REPLACE( SUBSTR(object_alias,1,INSTR(object_alias,'@')-1 ), '"','' ),'NO-ALIAS')
 INTO v_objAlias
 FROM TABLE(cast (sqldetails_tab as tab_sqldetail_type))
 WHERE plan_hash_value=v_plan_hash_value
 AND (object_type ='TABLE' OR object_type LIKE 'INDEX%' )
 --AND OBJECT_NAME = v_tabNm
 AND object_owner = v_obj_owner
 AND rownum<2;
 IF v_objAlias = 'NO-ALIAS' THEN
    v_Msg := 'Generate hint for sql_id: '|| v_sqlid ||' and table: '||v_tabNm;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    v_hint_flg := TRUE ;
    v_hint := ' USE_INVISIBLE_INDEXES(' || v_tabNm ||' '|| v_idxNm || ') ' ;
    -- dbms_output.put_line( 'EXEC GEN_SQL_XP_OULTINE( '''|| v_sqlid ||''', '''|| v_obj_owner ||''', '''||v_hint || ''' );' ) ;
    -- dbms_output.put_line( 'EXEC SET_SQLPROFILE_BYID ( '''|| v_sqlid ||''' );' ) ;
 ELSE
    v_Msg := 'Generate hint for sql_id: '|| v_sqlid ||' and table: '||v_tabNm;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
    v_hint_flg := TRUE ;
    v_hint := ' USE_INVISIBLE_INDEXES(' || v_objAlias ||' '|| v_idxNm || ') ' ;
    -- dbms_output.put_line( 'EXEC GEN_SQL_XP_OULTINE( '''|| v_sqlid ||''', '''|| v_obj_owner ||''', '''||v_hint || ''' );' ) ;
    -- dbms_output.put_line( 'EXEC SET_SQLPROFILE_BYID ( '''|| v_sqlid ||''' );' ) ;
 END IF;
 /* Assign values to output variables */
 v_Msg := 'Assign values to output variables for sql_id: '|| v_sqlid ;
 dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
 write_log( v_PrgNm, v_Msg, debug) ;
 hint_text := v_hint ;
 conf_score := v_conf_scr ;
 hint_flg :=v_hint_flg ;
 IF hint_flg THEN
    v_Msg := 'Hint '|| v_hint ||' generated for sql_id: '|| v_sqlid ||' with confidence score of:'||v_conf_scr;
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;
 END IF;
EXCEPTION
   WHEN sqlid_notfound THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' details not found in AWR/CACHE ' ;
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
    CLOSE c_getsqltxt_cache;
    CLOSE c_getsqltxt_awr;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN dqtime_not_in_pred THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' filter predicate does not have DQ_TIME column';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN no_filter_criteria THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' does not have filter criteria';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
    CLOSE c_get_sqlbind_cache ;
    CLOSE c_get_sqlbind_awr ;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN table_not_amq THEN
    v_Msg :='ERROR: Table: '||v_tabNm||' is not part of AMQ';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
    write_log( v_PrgNm, v_Msg, debug) ;
    Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN no_data_found THEN
    dbms_output.put_line(' ');
    IF v_flg = 'get_dq_idx' THEN
       v_Msg := 'ERROR: Table: '||v_tabNm||' does not have DQ_TIME index';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
    END IF;
    dbms_output.put_line(' ');
	Msg := v_PrgNm || ':' ||v_Msg ;  
END AMQ_GENERATE_HINT;
/