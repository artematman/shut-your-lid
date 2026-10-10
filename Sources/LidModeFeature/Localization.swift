import Foundation

/// Interface language: Russian when the user's first preferred language is
/// Russian, English otherwise.
public enum LidLanguage: Sendable {
 case ru, en
 public static var current: LidLanguage { resolve(Locale.preferredLanguages) }
 /// Follows the macOS language: Russian when it is first, English for anything else.
 public static func resolve(_ preferred: [String]) -> LidLanguage {
  (preferred.first ?? "en").lowercased().hasPrefix("ru") ? .ru : .en
 }
}

public func loc(_ key: String, _ arguments: CVarArg...) -> String {
 lidString(key, language: .current, arguments)
}

/// A duration in full words: «1 час 30 минут», «2 часа», «6 часов», «45 минут»; «1 hour 30 minutes».
public func lidDuration(minutes: Int) -> String { lidDuration(minutes: minutes, language: .current) }

func lidDuration(minutes: Int, language: LidLanguage) -> String {
 let hours = minutes / 60, rest = minutes % 60
 var parts: [String] = []
 if hours > 0 { parts.append("\(hours) " + lidUnit(hours, language == .ru ? ("час", "часа", "часов") : ("hour", "hours", "hours"), language)) }
 if rest > 0 || hours == 0 { parts.append("\(rest) " + lidUnit(rest, language == .ru ? ("минута", "минуты", "минут") : ("minute", "minutes", "minutes"), language)) }
 return parts.joined(separator: " ")
}

/// Russian plural forms (one / few / many); English uses one / other.
func lidUnit(_ n: Int, _ forms: (one: String, few: String, many: String), _ language: LidLanguage) -> String {
 guard language == .ru else { return n == 1 ? forms.one : forms.many }
 let mod10 = n % 10, mod100 = n % 100
 if mod10 == 1 && mod100 != 11 { return forms.one }
 if (2...4).contains(mod10) && !(12...14).contains(mod100) { return forms.few }
 return forms.many
}

func lidString(_ key: String, language: LidLanguage, _ arguments: [CVarArg] = []) -> String {
 let template = (language == .ru ? lidStringsRU[key] : lidStringsEN[key]) ?? lidStringsRU[key] ?? key
 guard !arguments.isEmpty else { return template }
 // Templates use %@ for substitution; all other percent signs are literal.
 let format = template.replacingOccurrences(of: "%", with: "%%").replacingOccurrences(of: "%%@", with: "%@")
 return String(format: format, arguments: arguments)
}

let lidStringsRU: [String: String] = [
 "lid.title": "Работать с закрытой крышкой",
 "status.working": "Применяем…",
 "lid.unavailable": "Недоступно в этой сборке: нет системного помощника.",
 "lid.helperGone": "системный помощник не отвечает",
 "lid.conflict": "Сначала выключите режим закрытой крышки в другом приложении и отключите его фоновый помощник в настройках macOS.",
 "lid.openApproval": "Открыть настройки macOS",
 "lid.openApproval.help": "Откроет Системные настройки на странице, где разрешают фоновые объекты",
 "lid.stop.battery": "Выключено: заряд 10%",
 "lid.stop.thermal": "Выключено: перегрев",
 "lid.stop.time": "Выключено: время истекло",
 "lid.stop.telemetry": "Выключено: нет данных о питании",
 "lid.stop.failed": "Ошибка восстановления сна",
 "menu.settings": "Настройки…",
 "menu.quit": "Выйти из Shut Your Lid",
 "menu.quit.short": "Выйти",
 "settings.title": "Настройки",
 "settings.back": "Назад",
 "settings.duration": "Выключать через",
 "settings.duration.custom": "Своё значение",
 "settings.duration.minutes": "Минуты",
 "settings.duration.range": "От 1 минуты до 12 часов.",
 "settings.protection": "Защита",
 "settings.protection.battery": "При 10% на аккумуляторе режим выключится, и Mac уснёт.",
 "settings.protection.thermal": "При перегреве или неизвестном питании режим остановится.",
 "settings.loginItems": "Настроить объекты входа macOS",
 "edit.menu": "Правка",
 "edit.cut": "Вырезать",
 "edit.copy": "Копировать",
 "edit.paste": "Вставить",
 "edit.selectAll": "Выбрать всё",
 "status.off": "Выключено",
 "status.battery %@": "Заряд аккумулятора %@%",
 "status.battery.requirement": "На аккумуляторе режим работает только при заряде выше 10%. Зарядите MacBook или подключите питание.",
 "status.enabling": "Включаем…",
 "status.disabling": "Выключаем…",
 "status.on": "Включено",
 "status.on.until %@": "Включено до %@",
 "status.on.tomorrow %@": "Включено до %@ завтра",
 "status.needsApproval": "Нужно разрешение macOS",
 "status.failed": "Ошибка",
 "status.unavailable": "Недоступно",
 "onboarding.message": "Управление — в строке меню, под значком ноутбука.",
 "onboarding.hint": "Нажмите на него, когда понадобится работать с закрытой крышкой.",
 "onboarding.hidden": "Если значка не видно, освободите место в строке меню.",
 "onboarding.skip": "Пропустить",
 "onboarding.done": "Готово",
 "onboarding.logo": "Логотип Shut Your Lid: губы, застёгнутые на молнию",
 "onboarding.icon": "Значок Shut Your Lid в строке меню",
 "lid.connectionLost": "Нет связи с системным помощником; состояние режима не подтверждено.",
]

