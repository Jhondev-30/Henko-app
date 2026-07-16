# 🩰 Henko — App de pagos semanales

App privada de **Android** para administrar los pagos semanales de la academia de baile **Henko**. Una sola persona la usa (el admin). Los datos se guardan **localmente en el dispositivo** (SQLite), no hay servidor ni login.

> 🇻🇪 Hecho en Barquisimeto, Lara — Venezuela.

---

## ✨ Funcionalidades

| | |
|---|---|
| ✅ | Lista de miembros del henko con **búsqueda en tiempo real** |
| ✅ | Toggle de "pagado esta semana" por miembro (1 toque) |
| ✅ | Sheet con 3 opciones: **subir captura + marcar**, **marcar sin captura**, **cancelar** |
| ✅ | Captura de pantalla del pago (galería o cámara) por semana |
| ✅ | Reemplazar / eliminar / ampliar captura |
| ✅ | Foto del miembro para identificarlos mejor |
| ✅ | Selector de semana ‹ › (actual + 8 semanas atrás) |
| ✅ | Header con 3 stats: **pagaron, dinero recaudado, días restantes** |
| ✅ | Detalle del miembro con **historial por semana** (estilo `<details>`/`<summary>`) |
| ✅ | Historial por semana: ver quién pagó y quién no |
| ✅ | Confirmación al desmarcar (advierte si se borrará una captura) |
| ✅ | Soft-delete de miembros (no se borra el historial) |
| ✅ | **Material 3** + paleta de marca (coral + navy) |
| ✅ | Logo de bailarina de danza contemporánea (auto-generado) |

---

## 🛠️ Stack técnico

| Categoría | Tecnología |
|---|---|
| **Framework** | Flutter 3.44 (Dart 3.12) |
| **State management** | Riverpod 2.5 |
| **DB local** | sqflite (SQLite nativo en Android/iOS/Windows) |
| **Imágenes** | image_picker 1.x + path_provider |
| **Formatos** | intl 0.20 (fechas, moneda) |
| **UI** | Material 3 con tokens semánticos |

---

## 📂 Estructura del proyecto

```
henko_app/
├── lib/
│   ├── main.dart                       # Entry point + i18n
│   ├── app_config.dart                 # Constantes (cuota, app name)
│   ├── theme/
│   │   └── app_theme.dart              # Paleta Material 3, spacing, radius
│   ├── models/
│   │   ├── member.dart                 # Miembro (id, name, photoPath, active)
│   │   └── payment.dart                # Pago (week, amount, screenshotPath)
│   ├── data/
│   │   ├── database.dart               # SQLite schema + migrations v1→v2
│   │   ├── in_memory_store.dart        # Mock en memoria (web)
│   │   ├── member_repository.dart      # CRUD miembros
│   │   └── payment_repository.dart     # CRUD pagos
│   ├── providers/
│   │   ├── repositories_provider.dart  # Provider de DBs
│   │   ├── members_provider.dart       # Notifier de miembros
│   │   ├── payments_provider.dart      # Notifier + week selector
│   │   └── home_providers.dart         # Members + status combinado
│   ├── screens/
│   │   ├── home_screen.dart            # Lista + búsqueda + selector semana
│   │   ├── add_member_screen.dart      # Form agregar miembro + foto
│   │   ├── member_detail_screen.dart   # Detalle + historial ExpansionTile
│   │   └── week_history_screen.dart    # Vista por semana específica
│   ├── widgets/
│   │   ├── header_stats.dart           # 3 stat cards + selector
│   │   ├── member_tile.dart            # Card de miembro M3
│   │   ├── pay_sheet.dart              # Sheet de marcar/desmarcar
│   │   └── shimmer.dart                # Loading placeholder animado
│   └── utils/
│       ├── week_calculator.dart        # Lunes→domingo, navegación
│       └── currency_formatter.dart     # $1.75 formatting
├── assets/
│   └── henko_logo.png                  # Logo de bailarina
└── android/
    └── app/src/main/res/mipmap-*/      # Iconos Android (5 densidades)
```

---

## 🚀 Setup

