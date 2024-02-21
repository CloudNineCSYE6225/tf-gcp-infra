#defining variables
variable "project_id" {
  type    = string
  description = "The Google Cloud project ID."
  default = "dev6225webapp"
}


variable "vpc_name" {
  description = "The name of the VPC network"
  type        = list(string)
  default     = ["cloudvpc-vpc"]
}

variable "webapp_subnet_cidr" {
  description = "The IP CIDR range for the webapp subnet"
  type        = string
  default     = "10.1.0.0/24"
}

variable "db_subnet_cidr" {
  description = "The IP CIDR range for the db subnet"
  type        = string
  default     = "10.2.0.0/24"
}

variable "custom_image" {
  description = "The custom image for the boot disk of the compute instance"
  type        = string
}

