# ============================================================
# VPC - Réseau principal
# ============================================================

locals {
  name_prefix = "gin208"
  az_a        = "${var.aws_region}a" # us-east-1a
  az_b        = "${var.aws_region}b" # us-east-1b
}

# enable_dns_hostnames est requis pour SSM Session Manager et les points de montage EFS.
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

# ============================================================
# Internet Gateway
# ============================================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# ============================================================
# Subnets publics
# ============================================================
# 0.0.0.0/0 → IGW.
# On en crée 2 (AZ-a et AZ-b) : l'ALB et les EFS Mount Targets exigent 2 AZ minimum.

resource "aws_subnet" "public_az_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_az_a_cidr
  availability_zone = local.az_a

  # Les instances lancées ici reçoivent une IP publique automatiquement.
  # Utile pour debug. Les instances de prod s'appuient sur l'ALB, pas sur leur IP.
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-az-a"
  }
}

resource "aws_subnet" "public_az_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_az_b_cidr
  availability_zone = local.az_b

  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-az-b"
  }
}

# ============================================================
# Subnets privés
# ============================================================
# Pas de route vers Internet. Tout trafic sortant passe par le NAT Gateway (nat.tf).

resource "aws_subnet" "private_az_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_az_a_cidr
  availability_zone = local.az_a

  tags = {
    Name = "${local.name_prefix}-private-az-a"
  }
}

resource "aws_subnet" "private_az_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_az_b_cidr
  availability_zone = local.az_b

  tags = {
    Name = "${local.name_prefix}-private-az-b"
  }
}

# ============================================================
# Route Table publique (partagée entre les 2 subnets publics)
# ============================================================
# Route table = liste de règles de routage.
# 0.0.0.0/0 → IGW : tout le trafic vers Internet sort par l'IGW.
# La route locale (10.0.0.0/16 → local) est créée automatiquement par AWS.

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

resource "aws_route_table_association" "public_az_a" {
  subnet_id      = aws_subnet.public_az_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az_b" {
  subnet_id      = aws_subnet.public_az_b.id
  route_table_id = aws_route_table.public.id
}

# ============================================================
# Route Tables privées (une par AZ)
# ============================================================
# Dans nat.tf, chaque route table privée pointera vers le NAT GW de SA propre AZ.
# La route 0.0.0.0/0 → NAT GW sera ajoutée dans nat.tf.

resource "aws_route_table" "private_az_a" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-private-az-a"
  }
}

resource "aws_route_table" "private_az_b" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-rt-private-az-b"
  }
}

resource "aws_route_table_association" "private_az_a" {
  subnet_id      = aws_subnet.private_az_a.id
  route_table_id = aws_route_table.private_az_a.id
}

resource "aws_route_table_association" "private_az_b" {
  subnet_id      = aws_subnet.private_az_b.id
  route_table_id = aws_route_table.private_az_b.id
}

# ============================================================
# VPC Flow Logs → CloudWatch
# ============================================================
# DESACTIVE : necessite iam:CreateRole, non autorise dans ce compte SSO.
# ============================================================

/*
resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/flowlogs/${local.name_prefix}"
  retention_in_days = 30

  tags = {
    Name = "${local.name_prefix}-vpc-flow-logs"
  }
}

resource "aws_iam_role" "vpc_flow_logs" {
  name = "${local.name_prefix}-vpc-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "vpc_flow_logs" {
  name = "${local.name_prefix}-vpc-flow-logs-policy"
  role = aws_iam_role.vpc_flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.vpc_flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = {
    Name = "${local.name_prefix}-flow-log"
  }
}
*/
