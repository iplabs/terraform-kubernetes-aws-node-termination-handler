locals {
  k8s_namespace                         = "kube-system"
  k8s_pod_annotations                   = var.k8s_pod_annotations
  node_termination_handler_docker_image = "docker.io/amazon/aws-node-termination-handler:v${var.node_termination_handler_version}"
  node_termination_handler_version      = var.node_termination_handler_version
}

resource "kubernetes_service_account" "this" {
  automount_service_account_token = true
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "aws-node-termination-handler"
    }
    name      = "aws-node-termination-handler"
    namespace = local.k8s_namespace
  }
}

resource "kubernetes_cluster_role" "this" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "aws-node-termination-handler"
    }
    name = "aws-node-termination-handler"
  }
  rule {
    api_groups = [""]
    resources  = ["nodes"]
    verbs      = ["get", "patch", "update"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["list"]
  }
  rule {
    api_groups = [""]
    resources  = ["pods/eviction"]
    verbs      = ["create"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["daemonsets"]
    verbs      = ["get", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "this" {
  metadata {
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "aws-node-termination-handler"
    }
    name = "aws-node-termination-handler"
  }
  subject {
    api_group = ""
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.this.metadata[0].name
    namespace = kubernetes_service_account.this.metadata[0].name
  }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.this.metadata[0].name
  }
}

resource "kubernetes_daemonset" "this" {
  metadata {
    annotations = {
      "field.cattle.io/description" = "AWS Node Termination Handler"
    }
    labels = {
      "app.kubernetes.io/instance"   = "default"
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/name"       = "aws-node-termination-handler"
      "app.kubernetes.io/version"    = "v${local.node_termination_handler_version}"
      "k8s-app"                      = "aws-node-termination-handler"
    }
    name      = "aws-node-termination-handler"
    namespace = local.k8s_namespace
  }
  spec {
    selector {
      match_labels = {
        "app.kubernetes.io/instance" = "default"
        "app.kubernetes.io/name"     = "aws-node-termination-handler"
      }
    }
    template {
      metadata {
        labels = {
          "app.kubernetes.io/instance" = "default"
          "app.kubernetes.io/name"     = "aws-node-termination-handler"
          "app.kubernetes.io/version"  = "v${local.node_termination_handler_version}"
          "k8s-app"                    = "aws-node-termination-handler"
        }
      }
      spec {
        affinity {
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                match_expressions {
                  key      = "kubernetes.io/os"
                  operator = "In"
                  values   = ["linux"]
                }
                match_expressions {
                  key      = "kubernetes.io/arch"
                  operator = "In"
                  values   = ["amd64"]
                }
              }
            }
          }
        }
        automount_service_account_token = true
        container {
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          env {
            name = "POD_NAME"
            value_from {
              field_ref {
                field_path = "metadata.name"
              }
            }
          }
          env {
            name = "NAMESPACE"
            value_from {
              field_ref {
                field_path = "metadata.namespace"
              }
            }
          }
          env {
            name = "SPOT_POD_IP"
            value_from {
              field_ref {
                field_path = "status.podIP"
              }
            }
          }
          env {
            name  = "KUBERNETES_SERVICE_HOST"
            value = "kubernetes.default.svc.cluster.local"
          }
          env {
            name  = "KUBERNETES_SERVICE_PORT"
            value = "443"
          }
          env {
            name  = "DELETE_LOCAL_DATA"
            value = "false"
          }
          env {
            name  = "IGNORE_DAEMON_SETS"
            value = "false"
          }
          env {
            name  = "POD_TERMINATION_GRACE_PERIOD"
            value = var.pod_termination_grace_period
          }
          env {
            name  = "INSTANCE_METADATA_URL"
            value = ""
          }
          env {
            name  = "NODE_TERMINATION_GRACE_PERIOD"
            value = var.node_termination_grace_period
          }
          env {
            name  = "WEBHOOK_URL"
            value = ""
          }
          env {
            name  = "WEBHOOK_HEADERS"
            value = ""
          }
          env {
            name  = "WEBHOOK_TEMPLATE"
            value = ""
          }
          env {
            name  = "DRY_RUN"
            value = "false"
          }
          env {
            name  = "ENABLE_SPOT_INTERRUPTION_DRAINING"
            value = ""
          }
          env {
            name  = "ENABLE_SCHEDULED_DRAINING"
            value = ""
          }
          image             = local.node_termination_handler_docker_image
          image_pull_policy = "IfNotPresent"
          name              = "aws-node-termination-handler"
          resources {
            limits {
              cpu    = "100m"
              memory = "128Mi"
            }
            requests {
              cpu    = "50m"
              memory = "64Mi"
            }
          }
          volume_mount {
            mount_path = "/proc/uptime"
            name       = "uptime"
            read_only  = true
          }
        }
        dns_policy           = "ClusterFirstWithHostNet"
        host_network         = true
        priority_class_name  = "system-node-critical"
        service_account_name = kubernetes_service_account.this.metadata[0].name
        dynamic "toleration" {
          for_each = var.k8s_node_tolerations
          content {
            effect   = toleration.value["effect"]
            key      = toleration.value["key"]
            operator = toleration.value["operator"]
            value    = toleration.value["value"]
          }
        }
        volume {
          name = "uptime"
          host_path {
            path = "/proc/uptime"
          }
        }
      }
    }
  }
}