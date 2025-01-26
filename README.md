Примечание: ip адреса хостов будут меняться, т.к я деала это задание не один день и не одну неделю, а деньги на промокоде сильно ограничены

**Создание облачной инфраструктуры**

Для начала подготовим всю нашу инфрастркутуру в Yandex Cloud в Terraform-манифестах

1) Подготовим манифест для сервисного аккаунта для доступа к S3-бакету в котором будут удаленно хранится наши Terraform-стейты

[service-account.tf](https://github.com/mezhibo/DiplomV2/blob/da27501c50d6d1107a6be1c36ea95701e626f48b/Chapter1/service-account.tf)

```
# Создание сервисного аккаунта для Terraform
resource "yandex_iam_service_account" "service" {
  name      = var.account_name
  description = "service account to manage VMs"
  folder_id = var.folder_id
}

# Назначение роли editor сервисному аккаунту
resource "yandex_resourcemanager_folder_iam_member" "editor" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.service.id}"
  depends_on = [yandex_iam_service_account.service]
}

# Создание статического ключа доступа для сервисного аккаунта
resource "yandex_iam_service_account_static_access_key" "terraform_service_account_key" {
  service_account_id = yandex_iam_service_account.service.id
  description        = "static access key for object storage"
}

# Создание сервисного аккаунта для K8s
resource "yandex_iam_service_account" "kuber" {
  name      = var.kuber
  description = "service account to manage VMs"
  folder_id = var.folder_id
}

# Назначение роли editor сервисному аккаунту
resource "yandex_resourcemanager_folder_iam_member" "kuber-admin" {
  folder_id = var.folder_id
  role      = "editor"
  member    = "serviceAccount:${yandex_iam_service_account.kuber.id}"
  depends_on = [yandex_iam_service_account.kuber]
}

# Создание статического ключа доступа для сервисного аккаунта
resource "yandex_iam_service_account_static_access_key" "terraform_service_account_key_k8s" {
  service_account_id = yandex_iam_service_account.kuber.id
  description        = "static access key for object storage"
}

```

2) Далее подготовим манифест нашего бэкэнда для удаленного хранения стейтов в S3

[backend.tf](https://github.com/mezhibo/DiplomV2/blob/051150b968bd700f8cf39b1742edd75976a3473e/Chapter1/backend.tf)

```
# Создание объекта в существующей папке
resource "yandex_storage_object" "backend" {
  access_key = yandex_iam_service_account_static_access_key.terraform_service_account_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.terraform_service_account_key.secret_key
  bucket = local.bucket_name
  key    = "terraform.tfstate"
  source = "./terraform.tfstate"
  depends_on = [yandex_storage_bucket.state_storage]
}
```


3) Создадим сеть и подсети для наших виртуальных машин в разных зонах доступности

[network.tf](https://github.com/mezhibo/DiplomV2/blob/f6b8219d845884f74ed150313380010b5f24a2b8/Chapter1/network.tf)

```
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
```

4) Создадим наш файл провайдера для доступа к Terraform

[provider.tf](https://github.com/mezhibo/DiplomV2/blob/276cea98f95b9ff23dc58c3f16ba6ce65f9c637c/Chapter1/provider.tf)

```
terraform {
  required_providers {
    yandex = {
      source = "yandex-cloud/yandex"
    }
  }
  required_version = ">=0.13"
}

provider "yandex" {
  token     = var.token
  cloud_id  = var.cloud_id
  folder_id = var.folder_id
  zone      = var.default_zone
}
```

5) Подготовим манифест для  создания нашего S3 бакета для хранения стейтов

[s3.tf](https://github.com/mezhibo/DiplomV2/blob/23daa6656aa6ff5b35168997ade6a4cd9be1b17f/Chapter1/s3.tf)

```
# Создадим бакет с использованием ключа
resource "yandex_storage_bucket" "state_storage" {
  bucket     = local.bucket_name
  access_key = yandex_iam_service_account_static_access_key.terraform_service_account_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.terraform_service_account_key.secret_key

  anonymous_access_flags {
    read = false
    list = false
  }
}

# Локальная переменная отвечающая за текущую дату в названии бакета
locals {
    current_timestamp = timestamp()
    formatted_date = formatdate("DD-MM-YYYY", local.current_timestamp)
    bucket_name = "state-storage-${local.formatted_date}"
}

```

6) Так как безопасность-наше все, создадим security groups для контроля траффика

