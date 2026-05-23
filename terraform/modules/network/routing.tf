#--------------------------------------------------------------
# Route Table: Public (→ IGW)
#--------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-public"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = local.az_map

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

#--------------------------------------------------------------
# Route Tables: Private (→ NAT Gateway) — per AZ
#--------------------------------------------------------------
resource "aws_route_table" "private" {
  for_each = local.az_map

  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-private-${each.value}"
  })
}

resource "aws_route" "private_nat" {
  for_each = local.az_map

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? keys(local.nat_az_map)[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = local.az_map

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}

#--------------------------------------------------------------
# Route Table: Data (local only — NO internet access)
#--------------------------------------------------------------
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-data"
  })
}

resource "aws_route_table_association" "data" {
  for_each = local.az_map

  subnet_id      = aws_subnet.data[each.key].id
  route_table_id = aws_route_table.data.id
}

#--------------------------------------------------------------
# Route Tables: Mgmt (→ NAT Gateway) — per AZ
# Separate route tables enable future NACL/routing differences
#--------------------------------------------------------------
resource "aws_route_table" "mgmt" {
  for_each = local.az_map

  vpc_id = aws_vpc.this.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-rt-mgmt-${each.value}"
  })
}

resource "aws_route" "mgmt_nat" {
  for_each = local.az_map

  route_table_id         = aws_route_table.mgmt[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? keys(local.nat_az_map)[0] : each.key].id
}

resource "aws_route_table_association" "mgmt" {
  for_each = local.az_map

  subnet_id      = aws_subnet.mgmt[each.key].id
  route_table_id = aws_route_table.mgmt[each.key].id
}
