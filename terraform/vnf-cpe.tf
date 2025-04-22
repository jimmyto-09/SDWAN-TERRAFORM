resource "kubernetes_pod" "vnf_cpe" {
  metadata {
    name      = "vnf-cpe"
    namespace = "rdsv"
    labels = {
      "k8s-app" = "vnf-cpe"
    }
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        { "name": "extnet1" }
      ])
    }
  }

  spec {
    container {
      name  = "vnf-cpe"
      image = "educaredes/vnf-cpe"

      command = ["/bin/sh", "-c", <<EOT
set -x

# Iniciar Open vSwitch
/usr/share/openvswitch/scripts/ovs-ctl start
while [ ! -e /var/run/openvswitch/db.sock ]; do echo '⏳ Esperando OVS...'; sleep 1; done

# Esperar a que vnf-access tenga IP usando el nombre del servicio headless
while true; do
  ACCESS_IP=$(getent hosts vnf-access-service | awk '{ print $1 }')
  if [ ! -z "$ACCESS_IP" ]; then break; fi
  echo "⏳ Esperando IP de vnf-access..."; sleep 2
done

SELF_IP=$(hostname -i)
REMOTE_IP=$ACCESS_IP

echo "🌐 IP local (cpe): $SELF_IP"
echo "🎯 IP remota (access): $REMOTE_IP"

ovs-vsctl add-br brint
ip link set brint up
ifconfig brint 192.168.255.254/24

# Limpieza previa
ip link del vxlan2 2>/dev/null || true
ip link del axscpe 2>/dev/null || true

# Crear interfaz VXLAN hacia vnf-access
ip link add axscpe type vxlan id 4 remote $ACCESS_IP dstport 8742 dev eth0
ovs-vsctl add-port brint axscpe
ip link set axscpe up

# Configurar red hacia Internet (salida)
ifconfig net1 10.100.1.1/24

ip route add 169.254.1.1 dev eth0 scope link
ip route add $REMOTE_IP/32 via 169.254.1.1
ip route add 10.20.1.0/24 via 192.168.255.253 dev brint
ip route del 0.0.0.0/0 via 169.254.1.1
ip route add 0.0.0.0/0 via 10.100.1.254

# NAT para dar salida a Internet
iptables -t nat -A POSTROUTING -o net1 -j MASQUERADE
iptables -A FORWARD -i net1 -o brint -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i brint -o net1 -j ACCEPT

echo "✅ vnf-cpe configurado"
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

resource "kubernetes_service" "vnf_cpe" {
  metadata {
    name      = "vnf-cpe-service"
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"  # 👈 headless: devuelve IP real del pod
    selector = {
      "k8s-app" = "vnf-cpe"
    }

    port {
      name        = "bgp"
      protocol    = "TCP"
      port        = 179
      target_port = 179
    }
  }
}