[sg.tf](https://github.com/mezhibo/DiplomV2/blob/f9e9b285b4695c689aea3eb9abfcb8d709620d41/Chapter1/sg.tf)


```
resource "yandex_vpc_security_group" "k8s-main-sg" {
  name        = "k8s-main-sg"
  description = "Правила группы обеспечивают базовую работоспособность кластера"
  network_id  = "${yandex_vpc_network.default.id}"
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает проверки доступности с диапазона адресов балансировщика нагрузки. Нужно для работы отказоустойчивого кластера и сервисов балансировщика."
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol          = "ANY"
    description       = "Правило разрешает взаимодействие мастер-узел и узел-узел внутри группы безопасности."
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }
  ingress {
    protocol       = "ANY"
    description    = "Правило разрешает взаимодействие под-под и сервис-сервис. Указываем подсети нашего кластера и сервисов."
    v4_cidr_blocks = concat("${yandex_vpc_subnet.public-a.v4_cidr_blocks}", "${yandex_vpc_subnet.public-b.v4_cidr_blocks}", "${yandex_vpc_subnet.public-d.v4_cidr_blocks}", )
    from_port      = 0
    to_port        = 65535
  }
  ingress {
    protocol       = "ICMP"
    description    = "Правило разрешает отладочные ICMP-пакеты из внутренних подсетей."
    v4_cidr_blocks = ["172.16.0.0/12", "10.0.0.0/8", "192.168.0.0/16"]
  }
  ingress {
    protocol          = "TCP"
    description       = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавляем или изменяем порты на нужные нам."
    v4_cidr_blocks    = ["0.0.0.0/0"]
    from_port         = 30000
    to_port           = 32767
  }

  egress {
    protocol       = "ANY"
    description    = "Правило разрешает весь исходящий трафик. Узлы могут связаться с Yandex Container Registry, Object Storage, Docker Hub и т.д."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

resource "yandex_vpc_security_group" "k8s-public-services" {
  name        = "k8s-public-services"
  description = "Правила группы разрешают подключение к сервисам из интернета. Применяем правила только для групп узлов."
  network_id  = "${yandex_vpc_network.default.id}"

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает входящий трафик из интернета на диапазон портов NodePort. Добавляем или изменяем порты на нужные нам."
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 30000
    to_port        = 32767
  }
}

resource "yandex_vpc_security_group" "k8s-nodes-ssh-access" {
  name        = "k8s-nodes-ssh-access"
  description = "Правила группы разрешают подключение к узлам кластера по SSH. Применяем правила только для групп узлов."
  network_id  = "${yandex_vpc_network.default.id}"

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к узлам по SSH с указанных IP-адресов."
    v4_cidr_blocks = ["${var.host_ip}"]
    port           = 22
  }
}

resource "yandex_vpc_security_group" "k8s-master-whitelist" {
  name        = "k8s-master-whitelist"
  description = "Правила группы разрешают доступ к API Kubernetes из интернета. Применяем правила только к кластеру."
  network_id  = "${yandex_vpc_network.default.id}"

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 6443 из указанной сети."
    v4_cidr_blocks = ["${var.host_ip}"]
    port           = 6443
  }

  ingress {
    protocol       = "TCP"
    description    = "Правило разрешает подключение к API Kubernetes через порт 443 из указанной сети."
    v4_cidr_blocks = ["${var.host_ip}"]
    port           = 443
  }
}
```



7) Заполним файл с перменными для получения всех значений в наших манифестах


