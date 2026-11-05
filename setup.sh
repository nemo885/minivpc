#!/bin/bash
set -e

bash "$(dirname "$0")/teardown.sh

# шаг 1: namespaces
for ns in public app db router; do
  ip netns add $ns
done

# шаг 2: кабель public <-> router
ip link add veth-pub type veth peer name veth-pub-r
ip link set veth-pub netns public
ip link set veth-pub-r netns router

ip netns exec public ip addr add 10.50.1.2/24 dev veth-pub
ip netns exec public ip link set veth-pub up
ip netns exec public ip link set lo up

ip netns exec router ip addr add 10.50.1.1/24 dev veth-pub-r
ip netns exec router ip link set veth-pub-r up
ip netns exec router ip link set lo up

ip link add veth-app type veth peer name veth-app-r
ip link set veth-app netns app
ip link set veth-app-r netns router

ip netns exec app ip addr add 10.50.2.2/24 dev veth-app
ip netns exec app ip link set veth-app up
ip netns exec app ip link set lo up

ip netns exec router ip addr add 10.50.2.1/24 dev veth-app-r
ip netns exec router ip link set veth-app-r up


ip link add veth-db type veth peer name veth-db-r
ip link set veth-db netns db
ip link set veth-db-r netns router

ip netns exec db ip addr add 10.50.3.2/24 dev veth-db
ip netns exec db ip link set veth-db up
ip netns exec db ip link set lo up

ip netns exec router ip addr add 10.50.3.1/24 dev veth-db-r
ip netns exec router ip link set veth-db-r up


ip netns exec router sysctl -w net.ipv4.ip_forward=1

ip netns exec public ip route add default via 10.50.1.1
ip netns exec app ip route add default via 10.50.2.1
ip netns exec db ip route add default via 10.50.3.1

ip netns exec router nft add table inet minivpc
ip netns exec router nft add chain inet minivpc forward '{ type filter hook forward priority 0; policy drop; }'
ip netns exec router nft add rule inet minivpc forward ct state established,related accept
ip netns exec router nft add rule inet minivpc forward ip saddr 10.50.1.2 ip daddr 10.50.2.2 tcp dport 8000 counter accept
ip netns exec router nft add rule inet minivpc forward ip saddr 10.50.2.2 ip daddr 10.50.3.2 tcp dport 5432 counter accept

ip netns exec router nft  add rule inet minivpc forward counter drop

ip link add veth-up type veth peer name veth-up-r
ip link set veth-up-r netns router

ip addr add 10.50.0.1/30 dev veth-up
ip link set veth-up up

ip netns exec router ip addr add 10.50.0.2/30 dev veth-up-r
ip netns exec router ip link set veth-up-r up

ip netns exec router ip route add default via 10.50.0.1

ip netns exec router nft insert rule inet minivpc forward iifname "veth-pub-r" oifname "veth-up-r" counter accept


WAN=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')

sysctl -w net.ipv4.ip_forward=1
ip route add 10.50.1.0/24 via 10.50.0.2
nft add table ip minivpc_nat
nft add chain ip minivpc_nat postrouting '{ type nat hook postrouting priority 100; }'
nft add rule ip minivpc_nat postrouting ip saddr 10.50.1.0/24 oifname "$WAN" counter masquerade
ufw route allow in on veth-up out on "$WAN"
