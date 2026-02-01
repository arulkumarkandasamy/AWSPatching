locals {

# 1. Read the CSV file
  raw_csv_data = csvdecode(file("${path.module}/account_owners.csv"))

  # 2. Group the data by Account ID
  # The ellipsis (...) creates a list of rows for each unique accountid
  grouped_by_account = {
    for row in local.raw_csv_data : row.accountid => row...
  }

  # 3. Final Transformation: Create the variable object
  # Structure: { "AccountID" = { "InstanceID" = "OwnerEmail" } }
  instance_owner_map = {
    for account_id, items in local.grouped_by_account : account_id => {
      for item in items : item.instanceid => item.owner_email
    }
  }

  # --- WINDOWS BASELINES ---
  patch_baselines = [
    {
      name               = "CCS-Windows-${var.patch_tag_value}"
      description        = "Baseline for WINDOWS ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "WINDOWS"
      # LOGIC: If Prod, this is 30. If Dev, this is 0.
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["CriticalUpdates", "SecurityUpdates"]
        },
        {
          key    = "MSRC_SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    # --- LINUX BASELINES ---
    {
      name               = "CCS-SUSE-${var.patch_tag_value}"
      description        = "Baseline for SUSE ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "SUSE"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Recommended"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-rhel-${var.patch_tag_value}"
      description        = "Baseline for REDHAT_ENTERPRISE_LINUX ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "REDHAT_ENTERPRISE_LINUX"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-ubuntu-${var.patch_tag_value}"
      description        = "Baseline for UBUNTU ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "UBUNTU"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "PRIORITY"
          values = ["Important", "Required"]
        }
      ]
    },
    {
      name               = "CCS-centos-${var.patch_tag_value}"
      description        = "Baseline for CENTOS ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "CENTOS"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-debian-${var.patch_tag_value}"
      description        = "Baseline for DEBIAN ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "DEBIAN"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "PRIORITY"
          values = ["Important", "Required"]
        }
      ]
    },
    {
      name               = "CCS-oracle-linux-${var.patch_tag_value}"
      description        = "Baseline for ORACLE_LINUX ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "ORACLE_LINUX"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-amazon-linux-${var.patch_tag_value}"
      description        = "Baseline for AMAZON_LINUX ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "AMAZON_LINUX"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-amazon-linux-2-${var.patch_tag_value}"
      description        = "Baseline for AMAZON_LINUX_2 ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "AMAZON_LINUX_2"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    },
    {
      name               = "CCS-amazon-linux-2023-${var.patch_tag_value}"
      description        = "Baseline for AMAZON_LINUX_2023 ${var.patch_tag_value} (Delay: ${var.patch_delay_days} days)"
      os                 = "AMAZON_LINUX_2023"
      approve_after_days = var.patch_delay_days
      patch_filters = [
        {
          key    = "CLASSIFICATION"
          values = ["Security", "Bugfix"]
        },
        {
          key    = "SEVERITY"
          values = ["Critical", "Important"]
        }
      ]
    }
  ]
}
