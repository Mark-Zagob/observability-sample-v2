#--------------------------------------------------------------
# Elastic IPs for NAT Gateways
#--------------------------------------------------------------
resource "aws_eip" "nat" {
  for_each = local.nat_az_map

  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-eip-${each.value}"
  })

}

#--------------------------------------------------------------
# NAT Gateways
#--------------------------------------------------------------
resource "aws_nat_gateway" "this" {
  for_each = local.nat_az_map

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-${each.value}"
  })

  depends_on = [aws_internet_gateway.this]
}
