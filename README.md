# Learning Steps on AWS

A production-style AWS rebuild of my Azure **Learning Steps** project, written in Terraform.
The Azure version runs a FastAPI app on AKS with ACR, PostgreSQL Flexible Server, Key Vault and NSGs.
This repo moves the same design to AWS: **EKS, ECR, RDS PostgreSQL, Secrets Manager, security groups and the AWS Load Balancer Controller**, built across two Availability Zones with a security-first mindset.

![AWS network map](network-map-full.png)

*Solid = built in Terraform today. Dashed / PLANNED = next steps. Source: [`network-map-full.drawio`](network-map-full.drawio).*

## Architecture

| Layer | What's built |
|---|---|
| **Network** | VPC `10.0.0.0/16` in `eu-central-1` (Frankfurt), 2 AZs. Per AZ: a public subnet (load balancer, NAT), a private EKS subnet and an isolated DB subnet |
| **Egress** | One NAT gateway per AZ, each EKS route table points to the NAT in its own AZ. S3 gateway endpoint for ECR image layers |
| **Kubernetes** | EKS 1.36, managed node group (2 × t3.medium, AL2023) in private subnets, no public IPs, no SSH |
| **Load balancing** | AWS Load Balancer Controller v3.5.0 (Helm), IAM role via EKS Pod Identity. A `type: LoadBalancer` Service becomes an internet-facing **NLB** in the public subnets that sends traffic straight to pod IPs |
| **Database** | RDS PostgreSQL 18.6, Multi-AZ, encrypted, not publicly accessible, isolated route table with no internet route |
| **Registry** | ECR with immutable tags, scan on push and a lifecycle policy |
| **Secrets** | RDS-managed master password in Secrets Manager (auto-rotated), read by pods through the Secrets Store CSI driver + AWS provider and EKS Pod Identity |
| **App** | FastAPI container (non-root, all capabilities dropped), 2 replicas, DB setup Job, TLS to RDS (`sslmode=require`) |
| **Logging** | EKS control plane logs (`api`, `audit`, `authenticator`) to a Terraform-managed CloudWatch log group, 7-day retention |
| **State** | S3 backend (own bucket: versioning, encryption, Block Public Access), S3-native state locking |

## Azure → AWS mapping

| Azure (original) | AWS (this repo) |
|---|---|
| AKS | EKS + managed node group |
| ACR + `AcrPull` | ECR + node role policy `AmazonEC2ContainerRegistryReadOnly` |
| PostgreSQL Flexible Server (delegated subnet) | RDS PostgreSQL + DB subnet group |
| Key Vault + CSI add-on | Secrets Manager + Secrets Store CSI driver (ASCP) + Pod Identity |
| NSGs on subnets | Security groups on resources (SG-to-SG references) |
| Managed identity / role assignments | IAM roles (trust policy = who, attached policies = what) |
| `authorized_ip_ranges` | EKS `public_access_cidrs` |
| Azure Load Balancer (managed by AKS) | AWS Load Balancer Controller + Network Load Balancer |
| Storage account backend | S3 backend with `use_lockfile` |

## Security decisions

- **Database trusts an identity, not a location.** PostgreSQL (TCP 5432) is only reachable from the **EKS cluster security group**, not from whole subnet ranges. The DB security group has no egress rule.
- **No secrets in code, git or Terraform state.** `manage_master_user_password` lets RDS generate and rotate the password itself. Terraform only knows the secret's ARN. There is no Kubernetes Secret either: pods read the password from a mounted file into `PGPASSWORD`.
- **Least privilege down to one pod.** The app role can call `secretsmanager:GetSecretValue` / `DescribeSecret` on **one secret only**, and only pods running as ServiceAccount `learningsteps-api` in namespace `learningsteps` can use it (Pod Identity association).
- **Separate identity for the load balancer controller.** Its IAM role (the official v3.5.0 policy) is bound to ServiceAccount `aws-load-balancer-controller` in `kube-system` only. The app never gets load balancer permissions.
- **Locked-down admin access.** The EKS API's public endpoint only accepts one `/32` (tested: other networks time out). Nodes use the private endpoint.
- **No shadow resources.** The EKS log group is created by Terraform (with retention), so `terraform destroy` removes everything.
- **Temporary credentials everywhere.** Humans log in with IAM Identity Center (`aws sso login`) or `aws login` (IAM user + MFA), services and pods get short-lived STS credentials. No long-lived access keys.

## Repository layout

