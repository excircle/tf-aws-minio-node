# Assume Role
resource "aws_iam_role" "ec2_cli_role" {
  name = var.aws_iam_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "ec2.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      },
    ]
  })
  tags = merge(
    local.tag,
    {
      Name = format("%s-ec2-cli-role", var.application_name)
      Purpose = format("%s ec2 cli role", var.application_name)
    }
  )
}

# Grants policy holder auth to use AWS CLI
resource "aws_iam_policy" "describe_instances" {
  name        = var.aws_iam_policy_name
  description = "Allow EC2 instances to access Secrets Manager and write secrets to the file system"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action   = "ec2:*",
        Effect   = "Allow",
        Resource = "*"
      },
      {
        Action: [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ],
        Effect   = "Allow",
        Resource = "*" # You can specify a more specific ARN for the secrets if needed.
      },
      {
        Action: [
          "ssm:SendCommand",
          "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations",
          "ssm:DescribeInstanceInformation"
        ],
        Effect   = "Allow",
        Resource = "*" # You can restrict this to the EC2 instance ARN.
      }
    ]
  })

  tags = merge(
    local.tag,
    {
      Name = format("%s-iam-policy", var.application_name)
      Purpose = format("%s Secrets Manager and SSM access policy", var.application_name)
    }
  )
}

# Bind 'describe instances' policy to 'ec2_cli_role'
resource "aws_iam_role_policy_attachment" "ec2_describe_instances" {
  role       = aws_iam_role.ec2_cli_role.name
  policy_arn = aws_iam_policy.describe_instances.arn
}

# Bind 'ec2_cli_role' to 'ec2_instance_profile'
# Profile will be bound to EC2 during instance declaration
resource "aws_iam_instance_profile" "ec2_profile" {
  name = var.ec2_instance_profile_name
  role = aws_iam_role.ec2_cli_role.name
  tags = merge(
    local.tag,
    {
      Name = format("%s-ec2-instance-profile", var.application_name)
      Purpose = format("%s ec2 instance profile", var.application_name)
    }
  )
}