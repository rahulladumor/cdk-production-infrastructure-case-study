# MODEL_FAILURE.md - Common CDK Implementation Mistakes

This document demonstrates common mistakes and failures that can occur when implementing AWS CDK infrastructure, based on typical implementation errors.

## ❌ Common Implementation Failures

### 1. **Missing Environment Configuration**
```python
# ❌ FAILURE: Hardcoded project name without environment support
self.project_name = "tap-webapp"  # No environment suffix

# ✅ SUCCESS: Environment-aware naming
self.environment_suffix = os.environ.get('ENVIRONMENT_SUFFIX', 'dev')
self.project_name = f"tap-webapp-{self.environment_suffix}"
```

### 2. **Incorrect IAM Policy References**
```python
# ❌ FAILURE: Wrong managed policy name
iam.ManagedPolicy.from_aws_managed_policy_name("service-role/ConfigRole")

# ✅ SUCCESS: Correct managed policy name
iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWS_ConfigRole")
```

### 3. **Missing Egress Rules in Security Groups**
```python
# ❌ FAILURE: ALB security group missing egress rules
self.alb_sg = ec2.SecurityGroup(
    self, f"{self.project_name}-alb-sg",
    # ... other properties
    allow_all_outbound=False  # No egress rules defined
)
# Missing: self.alb_sg.add_egress_rule(...)

# ✅ SUCCESS: Proper egress rules defined
self.alb_sg.add_egress_rule(
    ec2.Peer.any_ipv4(),
    ec2.Port.tcp(80),
    "Allow HTTP traffic to EC2 instances"
)
```

### 4. **Outdated MySQL Engine Version**
```python
# ❌ FAILURE: Using outdated MySQL version
engine=rds.DatabaseInstanceEngine.mysql(
    version=rds.MysqlEngineVersion.VER_8_0_35  # Outdated
)

# ✅ SUCCESS: Using latest stable version
engine=rds.DatabaseInstanceEngine.mysql(
    version=rds.MysqlEngineVersion.VER_8_0_37  # Latest stable
)
```

### 5. **Poor User Data Implementation**
```python
# ❌ FAILURE: Complex user data with potential syntax issues
self.launch_template.add_user_data(
    "#!/bin/bash",
    "yum update -y",
    "yum install -y httpd",
    "systemctl start httpd",
    "systemctl enable httpd",
    "echo '<h1>Tap Web Application</h1>' > /var/www/html/index.html",
    "echo '<p>Instance ID: ' $(curl -s http://169.254.169.254/latest/meta-data/instance-id) '</p>' >> /var/www/html/index.html"
)

# ✅ SUCCESS: Clean, readable user data
user_data_script = """#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo '<h1>Tap Web Application</h1>' > /var/www/html/index.html
echo '<p>Instance ID: ' $(curl -s http://169.254.169.254/latest/meta-data/instance-id) '</p>' >> /var/www/html/index.html
"""
self.launch_template = ec2.LaunchTemplate(
    # ... other properties
    user_data=ec2.UserData.custom(user_data_script)
)
```

### 6. **Incorrect Machine Image Reference**
```python
# ❌ FAILURE: Using deprecated image method
machine_image=ec2.AmazonLinuxImage(
    generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
)

# ✅ SUCCESS: Using latest Amazon Linux 2
machine_image=ec2.MachineImage.latest_amazon_linux2()
```

### 7. **Missing Resource Policy Conditions**
```python
# ❌ FAILURE: Incomplete S3 bucket policy for Config service
self.config_bucket.add_to_resource_policy(
    iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        principals=[iam.ServicePrincipal("config.amazonaws.com")],
        actions=["s3:PutObject"],
        resources=[f"{self.config_bucket.bucket_arn}/*"]
        # Missing: conditions for proper access control
    )
)

# ✅ SUCCESS: Proper conditions for Config service access
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
```

### 8. **Poor Code Formatting and Readability**
```python
# ❌ FAILURE: Long lines without proper formatting
statement=wafv2.CfnWebACL.StatementProperty(
    managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(
        vendor_name="AWS",
        name="AWSManagedRulesCommonRuleSet"
    )
)

# ✅ SUCCESS: Proper line breaks and readability
statement=wafv2.CfnWebACL.StatementProperty(
    managed_rule_group_statement=wafv2.CfnWebACL.ManagedRuleGroupStatementProperty(  # pylint: disable=line-too-long
        vendor_name="AWS",
        name="AWSManagedRulesCommonRuleSet"
    )
)
```

