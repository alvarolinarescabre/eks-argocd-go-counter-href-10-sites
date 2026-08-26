module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.3"

  name               = local.name_cluster
  kubernetes_version = local.cluster_version

  endpoint_public_access                   = true
  endpoint_public_access_cidrs             = ["${chomp(data.http.my_ip.response_body)}/32"]
  enable_cluster_creator_admin_permissions = true

  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  tags = {
    Environment = var.environment
    Terraform   = "true"
    Project     = "Chamo"
  }
}
