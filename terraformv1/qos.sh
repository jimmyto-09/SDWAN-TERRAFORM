#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# qos.sh  –  Inyecta reglas QoS (OVSDB + Queue + Rule)
#                  en todos los sites (site1, site2, …)
# ──────────────────────────────────────────────────────────────
set -euo pipefail

######## Resolver cliente K8s (kubectl ó microk8s kubectl) #####
if command -v kubectl >/dev/null 2>&1; then
  KCTL="kubectl"
elif command -v microk8s >/dev/null 2>&1; then
  KCTL="microk8s kubectl"
else
  echo " No se encontró ni kubectl ni microk8s" >&2
  exit 1
fi
echo "  Cliente K8s = '$KCTL'"

######## Configuración #########################################
QOS_DIR="/home/upm/shared/sdedge-ns/json/qos"
NAMESPACE="rdsv"
QUEUE_JSON="$QOS_DIR/queue-to-voip.json"
RULE_JSON="$QOS_DIR/rule-to-voip.json"

[[ -f "$QUEUE_JSON" && -f "$RULE_JSON" ]] || {
  echo "No se encontraron $QUEUE_JSON o $RULE_JSON"; exit 1; }

######## Descubrir sites (sdedgeN → siteN) #####################
mapfile -t SITES < <(ls -d /home/upm/shared/sdedge-ns/json/sdedge* 2>/dev/null | sed 's#.*/sdedge##' | sort)
[[ ${#SITES[@]} -gt 0 ]] || { echo "No se encontraron sites"; exit 1; }

echo "🔎 Sites detectados: ${SITES[*]/#/site}"

for NETNUM in "${SITES[@]}"; do
  SITE="site${NETNUM}"
  SVC="knf-ctrl-${SITE}-svc"

  echo
  echo "════════════  QoS para ${SITE}  ════════════"

  ######## Esperar a Ryu y al datapath 3 #######################
  echo "⏳ Esperando Pod Ryu (${SITE}) Ready…"
  $KCTL wait --for=condition=ready \
        pod -l k8s-app="knf-ctrl-${SITE}" -n "$NAMESPACE" --timeout=120s

  # Port‑forward REST 8080 → puerto local aleatorio
  LOCAL_PORT=$(shuf -i 20000-29999 -n 1)
  $KCTL port-forward -n "$NAMESPACE" svc/"$SVC" ${LOCAL_PORT}:8080 >/dev/null 2>&1 &
  PF_PID=$!
  trap "kill $PF_PID 2>/dev/null || true" RETURN
  sleep 2

  RYU="http://localhost:${LOCAL_PORT}"
  echo "🎯 Ryu REST = ${RYU}"

  # Esperar a que el datapath 3 exista en Ryu
  for i in {1..12}; do
    curl -sf "$RYU/stats/portdesc/3" >/dev/null && break
    echo " Esperando datapath 3… ($i/12)"; sleep 3
  done

  ######## Configurar OVSDB address ############################
  ACCESS_IP=$($KCTL get pod -n "$NAMESPACE" -l "k8s-app=vnf-access-${SITE}" \
               -o jsonpath='{.items[0].status.podIP}')
  OVSDB_URL="$RYU/v1.0/conf/switches/0000000000000003/ovsdb_addr"
  echo "🔧 OVSDB = tcp:${ACCESS_IP}:6632"
  curl -s -X PUT -d "\"tcp:${ACCESS_IP}:6632\"" "$OVSDB_URL"


  # --- Esperar a que ovs_bridge exista ---
STATUS="$RYU/qos/status/0000000000000003"
for j in {1..12}; do
  MSG=$(curl -s "$STATUS")
  echo "$MSG" | grep -q '"axswan"' && break
  echo " Esperando que Ryu conecte OVSDB… ($j/12)"; sleep 3
done

  ######## Cargar Queue y Rule #################################
  echo "  queue-to-voip.json"
  curl -s -X POST -d @"$QUEUE_JSON" "$RYU/qos/queue/0000000000000003"

  echo "  rule-to-voip.json"
  curl -s -X POST -d @"$RULE_JSON"  "$RYU/qos/rules/0000000000000003"

  echo " QoS aplicado en ${SITE}"

  # Cierra el túnel antes de pasar al siguiente site
  kill "$PF_PID" 2>/dev/null || true
  trap - RETURN
done

echo
echo " Todas las configuraciones QoS se han inyectado correctamente"
