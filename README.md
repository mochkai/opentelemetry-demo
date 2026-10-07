# Open Telemetry Demo

## Introduction
This is a demo designed to explore the capabilities of open telemetry as well as the implementation of kubernetes and data colectors. This project was built with the assistance of claude code however this ReadMe file has been edited by the author directly and will be used as a documentation of the entire process.

## Initial steps
the first phase is to investigate and analyse what claude created to see if ti meets the requirements I need. The initial prompt was to create an Open Telemetry demo using the official open telemetry demo app and deploy that to AWS EKS. There are some cost concerns involved which made me ponder using a local kind implementation for this demo, and I am considering keeping that as an option and split this into two environemnts one local for initial setup and testing and one remote within AWS for live demos and final capability and integration testing.

## Telemetry Vendors
Claude initially configured the repo to include all telemetry vendors withn the original code with no distinction. After some repormpting and analysis of the exititng code I decided to move any vendor related code into a vendors folder this enables use of the Open Telemetry Demo with any vendor without any specific dependencies between the demo files.

### Coralogix Integration
Added terraform configurations to create an archive bucket for the coralogix logs. All coralogix specific configuration will be made directly in the UI.



## Initializing the project
As part of the concept behind this demo this needs to be reproducible anywhere. So the use of terraform and a makefile are with that intent in mind.

### make up
This will run all the commands required to create th EKS cluster and install the open telemetry demo onto the cluster.



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
