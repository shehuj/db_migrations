###############################################################################
# VPC + subnets
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count = length(var.public_subnet_cidrs)

  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = length(var.private_subnet_cidrs)

  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-${var.availability_zones[count.index]}"
    Tier = "private"
  })
}

###############################################################################
# NAT egress for private subnets (bastion package installs, RDS metadata)
###############################################################################

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-eip" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

###############################################################################
# Route tables
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(var.tags, { Name = "${var.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

###############################################################################
# Security groups
#
#   dev_db  : dev DB (public, SG-locked) — MySQL from allowed developer CIDRs
#   prod_db : prod DB (private)          — MySQL only from the SSM bastion
#   bastion : SSM jump host              — egress only
###############################################################################

resource "aws_security_group" "dev_db" {
  name        = "${var.name_prefix}-dev-db-sg"
  description = "Dev RDS (public, SG-locked)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-dev-db-sg" })
}

resource "aws_security_group" "prod_db" {
  name        = "${var.name_prefix}-prod-db-sg"
  description = "Prod RDS (private, bastion-only)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-prod-db-sg" })
}

resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-bastion-sg"
  description = "SSM bastion (egress only)"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-bastion-sg" })
}

# --- dev_db rules ------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "dev_mysql_from_devs" {
  count = length(var.dev_db_allowed_cidrs)

  security_group_id = aws_security_group.dev_db.id
  description       = "MySQL from allowed developer CIDRs"
  cidr_ipv4         = var.dev_db_allowed_cidrs[count.index]
  from_port         = var.db_port
  to_port           = var.db_port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "dev_all" {
  security_group_id = aws_security_group.dev_db.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- prod_db rules -----------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "prod_mysql_from_bastion" {
  security_group_id            = aws_security_group.prod_db.id
  description                  = "MySQL access from the SSM bastion (admin/Ansible via port forward)"
  referenced_security_group_id = aws_security_group.bastion.id
  from_port                    = var.db_port
  to_port                      = var.db_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "prod_all" {
  security_group_id = aws_security_group.prod_db.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- bastion rules -----------------------------------------------------------

resource "aws_vpc_security_group_egress_rule" "bastion_all" {
  security_group_id = aws_security_group.bastion.id
  description       = "Allow all outbound (SSM + reach the databases)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

###############################################################################
# SSM interface endpoints
#
# Keep the Session Manager control channel entirely inside the VPC (no internet
# path) so the private bastion can be managed without SSH or a public IP.
# NAT is still used for the host's package installs (apt), not for SSM.
###############################################################################

data "aws_region" "current" {}

resource "aws_security_group" "ssm_endpoints" {
  name        = "${var.name_prefix}-ssm-endpoints-sg"
  description = "HTTPS to SSM interface endpoints from within the VPC"
  vpc_id      = aws_vpc.this.id

  tags = merge(var.tags, { Name = "${var.name_prefix}-ssm-endpoints-sg" })
}

resource "aws_vpc_security_group_ingress_rule" "ssm_https" {
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "HTTPS from within the VPC (SSM agent)"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ssm_all" {
  security_group_id = aws_security_group.ssm_endpoints.id
  description       = "Allow all outbound"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_vpc_endpoint" "ssm" {
  for_each = toset(["ssm", "ssmmessages", "ec2messages"])

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.name}.${each.key}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-${each.key}-endpoint" })
}
