provider "kubernetes" {
  config_path = "~/.kube/config"
}

resource "kubernetes_pod" "vnf_access" {
  metadata {
    name      = "vnf-access"
    namespace = "rdsv"
    labels = {
      "k8s-app" = "vnf-access"
    }
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        { "name": "accessnet1" }
      ])
    }
  }

  spec {
    container {
      name  = "vnf-access"
      image = "educaredes/vnf-access"

      command = ["/bin/sh", "-c", <<EOT
set -x

# Iniciar OVS
/usr/share/openvswitch/scripts/ovs-ctl start
while [ ! -e /var/run/openvswitch/db.sock ]; do echo '⏳ Esperando OVS...'; sleep 1; done

# Esperar a que vnf-cpe tenga IP usando el nombre del servicio
while true; do
  CPE_IP=$(getent hosts vnf-cpe-service | awk '{ print $1 }')
  if [ ! -z "$CPE_IP" ]; then break; fi
  echo "⏳ Esperando IP de vnf-cpe..."; sleep 2
done

SELF_IP=$(hostname -i)

echo "🌐 IP local (access): $SELF_IP"
echo "🎯 IP remota (cpe): $CPE_IP"

ovs-vsctl add-br brint
ip link set brint up
ifconfig net1 10.255.0.1/24

# Limpieza previa
ip link del vxlan2 2>/dev/null || true
ip link del axscpe 2>/dev/null || true

ip link add vxlan2 type vxlan id 2 remote 10.255.0.2 dstport 8742 dev net1
ip link add axscpe type vxlan id 4 remote $CPE_IP dstport 8742 dev eth0

ovs-vsctl add-port brint vxlan2
ovs-vsctl add-port brint axscpe
ip link set vxlan2 up
ip link set axscpe up

ip route add 169.254.1.1 dev eth0 scope link || true
ip route add default via 169.254.1.1 dev eth0

echo "✅ vnf-access configurado"
sleep infinity
EOT
      ]

      security_context {
        privileged = true
        capabilities {
          add = ["NET_ADMIN", "SYS_ADMIN"]
        }
      }
    }
  }
}

resource "kubernetes_service" "vnf_access" {
  metadata {
    name      = "vnf-access-service"
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"  # 👈 Esto lo hace "headless"

    selector = {
      "k8s-app" = "vnf-access"
    }

    port {
      name        = "bgp"
      protocol    = "TCP"
      port        = 179
      target_port = 179
    }
  }
}