[variables.tf](https://github.com/mezhibo/DiplomV2/blob/146ec02c5984250481177e27158cda96986b2ab1/Chapter1/variables.tf)

```
#cloud vars
variable "token" {
  type        = string
  default     = "ЗДЕСЬ_МОГЛА_БЫТЬ_ВАША_РЕКЛАМА"
  description = "OAuth-token; https://cloud.yandex.ru/docs/iam/concepts/authorization/oauth-token"
}

variable "cloud_id" {
  type        = string
  default     = "ЗДЕСЬ_МОГЛА_БЫТЬ_ВАША_РЕКЛАМА"
  description = "https://cloud.yandex.ru/docs/resource-manager/operations/cloud/get-id"
}

variable "folder_id" {
  type        = string
  default     = "ЗДЕСЬ_МОГЛА_БЫТЬ_ВАША_РЕКЛАМА"
  description = "https://cloud.yandex.ru/docs/resource-manager/operations/folder/get-id"

}

variable "default_zone" {
  type        = string
  default     = "ru-central1-a"
  description = "https://cloud.yandex.ru/docs/overview/concepts/geo-scope"
}

variable "account_name" {
  type        = string
  default     = "service"
  description = "account_name"
}

variable "kuber" {
  type        = string
  default     = "kuber"
  description = "account_name"
}

# IP
variable "host_ip" {
  default = "0.0.0.0/0"
}


variable "vpc_name" {
  type        = string
  default     = "vpc0"
  description = "VPC network"
}

variable "subnet-a" {
  type        = string
  default     = "subnet-a"
  description = "subnet name"
}

variable "subnet-b" {
  type        = string
  default     = "subnet-b"
  description = "subnet name"
}

variable "subnet-d" {
  type        = string
  default     = "subnet-d"
  description = "subnet name"
}

variable "zone-a" {
  type        = string
  default     = "ru-central1-a"
  description = "https://cloud.yandex.ru/docs/overview/concepts/geo-scope"
}

variable "zone-b" {
  type        = string
  default     = "ru-central1-b"
  description = "https://cloud.yandex.ru/docs/overview/concepts/geo-scope"
}

variable "zone-d" {
  type        = string
  default     = "ru-central1-d"
  description = "https://cloud.yandex.ru/docs/overview/concepts/geo-scope"
}

variable "cidr-a" {
  type        = list(string)
  default     = ["10.0.1.0/24"]
  description = "https://cloud.yandex.ru/docs/vpc/operations/subnet-create"
}

variable "cidr-b" {
  type        = list(string)
  default     = ["10.0.2.0/24"]
  description = "https://cloud.yandex.ru/docs/vpc/operations/subnet-create"
}

variable "cidr-d" {
  type        = list(string)
  default     = ["10.0.3.0/24"]
  description = "https://cloud.yandex.ru/docs/vpc/operations/subnet-create"
}
```


Манифесты готовы, теперь делаем Terraform apply и создаем наши ресурсы

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/1.jpg)


Видим что наша сеть и подсети создались (дефолтные создает сам яндекс в клауде, удалять не стал так все пересоздадутся, и работе не мешают)


Создался бакет для хранения


![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/2.jpg)


Теперь через веб-интерфейс сходим в бакет, и увидим там файлы стейтов (состояний) Terraform


![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/3.jpg)


Скачиваем его к себе и видим описание всех созданных нами ресурсов через Terraform


![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/4.jpg)

Теперь также одной командой грохнем всю инфраструктуру и пойдем писать далее Terraform манифесты для виртуальных машин под наш k8s кластер.


![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/5.jpg)


Первая часть диплома по подготовке инфраструктуры готова. Теперь можно приступать к созданию окружения на ВМ для развертывания на них k8s кластера.



**Создание Kubernetes кластера**

Создавать кластер буду через наиболее рациональное решение, и более выгодное, т.к оно умеет удалять ноды по мере надобности и их создавать, а именно
подниму отказоустойчивый k8s кластер через Yandex Managed Service for Kubernetes, очень удобное и выгодное решение с огромным множеством плюсов (более подробно расскажут менеджеры Яндекс, я здесь не за этим))))

Создам манифест для развертывания кластера из 3 нод

