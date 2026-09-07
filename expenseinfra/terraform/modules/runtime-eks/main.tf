data "aws_partition" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name             = "${var.project_name}-expense-eks"
  eks_admin_access         = var.enabled && var.eks_admin_principal_arn != ""
  eks_ci_access            = var.enabled && var.eks_ci_principal_arn != "" && var.eks_ci_principal_arn != var.eks_admin_principal_arn
  cluster_admin_policy_arn = "arn:${data.aws_partition.current.partition}:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  az_names                 = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "eks" {
  count = var.enabled ? 1 : 0

  cidr_block           = var.eks_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-eks-vpc"
  }
}

resource "aws_internet_gateway" "eks" {
  count = var.enabled ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  tags = {
    Name = "${var.project_name}-eks-igw"
  }
}

resource "aws_subnet" "eks_public" {
  count = var.enabled ? 2 : 0

  vpc_id                  = aws_vpc.eks[0].id
  availability_zone       = local.az_names[count.index]
  cidr_block              = var.eks_public_subnet_cidrs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                          = "${var.project_name}-eks-public-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }
}

resource "aws_subnet" "eks_private" {
  count = var.enabled ? 2 : 0

  vpc_id            = aws_vpc.eks[0].id
  availability_zone = local.az_names[count.index]
  cidr_block        = var.eks_private_subnet_cidrs[count.index]

  tags = {
    Name                                          = "${var.project_name}-eks-private-${count.index + 1}"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }
}

resource "aws_eip" "eks_nat" {
  count = var.enabled ? 1 : 0

  domain = "vpc"

  tags = {
    Name = "${var.project_name}-eks-nat-eip"
  }
}

resource "aws_nat_gateway" "eks" {
  count = var.enabled ? 1 : 0

  subnet_id     = aws_subnet.eks_public[0].id
  allocation_id = aws_eip.eks_nat[0].id

  tags = {
    Name = "${var.project_name}-eks-nat"
  }

  depends_on = [aws_internet_gateway.eks]
}

resource "aws_route_table" "eks_public" {
  count = var.enabled ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks[0].id
  }

  tags = {
    Name = "${var.project_name}-eks-public-rt"
  }
}

resource "aws_route_table_association" "eks_public" {
  count = var.enabled ? 2 : 0

  subnet_id      = aws_subnet.eks_public[count.index].id
  route_table_id = aws_route_table.eks_public[0].id
}

resource "aws_route_table" "eks_private" {
  count = var.enabled ? 1 : 0

  vpc_id = aws_vpc.eks[0].id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks[0].id
  }

  tags = {
    Name = "${var.project_name}-eks-private-rt"
  }
}

resource "aws_route_table_association" "eks_private" {
  count = var.enabled ? 2 : 0

  subnet_id      = aws_subnet.eks_private[count.index].id
  route_table_id = aws_route_table.eks_private[0].id
}

# Step 7: ALB security group — created by us in Terraform so we can reference it
# in the node SG rules and pass it to the Ingress via annotation.
# The LB Controller will use THIS SG for the ALB instead of creating one itself.
resource "aws_security_group" "eks_alb" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-eks-alb-"
  description = "ALB for EKS Ingress - internet-facing HTTP"
  vpc_id      = aws_vpc.eks[0].id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound to Pods (target-type: ip)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # LBC v2 IAM conditions key off elbv2.k8s.aws/cluster (not the v1 ingress.k8s.aws/cluster tag).
  tags = {
    Name                      = "${var.project_name}-eks-alb"
    "elbv2.k8s.aws/cluster"   = local.cluster_name
    "ingress.k8s.aws/cluster" = local.cluster_name
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Allow ALB -> backend Pod port (8080) and frontend Pod port (80) on nodes.
resource "aws_security_group_rule" "node_ingress_from_alb_backend" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "ALB to backend Pod (8080)"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_security_group.eks_alb[0].id
}

resource "aws_security_group_rule" "node_ingress_from_alb_frontend" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "ALB to frontend Pod (80)"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_security_group.eks_alb[0].id
}

