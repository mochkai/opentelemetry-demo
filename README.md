# Open Telemetry Demo

## Introduction
This is a demo designed to explore the capabilities of open telemetry as well as the implementation of kubernetes and data colectors. This project was built with the assistance of claude code however this ReadMe file has been edited by the author directly and will be used as a documentation of the entire process.

## Initial steps
the first phase is to investigate and analyse what claude created to see if ti meets the requirements I need. The initial prompt was to create an Open Telemetry demo using the official open telemetry demo app and deploy that to AWS EKS. There are some cost concerns involved which made me ponder using a local kind implementation for this demo, and I am considering keeping that as an option and split this into two environemnts one local for initial setup and testing and one remote within AWS for live demos and final capability and integration testing.

## Telemetry Vendors
Claude initially configured the repo to include all telemetry vendors withn the original code with no distinction. After some repormpting and analysis of the exititng code I decided to move any vendor related code into a vendors folder this enables use of the Open Telemetry Demo with any vendor without any specific dependencies between the demo files.

### Coralogix Integration
Added terraform configurations to create an archive bucket for the coralogix logs. All coralogix specific configuration will be made directly in the UI.
>coralogix related helm files are placed inside the helm folder, this includes configurations for the otel demo when corralogix environment is present.

## Initializing the project
As part of the concept behind this demo this needs to be reproducible anywhere. So the use of terraform and a makefile are with that intent in mind.

### make up
This will run all the commands required to create th EKS cluster and install the open telemetry demo onto the cluster.

### make down
This command will remove and destroy any resource that has been previously deplouyed with the exception of the S3 archive buckets.

### make sleep
This will reduce the node count to 0 effectivelly stoping the kubernetes cluster to avoid incuring costs when not in use.

### make wake
This will re-instate the kubernetes cluster by restoring the node count and resuming the service.

### make check-env
This will list all the pods and which nodes they belong to by IP.

### make rebalance
This will redistribute pods betweeen the available nodes and should always be run after funning the `make wake` command as this command will cause most pods to be allocated to the first availalable node that becomes ready.

## Terraform + AWS
when using this project along with terraform and AWS, a user with the apropriate permissions need to be set up. If a user already exists for terraform deployments ensure that the following policies get added to the user:

```JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "RegionalServicesEuNorth1",
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "eks:*",
        "autoscaling:*",
        "kms:*",
        "logs:*",
        "s3:*",
        "ssm:GetParameter",
        "ssm:GetParameters"
      ],
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "aws:RequestedRegion": "eu-north-1"
        }
      }
    },
    {
      "Sid": "IamProjectRoles",
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:GetRole",
        "iam:UpdateRole",
        "iam:UpdateRoleDescription",
        "iam:UpdateAssumeRolePolicy",
        "iam:TagRole",
        "iam:UntagRole",
        "iam:ListRoleTags",
        "iam:ListRolePolicies",
        "iam:GetRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:ListAttachedRolePolicies",
        "iam:ListInstanceProfilesForRole"
      ],
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/cx-otel-lab-*"
    },
    {
      "Sid": "IamAttachOnlyEksAndProjectPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy"
      ],
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/cx-otel-lab-*",
      "Condition": {
        "ArnLike": {
          "iam:PolicyARN": [
            "arn:aws:iam::aws:policy/AmazonEKS*",
            "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistry*",
            "arn:aws:iam::{AWS_ACCOUNT_ID}:policy/cx-otel-lab-*"
          ]
        }
      }
    },
    {
      "Sid": "IamPassProjectRolesToEksOnly",
      "Effect": "Allow",
      "Action": "iam:PassRole",
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/cx-otel-lab-*",
      "Condition": {
        "StringEquals": {
          "iam:PassedToService": "eks.amazonaws.com"
        }
      }
    },
    {
      "Sid": "IamProjectPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:CreatePolicy",
        "iam:DeletePolicy",
        "iam:GetPolicy",
        "iam:GetPolicyVersion",
        "iam:ListPolicyVersions",
        "iam:CreatePolicyVersion",
        "iam:DeletePolicyVersion",
        "iam:TagPolicy",
        "iam:UntagPolicy",
        "iam:ListPolicyTags"
      ],
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:policy/cx-otel-lab-*"
    },
    {
      "Sid": "IamReadAwsManagedPolicies",
      "Effect": "Allow",
      "Action": [
        "iam:GetPolicy",
        "iam:GetPolicyVersion"
      ],
      "Resource": "arn:aws:iam::aws:policy/*"
    },
    {
      "Sid": "IamEksOidcProvider",
      "Effect": "Allow",
      "Action": [
        "iam:CreateOpenIDConnectProvider",
        "iam:DeleteOpenIDConnectProvider",
        "iam:GetOpenIDConnectProvider",
        "iam:UpdateOpenIDConnectProviderThumbprint",
        "iam:AddClientIDToOpenIDConnectProvider",
        "iam:TagOpenIDConnectProvider",
        "iam:UntagOpenIDConnectProvider"
      ],
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:oidc-provider/oidc.eks.eu-north-1.amazonaws.com/id/*"
    },
    {
      "Sid": "IamEksServiceLinkedRoles",
      "Effect": "Allow",
      "Action": "iam:CreateServiceLinkedRole",
      "Resource": "arn:aws:iam::{AWS_ACCOUNT_ID}:role/aws-service-role/*",
      "Condition": {
        "StringEquals": {
          "iam:AWSServiceName": [
            "eks.amazonaws.com",
            "eks-nodegroup.amazonaws.com",
            "autoscaling.amazonaws.com"
          ]
        }
      }
    },
    {
      "Sid": "IamReadServiceLinkedRoles",
      "Effect": "Allow",
      "Action": "iam:GetRole",
      "Resource": [
        "arn:aws:iam::{AWS_ACCOUNT_ID}:role/aws-service-role/*",
        "arn:aws:iam::{AWS_ACCOUNT_ID}:role/AWSServiceRoleFor*"
      ]
    }
  ]
}
```

## Development Notes

### Problems Encountered

#### Misconfigured variables.tf file
When first deploying, after setting everything up, the variables file still contained non default values which meant the var options would have to be used along terraform apply commands.

#### Missing coralogix agent
During the demo run test if the coralogix agent is not installed the frontend will crash when trying to process the telemetry data rendering it unusable. The only workaround for that would be to use the out of the box telemetry collectors within the demo itself.
For the Coralogix agent to fully function the private key must be included into the environment file, if it is not configured correctly it will cause the same crashes.

#### Data archive not retaining configuration value
When trying to Configure metrics Bucket after adding the bucket name value and hitting the save button it returns a positive response letting the user know the change has been implemented but once the page is refreshed the field is still blank... This is under investigation.

#### Alerts not saving
When trying to create an alerts based on metrics and sending data via webhooks, there is a generic error occurring in the last step with no meaningful message for clear understanding of the error, leaving the use unsure if it is a configuration or permission issue.

### AI usage
AI was used do build and configure some of the initial structure, however the initially proposed folder structure and overall architecture needed adjustments as it proposed all configuration files should be placed within the same folder. After consideration the appropriate structure would be to use a vendor based approach to be in line of a real production ready scenario where the vendors can be added or removed without affecting the core structure of the demo.

AI assistance was also employed in the permission based configuration for AWS, and initial terraform script creation.