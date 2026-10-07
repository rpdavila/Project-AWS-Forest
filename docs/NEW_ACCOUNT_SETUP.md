# Moving the project to a new AWS account

A step-by-step guide for moving this Terraform + EKS project from the shared course account ("Playground") to **another AWS account**, where you sign in as an **IAM user**. All commands are for **Windows PowerShell** and run from the **project root** (the folder that contains `infrastructure/` and `k8s/`).

> **Why move?** In the Playground account, the AWS Load Balancer Controller could not create the public load balancer:
> `OperationNotPermitted: This AWS account currently does not support creating load balancers.`
> This is an **account-level block**, not an IAM permission problem (that would say `AccessDenied`). No change in your code or IAM fixes it, so the project needs an account that allows load balancers.

## Placeholders used in this guide

Replace every `<...>` with your own value. Never commit real values that identify you (IP address, email, keys).

| Placeholder | Meaning | Example format |
|---|---|---|
| `<ACCOUNT_ID>` | 12-digit ID of the **new** AWS account | `123456789012` |
| `<IAM_USER>` | Your IAM user name in the new account | `jane` |
| `<LOGIN_PROFILE>` | CLI profile that holds your `aws login` session | `jane-login` |
| `<TF_PROFILE>` | CLI "bridge" profile that Terraform uses | `jane-tf` |
| `<REGION>` | Region for **everything** (state bucket + resources) | `eu-central-1` |
| `<AZ_A>` / `<AZ_B>` | Two Availability Zones in `<REGION>` | `eu-central-1a` / `eu-central-1b` |
| `<PROJECT_NAME>` | Your `project_name` variable (resource prefix) | `jane-forestproject` |
| `<STATE_BUCKET>` | Globally unique S3 bucket for Terraform state | `<PROJECT_NAME>-tfstate-<ACCOUNT_ID>` |
| `<STATE_KEY>` | Path of the state file inside the bucket | `learning-steps/prod/terraform.tfstate` |
| `<YOUR-PUBLIC-IP>` | Your home IP (look it up at https://checkip.amazonaws.com) | `203.0.113.10` |
| `<CLUSTER_NAME>` | EKS cluster name (from `terraform output`) | `<PROJECT_NAME>-eks-cluster` |
| `<VPC_ID>` | From `terraform output -raw vpc_id` | `vpc-0abc...` |
| `<ECR_REPO_URL>` | From `terraform output -raw ecr_repository_url` | `<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/<PROJECT_NAME>/learningsteps` |
| `<RDS_HOST>` | From `terraform output -raw rds_endpoint` (host part only, without `:5432`) | `<PROJECT_NAME>-postgres.xxxx.<REGION>.rds.amazonaws.com` |
| `<DB_SECRET_ARN>` | From `terraform output -raw db_secret_arn` | `arn:aws:secretsmanager:<REGION>:<ACCOUNT_ID>:secret:rds!db-...` |
| `<IMAGE_TAG>` | Git short SHA of the image you push | `ed15632` |

---

## Step 0: what you need

- **AWS CLI v2.32 or newer** (`aws --version`). Older versions don't have `aws login`.
- **Terraform 1.10 or newer**, kubectl, Helm, Docker Desktop.
- **Console access** (user name + password) to the new account as an IAM user, with permissions to build the project. An admin policy works. Minimum for the CLI login: the managed policy `SignInLocalDevelopmentAccess`.

> **If someone added you to *their* AWS Organization:** the organization's admins can see and control your account (and may apply SCPs that block services), and **they pay the bill**. Destroy everything at the end of every session.

## Step 1: secure your IAM user first

1. **Turn on MFA**: AWS console, your user name (top right) → **Security credentials** → **Assign MFA device**. A passkey or security key is the strongest choice (phishing-resistant); an authenticator app is fine too.
2. **Do not create access keys.** `aws login` (Step 2) gives you temporary credentials instead. Long-lived keys are the #1 way AWS accounts get hijacked.

## Step 2: connect the CLI with `aws login` (no access keys)

SSO (`aws sso login`) only works for IAM Identity Center users. For an IAM user, use `aws login`: you sign in through the browser and get temporary credentials that refresh automatically for up to 12 hours.

```powershell
aws login --profile <LOGIN_PROFILE>
```

- When asked for a region, enter `<REGION>`.
- The browser opens. Sign in as `<IAM_USER>` (with MFA) and go back to the terminal.
- If it asks "Configure AWS skills and the AWS MCP server for your AI coding agent(s)?", answer **`n`** unless you know exactly what it changes.

Check it:

```powershell
aws sts get-caller-identity --profile <LOGIN_PROFILE>
```

The `Arn` should be `arn:aws:iam::<ACCOUNT_ID>:user/<IAM_USER>`.

### The bridge profile for Terraform

The Terraform AWS provider is built on the AWS SDK for Go v2, which **can't read `aws login` sessions yet** ([AWS docs](https://docs.aws.amazon.com/sdkref/latest/guide/feature-login-credentials.html)). The documented workaround is a second profile that asks the CLI for the credentials.

Open the config file:

```powershell
notepad $HOME\.aws\config
```

Add this at the end (leave existing profiles alone):

```ini
[profile <TF_PROFILE>]
credential_process = aws configure export-credentials --profile <LOGIN_PROFILE> --format process
region = <REGION>
```

Use it in your PowerShell window (needed again in **every new window**):

```powershell
$env:AWS_PROFILE = "<TF_PROFILE>"
aws sts get-caller-identity
```

> **Two accounts on one PC?** Always run `aws sts get-caller-identity` before creating anything. If your window still uses the old profile, commands go to the **old account** (or fail with "bucket not found" there).

Docs: [Login for AWS local development using console credentials](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html)

## Step 3: create the Terraform state bucket

**Chicken and egg:** Terraform stores its state in this bucket, so Terraform can't create the bucket itself. Make it once with the CLI.

Bucket names are **global across all AWS accounts**, so include your account ID.

```powershell
# any region except us-east-1 (LocationConstraint is REQUIRED there)
aws s3api create-bucket --bucket <STATE_BUCKET> --region <REGION> --create-bucket-configuration LocationConstraint=<REGION>

# us-east-1 only (it must NOT have LocationConstraint)
aws s3api create-bucket --bucket <STATE_BUCKET> --region us-east-1
```

Turn on **versioning**, the "undo button" if a state file ever gets corrupted:

```powershell
aws s3api put-bucket-versioning --bucket <STATE_BUCKET> --versioning-configuration Status=Enabled
```

Verify (new buckets are encrypted and private by default since 2023, but always check):

```powershell
aws s3api get-bucket-versioning --bucket <STATE_BUCKET>        # "Status": "Enabled"
aws s3api get-bucket-encryption --bucket <STATE_BUCKET>        # "SSEAlgorithm": "AES256"
aws s3api get-public-access-block --bucket <STATE_BUCKET>      # all four settings: true
```

## Step 4: point Terraform at the new bucket

Edit `infrastructure/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket = "<STATE_BUCKET>"
    key    = "<STATE_KEY>"
    region = "<REGION>"

    encrypt      = true
    use_lockfile = true
  }
}
```

Then re-initialize:

```powershell
terraform -chdir=infrastructure init -reconfigure
```

Look for `Successfully configured the backend "s3"!`

- Use **`-reconfigure`** when the old state is empty (you destroyed everything in the old account).
- Use **`-migrate-state`** only if you want to *copy* existing state over. Don't do that across accounts: the resources in that state live in the old account.
- If `plan` says `Backend initialization required`, the `init` didn't run (or failed). Run it again.

## Step 5: change the region (if you're switching regions)

In `infrastructure/variables.tf`, change **both**:

1. `aws_region` → `<REGION>`
2. **Every** `az = "..."` in the subnet maps (public, EKS, DB) → `<AZ_A>` / `<AZ_B>`. Keep the keys (`a`, `b`) and the CIDRs as they are.

> ⚠️ **Trap:** if you change only `aws_region`, `terraform plan` still succeeds. Terraform doesn't know which AZs exist. `apply` then builds the VPC and fails on the first subnet:
> `InvalidParameterValue: Value (us-east-1a) for parameter availabilityZone is invalid`

Check that everything the project uses exists in the new region **before** you apply:

```powershell
$R = "<REGION>"
aws ec2 describe-availability-zones --region $R --query "AvailabilityZones[].ZoneName" --output text
aws eks describe-cluster-versions --region $R --query "clusterVersions[?versionStatus=='STANDARD_SUPPORT'].clusterVersion" --output text
aws eks describe-addon-versions --region $R --kubernetes-version <EKS_VERSION> --addon-name eks-pod-identity-agent --query "addons[0].addonVersions[].addonVersion" --output text
aws eks describe-addon-versions --region $R --kubernetes-version <EKS_VERSION> --addon-name aws-secrets-store-csi-driver-provider --query "addons[0].addonVersions[].addonVersion" --output text
aws rds describe-orderable-db-instance-options --region $R --engine postgres --engine-version <PG_VERSION> --db-instance-class <DB_INSTANCE_CLASS> --query "OrderableDBInstanceOptions[].[MultiAZCapable,AvailabilityZones[].Name]" --output json
aws ec2 describe-instance-type-offerings --region $R --location-type availability-zone --filters Name=instance-type,Values=<NODE_INSTANCE_TYPE> --query "InstanceTypeOfferings[].Location" --output text
```

(`<EKS_VERSION>`, `<PG_VERSION>`, `<DB_INSTANCE_CLASS>` and `<NODE_INSTANCE_TYPE>` are the values in your `eks.tf` and `postgresql.tf`.)

## Step 6: your IP, plan, apply

`infrastructure/terraform.tfvars` (gitignored, never commit it):

```hcl
my_ip_cidr = "<YOUR-PUBLIC-IP>/32"
```

```powershell
aws sts get-caller-identity                 # must show <ACCOUNT_ID>
terraform -chdir=infrastructure fmt -check -recursive
terraform -chdir=infrastructure validate
terraform -chdir=infrastructure plan        # read the summary: every resource "to add", 0 to destroy
terraform -chdir=infrastructure apply       # ~25-30 min
```

Connect kubectl to the new cluster:

```powershell
terraform -chdir=infrastructure output -raw kubeconfig_cmd    # prints the command, then run it
kubectl config current-context                                # must end with <CLUSTER_NAME>
kubectl get nodes -o wide
```

## Step 7: everything else that contains the account ID or region

Terraform values update themselves. These files **don't**, so update them after every new account, region or rebuild:

| Where | What to change |
|---|---|
| `~/.docker/config.json` → `credHelpers` | `"<ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com": "ecr-login"` |
| `k8s/deployment.yaml` → `image` | `<ECR_REPO_URL>:<IMAGE_TAG>` |
| `k8s/deployment.yaml` → `DATABASE_URL` | `postgresql://learningsteps@<RDS_HOST>:5432/learning_journal?sslmode=require` |
| `k8s/db-setup-job.yaml` → `psql "host=..."` | `<RDS_HOST>` |
| `k8s/secretproviderclass.yaml` → `region` | `<REGION>` |
| `k8s/secretproviderclass.yaml` → `objectName` | `<DB_SECRET_ARN>` (changes with **every** new RDS instance) |

Then build and push the image (ECR is empty in a new account):

```powershell
$REPO = terraform -chdir=infrastructure output -raw ecr_repository_url
docker build --platform linux/amd64 --provenance=false -f docker/Dockerfile -t learningsteps:local learningsteps
docker tag learningsteps:local "${REPO}:<IMAGE_TAG>"
docker push "${REPO}:<IMAGE_TAG>"
```

And apply the manifests (namespace, ServiceAccount, SecretProviderClass, ConfigMap, Job, Deployment) as described in the main README.

## Step 8: AWS Load Balancer Controller + public Service

The IAM policy, role and Pod Identity association are in `infrastructure/lbcontroller.tf`. Install the controller with Helm:

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update
$vpc = terraform -chdir=infrastructure output -raw vpc_id
helm install aws-load-balancer-controller eks/aws-load-balancer-controller -n kube-system --version 3.5.0 --set clusterName=<CLUSTER_NAME> --set serviceAccount.create=true --set serviceAccount.name=aws-load-balancer-controller --set region=<REGION> --set vpcId=$vpc
kubectl get deployment -n kube-system aws-load-balancer-controller     # wait for 2/2
```

- `serviceAccount.name` must match `service_account` in the Pod Identity association **exactly**.
- `--version` must match the IAM policy file (`policies/aws-lb-controller-v3.5.0.json`).

```powershell
kubectl apply --dry-run=server -f k8s/service.yaml    # validate first
kubectl apply -f k8s/service.yaml
kubectl get svc -n learningsteps learningsteps-api -w # wait for EXTERNAL-IP (Ctrl+C)
```

> 🔐 The app has no login. Once the load balancer is up, **anyone on the internet** can reach `/docs` and write to the database. Keep it up only while you test, and destroy afterwards.

## Step 9: destroy in the right order

The load balancer, its target group and its `k8s-...` security groups are created by **Kubernetes, not Terraform**. If they still exist, `terraform destroy` gets stuck on the VPC.

```powershell
kubectl delete -f k8s/service.yaml                     # the controller cleans up its AWS resources
# wait ~1-2 minutes, then check that these are empty:
aws elbv2 describe-load-balancers --query "LoadBalancers[].LoadBalancerName" --output text
aws ec2 describe-security-groups --filters "Name=group-name,Values=k8s-*" --query "SecurityGroups[].GroupId" --output text
terraform -chdir=infrastructure destroy
```

After destroy, check for leftovers (EKS clusters, EC2 instances, NAT gateways, Elastic IPs, VPCs, RDS instances and snapshots, ECR repositories, IAM roles/policies, the EKS log group). The state bucket from Step 3 stays: it's needed next time and costs almost nothing.

> **Working with an AI assistant** (Claude Code, AWS Knowledge MCP, `CLAUDE.md` template, safety rules)? See [AI assistant setup](../README.md#ai-assistant-setup-claude-code--mcp) in the main README.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `OperationNotPermitted ... does not support creating load balancers` | Account-level block | Different account, or ask the account owner to contact AWS Support |
| `AccessDenied` / `UnauthorizedOperation` | IAM permissions (or an SCP in the organization) | Check your policies / ask the organization admin |
| Command works on the wrong account / "bucket not found" | Window uses the old profile | `$env:AWS_PROFILE = "<TF_PROFILE>"`, then `aws sts get-caller-identity` |
| `Backend initialization required` | `backend.tf` changed, `init` not run | `terraform -chdir=infrastructure init -reconfigure` |
| `chdir infrastructure: cannot find the file` | Terminal is inside a subfolder (e.g. `k8s\`) | `cd ..` to the project root |
| `availabilityZone is invalid` during apply | AZ names from the old region | Update every `az = ...` in `variables.tf` |
| kubectl `i/o timeout` | Your public IP changed | Update `my_ip_cidr` in `terraform.tfvars`, then `apply` |
| kubectl `no such host` | Old kubeconfig context (cluster was recreated) | Run the `kubeconfig_cmd` output again |
| Pods `FailedMount`: failed to fetch secret | Old secret ARN or region in the SecretProviderClass | New `db_secret_arn` output + `<REGION>` |
| `ImagePullBackOff` | Image not pushed to the new ECR, or wrong URL | Push the image, check the `image:` line |
| Service `EXTERNAL-IP <pending>` | Controller can't build the load balancer | `kubectl get events -n learningsteps --field-selector involvedObject.name=learningsteps-api`, then the controller logs |