# Published so expenseapp's CI can read it at deploy time (aws ssm get-parameter)
# instead of a manually pasted CI/CD variable. CI IAM identity needs ssm:GetParameter
# on this parameter's ARN.
resource "aws_ssm_parameter" "eks_alb_security_group_id" {
  count = var.enabled ? 1 : 0

  name        = "/${var.project_name}/expense/eks-alb-security-group-id"
  type        = "String"
  value       = aws_security_group.eks_alb[0].id
  description = "ALB SG ID for eks-workload.yaml Ingress annotation alb.ingress.kubernetes.io/security-groups (read by expenseapp CI)."
}

# Step 2: explicit security groups (learning baseline, close to real projects).
# - EKS still creates the "cluster primary" security group automatically; we attach an additional SG to the
#   control-plane cross-account ENIs and a dedicated node SG on workers (via launch template).
resource "aws_security_group" "eks_cluster_additional" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-eks-cp-"
  description = "Additional SG for EKS control plane ENIs in this VPC"
  vpc_id      = aws_vpc.eks[0].id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-cluster-additional"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "eks_node" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-eks-node-"
  description = "EKS managed node group - worker instances"
  vpc_id      = aws_vpc.eks[0].id

  egress {
    description = "Outbound via NAT (images, AWS APIs, etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-eks-node"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# API server endpoint (private) — nodes must reach control plane ENIs on 443.
resource "aws_security_group_rule" "cluster_additional_ingress_from_nodes_https" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "Nodes to Kubernetes API (HTTPS)"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_cluster_additional[0].id
  source_security_group_id = aws_security_group.eks_node[0].id
}

# Pod / kube-proxy style traffic between nodes (same SG).
resource "aws_security_group_rule" "node_ingress_self_all" {
  count = var.enabled ? 1 : 0

  type              = "ingress"
  description       = "Node-to-node cluster traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.eks_node[0].id
  self              = true
}

resource "aws_iam_role" "eks_cluster" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node_group" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_node_group[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_node_group[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_pull_policy" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_node_group[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "expense" {
  count = var.enabled ? 1 : 0

  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster[0].arn
  version  = var.eks_kubernetes_version

  access_config {
    authentication_mode = "API"
    # Grant cluster-admin to the IAM principal that runs CreateCluster (e.g. CI pilotuser on first apply).
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids         = aws_subnet.eks_private[*].id
    security_group_ids = [aws_security_group.eks_cluster_additional[0].id]
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_policy]
}

# After the cluster exists: EKS cluster primary SG -> kubelet on nodes (required when using extra node SGs).
resource "aws_security_group_rule" "node_ingress_kubelet_from_cluster_primary" {
  count = var.enabled ? 1 : 0

  type                     = "ingress"
  description              = "Kubelet from EKS cluster primary security group"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.eks_node[0].id
  source_security_group_id = aws_eks_cluster.expense[0].vpc_config[0].cluster_security_group_id
}

resource "aws_launch_template" "eks_node" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-eks-node-lt-"

  # AWS requires the cluster primary SG plus any custom node SGs on managed nodes.
  vpc_security_group_ids = [
    aws_eks_cluster.expense[0].vpc_config[0].cluster_security_group_id,
    aws_security_group.eks_node[0].id,
  ]

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = {
    Name = "${var.project_name}-eks-node-lt"
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_eks_cluster.expense]
}

# Human/admin kubectl access (set var.eks_admin_principal_arn). IRSA handles app Pod AWS API calls separately.
resource "aws_eks_access_entry" "cluster_admin" {
  count = local.eks_admin_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_admin_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_admin" {
  count = local.eks_admin_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_admin_principal_arn
  policy_arn    = local.cluster_admin_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_admin[0]]
}

# CI automation user (pilotuser) — separate from the human admin principal.
resource "aws_eks_access_entry" "cluster_ci" {
  count = local.eks_ci_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_ci_principal_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "cluster_ci" {
  count = local.eks_ci_access ? 1 : 0

  cluster_name  = aws_eks_cluster.expense[0].name
  principal_arn = var.eks_ci_principal_arn
  policy_arn    = local.cluster_admin_policy_arn

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.cluster_ci[0]]
}

