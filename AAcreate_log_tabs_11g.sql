/* create table to stored interim results for debugging purpose */

CREATE SEQUENCE prog_debug_interim_op_seq
START WITH 1000
INCREMENT BY 1
NOCYCLE;

CREATE TABLE prog_debug_interim_op
(id NUMBER NOT NULL ,
 Prog_Nm VARCHAR2(100),
 sql_id VARCHAR2(30),
 sql_text clob,
created_time TIMESTAMP(6) DEFAULT SYSTIMESTAMP) ;

GRANT SELECT ON  sqlmon.prog_debug_interim_op TO PUBLIC ;
CREATE PUBLIC SYNONYM prog_debug_interim_op FOR sqlmon.prog_debug_interim_op;

CREATE OR REPLACE TRIGGER bfr_interim_ins
  BEFORE INSERT 
  ON prog_debug_interim_op
  FOR EACH ROW
  WHEN (new.id is null)
DECLARE
  v_id prog_debug_interim_op.id%TYPE;
BEGIN
  SELECT prog_debug_interim_op_seq.nextval INTO v_id FROM DUAL;
  :new.id := v_id;
END bfr_debug_ins;
/

/* create table to log execution details for debugging purpose */

CREATE SEQUENCE prog_debug_seq
START WITH 1000
INCREMENT BY 1
NOCYCLE;

CREATE TABLE prog_debug_log
(log_id NUMBER NOT NULL ,
 prog_name VARCHAR2(100),
 prog_stage VARCHAR2(500),
 CREATED_TIME TIMESTAMP(6) DEFAULT SYSTIMESTAMP) ;
 
GRANT SELECT ON  sqlmon.prog_debug_log TO PUBLIC ;
CREATE PUBLIC SYNONYM prog_debug_log FOR sqlmon.prog_debug_log;

CREATE OR REPLACE TRIGGER bfr_debug_ins
  BEFORE INSERT 
  ON prog_debug_log
  FOR EACH ROW
  WHEN (new.log_id is null)
DECLARE
  v_id prog_debug_log.log_id%TYPE;
BEGIN
  SELECT prog_debug_seq.nextval INTO v_id FROM DUAL;
  :new.log_id := v_id;
END bfr_debug_ins;
/
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

GRANT SELECT ON  sqlmon.amq_sql_tuning TO PUBLIC ;
CREATE PUBLIC SYNONYM amq_sql_tuning FOR sqlmon.amq_sql_tuning;