### Pre-requisitos
- **Flutter 3.44+** → https://docs.flutter.dev/get-started/install/windows
- **Android Studio** (incluye Android SDK + JDK 17)
- **Windows 10/11**

### Verificar entorno
```powershell
flutter doctor
```

### Correr en modo desarrollo (con hot reload)
```powershell
cd C:\Users\User\Documents\henko\henko_app
flutter run
```

> Conectá un device Android por USB o iniciá un emulador. `flutter run` lo detecta y compila.

### Compilar APK
```powershell
# APK debug (testing, sin firmar)
flutter build apk --debug

# APK release (distribución, firmado con tu keystore)
flutter build apk --release
```

El APK queda en `build/app/outputs/flutter-apk/`.

### Instalar en device
```powershell
flutter devices          # confirmar que aparece el device
flutter install          # instala el APK debug
```

---

## 🔐 Generar APK firmado (Release)

Una sola vez en la vida del proyecto:

```powershell
# 1. Crear keystore (te pide password, mín 6 chars, GUARDALO)
& "E:\AndroidStudio\studio\jbr\bin\keytool.exe" -genkey -v `
  -keystore "C:\Users\User\Documents\henko\henko-release-key.jks" `
  -keyalg RSA -keysize 2048 -validity 10000 -alias henko

# 2. Crear android\key.properties con tus credenciales (NO commitear)

# 3. flutter build apk --release
```

⚠️ **El `.jks` es tu firma digital para siempre.** Guardá una copia en USB o cloud.

---

## 💾 Modelo de datos (SQLite v2)

```sql
-- Miembros
CREATE TABLE members (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  active INTEGER NOT NULL DEFAULT 1,
  photo_path TEXT                       -- agregado en v2
);

-- Pagos
CREATE TABLE payments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  member_id INTEGER NOT NULL REFERENCES members(id) ON DELETE CASCADE,
  week_start INTEGER NOT NULL,          -- lunes 00:00 de la semana
  week_end INTEGER NOT NULL,
  amount REAL NOT NULL,
  screenshot_path TEXT,                 -- ruta o data: URL
  paid_at INTEGER NOT NULL,
  note TEXT
);

CREATE INDEX idx_payments_member_week ON payments(member_id, week_start);
CREATE INDEX idx_payments_week ON payments(week_start);
```

**Regla de negocio**: 1 pago por persona por semana (constraint implícito en `upsert`).

**Migración v1 → v2**: agrega `photo_path` a `members` (ver `database.dart`).

---

## ⚙️ Configuraciones

`lib/app_config.dart`:
```dart
static const double weeklyFee = 1.75;    // Cuota semanal USD
static const int historyWeeksBack = 8;   # Semanas en el selector
```

`lib/theme/app_theme.dart`:
- `brandPrimary` (default `#E63946` coral)
- `brandSecondary` (default `#1D3557` navy)
- Spacing tokens: `s1`-`s12`
- Radius tokens: `rSm`-`rFull`

---

## 🐛 Troubleshooting

| Problema | Solución |
|---|---|
| `MissingPluginException` en web | Hot reload puede romper el estado. Recargá Chrome |
| `Visual Studio toolchain` not found | Abrí Android Studio → SDK Manager → install |
| `cmdline-tools missing` | Reinstala Android Studio con "Custom" + cmdline-tools |
| `pub get` falla | Borrá `.dart_tool/` y `pubspec.lock`, corré `flutter pub get` |
| Hot reload pierde el state | Hot **restart** (Shift+F5 + F5) o `r` en la terminal |
| Emulator se queda en negro | Verificá que AVD usa API 30+ y que tenés HAXM/AEHD instalado |

---

## 📋 Roadmap (no implementado)

- [ ] Exportar historial a CSV / Excel
- [ ] Backup automático (Google Drive / iCloud)
- [ ] Notificación recordatorio los domingos
- [ ] Multi-academia (multi-tenant)
- [ ] Tema oscuro
- [ ] Versión iOS

---

## 📄 Licencia

Privado — uso interno de **Academia de Baile Henko**.

---

<p align="center">
  Hecho con 🩰 en Barquisimeto, Venezuela
</p>
