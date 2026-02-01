
# =============================================================================
# 3. WSUS SERVER (Windows 2022)
# =============================================================================

resource "aws_security_group" "wsus_sg" {
  name        = "CCS-WSUS-SG"
  description = "Allow Port 8530 from Internal Networks"
  vpc_id      = aws_vpc.hub_vpc.id

  ingress {
    description = "Patch Traffic from Dev"
    from_port   = 8530
    to_port     = 8530
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/16"] 
  }
  
  ingress {
    description = "RDP Admin"
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict in real prod
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"] 
  }
}

# The Instance
# resource "aws_instance" "wsus_server" {
#   ami           = data.aws_ami.windows_2022.id # Win Server 2022
#   instance_type = "t3.large"
#   key_name      = "wsuskey"
#   subnet_id     = aws_subnet.hub_public.id
#   vpc_security_group_ids = [aws_security_group.wsus_sg.id]
#   iam_instance_profile   = aws_iam_instance_profile.wsus_profile.name
  
#   tags = { Name = "CCS-Master-WSUS" }

#   user_data = <<EOF
# <powershell>
# Install-WindowsFeature -Name UpdateServices -IncludeManagementTools
# New-Item -Path "C:\WSUS" -ItemType Directory -Force
# </powershell>
# EOF
# }


# resource "aws_instance" "wsus_server" {
#   ami           = data.aws_ami.windows_2022.id
#   instance_type = "t3.large"
#   key_name      = "-----BEGIN RSA PRIVATE KEY-----\nMIIEpAIBAAKCAQEAu3rGyKcRnu4o4DfXWeymFpvj2NPG5wl7gnBKN+znjVVBjQWl\nyhVEZAuE7x/5DVi3kbsSzUcDftHV6YTQkEXsA773BvB6+OIxgcblwhndhxDSm/bf\neEik4q64ihIcZoRk93LqofjzCmANadM9nA2xgaJvdWKHTCnxPBcfny+6Yw0nzUQ6\nMW8YbO4FNfUb6KG5MCA5SaKKafMGTptkmfe8+Ar7Q68IjdaftsMSIoquqQHSCvSL\nSrifbXH69Gww5oYFMA22ZW96Oomkl2tnmYRfB2vgkDuQyZi3GqYzm6tEbd+GOKst\nnFEqt2+vgVX+3ft5FUUDAlbwW8WDqRwbOPfDUwIDAQABAoIBAATJ7A3wBokyuCSS\nCJQpcUyeisFdF3WLTnZUe/DVwkxf4x7BCC0TQf30NV8OSARJQdcdGivYJoS0w2wF\nknY88vxdgl3RArMcw/r2o6PDmV771QVa1vZxlJSdteUA9WzA8PtJGiks/LhFH9KW\nLLqxttkC1yn+bEpLv/ey94HPbElfX3W4zA+eSTrl1hHVtajW9GI+6te7dg6Pbpts\nQyYppWzPZvz9oI92BPP9IGtEo/ydAAljKcg3vdGygIJmyhZJTbzKt0T2oWvgVSVD\nLUZezRkQANNd2palV0ma60G6LIeHRvbOPHk8dCRmyRZ6x3bWNeXe3rIQ6wMwGMHk\nyKo4pBECgYEA3G2K3hL2plh6AbPs6KVp6SLG4Rd/Kd+b8BXczyfckjrM+YgQYB08\naY+V9vxGvGrjOiIJY1qovn4e3zPfCWCMChll408uOkmRrrqwG7w5Deadufp3JzgG\n5mywyaNfUNq1LmSh/Sw/03zMnizL+oo0E3A3CnNneBed2eET0BnsFg0CgYEA2bwN\ngMIMp7qswTAYyzApQB341X8qv/aw1FUOUwKnT62EYlKeHWplipFLoQ2ikbTyJSe9\ntfLjN+IfsXuJGoNRJUgidnZO9FFZrW/MV45fR1yVlbTcRp/0ncNWPOkXTic6emCL\nl+WuCH5lDrCfISLkV0HXIu3PMK4d4l2qT44tRt8CgYAdCHCZ/3VtQ4oOX1x86Ayj\nIGmBjE67fTBU1wxWXLG4sPX+h+VgQ3mJjdf6yA+pEYsMRR9nbrF7JbF7RKHD4muP\niPjaj7tPAhGmKgC4Jnp9UjrEHDFFgSOnhfljFZmgVK44hhiv9/wQJwfsbYoQXdOu\nG8GkJr8iGjo4UGUDq+ZkoQKBgQCxoKm/Zg9e8nqm7C797F9qsEjlG2Zrzrv5rR4P\neHW4Gc2LTO0zAC6wedIiJHaAugZla2NoQSs+1tmWODrkh0a2zH9Y9zF4PbmUNUWW\nFE8Eb7KUvESL1UiBP+9lp57cokIhvguDsttkkICvGEXpiYaQ7OSu2SUTCKjWmCUt\n28ZyLwKBgQCMDnE+tB+DsVOvIn6vdqjR8Qm6YZZKo+qkhRypEi7vdSS1xSAtaYRt\n3Hq9i6kzmk092pLXAaliiS3gxPYFWQllE/X8xfsZ3mFL26NvEtmOlM7EtUtQdmF3\noUjCf5kWptMG/pUBXKDLlkTqE0L7GAT5HG3idAtAOsvwQIrEFf4xhw==\n-----END RSA PRIVATE KEY-----\n"
#   # ... rest of config ...
# }