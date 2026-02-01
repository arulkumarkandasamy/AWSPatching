# AWS Automated Patching Module with Opt-Out & Orchestration

This Terraform module deploys a robust, automated patching framework for AWS EC2 instances (Windows & Linux). It includes an orchestrated workflow with safety checks, an "Opt-Out" self-service capability for account owners, and automated compliance reporting.

## 🏗️ Architecture

This module implements a **Hub-and-Spoke** patching strategy (or standalone per account) with the following key workflows:

1. **Scheduling:** A Maintenance Window runs weekly (Saturday 22:00 UTC).
2. **Notification & Opt-Out:**
* **Smart Poller:** A Lambda function polls upcoming windows and sends emails at T-7 days, T-1 day, and T-1 hour.
* **Self-Service:** Emails contain a link to an API Gateway + Lambda that logs an "Opt-Out" request in DynamoDB.


3. **Orchestration (SSM Automation):**
* **Step 1:** Check DynamoDB for valid "Opt-Out" status. (Stops if found).
* **Step 2:** Disable CloudWatch Alarms (prevent noise).
* **Step 3:** Run Pre-Check (Disk Space > 10%).
* **Step 4:** Apply Patches (`AWS-RunPatchBaseline`).
* **Step 5:** Run Post-Check (Service validation).
* **Step 6:** Re-enable CloudWatch Alarms.


4. **Reporting:**
* **Instant:** SNS Alerts on Task Failure or Success.
* **Monthly:** Static CSV report exported to S3 on the 1st of every month.



## ✨ Key Features

* **N-1 Strategy:** Production patches are delayed by 30 days; Development patches are installed immediately.
* **Multi-OS Support:** Automatically maps `PatchGroup` tags to the correct Baseline (Windows or Amazon Linux 2).
* **Safety First:** Pre-checks prevent patching if disk space is low.
* **User Control:** One-click Opt-Out mechanism postpones patching for 1 week.
* **Dynamic Monitoring:** "Smart Poller" handles manual schedule changes in the AWS Console automatically.

## 📂 Repository Structure

```text
.
├── main.tf                 # Root entry point (calls modules)
├── variables.tf            # Global variables
├── modules/
│   ├── patching-spoke-execution/
│   │   ├── main.tf         # Maintenance Windows & Baselines
│   │   ├── documents.tf    # SSM Automation (Orchestrator, Pre/Post Checks)
│   │   ├── opt_out.tf      # API Gateway, Lambda, DynamoDB (Opt-Out logic)
│   │   ├── csv_reporting.tf# Monthly S3 Report automation
│   │   ├── iam.tf          # IAM Roles for SSM, Lambda, and EventBridge
│   │   ├── variables.tf    # Module-specific variables
│   │   └── outputs.tf      # Module outputs

```

## 📋 Prerequisites

1. **Terraform:** v1.0.0 or later.
2. **AWS CLI:** Configured with appropriate permissions.
3. **S3 Bucket (Central):** A bucket must exist for storing patch reports (referenced via `central_bucket_name`).
4. **Tagging Strategy:** Target instances must be tagged with `PatchGroup`.

## ⚙️ Configuration Variables

| Variable | Description | Default | Required |
| --- | --- | --- | --- |
| `patch_tag_value` | The tag value to target (e.g., "Production" or "Development"). | N/A | **Yes** |
| `patch_delay_days` | Days to wait before approving patches (0 for Dev, 30 for Prod). | `0` | **Yes** |
| `require_reboot` | Boolean to determine if instances reboot after patching. | `true` | No |
| `central_bucket_name` | Name of the S3 bucket for storing CSV reports. | N/A | **Yes** |
| `patching_task_notification_events` | List of statuses to notify on (Success, Failed, etc.). | `["Failed", "TimedOut", "Success"]` | No |

## 🚀 Execution Steps

### 1. Initialize Terraform

Download the required provider plugins and initialize the backend.

```bash
terraform init

```

### 2. Plan the Deployment

Review the resources that will be created. Use a `.tfvars` file for specific environment settings.

**Example `production.tfvars`:**

```hcl
patch_tag_value  = "Production"
patch_delay_days = 30
central_bucket_name = "my-org-central-reports"

```

Run the plan:

```bash
terraform plan -var-file="production.tfvars" -out=tfplan

```

### 3. Apply the Configuration

Deploy the infrastructure.

```bash
terraform apply "tfplan"

```

### 4. Post-Deployment Verification

#### A. Verify Maintenance Window

1. Go to **AWS Systems Manager > Maintenance Windows**.
2. Confirm a window named `CCS-Patching-Window-Production` exists.
3. Verify the Next Execution time is correct (Saturday 22:00).

#### B. Verify Baselines

1. Go to **Patch Manager > Patch Baselines**.
2. Confirm `CCS-Windows-Production` and `CCS-AL2-Production` exist.
3. Check the "Approval Rules" to ensure the `Auto-approval delay` matches your variable (e.g., 30 days).

#### C. Test the Opt-Out Link

1. Wait for the hourly "Smart Poller" to run, or manually invoke the Lambda `CCS-Patching-Notification-Poller`.
2. Check your email for the notification.
3. Click the **Opt-Out Link**.
4. You should see a green "Opt-Out Successful" page.
5. Check the DynamoDB table `CCS-Patching-OptOut-State` to confirm your Account ID is listed with an expiry timestamp.

## 🛠️ Troubleshooting

**Issue: Emails are not arriving.**

* Check the **SNS Topic** subscription status. You must confirm the subscription via email link.
* Check **CloudWatch Logs** for the Lambda `CCS-Patching-Notification-Poller`.

**Issue: Patching ran even though I opted out.**

* Check the **DynamoDB** table. Is the `OptOutExpiry` timestamp in the future?
* Check the **Maintenance Window History**. Look at the `VerifyOptOut` step output. If it says `false`, the database check failed or returned no item.

**Issue: "InvalidDocumentContent" Error during Terraform Apply.**

* Ensure your `documents.tf` is using `python3.11` runtime (not 3.8).
* Ensure the `aws:branch` step in the Orchestrator document uses a String for `Default`, not a map.