### 9. **Missing Error Handling and Validation**
```python
# ❌ FAILURE: No validation of environment variables
self.environment_suffix = os.environ.get('ENVIRONMENT_SUFFIX', 'dev')
# No validation that the suffix is valid

# ✅ SUCCESS: Proper validation
environment_suffix = os.environ.get('ENVIRONMENT_SUFFIX', 'dev')
valid_suffixes = ['dev', 'staging', 'prod']
if environment_suffix not in valid_suffixes:
    raise ValueError(f"Invalid environment suffix: {environment_suffix}. Must be one of {valid_suffixes}")
self.environment_suffix = environment_suffix
```

### 10. **Inconsistent Resource Naming**
```python
# ❌ FAILURE: Inconsistent naming patterns
self.vpc = ec2.Vpc(self, "vpc", ...)  # No project prefix
self.alb = elbv2.ApplicationLoadBalancer(self, "alb", ...)  # No project prefix

# ✅ SUCCESS: Consistent naming with project prefix
self.vpc = ec2.Vpc(self, f"{self.project_name}-vpc", ...)
self.alb = elbv2.ApplicationLoadBalancer(self, f"{self.project_name}-alb", ...)
```

## 🚨 Critical Security Failures

### 1. **Overly Permissive IAM Policies**
```python
# ❌ FAILURE: Too broad permissions
self.ec2_role.add_to_policy(
    iam.PolicyStatement(
        effect=iam.Effect.ALLOW,
        actions=["s3:*"],  # Too broad!
        resources=["*"]    # Too broad!
    )
)

# ✅ SUCCESS: Least privilege principle
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
```

### 2. **Missing Encryption**
```python
# ❌ FAILURE: No encryption specified
self.database = rds.DatabaseInstance(
    # ... other properties
    # Missing: storage_encrypted=True
)

# ✅ SUCCESS: Encryption enabled
self.database = rds.DatabaseInstance(
    # ... other properties
    storage_encrypted=True
)
```

### 3. **Public Access to S3 Buckets**
```python
# ❌ FAILURE: S3 bucket with public access
self.app_bucket = s3.Bucket(
    # ... other properties
    # Missing: block_public_access=s3.BlockPublicAccess.BLOCK_ALL
)

# ✅ SUCCESS: Public access blocked
self.app_bucket = s3.Bucket(
    # ... other properties
    block_public_access=s3.BlockPublicAccess.BLOCK_ALL
)
```

## 🔧 Common Deployment Failures

### 1. **Missing CDK Bootstrap**
```bash
# ❌ FAILURE: Trying to deploy without bootstrapping
cdk deploy  # Will fail if CDK not bootstrapped

# ✅ SUCCESS: Bootstrap first
cdk bootstrap aws://ACCOUNT-NUMBER/us-west-2
cdk deploy
```

### 2. **Incorrect Region Configuration**
```python
# ❌ FAILURE: Hardcoded region in stack
TapStack(app, "tap-infrastructure-stack")  # No region specified

# ✅ SUCCESS: Explicit region configuration
TapStack(app, "tap-infrastructure-stack",
    env=cdk.Environment(
        region="us-west-2"
    )
)
```

### 3. **Missing Dependencies**
```bash
# ❌ FAILURE: Missing required packages
pip install aws-cdk-lib  # Missing constructs package

# ✅ SUCCESS: Install all dependencies
pip install -r requirements.txt
```

## 📋 Testing and Validation Failures

### 1. **No Unit Tests**
```python
# ❌ FAILURE: No test coverage
# Missing: tests/unit/test_tapstack.py

# ✅ SUCCESS: Comprehensive test coverage
def test_vpc_creation():
    # Test VPC creation logic
    pass

def test_security_group_rules():
    # Test security group configuration
    pass
```

### 2. **No Integration Tests**
```python
# ❌ FAILURE: No integration testing
# Missing: tests/integration/test_deployment.py

# ✅ SUCCESS: Integration tests
def test_stack_deployment():
    # Test actual stack deployment
    pass
```

## 🎯 Best Practices to Avoid Failures

1. **Always use environment variables** for configuration
2. **Implement proper error handling** and validation
3. **Follow least privilege principle** for IAM policies
4. **Enable encryption** for all storage resources
5. **Block public access** by default
6. **Use consistent naming conventions** across all resources
7. **Write comprehensive tests** before deployment
8. **Validate configurations** before applying
9. **Use proper CDK constructs** instead of raw CloudFormation
10. **Document all assumptions** and dependencies

## 🚀 Recovery Steps

When failures occur:

1. **Check CloudFormation events** for detailed error messages
2. **Review CDK synthesis output** for validation errors
3. **Verify AWS credentials** and permissions
4. **Check resource limits** in the target region
5. **Review security group rules** and network configuration
6. **Validate IAM policies** and roles
7. **Check for naming conflicts** in the target account
8. **Review VPC and subnet** configuration
9. **Verify service quotas** and limits
10. **Use CDK diff** to understand changes before deployment

Remember: **Failures are learning opportunities**. Each failure helps improve the infrastructure and deployment process.
