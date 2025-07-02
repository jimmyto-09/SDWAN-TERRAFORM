resource "kubernetes_pod" "vnf_wan" {
  for_each = local.vnf_wan_instances

  metadata {
    name      = "vnf-wan-${each.key}"
    namespace = "rdsv"
    labels = {
      "k8s-app" = "vnf-wan-${each.key}"
    }
    annotations = {
      "k8s.v1.cni.cncf.io/networks" = jsonencode([
        {
          name      = "mplswan"
          interface = "net1"
        }
      ])
    }
  }

  spec {
    container {
      name  = "vnf-wan"
      image = "educaredes/vnf-wan"

      volume_mount {
        name       = "json-flows"
        mount_path = "/json"
        read_only  = true
      }

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
            ACCESS_IP=$(getent hosts vnf-access-${each.key}-service | awk '{print $1}')
            if [ ! -z "$ACCESS_IP" ]; then break; fi
            echo "⏳ Esperando IP de vnf-access-${each.key}..."
            sleep 2
          done

          SELF_IP=$(hostname -i)
          echo "🌐 IP local (wan): $SELF_IP"
          echo "🎯 IP remota (access): $ACCESS_IP"

          ip link del axswan 2>/dev/null || true

          ####################################################
          ####################### BRWAN ######################
          ####################################################
          while true; do
            CPE_IP=$(getent hosts ${each.value.cpe_service_name} | awk '{ print $1 }')
            if [ ! -z "$CPE_IP" ]; then break; fi
            echo "⏳ Esperando IP de vnf-cpe..."
            sleep 2
          done

          ovs-vsctl add-br brwan

          ip link add axswan type vxlan id 3 remote $ACCESS_IP dstport 4788 dev eth0
          ovs-vsctl add-port brwan axswan
          ovs-vsctl add-port brwan net1

          ip link set axswan up
          ip route del $ACCESS_IP via 169.254.1.1 dev eth0 2>/dev/null || true
          ip route add $ACCESS_IP via 169.254.1.1 dev eth0


          ip link del cpewan 2>/dev/null || true
          ip link add cpewan type vxlan id 5 remote $CPE_IP dstport 8741 dev eth0
          ovs-vsctl add-port brwan cpewan
          ifconfig cpewan up

          #####################
          ####### RYU ########
          #####################

          ryu-manager /root/flowmanager/flowmanager.py ryu.app.ofctl_rest > /ryu.log 2>&1 &

          ovs-vsctl set bridge brwan protocols=OpenFlow10,OpenFlow12,OpenFlow13
          ovs-vsctl set-fail-mode brwan secure
          ovs-vsctl set bridge brwan other-config:datapath-id=0000000000000001
          ovs-vsctl set-controller brwan tcp:127.0.0.1:6633

         until curl -s http://127.0.0.1:8080/stats/switches | grep -q "\[1\]"; do
  sleep 1
done


echo "📡 Datapath activo. Esperando estabilización..."
sleep 2  # 💤 Espera adicional para evitar errores de tiempo

echo "📥 Cargando reglas SDN en Ryu..."
RYU_ADD_URL="http://127.0.0.1:8080/stats/flowentry/add"
curl -X POST -d @/json/from-cpe.json $RYU_ADD_URL || echo "❌ from-cpe.json failed"
curl -X POST -d @/json/to-cpe.json $RYU_ADD_URL || echo "❌ to-cpe.json failed"
curl -X POST -d @/json/broadcast-from-axs.json $RYU_ADD_URL || echo "❌ broadcast failed"
curl -X POST -d @/json/from-mpls.json $RYU_ADD_URL || echo "❌ from-mpls failed"
curl -X POST -d @/json/to-voip-gw.json $RYU_ADD_URL || echo "❌ to-voip-gw failed"
curl -X POST -d @/json/sdedge${each.value.netnum}/to-voip.json $RYU_ADD_URL || echo "❌ to-voip failed"


echo "--"
echo "sdedge${each.value.netnum}: abrir navegador en el host para ver los flujos OpenFlow:"
echo "firefox http://localhost:${each.value.netnum == 1 ? 31880 : 31881}/home/ &"



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

    volume {
      name = "json-flows"
      host_path {
        path = "/home/upm/shared/sdedge-ns/json"
        type = "Directory"
      }
    }
  }
}


resource "kubernetes_service" "vnf_wan" {
  for_each = local.vnf_wan_instances

  metadata {
    name      = "vnf-wan-${each.key}-service"
    namespace = "rdsv"
  }

  spec {
    type = "NodePort"
    selector = {
      "k8s-app" = "vnf-wan-${each.key}"
    }

    port {
      name        = "ryu"
      protocol    = "TCP"
      port        = 6633
      target_port = 6633
      node_port   = each.key == "site1" ? 31633 : 31634
    }
# 👇 Añade este bloque para exponer la API REST de Ryu
    port {
      name        = "ryu-rest"
      protocol    = "TCP"
      port        = 8080
      target_port = 8080
      node_port   = each.key == "site1" ? 31880 : 31881
    }
  }
}

#########################################################################
#  Servicio headless → devuelve la IP real del Pod WAN
#########################################################################
resource "kubernetes_service" "vnf_wan_pod" {
  for_each = local.vnf_wan_instances

  metadata {
    name      = "vnf-wan-${each.key}-pod"   # ←  **nombre que usará vnf-access**
    namespace = "rdsv"
  }

  spec {
    cluster_ip = "None"                     # headless
    selector   = { "k8s-app" = "vnf-wan-${each.key}" }

    # Puerto ficticio para crear Endpoints; VXLAN es UDP
    port {
      name        = "vxlan"
      protocol    = "UDP"
      port        = 4788
      target_port = 4788
    }
  }
}