[k8s.tf](https://github.com/mezhibo/DiplomV2/blob/b01b468fef44ccc52baa365dbea5200c5014b876/Chapter2/k8s.tf)

```

resource "yandex_kubernetes_cluster" "k8s-cluster" {
  name = "k8s-cluster"
  network_id = "${yandex_vpc_network.default.id}"

  master {
    regional {
      region = "ru-central1"

      location {
        zone      = "${yandex_vpc_subnet.public-a.zone}"
        subnet_id = "${yandex_vpc_subnet.public-a.id}"
      }

      location {
        zone      = "${yandex_vpc_subnet.public-b.zone}"
        subnet_id = "${yandex_vpc_subnet.public-b.id}"
      }

      location {
        zone      = "${yandex_vpc_subnet.public-d.zone}"
        subnet_id = "${yandex_vpc_subnet.public-d.id}"
      }
    }

    security_group_ids = ["${yandex_vpc_security_group.k8s-main-sg.id}",
                          "${yandex_vpc_security_group.k8s-master-whitelist.id}"
    ]

    version   = "1.28"
    public_ip = true

    master_logging {
      enabled = true
      folder_id = "${var.folder_id}"
      kube_apiserver_enabled = true
      cluster_autoscaler_enabled = true
      events_enabled = true
      audit_enabled = true
    }    
  }
  service_account_id      = yandex_iam_service_account.kuber.id
  node_service_account_id = yandex_iam_service_account.kuber.id
}

# Create worker-nodes-a
resource "yandex_kubernetes_node_group" "worker-nodes-a" {
  cluster_id = "${yandex_kubernetes_cluster.k8s-cluster.id}"
  name       = "worker-nodes-a"
  version    = "1.28"
  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.public-a.id}"]
      security_group_ids = [
        "${yandex_vpc_security_group.k8s-main-sg.id}",
        "${yandex_vpc_security_group.k8s-nodes-ssh-access.id}",
        "${yandex_vpc_security_group.k8s-public-services.id}"
      ]
    }

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
  }
  }

  allocation_policy {
    location {
      zone = "${yandex_vpc_subnet.public-a.zone}"
    }
  }
}


# Create worker-nodes-b
resource "yandex_kubernetes_node_group" "worker-nodes-b" {
  cluster_id = "${yandex_kubernetes_cluster.k8s-cluster.id}"
  name       = "worker-nodes-b"
  version    = "1.28"
  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.public-b.id}"]
      security_group_ids = [
        "${yandex_vpc_security_group.k8s-main-sg.id}",
        "${yandex_vpc_security_group.k8s-nodes-ssh-access.id}",
        "${yandex_vpc_security_group.k8s-public-services.id}"
      ]
    }

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
  }
  }

  allocation_policy {
    location {
      zone = "${yandex_vpc_subnet.public-b.zone}"
    }
  }
}

# Create worker-nodes-d
resource "yandex_kubernetes_node_group" "worker-nodes-d" {
  cluster_id = "${yandex_kubernetes_cluster.k8s-cluster.id}"
  name       = "worker-nodes-d"
  version    = "1.28"
  instance_template {
    platform_id = "standard-v2"

    network_interface {
      nat                = true
      subnet_ids         = ["${yandex_vpc_subnet.public-d.id}"]
      security_group_ids = [
        "${yandex_vpc_security_group.k8s-main-sg.id}",
        "${yandex_vpc_security_group.k8s-nodes-ssh-access.id}",
        "${yandex_vpc_security_group.k8s-public-services.id}"
      ]
    }

    resources {
      memory = 4
      cores  = 2
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    container_runtime {
      type = "containerd"
    }
  }

  scale_policy {
    fixed_scale {
      size = 1
  }
  }

  allocation_policy {
    location {
      zone = "${yandex_vpc_subnet.public-d.zone}"
    }
  }
}
```

Рабочие ноды были созданы в разных node-group для максимальной отказоустойчивости кластера, а именно, каждая node-группа
располагается в разной зоне доступности, и в случае падения зоны А (да-да, привет Яндекс и 3 падения зоны А за Декабрь 2024 года)

К сожалению Яндекс не дает возможности создать 3 разных ноды в разных зонах доступности в рамках однйо нод-группы, но нод группы будет 3.
И учитывая что архитектуру свой инфарструктуры клауда я продумывал долго и с умом, сети у меня тоже в 3 разных зонах, так что если у Яндекса опять
будут "Частичная недоступность сети ru-central1-a", то мое приложение от этого никак не пострадает.

Опять делаем
```
terraform apply
```

Смотрим ноды

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/6.jpg)

