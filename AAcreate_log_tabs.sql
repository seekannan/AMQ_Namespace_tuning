/* create table to stored interim results for debugging purpose */

CREATE SEQUENCE prog_debug_interim_op_seq
START WITH 1000
INCREMENT BY 1
NOCYCLE;

CREATE TABLE prog_debug_interim_op
(id NUMBER DEFAULT prog_debug_interim_op_seq.NEXTVAL ,
 Prog_Nm VARCHAR2(100),
 sql_id VARCHAR2(30),
 sql_text clob,
created_time TIMESTAMP(6) DEFAULT SYSTIMESTAMP) ;

GRANT SELECT ON  sqlmon.prog_debug_interim_op TO PUBLIC ;
CREATE PUBLIC SYNONYM prog_debug_interim_op FOR sqlmon.prog_debug_interim_op;

/* create table to log execution details for debugging purpose */

CREATE SEQUENCE prog_debug_seq
START WITH 1000
INCREMENT BY 1
NOCYCLE;

CREATE TABLE prog_debug_log
(log_id NUMBER DEFAULT prog_debug_seq.NEXTVAL ,
 prog_name VARCHAR2(100),
 prog_stage VARCHAR2(1000),
 CREATED_TIME TIMESTAMP(6) DEFAULT SYSTIMESTAMP) ;
 
GRANT SELECT ON  sqlmon.prog_debug_log TO PUBLIC ;
CREATE PUBLIC SYNONYM prog_debug_log FOR sqlmon.prog_debug_log;

/* create table to hold sql_ids to be tuned and track tuning activity */

CREATE TABLE amq_sql_tuning
( sql_id VARCHAR2(30),
  obj_owner VARCHAR2(100),
  hint_text VARCHAR2(200),
  tuning_conf_scr NUMBER,
  hint_generated VARCHAR2(20) DEFAULT 'PENDING',
  sql_profile_name VARCHAR2(50) ,
  profile_created VARCHAR2(20) DEFAULT 'PENDING',
  proc_output_msg VARCHAR2(2000),
  created_time TIMESTAMP(6) DEFAULT SYSTIMESTAMP,
  last_update_time TIMESTAMP(6)
);
CREATE UNIQUE INDEX amq_sql_tuning_ux on amq_sql_tuning(sql_id) ;

GRANT SELECT ON  sqlmon.amq_sql_tuning TO PUBLIC ;
CREATE PUBLIC SYNONYM amq_sql_tuning FOR sqlmon.amq_sql_tuning;