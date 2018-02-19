//
// Module: tf-vpc-flow-analysis
//

terraform {
  required_version = "0.11.2"
}

// VPC Flow Log
resource "aws_flow_log" "dp_flow_log_vpc" {
  count = "${var.flFootPrint == "vpc" ? 1 : 0}"
  iam_role_arn = "${aws_iam_role.dp_log_group_role.arn}"
  log_group_name = "${aws_cloudwatch_log_group.dp_log_group.name}"
  traffic_type = "${var.flTrafficType}"
  vpc_id = "${var.flVpcId}"
}

resource "aws_flow_log" "dp_flow_log_subnet" {
  count = "${var.flFootPrint == "subnet" ? 1 : 0}"
  iam_role_arn = "${aws_iam_role.dp_log_group_role.arn}"
  log_group_name = "${aws_cloudwatch_log_group.dp_log_group.name}"
  traffic_type = "${var.flTrafficType}"
  subnet_id = "${var.flSubnetId}"
}

resource "aws_flow_log" "dp_flow_log_eni" {
  count = "${var.flFootPrint == "eni" ? 1 : 0}"
  iam_role_arn = "${aws_iam_role.dp_log_group_role.arn}"
  log_group_name = "${aws_cloudwatch_log_group.dp_log_group.name}"
  traffic_type = "${var.flTrafficType}"
  eni_id = "${var.flEniId}"
}

// Cloudwatch Log Group to store flow logs
resource "aws_cloudwatch_log_group" "dp_log_group" {
  name = "${var.flLogGroupName}"
  tags = "${var.flTags}"
}

// Cloudwatch subscription filter
resource "aws_cloudwatch_log_subscription_filter" "dp_flow_log_destination" {
  name = "dp_log_group_lambda_stream_subscription"
  destination_arn = "${aws_lambda_function.dp_flow_log_exec_lambda.arn}"
  filter_pattern = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action, flowlogstatus]"
  log_group_name = "${aws_cloudwatch_log_group.dp_log_group.name}"
}

// Allow stream to lambda
resource "aws_lambda_permission" "dp_flow_log_to_lambda_perm" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.dp_flow_log_exec_lambda.function_name}"
  principal = "logs.${var.region}.amazonaws.com"
  statement_id = "AllowExecutionFromCloudWatch"
  source_arn = "${aws_cloudwatch_log_group.dp_log_group.arn}"
}

// Allow s3 notify lambda
resource "aws_lambda_permission" "dp_s3_notify_athena_partion_lambda_perm" {
  action = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.dp_athena_partition_exec_lambda.function_name}"
  principal = "s3.amazonaws.com"
  statement_id = "AllowExecutionFromS3"
  source_arn = "${aws_s3_bucket.dp_flow_log_bucket.arn}"
}

// Kinesis Firehose Stream
resource "aws_kinesis_firehose_delivery_stream" "dp_flow_log_firehose" {
  name = "dp_flow_logs_firehose"
  destination = "s3"

  s3_configuration {
    bucket_arn = "${aws_s3_bucket.dp_flow_log_bucket.arn}"
    role_arn = "${aws_iam_role.dp_firehose_role.arn}"
    buffer_size = 10
    buffer_interval = 400
    compression_format = "GZIP"
  }
}

// Lambda Flow Logs to Kinesis
resource "aws_lambda_function" "dp_flow_log_exec_lambda" {
  filename = "lambda.zip"
  source_code_hash = "${data.archive_file.lambda_zip.output_base64sha256}"
  function_name = "VPCFlowLogsToFirehose"
  handler = "lambdacode.lambda_handler"
  role = "${aws_iam_role.dp_iam_lambda_kinesis_exec_role.arn}"
  runtime = "python2.7"
  timeout = 300
  memory_size = 512

  environment {
    variables = {
      DELIVERY_STREAM_NAME = "${aws_kinesis_firehose_delivery_stream.dp_flow_log_firehose.name}"
    }
  }

  tags = "${var.flTags}"
}

// Lambda Partition Athena
resource "aws_lambda_function" "dp_athena_partition_exec_lambda" {
  filename = "${path.module}/files/partitioning_lambda/target/aws-lambda-athena-1.0.0.jar"
  source_code_hash = "${base64sha256(file("${path.module}/files/partitioning_lambda/target/aws-lambda-athena-1.0.0.jar"))}"
  function_name = "CreateAthenaPartitions"
  handler = "com.amazonaws.services.lambda.CreateAthenaPartitionsBasedOnS3Event::handleRequest"
  role = "${aws_iam_role.dp_iam_lambda_athena_exec_role.arn}"
  runtime = "java8"
  timeout = 30
  memory_size = 512

  environment {
    variables = {
      TABLE_NAME = "${aws_athena_database.dp_flow_log_athena_db.name}.${var.flAthenaDbTableName}"
      PARTITION_TYPE = "${var.flathenaPartType}"
      ATHENA_REGION = "${var.region}"
      S3_STAGING_DIR = "s3://aws-athena-query-results-${data.aws_caller_identity.current.account_id}-${var.region}/dp-vpc-flow-logs-athena"
    }
  }

  tags = "${var.flTags}"
}

