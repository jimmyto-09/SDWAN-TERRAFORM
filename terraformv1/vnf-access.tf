provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_pod" "vnf_access" {
  for_each = local.vnf_access_instances   # site1, site2

  metadata {
    name      = "vnf-access-${each.key}"
    namespace = "rdsv"
    labels = {
      "k8s-app" = "vnf-access-${each.key}"
    }

    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name      = "accessnet${each.value.netnum}"
          interface = "net${each.value.netnum}"
        }
      ])
    }
  }


  spec {
    container {
      name  = "vnf-access"
      image = "educaredes/vnf-access"

     command = [
  "/bin/sh",
  "-c",
  <<-EOT
    set -e -x
    /usr/share/openvswitch/scripts/ovs-ctl start
    while [ ! -e /var/run/openvswitch/db.sock ]; do
      echo '⏳ Esperando OVS...'
      sleep 1
    done

    while true; do
      CPE_IP=$(getent hosts ${each.value.cpe_service_name} | awk '{ print $1 }')
      if [ ! -z "$CPE_IP" ]; then break; fi
      echo "⏳ Esperando IP de vnf-cpe..."
      sleep 2
    done

    ACCESS_IP=$(hostname -i)
    echo "🌐 IP local (access): $ACCESS_IP"
    echo "🎯 IP remota (cpe): $CPE_IP"

    ip link del vxlan2 2>/dev/null || true 
    ip link del axscpe 2>/dev/null || true 

    ovs-vsctl add-br brint
    ip link set brint up
    ifconfig net${each.value.netnum} ${each.value.vnftunip}/24

    ip link add vxlan2 type vxlan id 2 remote ${each.value.custunip} dstport 8742 dev net${each.value.netnum}
    ip link add axscpe type vxlan id 4 remote $CPE_IP dstport 8742 dev eth0

    ovs-vsctl add-port brint vxlan2
    ovs-vsctl add-port brint axscpe
    ip link set vxlan2 up
    ip link set axscpe up

    #########################################
    ###############  BRWAN  #################
    #########################################

    ovs-vsctl add-br brwan

    # VXLAN al cliente
    ip link add vxlan1 type vxlan id 1 remote ${each.value.custunip} dstport 4789 dev net${each.value.netnum}

    # Esperar IP del vnf-wan
    while true; do
    WAN_IP=$(getent hosts vnf-wan-${each.key}-pod | awk '{print $1}')
      if [ ! -z "$WAN_IP" ]; then break; fi
      echo "⏳ Esperando IP de vnf-wan-${each.key}..."
      sleep 2
    done

   # VXLAN al WAN
    ip link add axswan type vxlan id 3 remote $WAN_IP dstport 4788 dev eth0

    ovs-vsctl add-port brwan vxlan1
    ovs-vsctl add-port brwan axswan

    ip link set vxlan1 up
    ip link set axswan up
    
    
    #########################################
   #######  Conectar ambos bridges a Ryu ###
   #########################################

   while true; do
  RYU_IP=$(getent hosts knf-ctrl-${each.key}-svc | awk '{print $1}')
  if [ -n "$RYU_IP" ]; then
    echo "🔗 Ryu controller IP: $RYU_IP"
    break
  fi
  echo "⏳ Esperando IP de controller…"
  sleep 2
done

   ## 3. Activar el modo SDN en VNF:access"
        ovs-vsctl set bridge brwan protocols=OpenFlow10,OpenFlow12,OpenFlow13
        ovs-vsctl set-fail-mode brwan secure
        ovs-vsctl set bridge brwan other-config:datapath-id=0000000000000003
        ovs-vsctl set-controller brwan tcp:$RYU_IP:6633
        ovs-vsctl set-manager ptcp:6632

    sleep infinity
  EOT
]
      ### (c) Permisos adicionales
     security_context {
      privileged = true
      capabilities { add = ["NET_ADMIN", "SYS_ADMIN"] }
    }
  }

  # Contenedor Sidecar para Node Exporter
  container {
    name  = "node-exporter"
    image = "quay.io/prometheus/node-exporter:latest"

    port {
      container_port = 9100
    }

    resources {
      limits = {
        cpu    = "100m"
        memory = "128Mi"
      }
      requests = {
        cpu    = "50m"
        memory = "64Mi"
      }
    }
  }
  }
}
resource "kubernetes_service" "vnf_access" {
  for_each = local.vnf_access_instances

  metadata {
    name      = "vnf-access-${each.key}-service"
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"
    selector = {
      "k8s-app" = "vnf-access-${each.key}"
    }

    port {
      name        = "bgp"
      protocol    = "TCP"
      port        = 179
      target_port = 179
    }
  }
}
