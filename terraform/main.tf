provider "aws" {
  region = "us-west-2"
}

# VPC
resource "aws_vpc" "loadtest_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "LoadTestVPC"
  }
}

# Subnet in us-west-2a (10.0.1.0/24)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.loadtest_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true   # IMPORTANT: ensure public IP assignment
  tags = {
    Name = "PublicSubnetA"
  }
}

# Subnet in us-west-2b (10.0.2.0/24) - non-overlapping range
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.loadtest_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true   # already set, ensuring public IP assignment
  tags = {
    Name = "PublicSubnetB"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.loadtest_vpc.id
}

# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.loadtest_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
}

# Associate subnets with the public route table
resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}


# Updated Security Group for Load Tester
resource "aws_security_group" "api_sg" {
  name        = "api-security-group"
  description = "Allow API, SSH, Grafana and Prometheus"
  vpc_id      = aws_vpc.loadtest_vpc.id

  ingress {
    description = "API on port 8000"
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Grafana on port 3000"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH on port 22"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key Pair (we assume you already have ~/.ssh/id_ed25519 + id_ed25519.pub)
resource "aws_key_pair" "load_test_key" {
  key_name   = "load_test_key"
  public_key = file("~/.ssh/id_ed25519.pub")  # Path to your PUBLIC key
}

# API Server in us-west-2a
resource "aws_instance" "api_server" {
  ami                   = "ami-00c257e12d6828491"  # Ubuntu 22.04 LTS
  instance_type         = "t3.micro"
  subnet_id             = aws_subnet.public_a.id  # us-west-2a
  vpc_security_group_ids = [aws_security_group.api_sg.id]
  key_name              = aws_key_pair.load_test_key.key_name  # use same key

  credit_specification {
    cpu_credits = "standard"
  }

  user_data = <<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y docker.io
              systemctl start docker
              systemctl enable docker
              docker run -d -p 8000:8000 --name api csherman42/t3_micro_test:latest
              EOF

  tags = {
    Name = "API-Server"
  }
}

# Updated Load Tester with Automated Setup
resource "aws_instance" "load_tester" {
  ami           = "ami-00c257e12d6828491"
  instance_type = "c5.large"
  subnet_id     = aws_subnet.public_b.id
  vpc_security_group_ids = [aws_security_group.api_sg.id]
  key_name      = aws_key_pair.load_test_key.key_name

  user_data = <<-EOF
            #!/bin/bash
            set -ex
            apt-get update
            apt-get install -y docker.io docker-compose
            
            # Clone configs
            git clone https://github.com/christophersherman/aws_loadtesting.git /loadtest
            cd /loadtest
            
            # Set API endpoint
            echo "GET http://${aws_instance.api_server.private_ip}:8000/test" > vegeta-targets.txt
            
            # Start services
            docker-compose up -d
            
            # Wait for Grafana
            timeout 120 bash -c 'while ! curl -s http://localhost:3000; do sleep 5; done'
            EOF

  tags = {
    Name = "Load-Tester"
  }
}

# Grafana URL output
output "grafana_url" {
  value = "http://${aws_instance.load_tester.public_ip}:3000/dashboards"
}

# Outputs
output "api_endpoint" {
  description = "Private IP endpoint for the API inside the VPC"
  value       = "http://${aws_instance.api_server.private_ip}:8000/test"
}

output "api_server_ssh" {
  description = "SSH command for the API server"
  value       = "ssh ubuntu@${aws_instance.api_server.public_ip}"
}

output "load_tester_ssh" {
  description = "SSH command for the load tester"
  value       = "ssh ubuntu@${aws_instance.load_tester.public_ip}"
}
