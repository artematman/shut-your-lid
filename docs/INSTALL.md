# Install Shut Your Lid

**macOS 14 or newer · Apple Silicon and Intel · version 0.3.9 build 18.** The launch wordmark intentionally animates Lid → Lip.

This public prerelease is free to download. No GitHub account is required. The app is signed and notarized; each Mac keeps its own preferences and recovery state. No publisher account, password or private signing key is included or required.

## Установка на Mac

1. Скачайте [DMG](https://github.com/artematman/shut-your-lid/releases/download/v0.3.9-rc.1/Shut-Your-Lid-0.3.9-universal.dmg).
2. Откройте образ и перенесите **Shut Your Lid** в **Программы**. Запускайте копию из «Программ», затем извлеките образ.
3. При запуске появится анимация. Управление находится у значка MacBook в верхней строке меню.
4. Нажмите значок, откройте «Настройки» и выберите длительность. По умолчанию — 4 часа; доступны готовые значения и ползунок от 1 минуты до 12 часов. Во время работы длительность можно менять.
5. Включите «Работать с закрытой крышкой». При первом включении macOS может запросить разрешение на фоновый помощник: **Системные настройки → Основные → Объекты входа и расширения**. Разрешите элемент приложения. macOS может показать имя разработчика, подписавшего приложение.
6. Вернитесь в приложение. Закрывайте крышку только после того, как переключатель включился и приложение показало подтверждённое время окончания режима.

Если macOS блокирует запуск, не отключайте Gatekeeper и не удаляйте quarantine. Проверьте, что скачан актуальный подписанный пакет, и сообщите об ошибке. Если другая утилита уже удерживает Mac от сна, сначала отключите её режим.

## Что проверить перед общим выпуском

Это кандидат для проверки. Нужны отдельный чистый Mac для установки/обновления помощника и аппаратная приёмка закрытой крышки, батареи 10%, перегрева и восстановления сна. Анимация уже одобрена владельцем; автоматические тесты не заменяют проверки железа. См. [Validation](VALIDATION.md).

При 10% и ниже на аккумуляторе приложение восстанавливает обычный сон и запрашивает переход Mac в сон. При серьёзном перегреве или неизвестном питании режим останавливается. Не кладите работающий MacBook в сумку.

## Обновление и удаление

Перед обновлением выключите режим и завершите приложение. Замените приложение в «Программах» новой копией из DMG. Настройки сохраняются на этом Mac.

Перед удалением выключите режим, убедитесь, что обычный сон восстановлен, завершите приложение и отключите его фоновый элемент в настройках macOS. Затем удалите приложение из «Программ».

## Package verification

The release includes the signed DMG, an alternative app ZIP, a source-only ZIP and SHA256SUMS. App and DMG have Apple notarization tickets. To verify downloaded files with Terminal:

```sh
shasum -a 256 -c SHA256SUMS
```

Place the checksum file beside all three downloaded archives before running the command. Verification is optional for normal installation. See [Security](../SECURITY.md) for the reviewed scope and remaining limits.
