# net2.tf  (sin for_each / count)
resource "kubernetes_manifest" "net2" {
  manifest = {
    apiVersion = "k8s.cni.cncf.io/v1"
    kind       = "NetworkAttachmentDefinition"
    metadata = {
      name      = "net2"
      namespace = "rdsv"
    }
    spec = {
      config = jsonencode({
        cniVersion = "0.3.1",
        type       = "macvlan",
        master     = "eth0",
        mode       = "bridge",
        ipam       = {}
      })
    }
  }
}
