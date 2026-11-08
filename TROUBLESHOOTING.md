# Поломка и диагностика 



## 1. Отключён интерфейс veth-app-r в router

**Прогноз:** перестанет работать только сегмент app (кабель app-router), public и db не пострадают, потому что у каждого сегмента свой кабель до router. Ошибка у nc: timed out.

**Симптом:**
- `ping` app -> router (10.50.2.1): 100% packet loss
- `ping` router -> app (10.50.2.2): 100% packet loss
- `nc -zv` public -> app:8000: timed out, хотя сервер на app запущен

**Как нашёл причину:** `ip netns exec router ip link` показал, что у `veth-app-r` в флагах нет `UP` (`<BROADCAST,MULTICAST>`, state DOWN). В `app` у `veth-app` стоит `NO-CARRIER`: сам интерфейс включён, но сигнала нет, потому что выключен второй конец кабеля. Остальные интерфейсы router (`veth-public-r`, `veth-db-r`, `veth-up-r`) были `UP,LOWER_UP`.

**Как починил:** `ip netns exec router ip link set veth-app-r up`. После этого у обоих концов `UP,LOWER_UP`, ping и nc проходят.

**Вывод:** если у кабеля один конец без `UP`, а другой с `NO-CARRIER`, виноват тот, где нет `UP`. Таймаут при работающем сервере означает, что пакеты теряются по дороге. Ошибка `refused` означала бы, что пакет дошёл, а порт никто не слушает.
