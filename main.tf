provider "aws" {
  region = "eu-west-2"
}

# Creating VPC and finding all availability zones

resource "aws_vpc" "TerraformVPC" {
  cidr_block = "10.0.0.0/16"
}

data "aws_availability_zones" "azs" {
  state = "available"
}

# Creating internet gateway

resource "aws_internet_gateway" "Terra_igw" {
 vpc_id = "${aws_vpc.TerraformVPC.id}"
 tags = {
    Name = "Terra-igw"
 }
}

# Routing

resource "aws_route_table" "Terra-public-route" {
  vpc_id =  "${aws_vpc.TerraformVPC.id}"
  route {
      cidr_block = "0.0.0.0/0"
      gateway_id = "${aws_internet_gateway.Terra_igw.id}"
  }

   tags = {
       Name = "Terra-public-route"
   }
}

# This code block routes us to the private subnet

resource "aws_default_route_table" "Terra-default-route" {
  default_route_table_id = "${aws_vpc.TerraformVPC.default_route_table_id}"
  tags = {
      Name = "Terra-default-route"
  }
}

# Creating public subnets

resource "aws_subnet" "subnet_Terraform_az1" {
  availability_zone = "${data.aws_availability_zones.azs.names[0]}"
  cidr_block        = "10.0.1.0/24"
  vpc_id            = "${aws_vpc.TerraformVPC.id}"
  map_public_ip_on_launch = "true"
  tags = {
    Name = "First-Terra-Public-Subnet"
  }
}

resource "aws_subnet" "subnet_Terraform_az2" {
  availability_zone = "${data.aws_availability_zones.azs.names[1]}"
  cidr_block        = "10.0.2.0/24"
  vpc_id            = "${aws_vpc.TerraformVPC.id}"
  map_public_ip_on_launch = "true"
  tags = {
    Name = "Second-Terra-Public-Subnet"
  }
}

# Creating private subnets

resource "aws_subnet" "subnet_Terraform_az3" {
  availability_zone = "${data.aws_availability_zones.azs.names[0]}"
  cidr_block        = "10.0.3.0/24"
  vpc_id            = "${aws_vpc.TerraformVPC.id}"
  tags = {
    Name = "First-Terra-Private-Subnet"
  }
}

resource "aws_subnet" "subnet_Terraform_az4" {
  availability_zone = "${data.aws_availability_zones.azs.names[1]}"
  cidr_block        = "10.0.4.0/24"
  vpc_id            = "${aws_vpc.TerraformVPC.id}"
  tags = {
    Name = "Second-Terra-Private-Subnet"
  }
}

# Subnet Assiocation

resource "aws_route_table_association" "arts1a" {
  subnet_id = "${aws_subnet.subnet_Terraform_az1.id}"
  route_table_id = "${aws_route_table.Terra-public-route.id}"
}

resource "aws_route_table_association" "arts1b" {
  subnet_id = "${aws_subnet.subnet_Terraform_az2.id}"
  route_table_id = "${aws_route_table.Terra-public-route.id}"
}

resource "aws_route_table_association" "arts-p-1a" {
  subnet_id = "${aws_subnet.subnet_Terraform_az3.id}"
  route_table_id = "${aws_vpc.TerraformVPC.default_route_table_id}"
}

resource "aws_route_table_association" "arts-p-1b" {
  subnet_id = "${aws_subnet.subnet_Terraform_az4.id}"
  route_table_id = "${aws_vpc.TerraformVPC.default_route_table_id}"
}

# Creating auto balencer

resource "aws_lb" "myalb" {
    name = "myalb"
    internal = false
    load_balancer_type = "application"
    security_groups = [aws_security_group.my_alb_security_group.id]
    subnets = [
        aws_subnet.subnet_Terraform_az1.id,
        aws_subnet.subnet_Terraform_az2.id 
    ]
}

# Creating Security Group for ALB
resource "aws_security_group" "my_alb_security_group" {
    vpc_id = aws_vpc.TerraformVPC.id
    ingress {
        from_port = 80
        to_port = 80
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }
  }

# Creating Security Group for instances

resource "aws_security_group" "GD-Terra-SG" {
    name   = "HTTP and SSH"
    vpc_id = aws_vpc.TerraformVPC.id

    ingress {
        from_port        = 22
        to_port          = 22
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
    }

    ingress {
        from_port        = 80
        to_port          = 80
        protocol         = "tcp"
        cidr_blocks      = ["0.0.0.0/0"]
    }

    ingress {
        from_port        = 3306
        to_port          = 3306
        protocol         = "tcp"
       cidr_blocks      = ["0.0.0.0/0"]
    }
  }

# Creating ALB Listener

resource "aws_lb_listener" "my_alb_listener" {
    load_balancer_arn = aws_lb.myalb.arn
    port = 80
    protocol = "HTTP"
    default_action {
        target_group_arn = aws_lb_target_group.my_alb_target_group.arn
        type = "forward"
    }
}

