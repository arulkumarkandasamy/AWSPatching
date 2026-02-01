resource "aws_ssm_patch_baseline" "ssm_patch_baseline" {
  for_each = { for baseline in local.patch_baselines : baseline.name => baseline }

  name                              = each.value.name
  description                       = each.value.description
  operating_system                  = each.value.os
  approved_patches_compliance_level = "MEDIUM"

  approval_rule {
    approve_after_days = each.value.approve_after_days
    compliance_level   = "MEDIUM"

    dynamic "patch_filter" {
      for_each = each.value.patch_filters
      content {
        key    = patch_filter.value.key
        values = patch_filter.value.values
      }
    }
  }
}

# --- PATCH GROUP REGISTRATIONS ---
# This links the "PatchGroup" tag value (e.g., "Production") to the specific Baseline.
# When an EC2 instance has the tag "Patch Group: Production", SSM checks these registrations
# to find which Baseline to use.

resource "aws_ssm_patch_group" "ssm_patch_group" {
  for_each = { for baseline in local.patch_baselines : baseline.name => baseline }

  baseline_id = aws_ssm_patch_baseline.ssm_patch_baseline[each.key].id
  patch_group = var.patch_tag_value
}