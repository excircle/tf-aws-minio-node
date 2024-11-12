locals {
  // Universal AWS Tag
  tag = {
    Name      = null
    CreatedBy = var.createdby_tag
    Owner     = var.owner_tag
    Purpose   = null
  }
  // Host names
  host_names = [for v in range(1, var.hosts+1): "${var.application_name}-${v}"]
  
  // Disks
  disks = [
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z"
  ]
}