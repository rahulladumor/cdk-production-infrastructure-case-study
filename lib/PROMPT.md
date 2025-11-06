# Python CDK Setup for AWS Infrastructure

## Environment
We're building a secure, scalable web application infrastructure on AWS using Python CDK. Everything will be deployed in **us-west-2** and managed through CDK constructs so it's easy to reproduce and maintain. The application needs web servers, databases, networking, and content delivery — all properly secured and following AWS best practices for high availability and fault tolerance.

## Constraints
There are several important rules we need to follow:
- Everything stays inside **us-west-2** region
- VPC must span at least two availability zones for redundancy
- Use both private and public subnets with proper routing
- Security groups should be restrictive and follow least-privilege principles
- EC2 instances need to auto-scale behind a load balancer
- S3 buckets must have encryption enabled and block public access
- DynamoDB tables need point-in-time recovery for data protection
- RDS databases go in private subnets with no internet access
- Use AWS Secrets Manager for sensitive data like database passwords
- IAM roles should be minimal and clearly defined
- AWS Config integration for compliance monitoring
- AWS WAF integration with CloudFront for attack prevention
- Consistent naming convention: resource-type-project-name format

## Proposed Approach
The plan is to create a robust AWS environment using Python CDK, with all the infrastructure defined in organized constructs. We'll build a VPC with proper subnet separation, set up auto-scaling EC2 instances behind a load balancer, deploy databases in secure private subnets, and configure storage services with encryption and recovery features. The network design will support high availability across multiple AZs, while security groups and IAM policies keep everything locked down. CloudFront will handle edge caching and WAF integration, while AWS Config ensures compliance. Overall, this should give us a production-ready infrastructure that's secure, scalable, and follows AWS best practices.

## Folder Structure
project-root/
├── lib/
│   └── tap_stack.py  # main CDK stack with all resources
└── tap.py            # CDK app entry point for synthesis