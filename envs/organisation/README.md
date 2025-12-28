# Google Cloud Organization Setup

This Terraform configuration sets up a Google Cloud organization with the following structure:

## Structure

```
Organization
├── Development
│   ├── [project-prefix]-dev-shared
│   └── [project-prefix]-dev-apps
├── UAT
│   ├── [project-prefix]-uat-shared
│   └── [project-prefix]-uat-apps
└── Production
    ├── [project-prefix]-prod-shared
    └── [project-prefix]-prod-apps
```

## Prerequisites

1. Google Cloud SDK installed and authenticated
2. Organization Admin and Billing Account User permissions
3. Terraform >= 1.0.0

## Usage

1. Create a `terraform.tfvars` file with your configuration:

```hcl
domain          = "your-domain.com"
# customer_id is now automatically fetched via the domain
billing_account = "billing-accounts/XXXXXX-XXXXXX-XXXXXX"
project_prefix  = "my-org"
organization_name = "My Company"
```

2. Initialize Terraform:

```bash
terraform init
```

3. Review the execution plan:

```bash
terraform plan
```

4. Apply the configuration:

```bash
terraform apply
```

## Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| domain | The domain name of the organization | string | - | yes |
| billing_account | Billing account ID | string | - | yes |
| project_prefix | Prefix for project names | string | "my-org" | no |
| organization_name | Name of the organization | string | "My Organization" | no |
| default_region | Default region for resources | string | "europe-west1" | no |

## Outputs

- `organization_id`: The numeric ID of the organization
- `organization_name`: The resource name of the organization
- `organization_domain`: The domain of the organization
- `organizational_units`: Map of created organizational units
- `projects`: Map of created projects
- `enabled_apis`: List of enabled APIs in the organization