// Flow Log Athena DB
resource "aws_athena_database" "dp_flow_log_athena_db" {
  name = "${var.flAthenaDbName}"
  bucket = "${aws_s3_bucket.dp_flow_log_bucket.bucket}"
  force_destroy = true
}

// Flow Log Athena Named Query Table
resource "aws_athena_named_query" "dp_flow_log_athena_table_query" {
  name = "${var.flAthenaDbTableQueryName}"
  database = "${aws_athena_database.dp_flow_log_athena_db.name}"
  query = "${data.template_file.athena_table.rendered}"
}

// Flow Log Athena Named Query Table Partitioned
resource "aws_athena_named_query" "dp_flow_log_athena_table_partitioned_query" {
  name = "${var.flAthenaDbPartTableQueryName}"
  database = "${aws_athena_database.dp_flow_log_athena_db.name}"
  query = "${data.template_file.athena_partitioned_table.rendered}"
}

// Terraform does not support creating tables. You can use AWS CLI to create a table,
// however you cannot guarantee the database will be available and ready until TF apply is complete.
// Therefore we create a Named Query so that you can initialise the table you want to use (partitioned or not).

/*resource "null_resource" "dp_flow_log_athena_partitioned_table" {
  provisioner "local-exec" {
    command = "aws athena start-query-execution --query-string \"${data.template_file.athena_partitioned_table.rendered}\" --result-configuration OutputLocation=\"s3://aws-athena-query-results-${data.aws_caller_identity.current.account_id}-${var.region}/dp-vpc-flow-logs-athena\""
  }
  depends_on = ["aws_athena_database.dp_flow_log_athena_db"]
}*/

// Flow Log Athena Named Query
resource "aws_athena_named_query" "dp_flow_log_athena_top_25_rejects_query" {
  name = "${var.flAthenaDbTop25RejectsQueryName}"
  database = "${aws_athena_database.dp_flow_log_athena_db.name}"
  query = "${data.template_file.athena_query_top_25_rejects.rendered}"
}

// Flow Log Athena Named Query
resource "aws_athena_named_query" "dp_flow_log_athena_rejected_tcp_connections_query" {
  name = "${var.flAthenaDbTCPRejectsQueryName}"
  database = "${aws_athena_database.dp_flow_log_athena_db.name}"
  query = "${data.template_file.athena_query_rejected_tcp_connections.rendered}"
}

// Flow Log Athena Named Query
resource "aws_athena_named_query" "dp_flow_log_athena_highest_https_requests_query" {
  name = "${var.flAthenaDbHTTPSRequestsQueryName}"
  database = "${aws_athena_database.dp_flow_log_athena_db.name}"
  query = "${data.template_file.athena_query_highest_https_requests.rendered}"
}

// S3 bucket
resource "aws_s3_bucket" "dp_flow_log_bucket" {
  bucket = "${var.flS3Bucket}"
  acl = "private"
  tags = "${var.flTags}"
  force_destroy = true
}

// S3 Notify Lambda
resource "aws_s3_bucket_notification" "dp_flow_log_lambda_notify" {
  bucket = "${aws_s3_bucket.dp_flow_log_bucket.id}"

  lambda_function {
    lambda_function_arn = "${aws_lambda_function.dp_athena_partition_exec_lambda.arn}"
    events = ["s3:ObjectCreated:*"]
  }
}

// IAM Role for VPC Flow Logs
resource "aws_iam_role" "dp_log_group_role" {
  name = "dp_flow_logs_role"
  assume_role_policy = "${data.aws_iam_policy_document.dp_iam_log_group_policy_assume_doc.json}"
}

// IAM Policy cloudwatch logs
resource "aws_iam_role_policy" "dp_iam_log_group_policy" {
  name = "dp_flow_logs_policy"
  policy = "${data.aws_iam_policy_document.dp_iam_policy_logs_doc.json}"
  role = "${aws_iam_role.dp_log_group_role.id}"
}

// IAM Role firehose
resource "aws_iam_role" "dp_firehose_role" {
  name = "dp_firehose_role"
  assume_role_policy = "${data.aws_iam_policy_document.dp_iam_firehose_policy_assume_doc.json}"
}

// IAM Policy firehose
resource "aws_iam_role_policy" "dp_iam_firehose_policy" {
  name = "dp_firehose_policy"
  policy = "${data.aws_iam_policy_document.dp_iam_policy_firehose_doc.json}"
  role = "${aws_iam_role.dp_firehose_role.id}"
}

// IAM Role Lambda Kinesis Exec
resource "aws_iam_role" "dp_iam_lambda_kinesis_exec_role" {
  name = "dp_lambda_kinesis_exec_role"
  assume_role_policy = "${data.aws_iam_policy_document.dp_iam_lambda_policy_assume_doc.json}"
}

