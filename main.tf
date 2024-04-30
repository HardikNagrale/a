resource "aws_vpc" "wordpress_vpc" {
  enable_dns_support   = true
  enable_dns_hostnames = true
  cidr_block           = "10.0.0.0/16"
}

resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  map_public_ip_on_launch = true
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
}

resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.wordpress_vpc.id
  map_public_ip_on_launch = true
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
}

resource "aws_subnet" "private_subnet_1" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
}

resource "aws_subnet" "private_subnet_2" {
  vpc_id            = aws_vpc.wordpress_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
}

resource "aws_db_subnet_group" "wordpress_db_subnet_group" {
  name = "wordpress-db-subnet-group"

  subnet_ids = [
    aws_subnet.private_subnet_1.id,
    aws_subnet.private_subnet_2.id,
  ]
}

resource "aws_rds_cluster" "wordpress_rds_cluster" {
  skip_final_snapshot  = true
  master_username      = "wpadmin"
  master_password      = "yourpassword"
  engine_version       = "5.7.mysql_aurora.2.07.1"
  engine               = "aurora-mysql"
  db_subnet_group_name = aws_db_subnet_group.wordpress_db_subnet_group.name
  database_name        = "wordpressdb"
}

resource "aws_security_group" "wordpress_sg" {
  vpc_id = aws_vpc.wordpress_vpc.id

  egress {
    to_port   = 0
    protocol  = "-1"
    from_port = 0
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }

  ingress {
    to_port   = 80
    protocol  = "tcp"
    from_port = 80
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
  ingress {
    to_port   = 443
    protocol  = "tcp"
    from_port = 443
    cidr_blocks = [
      "0.0.0.0/0",
    ]
  }
}

resource "aws_elb" "wordpress_elb" {
  name                        = "wordpress-elb"
  idle_timeout                = 400
  cross_zone_load_balancing   = true
  connection_draining_timeout = 400
  connection_draining         = true

  availability_zones = [
    "us-east-1a",
    "us-east-1b",
  ]

  health_check {
    unhealthy_threshold = 2
    timeout             = 5
    target              = "HTTP:80/"
    interval            = 30
    healthy_threshold   = 2
  }

  listener {
    lb_protocol       = "HTTP"
    lb_port           = 80
    instance_protocol = "HTTP"
    instance_port     = 80
  }
}

resource "aws_launch_configuration" "wordpress_lc" {
  name          = "wordpress-launch-configuration"
  instance_type = "t2.micro"
  image_id      = "ami-123456"

  lifecycle {
    create_before_destroy = true
  }

  security_groups = [
    aws_security_group.wordpress_sg.id,
  ]
}

resource "aws_autoscaling_group" "wordpress_asg" {
  min_size             = 1
  max_size             = 3
  launch_configuration = aws_launch_configuration.wordpress_lc.id
  desired_capacity     = 2

  tag {
    value               = "wordpress-instance"
    propagate_at_launch = true
    key                 = "Name"
  }

  vpc_zone_identifier = [
    aws_subnet.public_subnet_1.id,
    aws_subnet.public_subnet_2.id,
  ]
}

resource "aws_route53_zone" "wordpress_zone" {
  name = "example.com"
}

resource "aws_route53_record" "wordpress_dns" {
  zone_id = aws_route53_zone.wordpress_zone.id
  type    = "A"
  name    = "www.example.com"

  alias {
    zone_id                = aws_elb.wordpress_elb.zone_id
    name                   = aws_elb.wordpress_elb.dns_name
    evaluate_target_health = true
  }
}

resource "aws_acm_certificate" "wordpress_cert" {
  validation_method = "DNS"
  domain_name       = "www.example.com"
}

resource "aws_elb_listener" "https" {
  default_action {
    type             = "forward"
    target_group_arn = aws_elb.wordpress_elb.id
  }
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate.wordpress_cert.arn
  load_balancer_arn = aws_elb.wordpress_elb.id
  port              = 443
}

