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



6) Заполним файл с перменными для получения всех значений в наших манифестах


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

![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/1.jpg)


Видим что наша сеть и подсети создались (дефолтные создает сам яндекс в клауде, удалять не стал так все пересоздадутся, и работе не мешают)


Создался бакет для хранения


![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/2.jpg)


Теперь через веб-интерфейс сходим в бакет, и увидим там файлы стейтов (состояний) Terraform


![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/3.jpg)


Скачиваем его к себе и видим описание всех созданных нами ресурсов через Terraform


![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/4.jpg)

Теперь также одной командой грохнем всю инфраструктуру и пойдем писать далее Terraform манифесты для виртуальных машин под наш k8s кластер.


![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/5.jpg)


Первая часть диплома по подготовке инфраструктуры готова. Теперь можно приступать к созданию окружения на ВМ для развертывания на них k8s кластера.



**Создание Kubernetes кластера**

Выбрал создание k8s кластера через создание виртальных машин и Ansible с Kubespray, так как этот вариант максимально универсален и применим и для 

On-premise решения, которому компании доверяют больше и также можно развернуть on-cloud, что я собсвенно буду делать

Yandex Managed Service for Kubernetes от Yandex Cloud более узкнонаправленое и неуниверсальное средство развертывания, но у него ест и свои плюсы, в виде динамического создания и удаления нод в зависимости от нагрузки, чего нет в On-premise решениях и при работе с Yndex cloud это будет более дешевле содержать кластер из 1-3 нод которые то есть то нет от нагрузки, нежели платить сразу за 3 вм.

Я решил пойти по более универсальному пути, который плотно используется в работе на On-premise  и On-cloud


Создади 3 вм под наш кубер, 1 ноду мастера и 2 воркер ноды


Описываем tf мастер-ноду

