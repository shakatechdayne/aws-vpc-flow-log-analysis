module "vpc_flow_log_analysis_test" {
  source = "..\/"
  region = "${var.region}"
  flTags = "${var.tags}"
  flVpcId = "${var.vpcId}"
  flathenaPartType = "Hour"
}