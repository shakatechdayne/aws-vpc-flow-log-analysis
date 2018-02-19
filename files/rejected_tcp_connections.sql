SELECT day_of_week(from_unixtime(starttime)) AS
  day,
  interfaceid,
  sourceaddress,
  action,
  protocol
FROM ${flow_log_athena_table}
WHERE action = 'REJECT' AND protocol = 6 AND ingestdatetime > '2017-01-01-01'
LIMIT 100;