let lidStringsEN: [String: String] = [
 "lid.title": "Work with the lid closed",
 "status.working": "Applying…",
 "lid.unavailable": "Unavailable in this build: the system helper is missing.",
 "lid.helperGone": "the system helper is not responding",
 "lid.conflict": "First turn off closed-lid mode in the other app and disable its background helper in macOS settings.",
 "lid.openApproval": "Open macOS Settings",
 "lid.openApproval.help": "Opens System Settings where background items are allowed",
 "lid.stop.battery": "Off: battery at 10%",
 "lid.stop.thermal": "Off: Mac too hot",
 "lid.stop.time": "Off: time is up",
 "lid.stop.telemetry": "Off: power state unknown",
 "lid.stop.failed": "Sleep restore failed",
 "menu.settings": "Settings…",
 "menu.quit": "Quit Shut Your Lid",
 "menu.quit.short": "Quit",
 "settings.title": "Settings",
 "settings.back": "Back",
 "settings.duration": "Turn off after",
 "settings.duration.custom": "Custom",
 "settings.duration.minutes": "Minutes",
 "settings.duration.range": "From 1 minute to 12 hours.",
 "settings.protection": "Protection",
 "settings.protection.battery": "At 10% on battery, the mode turns off and the Mac sleeps.",
 "settings.protection.thermal": "It stops on overheating or an unknown power state.",
 "settings.loginItems": "Open macOS Login Items",
 "edit.menu": "Edit",
 "edit.cut": "Cut",
 "edit.copy": "Copy",
 "edit.paste": "Paste",
 "edit.selectAll": "Select All",
 "status.off": "Off",
 "status.battery %@": "Battery charge %@%",
 "status.battery.requirement": "On battery, the mode works only above 10% charge. Charge your MacBook or connect power.",
 "status.enabling": "Turning on…",
 "status.disabling": "Turning off…",
 "status.on": "On",
 "status.on.until %@": "On until %@",
 "status.on.tomorrow %@": "On until %@ tomorrow",
 "status.needsApproval": "Needs macOS permission",
 "status.failed": "Error",
 "status.unavailable": "Unavailable",
 "onboarding.message": "Controls live in the menu bar, under the laptop icon.",
 "onboarding.hint": "Click it whenever you need to work with the lid closed.",
 "onboarding.hidden": "If you don't see the icon, make room in the menu bar.",
 "onboarding.skip": "Skip",
 "onboarding.done": "Done",
 "onboarding.logo": "Shut Your Lid logo: lips zipped shut",
 "onboarding.icon": "Shut Your Lid icon in the menu bar",
 "lid.connectionLost": "Lost connection to the system helper; the mode's state is unconfirmed.",
]
