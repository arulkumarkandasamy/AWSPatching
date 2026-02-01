# Central Patching Reporting Module

This Terraform module sets up the **Central Reporting Hub** for your AWS Patching infrastructure. It deploys the storage (S3), security policies, and the **Analytics Stack** (Glue & Athena) required to monitor compliance across your entire AWS Organization.

## 🏗️ Architecture

This module implements a serverless data lake for patch compliance:

1. **Ingestion:** Spoke accounts sync inventory data to the Central S3 Bucket.
2. **Cataloging (Glue):** A daily Glue Crawler scans the bucket to understand the data structure (schema).
3. **Analysis (Athena):** Pre-defined SQL queries allow you to export compliance reports.
4. **Visualization (QuickSight):** (Optional) The Glue Data Catalog serves as the source for QuickSight dashboards.

## ✨ Key Features

* 
**Centralized Storage:** Aggregates patch compliance data from the entire Organization into a single S3 bucket.


* 
**Automated Discovery:** An AWS Glue Crawler runs daily at **10:00 AM** to detect new accounts and update the database schema automatically.


* 
**SQL-Ready:** Creates an Athena Named Query (`OrgPatchComplianceCSV`) to instantly list all non-compliant instances across all accounts.


* **Security Best Practice:** Uses `aws:SourceOrgID` conditions to strictly limit write access to your AWS Organization.

## 📂 Resources Created

| Resource | Service | Description |
| --- | --- | --- |
| `aws_s3_bucket` | **S3** | The central repository for patch inventory data.

 |
| `aws_glue_catalog_database` | **Glue** | The database (`org_patch_compliance_db`) holding the table definitions.

 |
| `aws_glue_crawler` | **Glue** | <br>`org-patch-compliance-crawler` scans S3 daily to update tables.

 |
| `aws_athena_named_query` | **Athena** | <br>`OrgPatchComplianceCSV` - A saved SQL query to find non-compliant nodes.

 |

## ⚙️ Configuration Variables

| Variable | Description | Type | Required |
| --- | --- | --- | --- |
| `bucket_name` | The globally unique name for the central S3 bucket. | `string` | **Yes** |
| `org_id` | Your AWS Organization ID (starts with `o-`). | `string` | **Yes** |

## 📊 Analytics & Reporting Workflow

This module prepares your data for Business Intelligence (BI) tools.

### 1. AWS Glue (The Catalog)

The module creates a database named **`org_patch_compliance_db`**.

* **The Crawler:** Runs automatically every day at 10:00 UTC. It looks at your S3 data and creates/updates a table (usually named after your bucket, with `-` replaced by `_`).


* **Manual Run:** You can manually run the crawler from the AWS Console immediately after deployment to populate the initial tables.

### 2. AWS Athena (The Query Engine)

A named query **`OrgPatchComplianceCSV`** is saved in your Athena workgroup. You can run this to get a raw list of vulnerable servers.

**The Logic:**
It selects `accountid`, `instance_id`, `os`, and `hostname`, filtering specifically for items where `status != 'COMPLIANT'`.

### 3. Amazon QuickSight (The Dashboard)

While QuickSight is not provisioned via Terraform (it requires manual subscription), this module sets up the backend for it.

**How to connect QuickSight:**

1. Open QuickSight.
2. Create a **New Dataset**.
3. Select **Athena** as the data source.
4. Choose the database **`org_patch_compliance_db`**.
5. Select the table created by the crawler.
6. *Result:* You can now drag-and-drop fields to create pie charts (Compliant vs. Non-Compliant) or bar charts (Patch Status by Account).

## 🚀 Usage Example

```hcl
module "patch_reporting" {
  source = "./modules/patching-central-reporting"

  bucket_name = "ccs-central-patch-compliance-hub"
  org_id      = "o-1234567890"
}

```

## 🛠️ Post-Deployment Verification

1. **Check the Crawler:**
* Go to **AWS Glue > Crawlers**.
* Select `org-patch-compliance-crawler` and click **Run**.
* Wait for it to complete and verify it says "Table changes: 1".


2. **Test Athena:**
* Go to **Athena > Saved Queries**.
* Select `OrgPatchComplianceCSV`.
* Click **Run**. You should see rows of instance data if your spoke accounts have synced their inventory.



### **Part 3: Final Config Steps**

1. **Run Terraform Apply in Master:** This creates the TGW and WSUS.
2. **Get WSUS IP:** Copy the `wsus_ip` output.
3. **Update `TestSetup/main.tf`:** Paste that IP into `UpdateServiceUrl`.
4. **Run Terraform Apply in Dev:** This connects the VPCs.
5. **Configure WSUS Server (Manual Step):**
* RDP into the Master WSUS Server.
* Open "Server Manager" > WSUS.
* Run the Configuration Wizard.
* **Crucial:** Select "Synchronize from Microsoft Update".
* Let it sync (this takes time).


### **Prerequisite Check**

Ensure you have enabled RAM sharing in your Organization settings. If you haven't done this yet, run this one-time command in your Master account via CLI (or check the setting in the console):

```bash
aws ram enable-sharing-with-aws-organization

```


### **Method 1: Reset Password via Console (Fastest)**

Since your instance is managed by SSM, you can bypass the RDP lock immediately:

1. Go to the **AWS Console > Systems Manager**.
2. On the left menu, select **Session Manager**.
3. Click **Start session**.
4. Select your **CCS-Master-WSUS** instance and click **Start session**.
* *If you don't see it, wait 5 minutes for the instance to initialize.*


5. You will get a black terminal screen (PowerShell). Run this command to set your own password:
```powershell
net user Administrator "SecurePwd123!"

```