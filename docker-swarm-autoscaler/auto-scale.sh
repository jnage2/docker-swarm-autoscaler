#!/bin/bash

# Configurations par défaut
LOOP=${LOOP:='yes'}
CPU_PERCENTAGE_UPPER_LIMIT=${CPU_PERCENTAGE_UPPER_LIMIT:=85}
CPU_PERCENTAGE_LOWER_LIMIT=${CPU_PERCENTAGE_LOWER_LIMIT:=25}
PROMETHEUS_API="api/v1/query?query="
PROMETHEUS_QUERY="sum(rate(container_cpu_usage_seconds_total%7Bcontainer_label_com_docker_swarm_task_name%3D~%27.%2B%27%7D%5B5m%5D))BY(container_label_com_docker_swarm_service_name%2Cinstance)*100"
PROMETHEUS_URL=${PROMETHEUS_URL:-"http://prometheus:9090"}

# Fonction pour logger les messages
echo_log() {
  local level="$1"
  local message="$2"
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] [$level] $message"
}

# Message d'accueil
welcome_message() {
  echo "============================================="
  echo " Docker Swarm Autoscaler v1.0 "
  echo " Un outil pour automatiser le scaling des services Docker Swarm en fonction des métriques CPU. "
  echo " Auteur: ANDROGE Julien "
  echo "============================================="
}

# Fonction pour vérifier la disponibilité de Prometheus
check_prometheus() {
  curl -s "${PROMETHEUS_URL}" > /dev/null
  if [[ $? -ne 0 ]]; then
    echo_log "ERROR" "Prometheus n'est pas accessible à l'adresse ${PROMETHEUS_URL}. Vérifiez la configuration."
    exit 1
  fi
}

# Fonction pour récupérer les services avec une utilisation CPU élevée
get_high_cpu_services() {
  local prometheus_results="$1"
  local services=""
  services=$(echo "$prometheus_results" | jq ".data.result[] | select(.value[1]|tonumber > $CPU_PERCENTAGE_UPPER_LIMIT) | .metric.container_label_com_docker_swarm_service_name" | sed 's/\"//g')
  echo "$services"
}

# Fonction pour récupérer tous les services
get_all_services() {
  local prometheus_results="$1"
  local services=""
  services=$(echo "$prometheus_results" | jq ".data.result[].metric.container_label_com_docker_swarm_service_name" | sed 's/\"//g')
  echo "$services"
}

# Fonction pour mettre à l'échelle un service
scale_service() {
  local service="$1"
  local replicas="$2"
  docker service scale "$service=$replicas"
  if [[ $? -eq 0 ]]; then
    echo_log "INFO" "Service $service mis à l'échelle à $replicas réplicas."
  else
    echo_log "ERROR" "Échec de la mise à l'échelle du service $service."
  fi
}

# Fonction principale
run_autoscaler() {
  check_prometheus
  while [[ "$LOOP" == "yes" ]]; do
    echo_log "INFO" "Récupération des métriques depuis Prometheus."
    local prometheus_results
    prometheus_results=$(curl -s "${PROMETHEUS_URL}/${PROMETHEUS_API}${PROMETHEUS_QUERY}")

    if [[ -z "$prometheus_results" ]]; then
      echo_log "ERROR" "Impossible de récupérer les métriques de Prometheus."
      sleep 10
      continue
    fi

    local high_cpu_services
    high_cpu_services=$(get_high_cpu_services "$prometheus_results")

    for service in $high_cpu_services; do
      local current_replicas
      current_replicas=$(docker service inspect "$service" --format '{{.Spec.Mode.Replicated.Replicas}}')
      local new_replicas=$((current_replicas + 1))
      scale_service "$service" "$new_replicas"
    done

    sleep 30
  done
}

# Exécution du script
welcome_message
run_autoscaler
