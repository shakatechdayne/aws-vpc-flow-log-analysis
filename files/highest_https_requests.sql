SELECT SUM(packets) AS
  packetcount,
  destinationaddress
FROM ${flow_log_athena_table}
WHERE destinationport = 443 AND ingestdatetime > '2017-01-01-01'
GROUP BY destinationaddress
ORDER BY packetcount DESC
LIMIT 10;