SELECT count(*) cnt, sourceaddress, destinationport, networkaclid, securitygroupids
FROM ${flow_log_athena_table}
WHERE action = 'REJECT' and ingestdatetime > '2017-01-01-01'
GROUP BY sourceaddress, destinationport, networkaclid, securitygroupids
ORDER BY cnt desc
LIMIT 25;