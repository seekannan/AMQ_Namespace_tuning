CREATE OR REPLACE PROCEDURE AMQ_NAMESPACE_AUTO_TUNING
(
 gen_hint_flg IN BOOLEAN,
 cr_sql_profile IN BOOLEAN,
  debug IN BOOLEAN DEFAULT FALSE)
AUTHID CURRENT_USER
IS
 v_sqlid VARCHAR2(30) ;
 v_debug BOOLEAN := debug ;
 TYPE t_sqlid_tab IS TABLE OF VARCHAR2(30) ;
 v_sqlid_tab t_sqlid_tab;
 v_sqliddetails_tab tab_sqliddetails_type;
 v_obj_owner VARCHAR2(100) ;
 v_sqlid_cnt NUMBER := 0;
 v_chk_cnt NUMBER :=0 ;
 v_conf_scr NUMBER := 0;
 v_hint VARCHAR2(500) ;
 v_stmt_id VARCHAR2(30) ;
 v_profile_name VARCHAR2(50) ;
 v_flg VARCHAR2(20) ;
 v_gen_hint_flg BOOLEAN :=FALSE;
 v_PrgNm VARCHAR2(100) := 'AMQ_NAMESPACE_AUTO_TUNING';
 v_Msg VARCHAR2(1000) ;
 v_out_Msg VARCHAR2(2000) ;
 CURSOR get_sqlids_to_genhint  IS
 SELECT sql_id 
 FROM amq_sql_tuning
 WHERE hint_generated ='PENDING';
 CURSOR get_sqlids_to_crprofile  IS
 SELECT SQLIDDETAILS_TYPE (sql_id , obj_owner, hint_text) FROM
 (SELECT sql_id , obj_owner, hint_text 
  FROM amq_sql_tuning
  WHERE hint_generated ='COMPLETED'
  AND profile_created='PENDING');
  no_sqlid_found EXCEPTION;
BEGIN
 /* Check if generate hint flag is set */
 IF gen_hint_flg  THEN
    SELECT COUNT(sql_id) INTO v_sqlid_cnt
    FROM amq_sql_tuning
    WHERE hint_generated ='PENDING';
	IF v_sqlid_cnt > 0 THEN
       v_Msg := 'Get sql_ids for generating hint';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
       OPEN get_sqlids_to_genhint ;
       FETCH get_sqlids_to_genhint BULK COLLECT INTO v_sqlid_tab;
	   CLOSE get_sqlids_to_genhint;
	ELSE
	   v_Msg := 'No sql_ids found for generating hint';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
	   RAISE no_sqlid_found;
	END IF;
    /* Generate Hint for sql_ids */
    FOR i in v_sqlid_tab.FIRST .. v_sqlid_tab.LAST
	LOOP
	   AMQ_NAMSPC_AT_GENHINT(v_sqlid_tab(i), v_obj_owner, v_hint, v_conf_scr,v_gen_hint_flg,v_out_Msg, v_debug);
	   IF v_gen_hint_flg THEN
	      v_chk_cnt := 1;
	   ELSE
	      v_chk_cnt := 0;	   
	   END IF;
	   v_flg :='upd_gen_hint';
	   UPDATE amq_sql_tuning 
	   SET obj_owner = v_obj_owner,
	       hint_text = v_hint ,
	       tuning_conf_scr = v_conf_scr,
		   hint_generated = CASE WHEN v_chk_cnt = 1 THEN 'COMPLETED' ELSE 'FAILED' END,
		   proc_output_msg = v_out_Msg, 
		   last_update_time = SYSTIMESTAMP
	   WHERE sql_id = v_sqlid_tab(i) ;
	   COMMIT;
	END LOOP;
 END IF;   
 /* Initialize variables */
 v_flg := '' ;
 v_sqlid_cnt := 0;
 v_sqliddetails_tab :=tab_sqliddetails_type() ;
 v_chk_cnt := 0;
 /* Check if create profile is set */
 IF cr_sql_profile  THEN
    SELECT COUNT(sql_id) INTO v_sqlid_cnt
    FROM amq_sql_tuning
    WHERE hint_generated ='COMPLETED'
    AND profile_created='PENDING';
	IF v_sqlid_cnt > 0 THEN
       v_Msg := 'Get sql_ids for creating profile';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
       OPEN get_sqlids_to_crprofile ;
       FETCH get_sqlids_to_crprofile BULK COLLECT INTO v_sqliddetails_tab;
	   CLOSE get_sqlids_to_crprofile;
	ELSE
	   v_Msg := 'No sql_ids found for creating profile';
       dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
       write_log( v_PrgNm, v_Msg, debug) ;
	   RAISE no_sqlid_found;
	END IF;
    /* Create profile for sql_ids */
    FOR j in v_sqliddetails_tab.FIRST .. v_sqliddetails_tab.LAST
	LOOP
	   /* Call GEN_SQL_XP_OULTINE procedure to generate outline data */
	   GEN_SQL_XP_OULTINE ( v_sqliddetails_tab(j).sql_id, v_sqliddetails_tab(j).obj_owner , v_sqliddetails_tab(j).hint_text ,  v_stmt_id, v_out_Msg, v_debug) ;
	   IF v_stmt_id IS NOT NULL THEN
	      /* Call SET_SQLPROFILE_BYID to create or update profile with outline data for sql_id */
		  v_sqlid := v_sqliddetails_tab(j).sql_id ;
		  SET_SQLPROFILE_BYID ( v_sqlid , v_stmt_id, v_profile_name, 'DEFAULT', TRUE, v_out_Msg, v_debug) ;
		  IF v_profile_name IS NOT NULL THEN
		  	 v_chk_cnt := 1;
			 v_flg :='upd_cr_profile';
	         UPDATE amq_sql_tuning 
	         SET sql_profile_name = v_profile_name,
		         profile_created = CASE WHEN v_chk_cnt = 1 THEN 'COMPLETED' ELSE 'FAILED' END,
		         proc_output_msg = v_out_Msg, 
		         last_update_time = SYSTIMESTAMP
	         WHERE sql_id = v_sqliddetails_tab(j).sql_id ;
	         COMMIT;		  
		  END IF;
	   END IF;
	END LOOP;
 END IF;
  
EXCEPTION
   WHEN no_sqlid_found THEN     
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
   WHEN OTHERS THEN
    IF v_flg ='upd_gen_hint' OR v_flg ='upd_cr_profile' THEN
       v_Msg := 'ERROR: encountered at '|| v_flg||' - '||SQLCODE||' -ERROR- '||SQLERRM ;
	ELSE
       v_Msg := 'ERROR: encountered - '||SQLCODE||' -ERROR- '||SQLERRM ;	
	END IF;
    write_log( v_PrgNm, v_Msg, debug) ;
    RAISE_APPLICATION_ERROR(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END AMQ_NAMESPACE_AUTO_TUNING;
/