Все супер, все в разных зонах.

Теперь чтобы удобнее было работать с кластером, я подключу Lens через YC и Power Shell, и через yc и kubectl внутри WSL (инструкция есть в интернете, расписывать не буду)

Подключимся Линзой и глянем ест ли наши поды во всех неймспейсах


![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/7.jpg)

Теперь пойдем дальше, запилим наше приложение)))



**Создание тестового приложения**


Мы не разработчики приложений, поэтому сильно мудрить не будем, просто создадми свой образ nginx со стачной страницей.



Первым этапом создадим на github пустую репу нашего тестового приложения, и склонируем ее себе

```
git clone https://github.com/mezhibo/Test-application.git
```

Создадим в этом репозитории файл содержащую HTML-код ниже:
index.html

[index.html](https://github.com/mezhibo/DiplomV2/blob/75e4d4b1af491d3bed369fa4ba45191350dad199/Chapter3/index.html)


```
<html>
<head>
Hey, Netology
</head>
<body>
<h1>Dev Ops Mezhibo</h1>
</body>
</html>
```

Создадим Dockerfile, который будет запускать веб-сервер Nginx в фоне с индекс страницей:
Dockerfile


[Dockerfile](https://github.com/mezhibo/DiplomV2/blob/0c2a14b495d27372de178c6164a991cc786da2fc/Chapter3/Dockerfile)

```
FROM nginx:1.27-alpine

COPY index.html /usr/share/nginx/html
```
Теперь запушим эти изменения в наш гитхаб репозиторий

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/8.jpg)


Создадим папку для приложения mkdir mynginx и скопируем в нее ранее созданые файлы.
В этой папке выполним сборку приложения:

```
sudo docker build -t mezhibo/nginx:v1 .
```

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/9.jpg)


Проверим что образ сбилдился

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/10.jpg)



И теперь толкнем наш собрыный контейнерв в Docker Hub



![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/11.jpg)



Зайдем в Docker Hub и проверим что наш контейнер доехал

