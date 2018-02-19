variable "region" { type = "string" }
variable "flLogGroupName" { type = "string", default = "dp_flow_logs_log_group"}
variable "flTrafficType" { type = "string", default = "ALL" }
variable "flVpcId" { type = "string", default = "" }
variable "flSubnetId" { type = "string", default = "" }
variable "flEniId" { type = "string", default = "" }
variable "flFootPrint" { type = "string", default = "vpc"}
variable "flS3Bucket" { type = "string", default = "dp-flow-log-bucket" }
variable "flAthenaDbName" { type = "string", default = "dp_flow_log_athena_db" }
variable "flAthenaDbTableName" { type = "string", default = "vpc_flow_logs" }
variable "flAthenaDbTableQueryName" { type = "string", default = "dp_flow_log_table_query" }
variable "flAthenaDbPartTableQueryName" { type = "string", default = "dp_flow_log_part_table_query" }
variable "flAthenaDbTop25RejectsQueryName" { type = "string", default = "dp_flow_log_top_25_rejects_query" }
variable "flAthenaDbTCPRejectsQueryName" { type = "string", default = "dp_flow_log_tcp_rejected_connections_query" }
variable "flAthenaDbHTTPSRequestsQueryName" { type = "string", default = "dp_flow_log_highest_https_requests_query" }
variable "flathenaPartType" { type = "string", default = "Day" }
variable "flTags" { type = "map" }