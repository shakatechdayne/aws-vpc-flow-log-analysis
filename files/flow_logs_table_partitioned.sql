CREATE EXTERNAL TABLE IF NOT EXISTS ${flow_log_athena_table} (
Version INT,
Account STRING,
InterfaceId STRING,
SourceAddress STRING,
DestinationAddress STRING,
SourcePort INT,
DestinationPort INT,
Protocol INT,
Packets INT,
Bytes INT,
StartTime INT,
EndTime INT,
Action STRING,
LogStatus STRING,
NetworkAclId STRING,
SecurityGroupIds STRING
)
PARTITIONED BY (IngestDateTime STRING)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES ('input.regex' = '^([^ ]+)\\s+([0-9]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([0-9]+)\\s+([0-9]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)\\s+([^ ]+)$')
LOCATION 's3://${flow_log_bucket}/';