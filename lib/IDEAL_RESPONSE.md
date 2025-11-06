```py
import json
import os
from aws_cdk import (
  Stack,
  aws_ec2 as ec2,
  aws_elasticloadbalancingv2 as elbv2,
  aws_autoscaling as autoscaling,
  aws_s3 as s3,
  aws_dynamodb as dynamodb,
  aws_rds as rds,
  aws_secretsmanager as secretsmanager,
  aws_iam as iam,
  aws_config as config,
  aws_wafv2 as wafv2,
  aws_cloudfront as cloudfront,
  aws_cloudfront_origins as origins,
  RemovalPolicy,
  Duration,
  CfnOutput
)
from constructs import Construct


class TapStack(Stack):
  """Main CDK Stack for the Tap Web Application Infrastructure"""

  def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
    super().__init__(scope, construct_id, **kwargs)

    # Get environment suffix for resource naming
    self.environment_suffix = os.environ.get('ENVIRONMENT_SUFFIX', 'dev')

    # Project naming convention with environment suffix
    self.project_name = f"tap-webapp-{self.environment_suffix}"

    # Create VPC and networking components
    self.create_networking()

    # Create security groups
    self.create_security_groups()

    # Create IAM roles
    self.create_iam_roles()

    # Create storage resources
    self.create_storage()

    # Create database resources
    self.create_database()

    # Create compute resources
    self.create_compute()

    # Create monitoring and security
    self.create_monitoring_security()

    # Create CloudFront and WAF
    self.create_cloudfront_waf()

  def create_networking(self):
    """Create VPC with public and private subnets across two AZs"""

    # Create VPC
    self.vpc = ec2.Vpc(
      self, f"{self.project_name}-vpc",
      vpc_name=f"{self.project_name}-vpc",
      ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
      max_azs=2,
      subnet_configuration=[
        ec2.SubnetConfiguration(
          name=f"{self.project_name}-public-subnet",
          subnet_type=ec2.SubnetType.PUBLIC,
          cidr_mask=24
        ),
        ec2.SubnetConfiguration(
          name=f"{self.project_name}-private-subnet",
          subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidr_mask=24
        ),
        ec2.SubnetConfiguration(
          name=f"{self.project_name}-isolated-subnet",
          subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
          cidr_mask=24
        )
      ],
      enable_dns_hostnames=True,
      enable_dns_support=True
    )

  def create_security_groups(self):
    """Create security groups with least privilege access"""

    # ALB Security Group
    self.alb_sg = ec2.SecurityGroup(
      self, f"{self.project_name}-alb-sg",
      security_group_name=f"{self.project_name}-alb-sg",
      vpc=self.vpc,
      description="Security group for Application Load Balancer",
      allow_all_outbound=False
    )

    # Allow HTTP and HTTPS inbound
    self.alb_sg.add_ingress_rule(
      ec2.Peer.any_ipv4(),
      ec2.Port.tcp(80),
      "Allow HTTP traffic"
    )
    self.alb_sg.add_ingress_rule(
      ec2.Peer.any_ipv4(),
      ec2.Port.tcp(443),
      "Allow HTTPS traffic"
    )

    # Allow outbound traffic to EC2 instances
    self.alb_sg.add_egress_rule(
      ec2.Peer.any_ipv4(),
      ec2.Port.tcp(80),
      "Allow HTTP traffic to EC2 instances"
    )

    # EC2 Security Group
    self.ec2_sg = ec2.SecurityGroup(
      self, f"{self.project_name}-ec2-sg",
      security_group_name=f"{self.project_name}-ec2-sg",
      vpc=self.vpc,
      description="Security group for EC2 instances",
      allow_all_outbound=True
    )

    # Allow traffic from ALB
    self.ec2_sg.add_ingress_rule(
      self.alb_sg,
      ec2.Port.tcp(80),
      "Allow HTTP from ALB"
    )

    # RDS Security Group
    self.rds_sg = ec2.SecurityGroup(
      self, f"{self.project_name}-rds-sg",
      security_group_name=f"{self.project_name}-rds-sg",
      vpc=self.vpc,
      description="Security group for RDS database",
      allow_all_outbound=False
    )

    # Allow MySQL/Aurora access from EC2
    self.rds_sg.add_ingress_rule(
      self.ec2_sg,
      ec2.Port.tcp(3306),
      "Allow MySQL access from EC2"
    )

  def create_iam_roles(self):
    """Create IAM roles with least privilege permissions"""

    # EC2 Instance Role
    self.ec2_role = iam.Role(
      self, f"{self.project_name}-ec2-role",
      role_name=f"{self.project_name}-ec2-role",
      assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
      managed_policies=[
        iam.ManagedPolicy.from_aws_managed_policy_name(
          "CloudWatchAgentServerPolicy"
        )
      ]
    )

    # Add custom policy for S3 and DynamoDB access
    self.ec2_role.add_to_policy(
      iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=[
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject"
        ],
        resources=[f"arn:aws:s3:::{self.project_name}-*/*"]
      )
    )

    self.ec2_role.add_to_policy(
      iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=[
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem",
          "dynamodb:Query",
          "dynamodb:Scan"
        ],
        resources=[
          f"arn:aws:dynamodb:{self.region}:{self.account}:"
          f"table/{self.project_name}-*"
        ]
      )
    )

    # Config Service Role
    self.config_role = iam.Role(
      self, f"{self.project_name}-config-role",
      role_name=f"{self.project_name}-config-role",
      assumed_by=iam.ServicePrincipal("config.amazonaws.com"),
      managed_policies=[
        iam.ManagedPolicy.from_aws_managed_policy_name(
          "service-role/AWS_ConfigRole"
        )
      ]
    )

  def create_storage(self):
    """Create S3 buckets and DynamoDB tables"""

    # S3 Bucket for application data
    self.app_bucket = s3.Bucket(
      self, f"{self.project_name}-app-bucket",
      bucket_name=f"{self.project_name}-app-data-{self.account}-{self.region}",
      encryption=s3.BucketEncryption.S3_MANAGED,
      block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
      versioned=True,
      removal_policy=RemovalPolicy.DESTROY,
      auto_delete_objects=True
    )

    # S3 Bucket for logs
    self.logs_bucket = s3.Bucket(
      self, f"{self.project_name}-logs-bucket",
      bucket_name=f"{self.project_name}-logs-{self.account}-{self.region}",
      encryption=s3.BucketEncryption.S3_MANAGED,
      block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
      removal_policy=RemovalPolicy.DESTROY,
      auto_delete_objects=True
    )

    # DynamoDB Table for application data
    self.dynamodb_table = dynamodb.Table(
      self, f"{self.project_name}-dynamodb-table",
      table_name=f"{self.project_name}-app-data",
      partition_key=dynamodb.Attribute(
        name="id",
        type=dynamodb.AttributeType.STRING
      ),
      billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
      point_in_time_recovery=True,
      encryption=dynamodb.TableEncryption.AWS_MANAGED,
      removal_policy=RemovalPolicy.DESTROY
    )

  def create_database(self):
    """Create RDS database in private subnets with Secrets Manager"""

    # Create database credentials in Secrets Manager
    self.db_secret = secretsmanager.Secret(
      self, f"{self.project_name}-db-secret",
      secret_name=f"{self.project_name}-db-credentials",
      description="Database credentials for the web application",
      generate_secret_string=secretsmanager.SecretStringGenerator(
        secret_string_template=json.dumps({"username": "admin"}),
        generate_string_key="password",
        exclude_characters="\"'@/\\",
        password_length=32
      )
    )

    # Create DB subnet group
    self.db_subnet_group = rds.SubnetGroup(
      self, f"{self.project_name}-db-subnet-group",
      subnet_group_name=f"{self.project_name}-db-subnet-group",
      description="Subnet group for RDS database",
      vpc=self.vpc,
      vpc_subnets=ec2.SubnetSelection(
        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED
      )
    )

    # Create RDS instance
    self.database = rds.DatabaseInstance(
      self, f"{self.project_name}-database",
      instance_identifier=f"{self.project_name}-database",
      engine=rds.DatabaseInstanceEngine.mysql(
        version=rds.MysqlEngineVersion.VER_8_0_37
      ),
      instance_type=ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        ec2.InstanceSize.MICRO
      ),
      credentials=rds.Credentials.from_secret(self.db_secret),
      vpc=self.vpc,
      subnet_group=self.db_subnet_group,
      security_groups=[self.rds_sg],
      allocated_storage=20,
      storage_encrypted=True,
      backup_retention=Duration.days(7),
      deletion_protection=False,
      removal_policy=RemovalPolicy.DESTROY
    )

  def create_compute(self):
    """Create EC2 instances in Auto Scaling Group with ALB"""

    # Create Launch Template
    self.launch_template = ec2.LaunchTemplate(
      self, f"{self.project_name}-launch-template",
      launch_template_name=f"{self.project_name}-launch-template",
      instance_type=ec2.InstanceType.of(
        ec2.InstanceClass.BURSTABLE3,
        ec2.InstanceSize.MICRO
      ),
      machine_image=ec2.MachineImage.latest_amazon_linux2(),
      security_group=self.ec2_sg,
      role=self.ec2_role,
      user_data=ec2.UserData.custom(
        "#!/bin/bash\n"
        "yum update -y\n"
        "yum install -y httpd\n"
        "systemctl start httpd\n"
        "systemctl enable httpd\n"
        "echo '<h1>Tap Web Application</h1>' > /var/www/html/index.html\n"
        "echo '<p>Instance ID: ' $(curl -s "
        "http://169.254.169.254/latest/meta-data/instance-id) "
        "'</p>' >> /var/www/html/index.html"
      )
    )

    # Create Auto Scaling Group
    self.asg = autoscaling.AutoScalingGroup(
      self, f"{self.project_name}-asg",
      auto_scaling_group_name=f"{self.project_name}-asg",
      vpc=self.vpc,
      vpc_subnets=ec2.SubnetSelection(
        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
      ),
      launch_template=self.launch_template,
      min_capacity=2,
      max_capacity=6,
      desired_capacity=2,
      health_check=autoscaling.HealthCheck.elb(
        grace=Duration.minutes(5)
      )
    )

    # Create Application Load Balancer
    self.alb = elbv2.ApplicationLoadBalancer(
      self, f"{self.project_name}-alb",
      load_balancer_name=f"{self.project_name}-alb",
      vpc=self.vpc,
      vpc_subnets=ec2.SubnetSelection(
        subnet_type=ec2.SubnetType.PUBLIC
      ),
      security_group=self.alb_sg,
      internet_facing=True
    )

    # Create Target Group
    self.target_group = elbv2.ApplicationTargetGroup(
      self, f"{self.project_name}-target-group",
      target_group_name=f"{self.project_name}-tg",
      port=80,
      protocol=elbv2.ApplicationProtocol.HTTP,
      vpc=self.vpc,
      target_type=elbv2.TargetType.INSTANCE,
      health_check=elbv2.HealthCheck(
        enabled=True,
        healthy_http_codes="200",
        interval=Duration.seconds(30),
        path="/",
        protocol=elbv2.Protocol.HTTP,
        timeout=Duration.seconds(5),
        unhealthy_threshold_count=3
      )
    )

    # Add ASG to target group
    self.asg.attach_to_application_target_group(self.target_group)

    # Create ALB Listener
    self.alb.add_listener(
      f"{self.project_name}-listener",
      port=80,
      protocol=elbv2.ApplicationProtocol.HTTP,
      default_target_groups=[self.target_group]
    )

  def create_monitoring_security(self):
    """Create AWS Config for monitoring configuration changes"""

    # Create S3 bucket for Config
    self.config_bucket = s3.Bucket(
      self, f"{self.project_name}-config-bucket",
      bucket_name=f"{self.project_name}-config-{self.account}-{self.region}",
      encryption=s3.BucketEncryption.S3_MANAGED,
      block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
      removal_policy=RemovalPolicy.DESTROY,
      auto_delete_objects=True
    )

    # Grant Config service permissions to the bucket
    self.config_bucket.add_to_resource_policy(
      iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        principals=[iam.ServicePrincipal("config.amazonaws.com")],
        actions=["s3:GetBucketAcl", "s3:ListBucket"],
        resources=[self.config_bucket.bucket_arn]
      )
    )

    self.config_bucket.add_to_resource_policy(
      iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        principals=[iam.ServicePrincipal("config.amazonaws.com")],
        actions=["s3:PutObject"],
        resources=[f"{self.config_bucket.bucket_arn}/*"],
        conditions={
          "StringEquals": {
            "s3:x-amz-acl": "bucket-owner-full-control"
          }
        }
      )
    )

    # Create Config Configuration Recorder
    self.config_recorder = config.CfnConfigurationRecorder(
      self, f"{self.project_name}-config-recorder",
      name=f"{self.project_name}-config-recorder",
      role_arn=self.config_role.role_arn,
      recording_group=config.CfnConfigurationRecorder.RecordingGroupProperty(
        all_supported=True,
        include_global_resource_types=True
      )
    )

    # Create Config Delivery Channel
    self.config_delivery_channel = config.CfnDeliveryChannel(
      self, f"{self.project_name}-config-delivery-channel",
      name=f"{self.project_name}-config-delivery-channel",
      s3_bucket_name=self.config_bucket.bucket_name
    )

  def create_cloudfront_waf(self):
    """Create CloudFront distribution with WAF protection"""

    # Create WAF Web ACL
    self.web_acl = wafv2.CfnWebACL(
      self, f"{self.project_name}-web-acl",
      name=f"{self.project_name}-web-acl",
      scope="CLOUDFRONT",
      default_action=wafv2.CfnWebACL.DefaultActionProperty(
        allow={}
      ),
      rules=[
        wafv2.CfnWebACL.RuleProperty(
          name="AWSManagedRulesCommonRuleSet",
          priority=1,
          override_action=wafv2.CfnWebACL.OverrideActionProperty(
            none={}
          ),
          statement=wafv2.CfnWebACL.StatementProperty(
            managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(  # pylint: disable=line-too-long
              vendor_name="AWS",
              name="AWSManagedRulesCommonRuleSet"
            )
          ),
          visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
            sampled_requests_enabled=True,
            cloud_watch_metrics_enabled=True,
            metric_name="CommonRuleSetMetric"
          )
        ),
        wafv2.CfnWebACL.RuleProperty(
          name="AWSManagedRulesKnownBadInputsRuleSet",
          priority=2,
          override_action=wafv2.CfnWebACL.OverrideActionProperty(
            none={}
          ),
          statement=wafv2.CfnWebACL.StatementProperty(
            managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(  # pylint: disable=line-too-long
              vendor_name="AWS",
              name="AWSManagedRulesKnownBadInputsRuleSet"
            )
          ),
          visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
            sampled_requests_enabled=True,
            cloud_watch_metrics_enabled=True,
            metric_name="KnownBadInputsRuleSetMetric"
          )
        )
      ],
      visibility_config=wafv2.CfnWebACL.VisibilityConfigProperty(
        sampled_requests_enabled=True,
        cloud_watch_metrics_enabled=True,
        metric_name=f"{self.project_name}-web-acl-metric"
      )
    )

    # Create CloudFront Distribution
    self.cloudfront_distribution = cloudfront.Distribution(
      self, f"{self.project_name}-cloudfront",
      default_behavior=cloudfront.BehaviorOptions(
        origin=origins.LoadBalancerV2Origin(
          self.alb,
          protocol_policy=cloudfront.OriginProtocolPolicy.HTTP_ONLY
        ),
        viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
        cached_methods=cloudfront.CachedMethods.CACHE_GET_HEAD,
        cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED
      ),
      web_acl_id=self.web_acl.attr_arn,
      comment=f"{self.project_name} CloudFront Distribution"
    )

    # Output important values
    CfnOutput(
      self, "LoadBalancerDNS",
      value=self.alb.load_balancer_dns_name,
      description="DNS name of the Application Load Balancer"
    )

    CfnOutput(
      self, "CloudFrontDomainName",
      value=self.cloudfront_distribution.distribution_domain_name,
      description="Domain name of the CloudFront distribution"
    )

    CfnOutput(
      self, "DatabaseEndpoint",
      value=self.database.instance_endpoint.hostname,
      description="RDS database endpoint"
    )
```