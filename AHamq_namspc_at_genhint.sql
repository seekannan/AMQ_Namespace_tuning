CREATE OR REPLACE PROCEDURE AMQ_NAMSPC_AT_GENHINT
(sql_id IN VARCHAR2,
 obj_owner OUT VARCHAR2,
 hint_text OUT VARCHAR2,
 conf_score OUT NUMBER,
 hint_flg OUT BOOLEAN,
 Msg OUT VARCHAR2,
 debug BOOLEAN DEFAULT FALSE)
AUTHID CURRENT_USER
IS
   v_debug BOOLEAN := debug ;
   v_sqlid VARCHAR2(30) := sql_id;
   TYPE t_phv_tab IS TABLE OF NUMBER ;
   v_phv_tab t_phv_tab;
   TYPE t_objowner_tab IS TABLE OF VARCHAR2(100) ;
   v_objowner_tab t_objowner_tab;
   v_sqldetails_tab tab_sqldetail_type;
   v_tab_cnt NUMBER;
   v_idx_cnt NUMBER;
   v_chk_cnt NUMBER :=0 ;
   v_conf_scr NUMBER := 0;
   v_tabNm VARCHAR2(128);
   v_tabNm_pre VARCHAR2(128);
   v_hint VARCHAR2(500) ;
   v_flg VARCHAR2(100) ;
   v_gen_hint_flg BOOLEAN :=FALSE;
   v_PrgNm VARCHAR2(100) := 'AMQ_NAMSPC_AT_GENHINT';
   v_Msg VARCHAR2(1000) ;
   v_out_Msg VARCHAR2(2000) ;
   CURSOR c_sqldet_cache (c_sqlid VARCHAR2) IS
   SELECT SQL_DETAIL_TYPE(sql_id , plan_hash_value, object#, object_owner , object_name , object_alias , object_type, options) FROM
   (SELECT DISTINCT sql_id , plan_hash_value, object#, object_owner , object_name , object_alias , object_type, options
   FROM v$sql_plan
   WHERE sql_id=c_sqlid
   AND ( object# IS NOT NULL
   AND object_owner IS NOT NULL
   AND object_name IS NOT NULL
   AND object_alias IS NOT NULL
   AND object_type IS NOT NULL )
   AND timestamp=(SELECT MAX(timestamp) FROM v$sql_plan WHERE sql_id = c_sqlid ));
   CURSOR c_sqldet_awr (c_sqlid VARCHAR2) IS
   SELECT SQL_DETAIL_TYPE(sql_id , plan_hash_value, object#, object_owner , object_name , object_alias , object_type, options) FROM
   (SELECT DISTINCT sql_id , plan_hash_value, object#, object_owner , object_name , object_alias , object_type, options
   FROM dba_hist_sql_plan
   WHERE sql_id=c_sqlid
   AND ( object# IS NOT NULL
   AND object_owner IS NOT NULL
   AND object_name IS NOT NULL
   AND object_alias IS NOT NULL
   AND object_type IS NOT NULL )
   AND timestamp=(SELECT MAX(timestamp) FROM dba_hist_sql_plan WHERE sql_id = c_sqlid ));
   tab_count_gt1 EXCEPTION;
   sqlid_notfound EXCEPTION;
   xp_has_noobj EXCEPTION;
BEGIN
   v_sqldetails_tab := tab_sqldetail_type() ;
   SELECT COUNT(1) INTO v_chk_cnt FROM v$sql_plan
   WHERE sql_id= v_sqlid
   AND ( object# IS NOT NULL
   AND object_owner IS NOT NULL
   AND object_name IS NOT NULL
   AND object_alias IS NOT NULL
   AND object_type IS NOT NULL );
   /* Gather SQL execution plan details */
   IF v_chk_cnt > 0 THEN
      v_Msg := 'Gather SQL execution plan details for sql_id: '|| v_sqlid || ' from CACHE';
      dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
      write_log( v_PrgNm, v_Msg, debug) ;
      OPEN c_sqldet_cache (v_sqlid);
      FETCH c_sqldet_cache BULK COLLECT INTO v_sqldetails_tab;
	  CLOSE c_sqldet_cache;
   ELSE
      SELECT COUNT(1) INTO v_chk_cnt FROM dba_hist_sql_plan
      WHERE sql_id=v_sqlid
       AND ( object# IS NOT NULL
       AND object_owner IS NOT NULL
       AND object_name IS NOT NULL
       AND object_alias IS NOT NULL
       AND object_type IS NOT NULL );
      IF v_chk_cnt > 0 THEN
         v_Msg := 'Gather SQL execution plan details for sql_id: '|| v_sqlid || ' from AWR';
         dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
         write_log( v_PrgNm, v_Msg, debug) ;	  
         OPEN c_sqldet_awr (v_sqlid);
         FETCH c_sqldet_awr BULK COLLECT INTO v_sqldetails_tab;
		 CLOSE c_sqldet_awr ;
      ELSE
         RAISE sqlid_notfound;
      END IF;
   END IF;
   /* Get plan hash value list for sqlid */
   SELECT DISTINCT plan_hash_value BULK COLLECT INTO v_phv_tab FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type ));
   v_Msg := 'Get plan hash value list for sqlid: '|| v_sqlid ;
   dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
   write_log( v_PrgNm, v_Msg, debug) ;
   FOR i in v_phv_tab.FIRST .. v_phv_tab.LAST
   LOOP
      EXIT WHEN v_gen_hint_flg ;
	  /* Get table owner list for given sql_id and PHV */
      SELECT DISTINCT object_owner  BULK COLLECT INTO v_objowner_tab FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type)) WHERE plan_hash_value=v_phv_tab(i);
      v_Msg := 'Get table owner list for given sql_id: '|| v_sqlid ||' and PHV: '|| v_phv_tab(i) ;
      dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
      write_log( v_PrgNm, v_Msg, debug) ;
      FOR j in v_objowner_tab.FIRST .. v_objowner_tab.LAST
      LOOP
         EXIT WHEN v_gen_hint_flg ;
         /* For given sql_id , PHV and owner get the table and index  count */
         v_Msg := 'For given sql_id:'|| v_sqlid ||' , PHV: '|| v_phv_tab(i) ||' and owner: '|| v_objowner_tab(j) || ' get table and index count' ;
         dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
         write_log( v_PrgNm, v_Msg, debug) ;	
         SELECT  COUNT(tbl_cnt)  INTO v_tab_cnt FROM
		 (SELECT DISTINCT object_name as tbl_cnt
          FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type))
          WHERE plan_hash_value=v_phv_tab(i)
            AND object_type ='TABLE'
           AND object_owner=v_objowner_tab(j)) ;
		 SELECT COUNT(idx_cnt) INTO v_idx_cnt FROM
		 (SELECT DISTINCT object_name as idx_cnt
          FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type))
          WHERE plan_hash_value=v_phv_tab(i)
          AND object_type LIKE 'INDEX%'
          AND object_owner=v_objowner_tab(j)) ;	 
         /* Verify if it is single table access execution plan */			 
         IF v_tab_cnt =1 THEN
            v_Msg := 'Single table access for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) || ' execution plan';
            dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
            write_log( v_PrgNm, v_Msg, debug) ;
			/* Get table name from execution plan detail */
			v_Msg := 'Get table name from  execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
            dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
            write_log( v_PrgNm, v_Msg, debug) ;
            SELECT object_name INTO v_tabNm FROM TABLE(cast (v_sqldetails_tab as tab_sqldetail_type))
            WHERE plan_hash_value=v_phv_tab(i)
            AND object_type ='TABLE'
            AND object_owner=v_objowner_tab(j) ;		
			v_tabNm_pre := v_tabNm ;		
            IF v_idx_cnt > 0 THEN
               IF v_idx_cnt = 1 THEN
                  v_Msg := 'Single table and index access in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
                  dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
                  write_log( v_PrgNm, v_Msg, debug) ;
			      /* Get table name from execution plan detail */
			      v_Msg := 'Get table name for the index in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
                  dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
                  write_log( v_PrgNm, v_Msg, debug) ;
                  SELECT  table_name INTO v_tabNm FROM dba_indexes
                  WHERE 
			      index_name=(SELECT DISTINCT  object_name  FROM TABLE (v_sqldetails_tab)
                              WHERE plan_hash_value=v_phv_tab(i)
                              AND object_type LIKE 'INDEX%'
                              AND object_owner=v_objowner_tab(j))
                  AND owner=v_objowner_tab(j) ;		 
                  IF v_tabNm <> v_tabNm_pre THEN
                     RAISE tab_count_gt1 ;
                  END IF;				  
               ELSIF v_idx_cnt > 1 THEN	
                  /* Loop through index_name and verify if they belong to same table */
                  v_Msg := 'Single table and Multiple indexes in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
                  dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
                  write_log( v_PrgNm, v_Msg, debug) ;
			      /* Verify if indexes belong to single table */	
                  FOR loop_idx in (SELECT DISTINCT  object_name  FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type))
                                   WHERE plan_hash_value=v_phv_tab(i)
                                   AND object_type LIKE 'INDEX%'
                                   AND object_owner=v_objowner_tab(j) )
                  LOOP
                     SELECT distinct table_name INTO v_tabNm FROM dba_indexes WHERE index_name=loop_idx.object_name and owner=v_objowner_tab(j) ;
                     IF v_tabNm <> v_tabNm_pre THEN
                        RAISE tab_count_gt1;
                     END IF;
                  END LOOP loop_idx;				  
			   END IF;
			   /* Call AMQ_GENERATE_HINT procedure to generate hint */
			   v_Msg := 'Call AMQ_GENERATE_HINT for sql_id: '|| v_sqlid || ' ,PHV: ' || v_phv_tab(i) ||' ,owner: '|| v_objowner_tab(j) || ' and tableNm: '|| v_tabNm;
               dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
               write_log( v_PrgNm, v_Msg, debug) ;
               AMQ_GENERATE_HINT(v_sqlid, v_phv_tab(i), v_objowner_tab(j),v_tabNm, v_sqldetails_tab, v_hint, v_conf_scr, v_gen_hint_flg, v_out_Msg, v_debug);
			   obj_owner := v_objowner_tab(j) ;
			   hint_text := v_hint;
               conf_score := v_conf_scr;
               hint_flg := v_gen_hint_flg;
               Msg := v_out_Msg ;				
			-- END IF;  
			      -- /* Call AMQ_GENERATE_HINT procedure to generate hint */
			      -- v_Msg := 'Call AMQ_GENERATE_HINT for sql_id: '|| v_sqlid || ' ,PHV: ' || v_phv_tab(i) ||' ,owner: '|| v_objowner_tab(j) || ' and tableNm: '|| v_tabNm;
                  -- dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
                  -- write_log( v_PrgNm, v_Msg, debug) ;
                  -- AMQ_GENERATE_HINT(v_sqlid, v_phv_tab(i), v_objowner_tab(j),v_tabNm, v_sqldetails_tab, v_hint, v_conf_scr, v_gen_hint_flg, v_out_Msg, v_debug);
			      -- obj_owner := v_objowner_tab(j) ;
			      -- hint_text := v_hint;
                  -- conf_score := v_conf_scr;
                  -- hint_flg := v_gen_hint_flg;
                  -- Msg := v_out_Msg ;	
			ELSIF v_idx_cnt = 0 THEN
			   v_Msg := 'Single table access for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) || ' execution plan';
               dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
               write_log( v_PrgNm, v_Msg, debug) ;
			   /* Call AMQ_GENERATE_HINT procedure to generate hint */
			   v_Msg := 'Call AMQ_GENERATE_HINT for sql_id: '|| v_sqlid || ' ,PHV: ' || v_phv_tab(i) ||' ,owner: '|| v_objowner_tab(j) || ' and tableNm: '|| v_tabNm;
               dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
               write_log( v_PrgNm, v_Msg, debug) ;
               AMQ_GENERATE_HINT(v_sqlid, v_phv_tab(i), v_objowner_tab(j),v_tabNm, v_sqldetails_tab, v_hint, v_conf_scr, v_gen_hint_flg, v_out_Msg, v_debug);
			   obj_owner := v_objowner_tab(j) ;
			   hint_text := v_hint;
               conf_score := v_conf_scr;
               hint_flg := v_gen_hint_flg;
               Msg := v_out_Msg ;				
			END IF;  
         ELSIF v_tab_cnt = 0 AND v_idx_cnt > 0 THEN
            /* For given sql_id , PHV and owner get the index count*/
            v_Msg := 'No table access in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
            dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
            write_log( v_PrgNm, v_Msg, debug) ;	
            -- SELECT  COUNT(1)  INTO v_idx_cnt FROM
            -- (SELECT DISTINCT object_name
             -- FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type))
             -- WHERE plan_hash_value=v_phv_tab(i)
              -- AND object_type LIKE 'INDEX%'
              -- AND object_owner=v_objowner_tab(j));
            v_Msg := ' For given sql_id:'|| v_sqlid ||' , PHV: '|| v_phv_tab(i) ||' and owner: '|| v_objowner_tab(j) || ' check index belong to same table' ;
            dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
            write_log( v_PrgNm, v_Msg, debug) ;			  
            /* Verify if it is single index access execution plan */
            IF v_idx_cnt = 1 THEN
               v_Msg := 'Single index in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
               dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
               write_log( v_PrgNm, v_Msg, debug) ;
               SELECT  table_name INTO v_tabNm FROM dba_indexes
               WHERE index_name=( SELECT DISTINCT  object_name  FROM TABLE (v_sqldetails_tab)
                               WHERE plan_hash_value=v_phv_tab(i)
                                AND object_type LIKE 'INDEX%'
                                AND object_owner=v_objowner_tab(j))
                      AND owner=v_objowner_tab(j) ;
            ELSIF v_idx_cnt > 1 THEN
               /* Loop through index_name and verify if they belong to same table */
               v_Msg := 'Multiple indexes in execution plan for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) ;
               dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
               write_log( v_PrgNm, v_Msg, debug) ;	
               v_chk_cnt :=1 ;
			   /* Verify if indexes belong to single table */	
               FOR loop_idx in ( SELECT DISTINCT  object_name  FROM TABLE (cast (v_sqldetails_tab as tab_sqldetail_type))
                              WHERE plan_hash_value=v_phv_tab(i)
                               AND object_type LIKE 'INDEX%'
                               AND object_owner=v_objowner_tab(j) )
               LOOP
                  SELECT distinct table_name INTO v_tabNm FROM dba_indexes WHERE index_name=loop_idx.object_name and owner=v_objowner_tab(j) ;
                  IF v_chk_cnt = 1 THEN
                     v_tabNm_pre := v_tabNm ;
                  END IF;
                  IF v_tabNm <> v_tabNm_pre THEN
                     RAISE tab_count_gt1   ;
                  END IF;
                  v_chk_cnt :=  v_chk_cnt + 1 ;
               END LOOP loop_idx;
            ELSE
               RAISE xp_has_noobj;
            END IF;
            v_Msg := 'Single table access for sql_id: '|| v_sqlid || ' and PHV: '|| v_phv_tab(i) || ' execution plan';
            dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
            write_log( v_PrgNm, v_Msg, debug) ;
            /* Call AMQ_GENERATE_HINT procedure to generate hint for SQL */			
            AMQ_GENERATE_HINT(v_sqlid, v_phv_tab(i), v_objowner_tab(j),v_tabNm, v_sqldetails_tab, v_hint, v_conf_scr, v_gen_hint_flg, v_out_Msg, v_debug);
			obj_owner := v_objowner_tab(j) ;
			hint_text := v_hint;
            conf_score := v_conf_scr;
            hint_flg := v_gen_hint_flg;
            Msg := v_out_Msg ;			
         ELSIF v_tab_cnt > 1 THEN
            RAISE tab_count_gt1;
         END IF;
      END LOOP;
   END LOOP;   
EXCEPTION
   WHEN tab_count_gt1 THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' accessing more than one table';      
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
	write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN sqlid_notfound THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' details not found in AWR/CACHE ' ;
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
	write_log( v_PrgNm, v_Msg, debug) ;
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN xp_has_noobj THEN
    v_Msg := 'ERROR: SQL: '||v_sqlid||' execution plan does not list objects';
    dbms_output.put_line(' ');
    dbms_output.put_line( v_PrgNm || ':' ||v_Msg ) ;
    dbms_output.put_line(' ');
	write_log( v_PrgNm, v_Msg, debug) ;	  
	Msg := v_PrgNm || ':' ||v_Msg ;
   WHEN OTHERS THEN
      RAISE_APPLICATION_ERROR(-20001,'An error was encountered - '||SQLCODE||' -ERROR- '||SQLERRM);
END AMQ_NAMSPC_AT_GENHINT;
/