![Image alt](https://github.com/mezhibo/DiplomV2/blob/05be97e401813ad0691112d03cd86de22efc6e97/IMG/12.jpg)


Так, приложение в контейнер сбилдили, в Доке хаб закинули, теперь его будем оттуда забирать и деплоить в наш кубер - кластер.


[ПРИЛОЖЕНИЕ_НА_ГИТХАБ](https://github.com/mezhibo/Test-application.git)


[ПРИЛОЖЕНИЕ_НА_ДОКЕРХАБ](https://hub.docker.com/repository/docker/mezhibo/nginx/general)




**Подготовка cистемы мониторинга и деплой приложения**


Задеплоим свое приложение в наш кубер кластер


Для этого создадим локальный репозиторий и создадим там файлы для наших сущностей кубера.


Первым делом создадим неймспейс под наше приложение

```
kubectl create namespace application

```



Далее создадим файл демонсета для деплоя нашего приложения из докер хаба, где мы его ранее опубликовывали


[Nginx-DaemonSet.yml](https://github.com/mezhibo/DiplomV2/blob/ecab765754b932a36c135c6409ab31f5ebad66fc/Chapter4/Nginx-DaemonSet.yml)

```
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nginx-deamonset
  namespace: application
spec:
  selector:
    matchLabels:
      app: daemonset
  template:
    metadata:
      labels:
        app: daemonset
    spec:
      containers:
      - name: nginx
        image: mezhibo/nginx:v1
```


Так как у нас приложение простое и тестовое, не будем усложнять схему и вместо Ingress или LoadBalancer создаим тип сервиса Node-port

Для проброса порт анашего приложения наружу

[Nginx-Service.yml](https://github.com/mezhibo/DiplomV2/blob/3a1bc957d70826bb361741b7d8f2c75f2f96d951/Chapter4/Nginx-Service.yml)

```
apiVersion: v1
kind: Service
metadata:
  name: nginx-service
  namespace: application
spec:
  ports:
    - name: nginx
      port: 80
      protocol: TCP
      targetPort: 80
      nodePort: 30000
  selector:
    app: daemonset
  type: NodePort
```

Манифесты описаны, теперь запустим создание всех трех сущностей разом


```
kubectl apply -f .

```
Теперь првоерим что все сущности созданы и работают


![Image alt](https://github.com/mezhibo/DiplomV2/blob/b4a2c590f41981f6213be37c04cf36a55ffc68ad/IMG/15.jpg)


Теперь перейдем на по внешнему ip-адресу на проброшенный порт 30000 


И видим что наше собранное приложение с кастомной веб-страницей работает

![Image alt](https://github.com/mezhibo/DiplomV2/blob/b4a2c590f41981f6213be37c04cf36a55ffc68ad/IMG/16.jpg)

УРА!!! Наше приложение работает в кластере.



*Теперь прикрутим мониторинг кластера*


Для удобства установки мониторинга воспользуемся Хельмом

```
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install monitoring prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace

```


Тут, есть один нюанс, по дефолту сервис Графаны у нас ClusterIp, нам его надо выпустить наружу, чтоб она была доступна по внешненму ip-адресу,
изменим тип порта на NodePort

Выполним команду

```
kubectl edit svc -n monitoring monitoring-grafana

```

Находим строку type и меняем ее занчение с ClusterIP на NodePort


**Установка и настройка CI/CD**


Для автоматической сборки и docker-образа при коммите в репозиторий с тестовым приложением воспользуемся платформой CI/CD GitHub Actions


Для начала зайдем на докер-хаб и создадим персональный токен 

Запишем эти 2 значения юзера и токена себе в блокнот


![Image alt](https://github.com/mezhibo/Diplom/blob/3923ca578c63cba70f495f0b1142de101dc25de1/IMG/26.jpg)



Цепочку CI/CD настроим через Github Action

Для этого создадим 2 секрета в Github для репозитория где хранится наше тестовое приложение в которых будут хранится наши логин и токен для доступа в докер-хаб


![Image alt](https://github.com/mezhibo/Diplom/blob/3923ca578c63cba70f495f0b1142de101dc25de1/IMG/27.jpg)


Далее, создадим workflow файл для автоматической сборки приложения nginx: 

[build.yml](https://github.com/mezhibo/Diplom/blob/d2f0b2f2e3735e8838899711a8872f6883e8e522/Chapter5/build.yml)


```
name: Сборка Docker-образа

on:
  push:
    branches:
      - '*'
jobs:
  my_build_job:
    runs-on: ubuntu-latest

    steps:
      - name: Проверка кода
        uses: actions/checkout@v4

      - name: Вход на Docker Hub
        uses: docker/login-action@v2
        with:
          username: ${{ secrets.USER_DOCKER_HUB }}
          password: ${{ secrets.MY_TOKEN_DOCKER_HUB }}

      - name: Сборка Docker-образа
        run: |
          docker build . --file Dockerfile --tag nginx:latest
          docker tag nginx:latest ${{ secrets.USER_DOCKER_HUB }}/nginx:latest

      - name: Push Docker-образа в Docker Hub
        run: |
          docker push ${{ secrets.USER_DOCKER_HUB }}/nginx:latest
```

Проверим что workflow успешно выполнился


![Image alt](https://github.com/mezhibo/Diplom/blob/3923ca578c63cba70f495f0b1142de101dc25de1/IMG/28.jpg)



Перейдем в докерхаб и увидим что появился загруженный образ


![Image alt](https://github.com/mezhibo/Diplom/blob/3923ca578c63cba70f495f0b1142de101dc25de1/IMG/29.jpg)


[ССЫЛКА_НА_ДОКЕРХАБ](https://hub.docker.com/repository/docker/mezhibo/nginx/general)
