#Создание пустой VPC
# Network
resource "yandex_vpc_network" "default" {
  name = "netology-vpc"
}

# subnet public-a
resource "yandex_vpc_subnet" "public-a" {
  name           = "public-a"
  zone           = "ru-central1-a"
  network_id     = "${yandex_vpc_network.default.id}"
  v4_cidr_blocks = ["192.168.10.0/24"]
}

# subnet public-b
resource "yandex_vpc_subnet" "public-b" {
  name           = "public-b"
  zone           = "ru-central1-b"
  network_id     = "${yandex_vpc_network.default.id}"
  v4_cidr_blocks = ["192.168.20.0/24"]
}

# subnet public-d
resource "yandex_vpc_subnet" "public-d" {
  name           = "public-d"
  zone           = "ru-central1-d"
  network_id     = "${yandex_vpc_network.default.id}"
  v4_cidr_blocks = ["192.168.30.0/24"]
}