// IAM Policy Lambda Kinesis Exec
resource "aws_iam_role_policy" "dp_iam_lambda_kinesis_exec_policy" {
  policy = "${data.aws_iam_policy_document.dp_iam_policy_lambda_doc.json}"
  role = "${aws_iam_role.dp_iam_lambda_kinesis_exec_role.id}"
}

// IAM Role Lambda Athena Exec
resource "aws_iam_role" "dp_iam_lambda_athena_exec_role" {
  name = "dp_lambda_athena_exec_role"
  assume_role_policy = "${data.aws_iam_policy_document.dp_iam_lambda_policy_assume_doc.json}"
}

// IAM Policy Lambda Athena Exec
resource "aws_iam_role_policy" "dp_iam_lambda_athena_exec_policy" {
  policy = "${data.aws_iam_policy_document.dp_iam_policy_lambda_athena_doc.json}"
  role = "${aws_iam_role.dp_iam_lambda_athena_exec_role.id}"
}

data "aws_caller_identity" "current" {}

data "archive_file" "lambda_zip" {
  type = "zip"
  source_dir = "${path.module}/lambda"
  output_path = "lambda.zip"
}

data "template_file" "athena_table" {
  template = "${file("${path.module}/files/flow_logs_table.sql")}"
  vars {
    flow_log_bucket = "${aws_s3_bucket.dp_flow_log_bucket.bucket}"
    flow_log_athena_table = "${var.flAthenaDbTableName}"

  }
}

data "template_file" "athena_partitioned_table" {
  template = "${file("${path.module}/files/flow_logs_table_partitioned.sql")}"
  vars {
    flow_log_bucket = "${aws_s3_bucket.dp_flow_log_bucket.bucket}"
    flow_log_athena_table = "${var.flAthenaDbTableName}"
  }
}

data "template_file" "athena_query_top_25_rejects" {
  template = "${file("${path.module}/files/top_25_rejects.sql")}"
  vars{
    flow_log_athena_table = "${var.flAthenaDbTableName}"
  }
}

data "template_file" "athena_query_rejected_tcp_connections" {
  template = "${file("${path.module}/files/rejected_tcp_connections.sql")}"
  vars{
    flow_log_athena_table = "${var.flAthenaDbTableName}"
  }
}

data "template_file" "athena_query_highest_https_requests" {
  template = "${file("${path.module}/files/highest_https_requests.sql")}"
  vars{
    flow_log_athena_table = "${var.flAthenaDbTableName}"
  }
}

data "aws_iam_policy_document" "dp_iam_log_group_policy_assume_doc" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "dp_iam_firehose_policy_assume_doc" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "dp_iam_lambda_policy_assume_doc" {
  statement {
    effect = "Allow"
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "dp_iam_policy_logs_doc" {
  statement {
    effect = "Allow"
    resources = ["*"]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]
  }
}

data "aws_iam_policy_document" "dp_iam_policy_firehose_doc" {
  statement {
    effect = "Allow"
    resources = ["${aws_s3_bucket.dp_flow_log_bucket.arn}"]
    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    effect = "Allow"
    resources = ["${aws_s3_bucket.dp_flow_log_bucket.arn}/*"]
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject"
    ]
  }
}

data "aws_iam_policy_document" "dp_iam_policy_lambda_doc" {
  statement {
    effect = "Allow"
    resources = ["arn:aws:logs:*:*:*"]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }

  statement {
    effect = "Allow"
    resources = ["${aws_kinesis_firehose_delivery_stream.dp_flow_log_firehose.arn}"]
    actions = [
      "firehose:PutRecordBatch"
    ]
  }

  statement {
    effect = "Allow"
    resources = ["*"]
    actions = [
      "ec2:Describe*"
    ]
  }
}

data "aws_iam_policy_document" "dp_iam_policy_lambda_athena_doc" {
  statement {
    effect = "Allow"
    resources = ["arn:aws:logs:*:*:*"]
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
  }
  statement {
    effect = "Allow"
    resources = ["*"]
    actions = [
      "athena:StartQueryExecution",
      "athena:RunQuery",
      "athena:GetQueryExecution",
      "athena:GetQueryExecutions",
      "athena:GetExecutionEngine",
      "athena:GetQueryResults",
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartitions",
      "glue:BatchCreatePartition",
      "glue:CreatePartition",
      "glue:DeletePartition",
      "glue:BatchDeletePartition",
      "glue:UpdatePartition",
      "glue:GetPartition",
    ]
  }
  statement {
    effect = "Allow"
    resources = ["arn:aws:s3:::aws-athena-query-results-*"]
    actions = [
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListMultipartUploadParts",
      "s3:AbortMultipartUpload",
      "s3:CreateBucket",
      "s3:PutObject"
    ]
  }
  statement {
    effect = "Allow"
    resources = ["${aws_s3_bucket.dp_flow_log_bucket.arn}"]
    actions = [
      "s3:ListBucket"
    ]
  }
  statement {
    effect = "Allow"
    resources = ["${aws_s3_bucket.dp_flow_log_bucket.arn}/*"]
    actions = [
      "s3:GetObject"
    ]
  }
}
