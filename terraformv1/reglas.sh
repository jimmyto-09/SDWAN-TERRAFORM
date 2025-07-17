#!/usr/bin/env bash
set -euo pipefail

# ──────────────── Resolver Kubernetes ───────────────────────────────
if command -v kubectl >/dev/null 2>&1; then
  KCTL="kubectl"
elif command -v microk8s >/dev/null 2>&1; then
  KCTL="microk8s kubectl"
else
  echo "No se encontró ni kubectl ni microk8s" >&2
  exit 1
fi
echo " Usando '$KCTL' como cliente Kubernetes"

# ─────────────────────────── Configuración ──────────────────────────────────
JSON_DIR="/home/upm/shared/sdedge-ns/json"   # carpeta con todos los .json
NAMESPACE="rdsv"                             # namespace de los pods Ryu
COMMON_JSONS=(
  "from-cpe.json"
  "to-cpe.json"
  "broadcast-from-axs.json"
  "from-mpls.json"
  "to-voip-gw.json"
)

# ────────────────────────── Verificaciones previas ──────────────────────────
[[ -d "$JSON_DIR" ]] || { echo " Carpeta $JSON_DIR no existe"; exit 1; }
command -v curl >/dev/null || { echo "curl no encontrado"; exit 1; }

# ───────────────────────────── Descubrir e identificar sites ──────────────────────────────
mapfile -t EDGE_DIRS < <(find "$JSON_DIR" -maxdepth 1 -type d -name 'sdedge*' | sort)
if [[ ${#EDGE_DIRS[@]} -eq 0 ]]; then
  echo " No se encontró ninguna carpeta sdedge* en $JSON_DIR"
  exit 1
fi
echo "🔎 Detectados $((${#EDGE_DIRS[@]})) sites → ${EDGE_DIRS[*]##*/}"

# ───────────────────────────── Bucle por cada site ──────────────────────────
for EDGE_DIR in "${EDGE_DIRS[@]}"; do
  NETNUM=$(basename "$EDGE_DIR" | sed 's/^sdedge//')
  SITE="site${NETNUM}"
  SVC="knf-ctrl-${SITE}-svc"

  echo
  echo "═══════════════  Cargando reglas en ${SITE}  ═══════════════"

  # 1) Esperar a que el Pod esté Ready
  echo "⏳ Esperando Pod Ryu (${SITE})..."
  $KCTL wait --for=condition=ready \
    pod -l k8s-app="knf-ctrl-${SITE}" -n "$NAMESPACE" --timeout=120s

  # 2) Port‑forward
  LOCAL_PORT=$(shuf -i 20000-29999 -n 1)
  echo "⏳ Port‑forward  localhost:${LOCAL_PORT} ↔ ${SVC}:8080"
  $KCTL port-forward -n "$NAMESPACE" svc/"${SVC}" \
          ${LOCAL_PORT}:8080 >/dev/null 2>&1 &
  PF_PID=$!
  trap "kill $PF_PID 2>/dev/null || true" RETURN
  sleep 2

  RYU_URL="http://localhost:${LOCAL_PORT}/stats/flowentry/add"
  echo "🎯  Endpoint REST = $RYU_URL"

  # 3) Enviar JSONs comunes
  for F in "${COMMON_JSONS[@]}"; do
    FILE="${JSON_DIR}/${F}"
    [[ -f "$FILE" ]] || { echo " $FILE no existe, se salta"; continue; }
    echo " $F"
    curl -s -X POST -d @"$FILE" "$RYU_URL"
  done

  # 4) Enviar el específico sdedgeX donde x puede ser 1,2,...,N/to-voip.json
  SPEC="${EDGE_DIR}/to-voip.json"
  if [[ -f "$SPEC" ]]; then
    echo "  $(basename "$SPEC")"
    curl -s -X POST -d @"$SPEC" "$RYU_URL"
  else
    echo "  $SPEC no encontrado, se omite"
  fi

  echo " Reglas cargadas en ${SITE}"

  # cerrar túnel
  kill "$PF_PID" 2>/dev/null || true
  trap - RETURN
done

echo
echo " Todas las reglas SDN se han inyectado con éxito"
