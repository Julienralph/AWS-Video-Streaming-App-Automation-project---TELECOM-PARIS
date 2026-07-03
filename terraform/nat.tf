# ============================================================
# NAT Gateway
# ============================================================
# DESACTIVE : quota EIP us-east-1 atteint dans le compte SSO Telecom Paris.
# Le Streamer est deplace dans un subnet public (ec2-streamer.tf).
# A re-activer quand le quota EIP sera augmente par l'administrateur.
# ============================================================

/*
resource "aws_eip" "nat" {
  domain = "vpc"

  depends_on = [aws_internet_gateway.main]

  tags = {
    Name = "${local.name_prefix}-nat-eip"
  }
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_az_a.id

  tags = {
    Name = "${local.name_prefix}-nat-gw"
  }
}

resource "aws_route" "private_az_a_internet" {
  route_table_id         = aws_route_table.private_az_a.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route" "private_az_b_internet" {
  route_table_id         = aws_route_table.private_az_b.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}
*/