resource "aws_eks_node_group" "expense_default" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.expense[0].name
  node_group_name = "${var.project_name}-expense-default"
  node_role_arn   = aws_iam_role.eks_node_group[0].arn
  # Pinned to AZ1 only — with desired_size=1 per group, letting the ASG pick from
  # both AZs (the old aws_subnet.eks_private[*].id) means both node groups can land
  # in the same AZ by chance (this happened in prod). Pinning one group per AZ
  # guarantees 1 node per zone at the same node count — no extra cost.
  subnet_ids     = [aws_subnet.eks_private[0].id]
  instance_types = var.eks_node_instance_types
  # Without this, bumping the cluster's Kubernetes version does NOT touch node
  # groups — confirmed empirically (plan showed 0 changes here after a control-plane
  # version bump). This is what actually triggers the node (kubelet/AMI) upgrade.
  version = var.eks_kubernetes_version

  launch_template {
    id      = aws_launch_template.eks_node[0].id
    version = aws_launch_template.eks_node[0].latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  # Default is already max_unavailable=1; declared explicitly so the rollout
  # behavior is documented, not implied. With 1 node per group, this just means
  # "replace this one node" — the real safety net during that replacement is the
  # PodDisruptionBudgets in expenseapp's k8s/eks-workload.yaml, not this setting.
  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_pull_policy,
    aws_security_group_rule.node_ingress_kubelet_from_cluster_primary,
    aws_launch_template.eks_node
  ]
}

# Step 3: second node group. Same IAM role and launch template as the first group —
# the distinction is the label (role=apps) so that in a later step we can steer
# workloads to specific node groups with nodeSelector or affinity rules.
resource "aws_eks_node_group" "expense_apps" {
  count = var.enabled ? 1 : 0

  cluster_name    = aws_eks_cluster.expense[0].name
  node_group_name = "${var.project_name}-expense-apps"
  node_role_arn   = aws_iam_role.eks_node_group[0].arn
  # AZ2 — see expense_default above.
  subnet_ids     = [aws_subnet.eks_private[1].id]
  instance_types = var.eks_node_instance_types
  # See expense_default above — this is what actually triggers the node upgrade.
  version = var.eks_kubernetes_version

  launch_template {
    id      = aws_launch_template.eks_node[0].id
    version = aws_launch_template.eks_node[0].latest_version
  }

  scaling_config {
    desired_size = var.eks_node_desired_size
    min_size     = var.eks_node_min_size
    max_size     = var.eks_node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    role = "apps"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_pull_policy,
    aws_security_group_rule.node_ingress_kubelet_from_cluster_primary,
    aws_launch_template.eks_node
  ]
}

# IRSA: Pods cannot use the node role via IMDS by default (hop limit 1). Use a dedicated role for the backend SA.
data "tls_certificate" "eks_oidc" {
  count = var.enabled ? 1 : 0
  url   = aws_eks_cluster.expense[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = var.enabled ? 1 : 0

  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.expense[0].identity[0].oidc[0].issuer

  tags = {
    Name = "${var.project_name}-eks-oidc"
  }
}

resource "aws_iam_policy" "eks_expense_ddb" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-eks-expense-ddb-"
  description = "Expense backend Pod (IRSA): same DynamoDB access as ECS task role"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["dynamodb:PutItem", "dynamodb:Query", "dynamodb:GetItem"]
      Resource = var.dynamodb_expenses_table_arn
    }]
  })
}

resource "aws_iam_role" "eks_expense_backend_irsa" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-eks-expense-backend-sa"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:expense:expense-backend"
          "${replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-expense-backend-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "eks_expense_backend_irsa_ddb" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.eks_expense_backend_irsa[0].name
  policy_arn = aws_iam_policy.eks_expense_ddb[0].arn
}

# Published so expenseapp's CI can read it at deploy time (aws ssm get-parameter)
# instead of a manually pasted CI/CD variable. CI IAM identity needs ssm:GetParameter
# on this parameter's ARN.
resource "aws_ssm_parameter" "eks_expense_backend_role_arn" {
  count = var.enabled ? 1 : 0

  name        = "/${var.project_name}/expense/eks-expense-backend-role-arn"
  type        = "String"
  value       = aws_iam_role.eks_expense_backend_irsa[0].arn
  description = "IRSA role ARN for the expense-backend ServiceAccount (read by expenseapp CI)."
}

