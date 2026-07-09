variable "enable_network_access_analyzer" {
  description = "Whether to create the Network Access Analyzer scope. Off by default; the scope is optional."
  type        = bool
  default     = false
}

variable "match_paths" {
  description = "Paths the scope matches, expressed as source/destination AWS resource types. A matched path in an out-of-band analysis is a segmentation-intent violation. Defaults to a single internet-gateway -> instance path."
  type = list(object({
    source_resource_types      = list(string)
    destination_resource_types = list(string)
  }))
  default = [{
    source_resource_types      = ["AWS::EC2::InternetGateway"]
    destination_resource_types = ["AWS::EC2::Instance"]
  }]
}

variable "exclude_paths" {
  description = "Paths excluded from the scope, expressed as source/destination AWS resource types. Excluded paths are ignored even if they would otherwise match."
  type = list(object({
    source_resource_types      = list(string)
    destination_resource_types = list(string)
  }))
  default = []
}
