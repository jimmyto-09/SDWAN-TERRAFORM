###############################################################################
# NAMESPACE -------------------------------------------------------------------
###############################################################################
resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
}

###############################################################################
# STORAGE CLASS: hostpath-immediate  (MicroK8s host-path, modo Immediate)
###############################################################################
resource "kubernetes_storage_class" "hostpath_immediate" {
  metadata {
    name = "hostpath-immediate"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "false"
    }
  }

  # ← este es el nombre del provisioner de MicroK8s
  storage_provisioner = "microk8s.io/hostpath"

  volume_binding_mode = "Immediate"
  reclaim_policy      = "Delete"
}


###############################################################################
# SECRET: CA CERT -------------------------------------------------------------
###############################################################################
resource "kubernetes_secret" "prometheus_cert" {
  metadata {
    name      = "prometheus-ca-cert"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "ca.crt" = base64encode(
      trimspace(<<-EOF
      -----BEGIN CERTIFICATE-----
      MIIDDzCCAfegAwIBAgIUPmkIE2ovQLp4Ayl4HQE3oYOU6MowDQYJKoZIhvcNAQEL
      BQAwFzEVMBMGA1UEAwwMMTAuMTUyLjE4My4xMB4XDTI0MTAyNjE3MzQzNloXDTM0
      MTAyNDE3MzQzNlowFzEVMBMGA1UEAwwMMTAuMTUyLjE4My4xMIIBIjANBgkqhkiG
      9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv2POXUxRNB3jgaTQUPuLBIE0FhiwhHErJusG
      t7GgVY3H+cB4mRNpo1MOPb6qoFG+LfqfMyK9JYP+CPpd2dtY144mq+Z8SDaMsu84
      W8V8eAPWAvjx5mZw99wgXYjTnV1iohUKzJLFkT0OO+Il/SUX8Zx7CFhsbWVEpAgd
      5Ma3sDzh8CP9VDxRpkEMdfdYKu23/xOm1j+7jFAs8trPpGvelX07Lw2CnjdV2d4u
      l3cdS/w79B52raZXtH6zQ1UQ7+yZkPDKCUQE+OscqTSQUfvQkbCqe8sCL061Za3x
      lEN/ESIxv4sTYUPyhck2R3yvYLn8/j1TxaQnCrZNrwmXUd18hQIDAQABo1MwUTAd
      BgNVHQ4EFgQU3x5KM3t/7VJgJcRLPEakFidET8YwHwYDVR0jBBgwFoAU3x5KM3t/
      7VJgJcRLPEakFidET8YwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOC
      AQEAUUUXP/Syrod1Tbx7UXy/SBONQVvhLA53Gc66B8/HcHNSxdjp5e4mArXXZA5i
      slRXbqkKwqJG7BGtQ96hSFWVs7X9rPPvi3UOCGUJX3l5hoNJJlBYjeHKCWXTiywX
      fh3/aHJuaylS+SERNs9l0YyW2Ag+lkfNulaympILl0zd+lJb724DzH9b5W9yYeSE
      2D6gHsVz0sO3K0EbKaYeEmTgJmUvaggEy9DqB1CBCW3StHj7m5bs5wgHe5NhJqdQ
      a69tRt38dnqcmdEcjt1bmsjaJmlQevUibnvo2m4W5nPmDsMYS2+4LMrdBNuQ0WHQ
      Aglt5OaOQhBwdovDqt9YzQhk6g==
      -----END CERTIFICATE-----
      EOF
      )
    )
  }
}

