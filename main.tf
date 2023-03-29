#-----------------------------------------------------------
# Provision Highly Available Web in any Region Default VPC
# Creat:
#    -  Security Group for web Server
#    -  Launch Configuration with Auto AMI Lookup
#    -  Auto Scaling Group using 2 Availability Zones
#    -  Classic Load Balancer in 2 Availability Zones
#
# Смотреть документацию на основном сайте
#------------------------------------------------------------

provider "aws" {
  region = "ca-central-1"
}

data "aws_availability_zones" "available"{}

data "aws_ami" "latest_ubuntu" {
    owners = [ "099720109477" ]
    most_recent = true
    filter {
        name = "name"
        values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-20.04-amd64-server-*"]
    }
}

#------------------------ Security Group for Web Server------------------------------------------------------

resource "aws_security_group" "web" {
  name = "Dynamic Security Group"

  dynamic "ingress" {
      for_each = ["80","443"]
      content {
          from_port = ingress.value
          to_port = ingress.value
          protocol = "tcp"
          cidr_blocks = ["0.0.0.0/0"]
      }
  }

  egress {
      from_port = 0
      to_port = 0
      protocol = "-1"
      cidr_blocks = [ "0.0.0.0/0" ]
  }

  tags = {
    Name = "Dynamic Security Group"
    Owner = "Me"
  }
}

#------------------------Launch Configuration with Auto AMI Lookup-----------------------------------------------

resource "aws_launch_configuration" "web" {
   //name = "WebServer-Highly-Available-LC"
  name_prefix = "WebServer-Highly-Available-LC-"  //  создадим префикс. остальная часть имени будет подставляться тераформом автоматически при
                                                  //  изменении launch configuration
  image_id = data.aws_ami.latest_ubuntu
  instance_type = "t3.micro"
  security_groups = [aws_security_group.web.id]
  user_data = file("user_data.sh")

  lifecycle {
    create_before_destroy = true
  }
}

#-------------------------Auto Scaling Group using 2 Availability Zones-------------------------------------------

resource "aws_autoscaling_group" "web" {
  //name = "WebServer-Highly-Available-ASG"
  name = "ASG-${aws_launch_configuration.web.name}"        // появилась зависимость от имени launch configuration
                                                          //  если имя будет менять, то будет создаваться новая ASG
  launch_configuration = aws_launch_configuration.web.name
  max_size = 2
  min_size = 2
  min_elb_capacity = 2
  vpc_zone_identifier = [aws_default_subnet.default_az1.id,aws_default_subnet.default_az2.id ]
  health_check_type = "ELB"
  load_balancers = [aws_elb.web.name]

  dynamic "tag" {
        
       for_each =  {
           Name = "WebServer in ASG"
           Owner = "Me"
           TAGKEY = "TAGVALUE"
       }

      content {
      key = tag.key
      value = tag.value
      propagate_at_launch = true
      }
  }

  lifecycle {
    create_before_destroy = true
  }

  
}

#-----------------Classic Load Balancer in 2 Availability Zones------------------------------------------------------

resource "aws_elb" "web" {
  name = "WebSerber-HA-ELB"
  availability_zones = [data.aws_availability_zones.available.names[0],data.aws_availability_zones.available.names[1]]
  security_groups = [aws_security_group.web.id]

  listener {
    lb_port = 80
    lb_protocol = "http"
    instance_port = 80
    instance_protocol = "http"
  }

  health_check {
    healthy_threshold = 2
    unhealthy_threshold = 2
    timeout = 3
    target = "HTTP:80/"
    interval = 10
  }

  tags = {
      Name = "WebServer-Highly-Available-ELB"
  }
}

#-------------------------------------------------------------------------------------------------------------------------

resource "aws_default_subnet" "default_az1" {
    availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_default_subnet" "default_az2" {
    availability_zone = data.aws_availability_zones.available.names[1]
}

#------------------------------------------------------------------------------------------------------------------------


output "web_loadbalancer_url" {
  value = aws_elb.web.dns_name
}