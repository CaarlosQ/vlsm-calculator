#!/usr/bin/env bash
#
# VLSM_Subnetting.sh — Calculadora VLSM en Bash (subredes opcionales)
# Requiere: bash, bc, sort
#

set -euo pipefail

# Convierte IP a entero
ip_to_int() {
  IFS=. read -r a b c d <<< "$1"
  echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# Convierte entero a IP
int_to_ip() {
  local int=$1
  echo "$(( (int >> 24) & 255 )).$(( (int >> 16) & 255 )).$(( (int >> 8) & 255 )).$(( int & 255 ))"
}

# Genera máscara de prefijos en decimal y binario
mask_from_prefix() {
  local prefix=$1
  local mask_int=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
  local mask_dec
  mask_dec=$(int_to_ip "$mask_int")

  local bin_oct bin=""
  for shift in 24 16 8 0; do
    oct=$(( (mask_int >> shift) & 0xFF ))
    bin_oct=$(printf "%08d" "$(echo "obase=2; $oct" | bc)")
    bin+="$bin_oct "
  done

  echo "$mask_dec"
  echo "$bin"
}

# Calcula mínimo n tal que 2^n - 2 >= hosts
minimal_bits() {
  local hosts=$1 n=0
  while [ $((2**n - 2)) -lt "$hosts" ]; do
    ((n++))
  done
  echo "$n"
}

# -------- Programa Principal --------

echo "===== Calculadora VLSM en Bash ====="

# 1) Leer red base
read -rp "Red base (ej: 192.168.1.0/24): " base
if [[ ! "$base" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
  echo "Formato incorrecto. Usa IP/Mascara, p.ej.: 192.168.1.0/24"
  exit 1
fi
IFS=/ read -r base_ip base_pref <<< "$base"

# 2) Cálculo de dirección de red
base_int=$(ip_to_int "$base_ip")
read mask_dec _ <<< "$(mask_from_prefix "$base_pref")"
net_int=$(( base_int & $(ip_to_int "$mask_dec") ))

echo

# 3) Leer número de subredes (opcional)
read -rp "Número de subredes (opcional, ENTER para inferir): " total_input

# 4) Leer lista de hosts
read -rp "Ingresa cantidades de hosts (separadas por espacios o comas): " hosts_input
# limpiar comas y duplicar espacios
hosts_input=${hosts_input//,/ }
read -a hosts_list <<< "$hosts_input"

if [ ${#hosts_list[@]} -eq 0 ]; then
  echo "No ingresaste ninguna cantidad de hosts. Saliendo."
  exit 1
fi

# 5) Ordenar de mayor a menor
IFS=$'\n' sorted=($(sort -nr <<<"${hosts_list[*]}"))
unset IFS

# 6) Determinar cuántas procesar
if [[ -n "$total_input" && "$total_input" =~ ^[0-9]+$ ]]; then
  total=$total_input
  if [ "$total" -gt "${#sorted[@]}" ]; then
    echo "Advertencia: pediste $total subredes pero solo hay ${#sorted[@]} valores. Usaré ${#sorted[@]}."
    total=${#sorted[@]}
  fi
else
  total=${#sorted[@]}
fi

echo "Total de subredes a crear: $total"

# 7) Calcular y mostrar subredes
current_net=$net_int
echo -e "\n===== RESULTADOS VLSM ====="

for idx in $(seq 0 $((total - 1))); do
  hosts=${sorted[$idx]}
  n=$(minimal_bits "$hosts")
  usable=$((2**n - 2))
  new_pref=$((32 - n))

  # máscara decimal y binaria
  tmp=$(mask_from_prefix "$new_pref")
  new_mask_dec=${tmp%%$'\n'*}
  new_mask_bin=${tmp#*$'\n'}

  subnet_int=$current_net
  mask_int=$(ip_to_int "$new_mask_dec")
  bc_int=$(( subnet_int | ((1 << (32 - new_pref)) - 1) ))

  first=$(( subnet_int + 1 ))
  last=$(( bc_int - 1 ))
  salto=$(( 256 - ${new_mask_dec##*.} ))

  echo -e "\n--- Subred $((idx + 1)) (hosts=$hosts, usables=$usable) ---"
  echo "Red:               $(int_to_ip $subnet_int)/$new_pref"
  echo "Primera IP usable: $(int_to_ip $first)"
  echo "Última IP usable:  $(int_to_ip $last)"
  echo "Broadcast:         $(int_to_ip $bc_int)"
  echo "Máscara decimal:   $new_mask_dec"
  echo "Máscara binaria:   $new_mask_bin"
  echo "Salto de subred:   $salto"

  # siguiente red
  current_net=$(( bc_int + 1 ))
done
