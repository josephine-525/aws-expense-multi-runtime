data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_default_subnet" "ecs" {
  count = var.enabled ? 2 : 0

  availability_zone = data.aws_availability_zones.available.names[count.index]
}

resource "aws_security_group" "expense_alb" {
  count = var.enabled ? 1 : 0

  name        = "${var.project_name}-expense-alb"
  description = "ALB for expense demo"
  vpc_id      = aws_default_subnet.ecs[0].vpc_id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
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

resource "aws_security_group" "expense_ecs_tasks" {
  count = var.enabled ? 1 : 0

  name        = "${var.project_name}-expense-ecs-tasks"
  description = "Fargate tasks"
  vpc_id      = aws_default_subnet.ecs[0].vpc_id

  ingress {
    description     = "From ALB"
    from_port       = 80
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.expense_alb[0].id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "expense" {
  count = var.enabled ? 1 : 0

  name               = "${var.project_name}-exp-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.expense_alb[0].id]
  subnets            = aws_default_subnet.ecs[*].id
}

resource "aws_lb_target_group" "expense_frontend" {
  count = var.enabled ? 1 : 0

  name        = "${var.project_name}-fe-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_default_subnet.ecs[0].vpc_id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "expense_backend" {
  count = var.enabled ? 1 : 0

  name        = "${var.project_name}-api-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_default_subnet.ecs[0].vpc_id
  target_type = "ip"

  # Backend Flask root returns 200 with a JSON health note.
  # Avoid /expenses: without ?month=YYYY-MM the handler returns 400 and ALB marks the target unhealthy.
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "expense_http" {
  count = var.enabled ? 1 : 0

  load_balancer_arn = aws_lb.expense[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.expense_frontend[0].arn
  }
}

resource "aws_lb_listener_rule" "expense_api_paths" {
  count = var.enabled ? 1 : 0

  listener_arn = aws_lb_listener.expense_http[0].arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.expense_backend[0].arn
  }

  condition {
    path_pattern {
      values = ["/expenses", "/expenses/*", "/months", "/months/*", "/summary"]
    }
  }
}

resource "aws_cloudwatch_log_group" "expense_backend" {
  count = var.enabled ? 1 : 0

  name              = "/ecs/${var.project_name}-expense-backend"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "expense_frontend" {
  count = var.enabled ? 1 : 0

  name              = "/ecs/${var.project_name}-expense-frontend"
  retention_in_days = 7
}

resource "aws_iam_role" "ecs_execution" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-ecs-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.ecs_execution[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task_backend" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-ecs-task-api"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task_backend_ddb" {
  count = var.enabled ? 1 : 0

  name = "ddb-expenses"
  role = aws_iam_role.ecs_task_backend[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"]
      Resource = var.dynamodb_expenses_table_arn
    }]
  })
}

resource "aws_ecs_cluster" "expense" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-expense"
}

resource "aws_ecs_task_definition" "expense_backend" {
  count = var.enabled ? 1 : 0

  family                   = "${var.project_name}-expense-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task_backend[0].arn

  container_definitions = jsonencode([{
    name      = "backend"
    image     = "${var.ecr_expense_backend_repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "TABLE_NAME", value = split("/", var.dynamodb_expenses_table_arn)[1] }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.expense_backend[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_task_definition" "expense_frontend" {
  count = var.enabled ? 1 : 0

  family                   = "${var.project_name}-expense-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution[0].arn

  container_definitions = jsonencode([{
    name      = "frontend"
    image     = "${var.ecr_expense_frontend_repository_url}:latest"
    essential = true
    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.expense_frontend[0].name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
}

resource "aws_ecs_service" "expense_backend" {
  count = var.enabled ? 1 : 0

  name            = "${var.project_name}-expense-api"
  cluster         = aws_ecs_cluster.expense[0].id
  task_definition = aws_ecs_task_definition.expense_backend[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = aws_default_subnet.ecs[*].id
    security_groups  = [aws_security_group.expense_ecs_tasks[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.expense_backend[0].arn
    container_name   = "backend"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener_rule.expense_api_paths]
}

resource "aws_ecs_service" "expense_frontend" {
  count = var.enabled ? 1 : 0

  name            = "${var.project_name}-expense-web"
  cluster         = aws_ecs_cluster.expense[0].id
  task_definition = aws_ecs_task_definition.expense_frontend[0].arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  network_configuration {
    subnets          = aws_default_subnet.ecs[*].id
    security_groups  = [aws_security_group.expense_ecs_tasks[0].id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.expense_frontend[0].arn
    container_name   = "frontend"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.expense_http]
}
