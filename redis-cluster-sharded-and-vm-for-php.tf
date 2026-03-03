# Infrastructure for sharded Yandex Managed Service for Valkey™ cluster and Virtual Machine in Yandex Compute Cloud
#
# RU: https://cloud.yandex.ru/docs/managed-valkey/tutorials/valkey-as-php-sessions-storage
# EN: https://cloud.yandex.com/en/docs/managed-valkey/tutorials/valkey-as-php-sessions-storage
#
# Set the following settings:

locals {
  # The following settings are to be specified by the user. Change them as you wish.
  
  # Settings for the Yandex Managed Service for Valkey™ cluster
  password = "" # Password for the Yandex Managed Service for Valkey™ cluster

  # Settings for the VM in Yandex Compute Cloud
  image_id        = "" # Public image ID for the VM in Compute Cloud. See: https://cloud.yandex.com/en/docs/compute/operations/images-with-pre-installed-software/get-list.
  vm_username     = "" # Username to connect to the VM in Compute Cloud via SSH. For Ubuntu images `ubuntu` username is used by default.
  vm_ssh_key_path = "" # Full path to the SSH public key for the VM in Compute Cloud. Example: "~/.ssh/key.pub".

  # The following settings are predefined. Change them only if necessary.
  
  # Settings for the Network infrastructure
  zone_a_v4_cidr_blocks = "10.1.0.0/16" # CIDR block for the subnet in the ru-central1-a availability zone
  zone_b_v4_cidr_blocks = "10.2.0.0/16" # CIDR block for the subnet in the ru-central1-b availability zone
  zone_d_v4_cidr_blocks = "10.3.0.0/16" # CIDR block for the subnet in the ru-central1-d availability zone
  
  # Settings for the Yandex Managed Service for Valkey™ cluster
  version = "7.2-valkey" # Version of the Yandex Managed Service for Valkey™
}

resource "yandex_vpc_network" "redis-and-vm-network" {
  description = "Network for the Yandex Managed Service for Valkey cluster and VM in Compute Cloud"
  name        = "redis-and-vm-network"
}

resource "yandex_vpc_subnet" "subnet-a" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = "subnet-a"
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.redis-and-vm-network.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_subnet" "subnet-b" {
  description    = "Subnet in the ru-central1-b availability zone"
  name           = "subnet-b"
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.redis-and-vm-network.id
  v4_cidr_blocks = [local.zone_b_v4_cidr_blocks]
}

resource "yandex_vpc_subnet" "subnet-d" {
  description    = "Subnet in the ru-central1-d availability zone"
  name           = "subnet-d"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.redis-and-vm-network.id
  v4_cidr_blocks = [local.zone_d_v4_cidr_blocks]
}

resource "yandex_vpc_default_security_group" "redis-and-vm-security-group" {
  description = "Security group for the Yandex Managed Service for Valkey cluster and VM in Compute Cloud"
  network_id  = yandex_vpc_network.redis-and-vm-network.id

  ingress {
    description    = "Allow incoming HTTP connections from the Internet"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow incoming HTTPS connections from the Internet"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow incoming connections to cluster from the Internet"
    protocol       = "TCP"
    port           = 6379
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "Allow incoming SSH connections to VM from the Internet"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description    = "Allow outgoing connections to any required resource"
    protocol       = "ANY"
    from_port      = 0
    to_port        = 65535
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "yandex_mdb_redis_cluster_v2" "redis-cluster" {
  description        = "Yandex Managed Service for Valkey cluster"
  name               = "valkey-cluster"
  environment        = "PRODUCTION"
  network_id         = yandex_vpc_network.redis-and-vm-network.id
  security_group_ids = [yandex_vpc_default_security_group.redis-and-vm-security-group.id]
  sharded            = true

  config = {
    password = local.password
    version  = local.version
  }

  resources = {
    resource_preset_id = "hm2.nano"
    disk_type_id       = "network-ssd"
    disk_size          = 16 # GB
  }

  hosts = {
    host1 = {
      zone       = "ru-central1-a"
      subnet_id  = yandex_vpc_subnet.subnet-a.id
      shard_name = "shard1"
    }

    host2 = {
      zone       = "ru-central1-b"
      subnet_id  = yandex_vpc_subnet.subnet-b.id
      shard_name = "shard2"
    }

    host3 = {
      zone       = "ru-central1-d"
      subnet_id  = yandex_vpc_subnet.subnet-d.id
      shard_name = "shard3"
    }
  }
}


resource "yandex_compute_instance" "lamp-vm" {
  description = "Virtual Machine in Compute Cloud"
  name        = "lamp-vm"
  platform_id = "standard-v3" # Intel Ice Lake

  resources {
    cores  = 2
    memory = 2 # GB
  }

  boot_disk {
    initialize_params {
      image_id = local.image_id
    }
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-a.id
    nat       = true # Required for connection from the Internet
  }

  metadata = {
    ssh-keys = "${local.vm_username}:${file(local.vm_ssh_key_path)}"
  }
}