# Step 4: AWS Load Balancer Controller — IRSA
#
# The controller runs as a Pod inside the cluster (kube-system namespace) and
# calls AWS APIs to create/update ALBs, target groups, listener rules, and SGs
# on behalf of your Ingress resources.  It needs an IAM role it can assume via
# OIDC (IRSA), just like the backend Pod does for DynamoDB.
#
# ServiceAccount name "aws-load-balancer-controller" in namespace "kube-system"
# is the default expected by the official Helm chart — keep this in sync with
# Step 5 when we install the chart.

locals {
  oidc_issuer_url = var.enabled ? replace(aws_eks_cluster.expense[0].identity[0].oidc[0].issuer, "https://", "") : ""
}

resource "aws_iam_policy" "aws_lbc" {
  count = var.enabled ? 1 : 0

  name_prefix = "${var.project_name}-aws-lbc-"
  description = "AWS Load Balancer Controller: create/manage ALBs, target groups, and SGs for Ingress resources."

  # Official LBC v2 policy: ALBs/TGs/SGs are tagged elbv2.k8s.aws/cluster.
  # The v1 tag ingress.k8s.aws/cluster on DeleteLoadBalancer causes AccessDenied
  # on delete (create still works), so Ingress finalizers never clear.
  # Source: https://github.com/kubernetes-sigs/aws-load-balancer-controller/blob/main/docs/install/iam_policy.json
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "elasticloadbalancing.amazonaws.com" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeAccountAttributes",
          "ec2:DescribeAddresses",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeInternetGateways",
          "ec2:DescribeVpcs",
          "ec2:DescribeVpcPeeringConnections",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeInstances",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeTags",
          "ec2:GetCoipPoolUsage",
          "ec2:DescribeCoipPools",
          "ec2:GetSecurityGroupsForVpc",
          "ec2:DescribeIpamPools",
          "ec2:DescribeRouteTables",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeLoadBalancerAttributes",
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeListenerCertificates",
          "elasticloadbalancing:DescribeSSLPolicies",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:DescribeTargetGroupAttributes",
          "elasticloadbalancing:DescribeTargetHealth",
          "elasticloadbalancing:DescribeTags",
          "elasticloadbalancing:DescribeTrustStores",
          "elasticloadbalancing:DescribeListenerAttributes",
          "elasticloadbalancing:DescribeCapacityReservation",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:DescribeUserPoolClient",
          "acm:ListCertificates",
          "acm:DescribeCertificate",
          "iam:ListServerCertificates",
          "iam:GetServerCertificate",
          "waf-regional:GetWebACL",
          "waf-regional:GetWebACLForResource",
          "waf-regional:AssociateWebACL",
          "waf-regional:DisassociateWebACL",
          "wafv2:GetWebACL",
          "wafv2:GetWebACLForResource",
          "wafv2:AssociateWebACL",
          "wafv2:DisassociateWebACL",
          "shield:GetSubscriptionState",
          "shield:DescribeProtection",
          "shield:CreateProtection",
          "shield:DeleteProtection",
        ]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:AuthorizeSecurityGroupIngress", "ec2:RevokeSecurityGroupIngress"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateSecurityGroup"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          StringEquals = { "ec2:CreateAction" = "CreateSecurityGroup" }
          Null         = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:CreateTags", "ec2:DeleteTags"]
        Resource = "arn:aws:ec2:*:*:security-group/*"
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:DeleteSecurityGroup",
        ]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateLoadBalancer", "elasticloadbalancing:CreateTargetGroup"]
        Resource = "*"
        Condition = {
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:CreateListener",
          "elasticloadbalancing:DeleteListener",
          "elasticloadbalancing:CreateRule",
          "elasticloadbalancing:DeleteRule",
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          Null = {
            "aws:RequestTag/elbv2.k8s.aws/cluster"  = "true"
            "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false"
          }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags", "elasticloadbalancing:RemoveTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:listener/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener/app/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/net/*/*/*",
          "arn:aws:elasticloadbalancing:*:*:listener-rule/app/*/*/*",
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:ModifyLoadBalancerAttributes",
          "elasticloadbalancing:SetIpAddressType",
          "elasticloadbalancing:SetSecurityGroups",
          "elasticloadbalancing:SetSubnets",
          "elasticloadbalancing:DeleteLoadBalancer",
          "elasticloadbalancing:ModifyTargetGroup",
          "elasticloadbalancing:ModifyTargetGroupAttributes",
          "elasticloadbalancing:DeleteTargetGroup",
          "elasticloadbalancing:ModifyListenerAttributes",
          "elasticloadbalancing:ModifyCapacityReservation",
          "elasticloadbalancing:ModifyIpPools",
        ]
        Resource = "*"
        Condition = {
          Null = { "aws:ResourceTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect = "Allow"
        Action = ["elasticloadbalancing:AddTags"]
        Resource = [
          "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/net/*/*",
          "arn:aws:elasticloadbalancing:*:*:loadbalancer/app/*/*",
        ]
        Condition = {
          StringEquals = {
            "elasticloadbalancing:CreateAction" = ["CreateTargetGroup", "CreateLoadBalancer"]
          }
          Null = { "aws:RequestTag/elbv2.k8s.aws/cluster" = "false" }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:RegisterTargets", "elasticloadbalancing:DeregisterTargets"]
        Resource = "arn:aws:elasticloadbalancing:*:*:targetgroup/*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "elasticloadbalancing:SetWebAcl",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:AddListenerCertificates",
          "elasticloadbalancing:RemoveListenerCertificates",
          "elasticloadbalancing:ModifyRule",
          "elasticloadbalancing:SetRulePriorities",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_iam_role" "aws_lbc" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-aws-lbc"

  # Trust policy: only the aws-load-balancer-controller ServiceAccount in
  # kube-system may assume this role (OIDC / IRSA).
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_url}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-aws-lbc-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "aws_lbc" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.aws_lbc[0].name
  policy_arn = aws_iam_policy.aws_lbc[0].arn
}

# Step 5: CloudWatch Observability — logs (Fluent Bit) + Container Insights metrics (CloudWatch Agent).
# EKS addon deploys both DaemonSets into the amazon-cloudwatch namespace; CloudWatchAgentServerPolicy
# covers both (it already includes logs:PutLogEvents / CreateLogGroup / CreateLogStream).
resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = var.enabled ? toset(["application", "host", "dataplane"]) : []

  name              = "/aws/containerinsights/${local.cluster_name}/${each.key}"
  retention_in_days = 14
}

