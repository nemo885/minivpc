#!/bin/bash
set -e

bash "$(dirname "$0")/teardown.sh"

# шаг 1: namespaces
for ns in public app db router; do
  ip netns add $ns
done

# шаг 2: кабель public <-> router
create_cable() {
    local ns="$1"
    local num="$2"
    ip link add veth-${ns} type veth peer name veth-${ns}-r
    ip link set veth-${ns} netns ${ns}
    ip link set veth-${ns}-r netns router

    ip netns exec ${ns} ip addr add 10.50.${num}.2/24 dev veth-${ns}
    ip netns exec ${ns} ip link set veth-${ns} up
    ip netns exec ${ns} ip link set lo up

    ip netns exec router ip addr add 10.50.${num}.1/24 dev veth-${ns}-r
    ip netns exec router ip link set veth-${ns}-r up

}

ip netns exec router ip link set lo up

create_cable public 1
create_cable app 2
create_cable db 3
    


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

ip netns exec router nft insert rule inet minivpc forward iifname "veth-public-r" oifname "veth-up-r" counter accept


WAN=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')

sysctl -w net.ipv4.ip_forward=1
ip route add 10.50.1.0/24 via 10.50.0.2
nft add table ip minivpc_nat
nft add chain ip minivpc_nat postrouting '{ type nat hook postrouting priority 100; }'
nft add rule ip minivpc_nat postrouting ip saddr 10.50.1.0/24 oifname "$WAN" counter masquerade
ufw route allow in on veth-up out on "$WAN"
