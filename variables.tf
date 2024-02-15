#defining variables
variable "project_id" {
  type    = string
  description = "The Google Cloud project ID."
  default = "cloud6225vpc"
}


variable "vpc_name" {
  description = "The name of the VPC network"
  type        = list(string)
  default     = ["cloudvpc-vpc"]
}
