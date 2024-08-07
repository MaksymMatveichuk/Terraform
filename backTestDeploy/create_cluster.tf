resource "aws_ecs_cluster" "cluster_back" {
  name       = "cluster_back"
  depends_on = [aws_ecs_task_definition.tertesttd]
}

resource "aws_launch_template" "ecs_launch" {
  name_prefix            = "ecs-launch"
  image_id               = data.aws_ami.aws_linux_latest_ecs.image_id
  instance_type          = var.instance_type
  vpc_security_group_ids = [aws_security_group.DevrateSG.id]
  key_name               = aws_key_pair.tf_key.key_name
  user_data = base64encode(<<-EOF
      #!/bin/bash
      echo ECS_CLUSTER=${aws_ecs_cluster.cluster_back.name} >> /etc/ecs/ecs.config;
    EOF
  )
  iam_instance_profile {
    arn = aws_iam_instance_profile.instance_profile.arn
  }

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    http_endpoint               = "enabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      volume_size = 20
      volume_type = "gp2"
    }
  }
  depends_on = [aws_ecr_repository.Create-ECR]
}

resource "aws_ecs_capacity_provider" "provider" {
  name = "example-ec2-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn         = aws_autoscaling_group.ecs_asg.arn
    managed_termination_protection = "DISABLED"
    managed_scaling {
      maximum_scaling_step_size = 2
      minimum_scaling_step_size = 1
      status                    = "ENABLED"
      target_capacity           = 100
    }
  }

  tags = {
    Name = "example-ec2-capacity-provider"
  }
}

resource "aws_ecs_cluster_capacity_providers" "main" {
  cluster_name       = aws_ecs_cluster.cluster_back.name
  capacity_providers = [aws_ecs_capacity_provider.provider.name]

  default_capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.provider.name
    base              = 0
    weight            = 1
  }
}

resource "aws_autoscaling_group" "ecs_asg" {
  name = "ASGn-${aws_launch_template.ecs_launch.name_prefix}"
  launch_template {
    id      = aws_launch_template.ecs_launch.id
    version = aws_launch_template.ecs_launch.latest_version
  }
  min_size                  = 1
  max_size                  = 2
  desired_capacity          = 1
  health_check_type         = "EC2"
  health_check_grace_period = 10
  vpc_zone_identifier = [
    aws_default_subnet.default_az1.id,
    aws_default_subnet.default_az2.id,
    aws_default_subnet.default_az3.id
  ]
  termination_policies = ["OldestInstance"]
  dynamic "tag" {
    for_each = {
      Name   = "EcsInstance-ASG"
      Owner  = "Max Matveychuk"
      TAGKEY = "TAGVALUE"
    }
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_service" "back_services" {
  name                 = "gft-test-first-services-${aws_ecs_task_definition.tertesttd.revision}"
  cluster              = aws_ecs_cluster.cluster_back.id
  task_definition      = aws_ecs_task_definition.tertesttd.arn
  scheduling_strategy  = "REPLICA"
  desired_count        = 1
  force_new_deployment = true
  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.provider.name
    base              = 1
    weight            = 100
  }

  ordered_placement_strategy {
    type  = "spread"
    field = "attribute:ecs.availability-zone"
  }
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_autoscaling_group.ecs_asg, aws_ecs_cluster.cluster_back]
}