###############################################################################
# SECRET: TOKEN ---------------------------------------------------------------
###############################################################################
resource "kubernetes_secret" "prometheus_token" {
  metadata {
    name      = "prometheus-token"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "token" = base64encode(
      "eyJhbGciOiJSUzI1NiIsImtpZCI6IjJUV2M1T09sdHNqSTZkak5XRnlKM1BVcmN2SGlzcnRqeTNnU3d5RnQwc0EifQ.eyJhdWQiOlsiaHR0cHM6Ly9rdWJlcm5ldGVzLmRlZmF1bHQuc3ZjIl0sImV4cCI6MjA2MjQ0MDQ3OCwiaWF0IjoxNzQ3MDgwNDc4LCJpc3MiOiJodHRwczovL2t1YmVybmV0ZXMuZGVmYXVsdC5zdmMiLCJqdGkiOiJmYjkyYTZkYi1mNmQ1LTQyYWUtODdlNy0zMjcxMWRjYTA5ZjAiLCJrdWJlcm5ldGVzLmlvIjp7Im5hbWVzcGFjZSI6Im1vbml0b3JpbmciLCJzZXJ2aWNlYWNjb3VudCI6eyJuYW1lIjoicHJvbWV0aGV1cyIsInVpZCI6IjY1MjEwMmI0LTk5N2ItNDI4Zi1iODA3LWEzZWQ3OGE1YWZiZiJ9fSwibmJmIjoxNzQ3MDgwNDc4LCJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6bW9uaXRvcmluZzpwcm9tZXRoZXVzIn0.Df6cDGB62dIyJRXCyKRqXjaSHtvPoh9Jf905tJLtuHhYP7vQ4LSmFPowLK-yVNCUI5ot7TbZR88iqTiVrnKsUXibR1SfsOT3X_Jr2TBkSWxE_jTWj-_pfPgOyVp0fpR5esrdZrLWDC9-XOSM2LoWBQygYLcyqbD-CQxFtYP2DAcxl4er9UQPvW9fu69Gznosyf3pdBqY2aWO6O5hX1EK_jI1-hAjEJb3Mi-v0Vi_s05_aRoeL0C69le2QLQtEg_kqAgo1ClcLhLzaWMfc8dwU570TwMIdP31pKDcP96EKzSOq-B6bADT2h5L9oZEEBdf3Y5t-b9Ezw3DLM--k_Y1cg"
    )
  }
}

###############################################################################
# CONFIGMAP: PROMETHEUS.YML ---------------------------------------------------
###############################################################################
resource "kubernetes_config_map" "prometheus_config" {
  metadata {
    name      = "prometheus-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "prometheus.yml" = <<-EOF
      global:
        scrape_interval: 15s
        evaluation_interval: 15s

      scrape_configs:
        - job_name: "kubernetes-pods"
          kubernetes_sd_configs:
            - role: pod
          relabel_configs:
            - source_labels: ["__meta_kubernetes_namespace"]
              regex: "rdsv"
              action: "keep"
            - source_labels: ["__meta_kubernetes_pod_label_k8s_app"]
              regex: "vnf-.*"
              action: "keep"
            - source_labels: ["__meta_kubernetes_pod_ip"]
              target_label: "__address__"
              replacement: "$1:9100"

      

        - job_name: "prometheus"
          static_configs:
            - targets: ["localhost:9090"]
EOF
  }
}

###############################################################################
# PVC: GRAFANA ----------------------------------------------------------------
###############################################################################
resource "kubernetes_persistent_volume_claim" "grafana_data" {
  metadata {
    name      = "grafana-data"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "hostpath-immediate"
    resources {
      requests = { storage = "5Gi" }
    }
  }
}

###############################################################################
# DEPLOYMENT: GRAFANA ---------------------------------------------------------
###############################################################################
resource "kubernetes_deployment" "grafana" {
  metadata {
    name      = "grafana"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "grafana" } }

    template {
      metadata { labels = { app = "grafana" } }

      spec {
        host_network = true

        container {
          name  = "grafana"
          image = "grafana/grafana-oss:latest"

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }
          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD"
            value = "admin"
          }

          port {
            name           = "http"
            container_port = 3000
          }

          volume_mount {
            name       = "grafana-data"
            mount_path = "/var/lib/grafana"
          }
        }

        volume {
          name = "grafana-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.grafana_data.metadata[0].name
          }
        }
      }
    }
  }
}

###############################################################################
# PVC: PROMETHEUS DATA --------------------------------------------------------
###############################################################################
resource "kubernetes_persistent_volume_claim" "prometheus_data" {
  metadata {
    name      = "prometheus-data"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "hostpath-immediate"
    resources {
      requests = { storage = "10Gi" }
    }
  }
}

###############################################################################
# DEPLOYMENT: PROMETHEUS ------------------------------------------------------
###############################################################################
resource "kubernetes_deployment" "prometheus" {
  metadata {
    name      = "prometheus"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  spec {
    replicas = 1
    selector { match_labels = { app = "prometheus" } }

    template {
      metadata { labels = { app = "prometheus" } }

      spec {
        host_network = true

        container {
          name  = "prometheus"
          image = "prom/prometheus:latest"

          args = [
            "--config.file=/etc/prometheus/prometheus.yml",
            "--storage.tsdb.path=/prometheus",
            "--web.enable-lifecycle"
          ]

          port {
            name           = "web"
            container_port = 9090
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/prometheus"
          }
          volume_mount {
            name       = "data"
            mount_path = "/prometheus"
          }
        }

        volume {
          name = "config"
          config_map { name = kubernetes_config_map.prometheus_config.metadata[0].name }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.prometheus_data.metadata[0].name
          }
        }
      }
    }
  }
}