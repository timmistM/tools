# 🛠 Tools

Коллекция скриптов для быстрой настройки серверов.

Все скрипты работают параллельно с существующими сервисами (3x-ui, Amnezia, WireGuard и др.) — автоматически находят свободные порты и не затрагивают текущую конфигурацию.

---

## MTProto Proxy для Telegram

Автоустановка MTProto прокси с fake-TLS маскировкой.

```bash
bash <(curl -sL https://raw.githubusercontent.com/timmistM/tools/main/mtproto_install.sh)
```

В конце скрипт выдаст готовую ссылку `https://t.me/proxy?...` — просто скопируй и отправь.
