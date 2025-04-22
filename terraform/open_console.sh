#!/bin/bash

# Esperar a que los pods estén listos antes de intentar abrir consola
echo "⏳ Esperando que los pods estén listos..."

kubectl wait --for=condition=Ready pod/vnf-access -n rdsv --timeout=60s
kubectl wait --for=condition=Ready pod/vnf-cpe -n rdsv --timeout=60s

# Verificar si tienen /bin/bash
check_shell() {
  local pod=$1
  if ! kubectl exec -n rdsv "$pod" -- which bash &>/dev/null; then
    echo "⚠️  El pod $pod no tiene /bin/bash. Usando /bin/sh en su lugar."
    echo "/bin/sh"
  else
    echo "/bin/bash"
  fi
}

shell_access=$(check_shell vnf-access)
shell_cpe=$(check_shell vnf-cpe)

echo "🔌 Abriendo consola de vnf-access..."
xfce4-terminal --title access-1 --hide-menubar \
  -x bash -c "kubectl exec -n rdsv -it vnf-access -- $shell_access || read -p 'Presione Enter para cerrar...'" &

echo "🔌 Abriendo consola de vnf-cpe..."
xfce4-terminal --title cpe-1 --hide-menubar \
  -x bash -c "kubectl exec -n rdsv -it vnf-cpe -- $shell_cpe || read -p 'Presione Enter para cerrar...'" &
