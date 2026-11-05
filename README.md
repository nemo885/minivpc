# minivpc: мини-VPC на Linux network namespaces

Сеть из трёх сегментов (public, app, db), роутера и firewall, собранная
вручную на namespaces, veth и nftables. Это то же самое, что VPC с подсетями
и security groups в облаке, только на голом Linux.

## Схема

```
                 интернет
                    │
                  [host]  NAT (masquerade) + ufw route
                    │ veth-up 10.50.0.1/30
                    │ veth-up-r 10.50.0.2/30
 public ───────── router ───────── app
 10.50.1.2/24      │ nft firewall   10.50.2.2/24
                   │ (policy drop)
                   db
                   10.50.3.2/24
```

## Адреса

| Namespace | Адрес | Шлюз (router) |
|---|---|---|
| public | 10.50.1.2/24 | 10.50.1.1 |
| app | 10.50.2.2/24 | 10.50.2.1 |
| db | 10.50.3.2/24 | 10.50.3.1 |

## Правила доступа (firewall в router, policy drop)

| Откуда | Куда | Порт | Решение |
|---|---|---|---|
| public | app | TCP 8000 | разрешено |
| app | db | TCP 5432 | разрешено |
| public | интернет | любой | разрешено (через NAT на хосте) |
| ответный трафик | любой | любой | разрешено (established,related) |
| всё остальное | | | запрещено |

## Запуск

```
sudo bash setup.sh      # поднять сеть
sudo bash teardown.sh   # убрать всё
```

Скрипты идемпотентные: их можно запускать повторно.

## Проверка

```
sudo ip netns exec app nc -lk 8000 &
sudo ip netns exec db nc -lk 5432 &

sudo ip netns exec public nc -zv -w1 10.50.2.2 8000   # проходит
sudo ip netns exec app nc -zv -w1 10.50.3.2 5432      # проходит
sudo ip netns exec public nc -zv -w1 10.50.3.2 5432   # timed out
sudo ip netns exec db nc -zv -w1 10.50.2.2 8000       # timed out
sudo ip netns exec public curl -I http://1.1.1.1      # проходит
sudo ip netns exec app curl -I --max-time 3 http://1.1.1.1  # timed out

sudo ip netns exec router nft list ruleset            # счётчики правил
```

Запрещённые пути режет именно firewall: счётчик последнего правила
(`counter drop`) растёт после каждой запрещённой проверки.

## Что я узнал

- Namespace: изолированный сетевой стек. Роутер здесь просто ещё один namespace.
- Чтобы Linux пересылал чужие пакеты, нужен ip_forward.
- timed out значит, что пакет выбросил firewall, refused значит, что порт никто не слушает.
- Частные адреса выходят в интернет через NAT (masquerade).
- Если на хосте включён ufw, транзитный трафик режется (deny routed), и нужно отдельное правило.
