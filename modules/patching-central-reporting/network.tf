# =============================================================================
# 1. HUB NETWORK (VPC + TGW)
# =============================================================================

# Hub VPC (Where WSUS lives)
resource "aws_vpc" "hub_vpc" {
  cidr_block           = "10.100.0.0/16" # Distinct CIDR from Prod/Dev
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "CCS-Master-Hub-VPC" }
}

resource "aws_internet_gateway" "hub_igw" {
  vpc_id = aws_vpc.hub_vpc.id
  tags   = { Name = "CCS-Hub-IGW" }
}

resource "aws_subnet" "hub_public" {
  vpc_id                  = aws_vpc.hub_vpc.id
  cidr_block              = "10.100.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = { Name = "CCS-Hub-Public-Subnet" }
}

#TGW SUBNET (The "Ingress" Zone)
resource "aws_subnet" "hub_tgw_subnet" {
  vpc_id            = aws_vpc.hub_vpc.id
  cidr_block        = "10.100.2.0/24" # New CIDR for TGW Attachment
  availability_zone = "us-east-1a"
  tags = { Name = "CCS-Hub-TGW-Subnet" }
}

resource "aws_route_table_association" "hub_assoc" {
  subnet_id      = aws_subnet.hub_public.id
  route_table_id = aws_route_table.hub_public.id
}

# A. Route Table for the TGW Subnet (Ingress)
resource "aws_route_table" "hub_tgw_ingress" {
  vpc_id = aws_vpc.hub_vpc.id
  
  # Send Internet traffic to NAT
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.hub.id
  }
  
}

# This RT points 0.0.0.0/0 -> NAT Gateway, which is exactly what we need)
resource "aws_route_table_association" "tgw_assoc" {
  subnet_id      = aws_subnet.hub_tgw_subnet.id
  route_table_id = aws_route_table.hub_tgw_ingress.id
}

# 1. Allocate a Static IP (Elastic IP) for the NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
  
  tags = {
    Name = "CCS-Hub-NAT-EIP"
  }
}

# 2. Create the NAT Gateway itself
resource "aws_nat_gateway" "hub" {
  allocation_id = aws_eip.nat.id
  
  # IMPORTANT: This must be your PUBLIC Subnet ID in the Hub VPC
  subnet_id     = aws_subnet.hub_public.id 

  tags = {
    Name = "CCS-Hub-NAT-GW"
  }

  # Ensure the Internet Gateway exists before creating the NAT
  depends_on = [aws_internet_gateway.hub_igw] 
}

# =============================================================================
# 2. TRANSIT GATEWAY
# =============================================================================

resource "aws_ec2_transit_gateway" "hub_tgw" {
  description = "CCS-Patching-Backbone"
  auto_accept_shared_attachments = "enable"
  tags = { Name = "CCS-Org-TGW" }
}

# Attach Hub VPC to TGW
resource "aws_ec2_transit_gateway_vpc_attachment" "hub_attachment" {
  # FIX: Change this from hub_public.id to the new tgw_subnet.id
  subnet_ids         = [aws_subnet.hub_tgw_subnet.id]
  
  transit_gateway_id = aws_ec2_transit_gateway.hub_tgw.id
  vpc_id             = aws_vpc.hub_vpc.id
}

resource "aws_route_table" "hub_public" {
  vpc_id = aws_vpc.hub_vpc.id
  
  # Route to Internet (For WSUS to get updates from Microsoft)
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.hub_igw.id
  }

  # Route to Development Spoke (Return Traffic)
  route {
    cidr_block = "10.20.0.0/16" # Your Dev VPC CIDR
    transit_gateway_id = aws_ec2_transit_gateway.hub_tgw.id
  }
  
  tags = { Name = "CCS-Hub-Public-RT" }
}

resource "aws_ec2_transit_gateway_route" "hub_to_default_internet" {
  destination_cidr_block         = "0.0.0.0/0"
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.hub_attachment.id
  transit_gateway_route_table_id = aws_ec2_transit_gateway.hub_tgw.association_default_route_table_id
}

# =============================================================================
# 2b. RAM SHARING (Corrected)
# =============================================================================

# 2. Share TGW with Organization
resource "aws_ram_resource_share" "tgw_share" {
  name                      = "CCS-TGW-Org-Share"
  allow_external_principals = false # MUST be false when sharing with your own Org
}

resource "aws_ram_resource_association" "tgw_assoc" {
  resource_arn       = aws_ec2_transit_gateway.hub_tgw.arn
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}

resource "aws_ram_principal_association" "org_share" {
  # FIX: Use the ARN from the data source, not the variable var.org_id
  principal          = data.aws_organizations_organization.org.arn 
  resource_share_arn = aws_ram_resource_share.tgw_share.arn
}
