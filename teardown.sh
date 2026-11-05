
for ns  in public app db router; do
  ip netns del $ns 2>/dev/null || true 
done

# убрать то, что setup создал на хосте
WAN=$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
nft delete table ip minivpc_nat 2>/dev/null || true
ufw --force route delete allow in on veth-up out on "$WAN" 2>/dev/null || true
