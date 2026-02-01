variable "central_bucket_name" { type = string }
variable "central_bucket_region" { type = string }
variable "schedule_cron" { 
  type = string
  description = "Cron schedule for maintenance window"
  default = "cron(50 21 ? * TUE *)" # Tuesday at 9 PM
}
variable "patch_tag_key" { 
  default = "PatchGroup" 
  description = "Tag Key to include instance in patching"
}
variable "patch_tag_value" { 
  default = "Development" 
  description = "The value for the PatchGroup tag (e.g., Production or Development)"
  type        = string
}
variable "patch_delay_days" {
  description = "Number of days to wait before approving patches. Set 30 for Production (N-1) and 0 for Development."
  type        = number
  default     = 0
}
variable "stakeholder_email" {
  type = string
  description = "Email to receive failure notifications"
}

variable "patching_task_notification_events" {
  description = "The list of Automation statuses to notify on."
  type        = list(string)
  default     = ["Failed", "TimedOut", "Success"] # Added "Success" as requested
}

variable "wsus_url" {
  type        = string
  description = "The HTTP URL of the WSUS Server (e.g., http://10.100.1.50:8530)"
  default     = "http://10.100.1.204:8530" 
}