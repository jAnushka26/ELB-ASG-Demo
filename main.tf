provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "demo-bucket-anushka26"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

#Subnets

resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet1"
  }
}

resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "subnet2"
  }

}

#Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

#Route Table
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

#Associate Route Table with Subnets
resource "aws_route_table_association" "rta1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.rt.id
}
resource "aws_route_table_association" "rta2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.rt.id
}

#Security Group
resource "aws_security_group" "asg_sg" {
  vpc_id = aws_vpc.main.id
  name   = "asg_sg"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 8080
    to_port     = 8080
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

#Target Group
resource "aws_lb_target_group" "tg" {
  name        = "tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path     = "/"
    protocol = "HTTP"
    port     = 80

    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
}

#Load Balancer
resource "aws_lb" "lb" {
  name               = "lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.asg_sg.id]
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

#Listener
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

#launch template
resource "aws_launch_template" "lt" {
  name_prefix            = "lt-"
  image_id               = "ami-0953476d60561c955" # Amazon Linux 2 AMI
  instance_type          = "t3.medium"
  vpc_security_group_ids = [aws_security_group.asg_sg.id]
  user_data = base64encode(<<EOF
#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x
 
# Update system
sudo yum update -y
 
# Install Java 21 (required by Jenkins)
sudo yum install -y java-21-amazon-corretto
 
# Install wget, git, unzip
sudo yum install -y wget git unzip
 
# Add Jenkins repo and key
sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
 
# Upgrade packages after adding Jenkins repo
sudo yum upgrade -y
 
# Install Jenkins
sudo yum install -y jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
 
# Install Node.js (LTS 18.x)
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install -y nodejs
 
# Install Docker
sudo yum install -y docker
sudo systemctl start docker
sudo systemctl enable docker
 
# Add ec2-user to docker group
sudo usermod -aG docker ec2-user
 
# Clone the GitHub repo
cd /home/ec2-user
git clone https://github.com/jAnushka26/jenkins-pipeline-2.0.git myapp
cd myapp
 
 
 
sudo docker build -t myapp .
sudo docker run -d -p 80:3000 --name myapp myapp
 
EOF
  )

}

#Auto Scaling Group
resource "aws_autoscaling_group" "asg" {
  desired_capacity    = 2
  max_size            = 3
  min_size            = 1
  vpc_zone_identifier = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  target_group_arns   = [aws_lb_target_group.tg.arn]
  health_check_type   = "ELB"
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }
}