[master-node.tf](https://github.com/mezhibo/Diplom/blob/913447f3ac52f0f7b08df2fc04159d425582a850/Chapter2/master-node.tf)


```
# Ресурсы для создания master-node

# Создадим ресурс образа виртуальной машины для облачного сервиса Yandex Compute Cloud из существующего архива.
data "yandex_compute_image" "debian" {
  family = var.os_image_node
}


resource "yandex_compute_instance" "master-node" {
  name        = "${var.yandex_compute_instance_web[0].vm_name}-${count.index+1}"
  platform_id = var.yandex_compute_instance_web[0].platform_id

  count = var.yandex_compute_instance_web[0].count_vms

  resources {
    cores         = var.yandex_compute_instance_web[0].cores
    memory        = var.yandex_compute_instance_web[0].memory
    core_fraction = var.yandex_compute_instance_web[0].core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian.image_id
      type     = var.boot_disk_web[0].type
      size     = var.boot_disk_web[0].size
    }
  }

  metadata = {  
    serial-port-enable = 1
    ssh-keys = "debian:${file("~/.ssh/id_rsa.pub")}"
 }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-a.id
    nat       = true
  }
  scheduling_policy {
    preemptible = true
  }
}
```

Теперь опишем воркер ноды

Так как воркер-нод у меня 2, самым правильным вариантом считаю создать ее через счетчик (count)


[worker-node.tf](https://github.com/mezhibo/Diplom/blob/00017d031f7693595c69a1d257f6506271e8c95e/Chapter2/worker-node.tf)


```
# Ресурсы для создания worker-node

resource "yandex_compute_instance" "worker-node" {
  name        = "${var.yandex_compute_instance_worker[0].vm_name}-${count.index+1}"
  platform_id = var.yandex_compute_instance_worker[0].platform_id

  count = var.yandex_compute_instance_worker[0].count_vms

  resources {
    cores         = var.yandex_compute_instance_worker[0].cores
    memory        = var.yandex_compute_instance_worker[0].memory
    core_fraction = var.yandex_compute_instance_worker[0].core_fraction
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.debian.image_id
      type     = var.boot_disk_worker[0].type
      size     = var.boot_disk_worker[0].size
    }
  }

  metadata = {  
    serial-port-enable = 1
    ssh-keys = "debian:${file("~/.ssh/id_rsa.pub")}"
 }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-a.id
    nat       = true
  }
  scheduling_policy {
    preemptible = true
  }
}
```


Теперь дополним наш файл с переменнынми нашими map-переменными для описания ресурсов наших виртуальных машин.

[variables.tf](https://github.com/mezhibo/Diplom/blob/7b54d9d0afbbedbb6a81ee44b8d4bd75a94f45f9/Chapter2/variables.tf)
  
Добавим код ниже



```
# Переменные для master-node

variable "yandex_compute_instance_web" {
  type        = list(object({
    vm_name = string
    cores = number
    memory = number
    core_fraction = number
    count_vms = number
    platform_id = string
  }))

  default = [{
      vm_name = "master"
      cores         = 2
      memory        = 4
      core_fraction = 20
      count_vms = 1
      platform_id = "standard-v1"
    }]
}

variable "boot_disk_web" {
  type        = list(object({
    size = number
    type = string
    }))
    default = [ {
    size = 30
    type = "network-hdd"
  }]
}


# Переменные для worker-node

variable "yandex_compute_instance_worker" {
  type        = list(object({
    vm_name = string
    cores = number
    memory = number
    core_fraction = number
    count_vms = number
    platform_id = string
  }))

  default = [{
      vm_name = "worker"
      cores         = 4
      memory        = 6
      core_fraction = 20
      count_vms = 2
      platform_id = "standard-v1"
    }]
}

variable "boot_disk_worker" {
  type        = list(object({
    size = number
    type = string
    }))
    default = [ {
    size = 30
    type = "network-hdd"
  }]
}
```


Теперь будем подготавливать наш файл авто-инвентаризации хостов


Первым этапом подготовим terrafrom-output созданных нами ВМ

[outputs.tf](https://github.com/mezhibo/Diplom/blob/b12f989871514b64e5fc07cd9649a2b0fff9bde4/Chapter2/outputs.tf)


```
output "master-node" {
  value = flatten([
    [for i in yandex_compute_instance.master-node : {
      name = i.name
      ip_external   = i.network_interface[0].nat_ip_address
      ip_internal = i.network_interface[0].ip_address
    }],
  ])
}

output "worker-node" {
  value = flatten([
    [for i in yandex_compute_instance.worker-node : {
      name = i.name
      ip_external   = i.network_interface[0].nat_ip_address
      ip_internal = i.network_interface[0].ip_address
    }],
  ])
}
```

Далее опишем манифест создания нашего инвентори-файла на основе шаблона

[create-hosts.tf](https://github.com/mezhibo/Diplom/blob/e779e4f9ac0b9167ae6a0062ed2e851d62398d7f/Chapter2/create-hosts.tf)

```
resource "local_file" "hosts_yml_kubespray" {

  content  = templatefile("${path.module}/hosts.tftpl", {
    workers = yandex_compute_instance.worker-node
    masters = yandex_compute_instance.master-node
  })
  filename = "../ansible/inventory/hosts.yml"
}
```

Теперь подготовим сам шаблон в формате tftpl в который и будут приниматься значения terraform-output

[hosts.tftpl](https://github.com/mezhibo/Diplom/blob/c8c971b721876d518faea080d7dac2357a6654fd/Chapter2/hosts.tftpl)


```
all:
  hosts:%{ for idx, master-node in masters }
    master-${idx + 1}:
      ansible_host: ${master-node.network_interface[0].nat_ip_address}
      ip: ${master-node.network_interface[0].ip_address}
      access_ip: ${master-node.network_interface[0].ip_address}%{ endfor }%{ for idx, worker-node in workers }
      ansible_user: debian
    worker-${idx + 1}:
      ansible_host: ${worker-node.network_interface[0].nat_ip_address}
      ip: ${worker-node.network_interface[0].ip_address}
      access_ip: ${worker-node.network_interface[0].ip_address}%{ endfor }
      ansible_user: debian
  children:
    kube_control_plane:
      hosts:%{ for idx, master-node in masters }
        ${master-node.name}:%{ endfor }
    kube_node:
      hosts:%{ for idx, worker-node in workers }
        ${worker-node.name}:%{ endfor }
    etcd:
      hosts:%{ for idx, master-node in masters }
        ${master-node.name}:%{ endfor }
    k8s_cluster:
      children:
        kube_control_plane:
        kube_node:
    calico_rr:
      hosts: {}
```

Все, на этом этапе работа с созданием облычных ресурсов в Yandex-cloud через terraform окончена

Далее начнем работать со средсвом управления конфигурацией Ansible

Выполянем terraform apply и создаем теперь полностью готовое окружение где будем разворчивать k8s и в него наше приложение и приложения мониторинга

![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/6.jpg)


Все, видим что ресурсы созданы, оутпуты показаны, идем проверим наш файл авто-инвентори, как он заполнился

![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/7.jpg)

Все, видим что все отлично, теперь подготовим Ansible - плейбук, который подготовит наш мастер-хост к настройке воркер-нод через kubespray


[site.yml](https://github.com/mezhibo/Diplom/blob/18ff462c131613ce306e9d4787c41837dd1faa45/Chapter2/site.yml)

```
- name: Установка pip
  hosts: master-1
  become: true

  tasks:

    - name: Скачиваем файл get-pip.py
      ansible.builtin.get_url:
        url: https://bootstrap.pypa.io/get-pip.py
        dest: "./"

    - name: Удаляем EXTERNALLY-MANAGED
      ansible.builtin.file:
        path: /usr/lib/python3.11/EXTERNALLY-MANAGED
        state: absent

    - name: Устанавливаем pip
      ansible.builtin.shell: python3.11 get-pip.py



- name: Установка зависимостей из ansible-playbook kubespray
  hosts: master-1
  become: true

  tasks:

    - name: Выполнение apt update и установка git
      ansible.builtin.apt:
        update_cache: true
        pkg:
        - git

    - name: Клонируем kubespray из репозитория
      ansible.builtin.git:
        repo: https://github.com/kubernetes-sigs/kubespray.git
        dest: ./kubespray

    - name: Изменение прав на папку kubspray
      ansible.builtin.file:
        dest: ./kubespray
        recurse: yes
        owner: debian
        group: debian

    - name: Установка зависимостей из requirements.txt
      ansible.builtin.pip:
        requirements: /home/debian/kubespray/requirements.txt
        extra_args: -r /home/debian/kubespray/requirements.txt

    - name: Копирование содержимого папки inventory/sample в папку inventory/mycluster
      ansible.builtin.copy:
        src: /home/debian/kubespray/inventory/sample/
        dest: /home/debian/kubespray/inventory/mycluster/
        remote_src: true


- name: Подготовка master-node к установке kubespray из ansible-playbook
  hosts: master-1
  become: true

  tasks:

    - name: Копирование на master-node файла hosts.yml
      ansible.builtin.copy:
        src: ./inventory/hosts.yml
        dest: ./kubespray/inventory/mycluster/

    - name: Копирование на мастер приватного ключа
      ansible.builtin.copy:
        src: /root/.ssh/id_rsa
        dest: ./.ssh
        owner: debian
        mode: '0600'
```

Роль готова, теперь идем посыпать Ансиблом нашу будущую мастер-ноду


Выполняем запуск роли

```
ansible-playbook -i inventory/hosts.yml site.yml
```

![Image alt](https://github.com/mezhibo/Diplom/blob/1e248f8ced6090ba91fd1e59c430e38e2ca06422/IMG/8.jpg)



Видим что все таски по настройке нашей мастер-ноды прошли успешно, подключаемся к мастер-ноде и на ней запускаем ansible-role 
для настройки k8s-кластера через kubespray


Перестрахуемся и дадим права пользователю debian на репу kubespray, чтобы у нас не падали ансибл таски при настройке кластера (уже проверено))))


```
sudo chown -R debian:debian ~/kubespray
```

Переходим в репу и запускаем роль

```
cd kubespay
```

```
ansible-playbook -i inventory/mycluster/hosts.yml cluster.yml -b -v
```

Видим что пошел процесс развертывания кластера k8s

![Image alt](https://github.com/mezhibo/Diplom/blob/1bd936baa7f16c3831ff84117f167158d75130b7/IMG/17.jpg)

Процесс достаточно долгий, минут 20 точно.

В этот раз хватило и 12 минут)) 


Видим что все завершилось у нас удачно


![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/10.jpg)


А вот в другой раз вышло аж 45 минут(((((

![Image alt](https://github.com/mezhibo/Diplom/blob/f82bafc55f1ba39283344915c252eff9d8c5186f/IMG/18.jpg)

Для выполнения команд kubectl без sudo скопируем папку .kube в домашнюю дирректорию пользователя и сменим владельца, а также группу владельцев папки с файлами:

```
sudo cp -r /root/.kube ~/
sudo chown -R debian:debian ~/.kube
```


И теперь командой

```
kubectl get pods --all-namespaces
```

Прверим как работает наш кластер


![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/11.jpg)


На этом второй этап готов! Кластер под наше приложение создан!



**Создание тестового приложения**


Мы не разработчики приложений, поэтому сильно мудрить не будем, просто создадми свой образ nginx со стачной страницей.



Первым этапом создадим на github пустую репу нашего тестового приложения, и склонируем ее себе

```
git clone https://github.com/mezhibo/Test-application.git
```

Создадим в этом репозитории файл содержащую HTML-код ниже:
index.html

[index.html](https://github.com/mezhibo/Diplom/blob/f1188c91b4ace7179e618ed83edfe2d478f79540/Chapter3/index%2Chtml)


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


[Dockerfile](https://github.com/mezhibo/Diplom/blob/f1188c91b4ace7179e618ed83edfe2d478f79540/Chapter3/Dockerfile)

```
FROM nginx:1.27-alpine

COPY index.html /usr/share/nginx/html
```
Теперь запушим эти изменения в наш гитхаб репозиторий

![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/12.jpg)


Создадим папку для приложения mkdir mynginx и скопируем в нее ранее созданые файлы.
В этой папке выполним сборку приложения:

```
sudo docker build -t mezhibo/nginx:v1 .
```

![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/13.jpg)


Проверим что образ сбилдился

![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/14.jpg)



И теперь толкнем наш собрыный контейнерв в Docker Hub



![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/15.jpg)



Зайдем в Docker Hub и проверим что наш контейнер доехал

![Image alt](https://github.com/mezhibo/Diplom/blob/dc524d33f6f7c3109adb35a02fd34c2d8bc3c3ed/IMG/16.jpg)


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


[Nginx-DaemonSet.yml](https://github.com/mezhibo/Diplom/blob/34384c711e6518f903256846af1c9128a28fcefa/Chapter4/Nginx-DaemonSet.yml)

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

[Nginx-Service.yml](https://github.com/mezhibo/Diplom/blob/34384c711e6518f903256846af1c9128a28fcefa/Chapter4/Nginx-Service.yml)

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


![Image alt](https://github.com/mezhibo/Diplom/blob/bf32392c7fb09354251598881e9fb2eb07111246/IMG/19.jpg)


Теперь перейдем на по внешнему ip-адресу на проброшенный порт 30000 


И видим что наше собранное приложение с кастомной веб-страницей работает

![Image alt](https://github.com/mezhibo/Diplom/blob/bf32392c7fb09354251598881e9fb2eb07111246/IMG/20.jpg)

УРА!!! Наше приложение работает в кластере.



*Теперь прикрутим мониторинг кластера*


Склонируем себе рпозиторий, который рекомендуют в выполнении дипломной работы

```
git clone https://github.com/prometheus-operator/kube-prometheus.git
```

Теперь есть огромный нюанс с которым я бился очень долго и упорно, а именно нужно изменить тип сервиса 
Grafana c ClusterIP на NodePort, для того чтобы веб-интерфейс графаны был проброшен на внешний айпи-адрес ноды, и можно было снаружи увидеть дашборды.

Правим конфиг сервиса графаны

```
nano kube-prometheus/manifests/grafana-service.yaml
```

Удаляем все старое значение, и вписываем вот такое значение для сервиса

[grafana-svc.yml](https://github.com/mezhibo/Diplom/blob/34384c711e6518f903256846af1c9128a28fcefa/Chapter4/grafana-svc.yml)

```
apiVersion: v1
kind: Service
metadata:
  labels:
    app.kubernetes.io/component: grafana
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: kube-prometheus
    app.kubernetes.io/version: 11.4.0
  name: grafana
  namespace: monitoring
spec:
  type: NodePort
  ports:
  - name: http
    port: 3000
    targetPort: http
    nodePort: 32000
  selector:
    app.kubernetes.io/component: grafana
    app.kubernetes.io/name: grafana
    app.kubernetes.io/part-of: kube-prometheus
```

Сохраняем конфиг с новым содержимым переходим в папку с файлами для деплоя, и запускаем наш стек мониторинга

```
cd kube-prometheus
```


```
kubectl apply --server-side -f manifests/setup
kubectl wait \
 --for condition=Established \
 --all CustomResourceDefinition \
 --namespace=monitoring
kubectl apply -f manifests/
```

И теперь командой проверим что все сущности нашего немйспейса monitoring работают

```
kubectl get all -n monitoring
```

Смотрим что все у нас поднялось и работает

![Image alt](https://github.com/mezhibo/Diplom/blob/9b03a619c9bcfcd64ccc2374a28a94d7d42d5d8b/IMG/22.jpg)



Теперь перейдем по внешнему ip-адресу однйо из нод, и убедимся что у нас работает мониторинг и графана получает данные о состоянии кластера

![Image alt](https://github.com/mezhibo/Diplom/blob/19d9cf86806f5f407d270fb56c54a8f29fdcc9ca/IMG/25.jpg)


Все супер, наше приложение задеплоино и мониторится.


Теперь к следующему пунку а именно к автоматичсекой сборке приложения после коммита и автоматическому деплою


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
