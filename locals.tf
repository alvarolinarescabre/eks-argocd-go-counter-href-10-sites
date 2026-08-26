locals {

  # General Information
  name = "${var.project_name}-${var.environment}"

  # EKS Cluster Information
  name_cluster     = "${local.name}-cluster"
  cluster_version  = var.cluster_version
  ami_type         = "AL2_x86_64"
  node_groups_name = "${local.name}-ng"

  # VPC Information
  name_vpc        = "${local.name}-vpc"
  cidr            = var.vpc_cidr
  azs             = slice(data.aws_availability_zones.available.names, 0, 3)
  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # My Public IP
  my_ip = "${chomp(data.http.my_ip.response_body)}/32"
}
