module "network" {
  source = "../../modules/network_compared"
  avai_zones = data.aws_availability_zones.available.names
  env_deploy = var.env_deploy
  project_name = var.project_name
  vpc_cidr = var.vpc_cidr
  single_nat_gateway = var.single_nat_gateway
}