resource "aws_lb_target_group" "my_alb_target_group" {
    port = 8080
    protocol = "HTTP"
    vpc_id = aws_vpc.TerraformVPC.id
stickiness {
    enabled = false
    type = "lb_cookie"
}
}

# Launch configuration for the auto-scaling.
resource "aws_launch_configuration" "my_launch_configuration" {
    image_id                             = "ami-0194c3e07668a7e36"
    security_groups                      = [aws_security_group.GD-Terra-SG.id]
#   aws_nat_gateway_id                   = "${module.network.Terra1-ngw.id}"
    instance_type                        = "t2.micro"
    key_name                             = "GD-Terraform-Test"
  }

# Creating autoscaling then attaching it into my_alb_target_group.
resource "aws_autoscaling_attachment" "my_aws_autoscaling_attachment" {
    alb_target_group_arn = aws_lb_target_group.my_alb_target_group.arn
    autoscaling_group_name = aws_autoscaling_group.my_autoscaling_group.id
}

# define the autoscaling group.
# attach my_launch_configuration into this newly created autoscaling group below.
resource "aws_autoscaling_group" "my_autoscaling_group" {
    name = "my-autoscaling-group"
    desired_capacity = 4 
    min_size = 2 
    max_size = 6
    health_check_type = "ELB"

    # allows deleting the autoscaling group without waiting
    # for all instances in the pool to terminate
#    force_delete = true

    launch_configuration = aws_launch_configuration.my_launch_configuration.id
    vpc_zone_identifier = [
        aws_subnet.subnet_Terraform_az1.id,
        aws_subnet.subnet_Terraform_az2.id
    ]
#    timeouts {
#        delete = "15m"
#    }
    lifecycle {
        # ensure the new instance is only created before the other one is destroyed.
        create_before_destroy = true
    }
}

# Enabling Sticky Session
# Hey! Hey! Solve this: Error creating LBCookieStickinessPolicy: ValidationError: LoadBalancer name cannot be longer than 32 characters
# Problem solved by moving policy into target group? 
#resource "aws_lb_cookie_stickiness_policy" "Sticky" {
#    name                                 = "Sticky-policy"
#    load_balancer                        = aws_lb.myalb.id
#    type                                 = "lb_cookie" 
#    lb_port                              = 80
#    cookie_expiration_period             = 600
#}

# print load balancer's DNS, test it using curl.
#
# curl my-alb-625362998.ap-southeast-1.elb.amazonaws.com
output "alb-url" {
    value = aws_lb.myalb.dns_name
}

# Creating RDS subnet group

resource "aws_db_subnet_group" "TerraRDS" {
  subnet_ids = ["${aws_subnet.subnet_Terraform_az3.id}", "${aws_subnet.subnet_Terraform_az4.id}"]
  tags = {
    Name = "My DB subnet group"
  }
}

# Creating RDS

resource "aws_db_instance" "RDSa" {
  allocated_storage                    = 20
  availability_zone                    = "${data.aws_availability_zones.azs.names[0]}"
  db_subnet_group_name                 = "${aws_db_subnet_group.TerraRDS.id}"
  engine                               = "MySQL"
  engine_version                       = "8.0.23"
  identifier                           = "subnet-a"
  instance_class                       = "db.m5.large"
  password                             = "password"
  skip_final_snapshot                  = true
  storage_encrypted                    = true
  username                             = "Admin"
}

resource "aws_db_instance" "RDSb" {
  allocated_storage                    = 20
  availability_zone                    = "${data.aws_availability_zones.azs.names[1]}"
  db_subnet_group_name                 = "${aws_db_subnet_group.TerraRDS.id}"
  engine                               = "MySQL"
  engine_version                       = "8.0.20"
  identifier                           = "subnet-b"
  instance_class                       = "db.m5.large"
  password                             = "password"
  skip_final_snapshot                  = true
  storage_encrypted                    = true
  username                             = "Admin"
}

# Creating Redis Keying

resource "aws_elasticache_subnet_group" "terra_redis" {
  name                                 = "redis-cache-subnet"
  subnet_ids                           = ["${aws_subnet.subnet_Terraform_az1.id}", "${aws_subnet.subnet_Terraform_az2.id}"]
}

resource "aws_elasticache_parameter_group" "pg" {
  name                                 = "terra-cache-params"
  family                               = "redis6.x"

  parameter {
    name                               = "activerehashing"
    value                              = "yes"
  }

#  parameter {
#    name                               = "min-slaves-to-write"
#    value                              = "2"
#  }
}

resource "aws_elasticache_replication_group" "baz" {
  replication_group_id          = "tf-redis-cluster"
  replication_group_description = "Keying made by Terraform"
  node_type                     = "cache.t2.small"
  port                          = 6379
  parameter_group_name          = "default.redis6.x.cluster.on"
  automatic_failover_enabled    = true

  cluster_mode {
    replicas_per_node_group = 1
    num_node_groups         = 2
  }
}