```
infrastructure/
├── backend.tf          S3 state backend
├── terraform.tf        providers + default tags
├── variables.tf        inputs (region, AZs, CIDRs, my_ip_cidr, ...)
├── outputs.tf          cluster name, kubeconfig command, ECR URL, RDS endpoint, secret ARN, VPC ID, ...
├── vpc.tf / subnets.tf / internet_gateway.tf / nat.tf / route_tables.tf / vpc_endpoint.tf
├── securitygroups.tf   DB security group (before/after kept for teaching)
├── ecr.tf              repository + lifecycle policy
├── postgresql.tf       RDS + DB subnet group
├── iam.tf              cluster, node and app roles
├── eks.tf              log group, cluster, node group, add-ons, app Pod Identity association
├── lbcontroller.tf     AWS Load Balancer Controller: IAM policy, role, Pod Identity association
└── policies/           official IAM policy JSON for the controller (v3.5.0)
docker/                 Dockerfile, .dockerignore, compose file for local testing
k8s/                    namespace, ServiceAccount, SecretProviderClass, DB setup Job, Deployment, Service
learningsteps/          the app (git submodule)
docs/                   NEW_ACCOUNT_SETUP.md: moving the project to another AWS account
network-map-full.drawio / .png   architecture diagram
```

## Deploy

**Prerequisites:** Terraform ≥ 1.10, AWS CLI v2 (logged in with `aws sso login` or `aws login`), kubectl, Helm, Docker Desktop.

> **Moving to your own or another AWS account** (IAM user, `aws login`, new state bucket, region change, load balancer, AI assistant setup)? Follow [docs/NEW_ACCOUNT_SETUP.md](docs/NEW_ACCOUNT_SETUP.md).

1. Create `infrastructure/terraform.tfvars` (gitignored, never commit it) with your own public IP:
   ```hcl
   my_ip_cidr = "<YOUR-PUBLIC-IP>/32"   # look it up at https://checkip.amazonaws.com
   ```
2. Deploy the infrastructure (about 25–30 minutes), from the project root:
   ```bash
   aws sts get-caller-identity          # right account?
   terraform -chdir=infrastructure init
   terraform -chdir=infrastructure plan
   terraform -chdir=infrastructure apply
   ```
3. Connect kubectl (run again after every new cluster, the endpoint changes):
   ```bash
   terraform -chdir=infrastructure output -raw kubeconfig_cmd    # prints the command, run it
   kubectl get nodes -o wide
   ```
4. Build and push the image, update the values that change on every rebuild (image URL, RDS host, secret ARN in `k8s/`), then apply the manifests. Details: [docs/NEW_ACCOUNT_SETUP.md](docs/NEW_ACCOUNT_SETUP.md#step-7-everything-else-that-contains-the-account-id-or-region).
5. Install the AWS Load Balancer Controller and expose the app:
   ```bash
   helm repo add eks https://aws.github.io/eks-charts
   helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.5.0 --set clusterName=<CLUSTER_NAME> --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller --set region=<REGION> --set vpcId=<VPC_ID>
   kubectl apply -f k8s/service.yaml
   kubectl get svc -n learningsteps learningsteps-api -w    # wait for EXTERNAL-IP
   ```

## Destroy

The load balancer is created by Kubernetes, not Terraform. Delete the Service **first**, so the controller removes the NLB, its target group and its security groups (otherwise they block deleting the VPC):

```bash
kubectl delete -f k8s/service.yaml
# wait ~1-2 minutes
terraform -chdir=infrastructure destroy
```

While deployed, this setup costs roughly **$0.35 per hour** (EKS control plane, 2 nodes, 2 NAT gateways, Multi-AZ RDS), plus the NLB while the Service exists. Destroy it after every session.

## Lessons learned

- `terraform validate` only checks syntax. Many errors only appear at `plan` or `apply`, because only AWS knows its rules (e.g. RDS gp3 under 400 GB rejects `storage_throughput`, `admin` is a reserved PostgreSQL username, add-on versions need the full `-eksbuild.N` suffix, AZ names from another region).
- One resource **per subnet** → `for_each`. One resource **spanning** subnets (DB, cluster, endpoint) → a list. Mixing them up creates duplicates.
- Referencing a resource that depends on you creates a **dependency cycle**. Build the value from variables instead.
- Read the error type: `AccessDenied` = IAM. `OperationNotPermitted` ("this account does not support creating load balancers") = an account-level block that no IAM change fixes. That one moved this project to a new account.
- Resources that Kubernetes creates in AWS are invisible to Terraform: clean them up through Kubernetes before `terraform destroy`.
- In a shared account: unique names, an `Owner` tag on everything, and always verify leftovers after `destroy`. With two accounts on one PC: `aws sts get-caller-identity` before every change.

## Next steps

- [x] Build and push the app image to ECR
- [x] Kubernetes manifests for AWS (ServiceAccount, `SecretProviderClass` with `provider: aws`, DB setup Job, Deployment, Service)
- [x] AWS Load Balancer Controller (Terraform IAM + Pod Identity, Helm install)
- [ ] Public NLB tested end to end in the new account
- [ ] GitHub Actions with OIDC (no stored AWS keys)
- [ ] Template the secret ARN, RDS endpoint and image tag from Terraform outputs
- [ ] TLS on the load balancer
- [ ] NetworkPolicies + Pod Security labels
