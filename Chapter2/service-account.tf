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


