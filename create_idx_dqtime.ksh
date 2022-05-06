tbl_Nm=${1}
for schema_name in `echo ${2} | sed '1,$s/,/ /g'`
do
sqlplus -s '/ as sysdba' <<EOF

--select count(1) as ${schema_name}_${tbl_Nm} from ${schema_name}.${tbl_Nm}  where rownum < 1;
alter session set current_schema=${schema_name} ;

create index ${tbl_Nm}_IDX1 on ${tbl_Nm} (DQ_TIME, SUBQUEUE_ID, MESSAGE_TYPE, MESSAGE_ID, PARTITION_ID)
TABLESPACE DATA01_LM
initrans 20 storage(pctincrease 0 freelists 23 freelist groups 17) online invisible local parallel 8;

alter index ${tbl_Nm}_IDX1 noparallel;

EOF
done;