resource "aws_iam_role" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  name = "${var.project_name}-eks-cloudwatch-observability"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRoleWithWebIdentity"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks[0].arn
      }
      Condition = {
        StringEquals = {
          "${local.oidc_issuer_url}:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "${local.oidc_issuer_url}:sub" = "system:serviceaccount:amazon-cloudwatch:*"
        }
      }
    }]
  })

  tags = {
    Name = "${var.project_name}-eks-cloudwatch-observability-irsa"
  }
}

resource "aws_iam_role_policy_attachment" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  role       = aws_iam_role.cloudwatch_observability[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_eks_addon" "cloudwatch_observability" {
  count = var.enabled ? 1 : 0

  cluster_name                = aws_eks_cluster.expense[0].name
  addon_name                  = "amazon-cloudwatch-observability"
  service_account_role_arn    = aws_iam_role.cloudwatch_observability[0].arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [
    aws_eks_node_group.expense_default,
    aws_eks_node_group.expense_apps,
    aws_cloudwatch_log_group.container_insights,
  ]
}

# Published so expenseapp's CI can read it at deploy time (aws ssm get-parameter)
# instead of a manually pasted CI/CD variable. CI IAM identity needs ssm:GetParameter
# on this parameter's ARN.
resource "aws_ssm_parameter" "aws_lbc_role_arn" {
  count = var.enabled ? 1 : 0

  name        = "/${var.project_name}/expense/eks-aws-lbc-role-arn"
  type        = "String"
  value       = aws_iam_role.aws_lbc[0].arn
  description = "IRSA role ARN for the AWS Load Balancer Controller Helm chart (read by expenseapp CI)."
}
