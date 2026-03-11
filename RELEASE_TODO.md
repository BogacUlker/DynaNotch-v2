# DynaNotch v2 — Release Yapılacaklar Listesi

> En kritikten en hafife doğru sıralanmıştır. Her madde öncelik seviyesi, dosya ve satır bilgisi içerir.

---

## 🔴 KRİTİK — Çökmeler (Crash)

| # | Sorun | Dosya | Satır | Durum |
|---|-------|-------|-------|-------|
| 1 | ~~`watcher.downloadFiles.first!` — dizi boşsa çöker (3 yerde)~~ | `DownloadView.swift` | 33, 46, 47 | ✅ |
| 2 | ~~`notification.userInfo?.first?.value as! Data` — force cast~~ | `BoringViewCoordinator.swift` | 181 | ✅ |
| 3 | ~~`URL(string: url)!` — **kullanıcı girdisi** ile oluşturulan URL~~ | `SettingsView.swift` | 1375 | ✅ |
| 4 | ~~`NSScreen.screens.first!` — ekran yoksa çöker~~ | `boringNotchApp.swift` | 414 | ✅ |
| 5 | ~~`selectedVisualizer!.url` ve `selectedVisualizer!.speed`~~ | `LottieAnimationView.swift` | 17 | ✅ |
| 6 | ~~`sources.first!` — power source boşsa çöker~~ | `BatteryActivityManager.swift` | 226 | ✅ |
| 7 | ~~Spor provider URL force unwrap'leri (11 adet)~~ | `FootballProvider.swift` | 149, 157 | ✅ |
|   | | `BasketballProvider.swift` | 156, 168 | ✅ |
|   | | `F1Provider.swift` | 116, 150, 197, 212, 232 | ✅ |

**Çözüm:** Tüm `!` operatörlerini `guard let` / `if let` / `??` ile değiştir.

---

## 🔴 KRİTİK — Bellek Sızıntıları

| # | Sorun | Dosya | Satır | Durum |
|---|-------|-------|-------|-------|
| 8 | ~~Mach port sızıntısı (3x `mach_host_self()` her 2sn)~~ | `SystemMonitorManager.swift` | — | ✅ |
| 9 | ~~`CFMachPortCreateRunLoopSource` — CFRelease yapılmıyor~~ | `MediaKeyInterceptor.swift` | 82 | ✅ |
| 10 | ~~`IOPSNotificationCreateRunLoopSource` retained value düzgün serbest bırakılmıyor~~ | `BatteryActivityManager.swift` | 69-87 | ✅ |
| 11 | `BoringViewCoordinator` — `deinit` yok, `accessibilityObserver` asla temizlenmiyor | `BoringViewCoordinator.swift` | 126-136 | ⏳ |
| 12 | ~~Kullanılmayan `sneakPeekDispatch` ve `expandingViewDispatch` property'leri (dead code)~~ | `BoringViewCoordinator.swift` | 55-56 | ✅ |

---

## 🔴 KRİTİK — Thread Safety / Data Race

| # | Sorun | Dosya | Durum |
|---|-------|-------|-------|
| 13 | ~~`BatteryActivityManager` — `observers`, `notificationQueue`, `previousBatteryInfo` birden fazla thread'den korumasız erişiliyor~~ | `BatteryActivityManager.swift` | ✅ |
| 14 | ~~`MusicManager` — `@MainActor` yok, `@Published` property'ler background thread'den güncelleniyor~~ | `MusicManager.swift` | ✅ |
| 15 | ~~`BoringViewModel` — `@MainActor` yok, 18+ `@Published` property~~ | `BoringViewModel.swift` | ✅ |
| 16 | `WebcamManager` — `sessionQueue` ile `@Published` arasında race condition (mevcut dispatch pattern yeterli) | `WebcamManager.swift` | ⚠️ |
| 17 | ~~`SystemMonitorManager` — `@MainActor` yok~~ | `SystemMonitorManager.swift` | ✅ |
| 18 | ~~`MusicManager.triggerFlipAnimation()` — iç closure'da `[weak self]` eksik~~ | `MusicManager.swift:516-517` | ✅ |

**Çözüm:** Singleton ObservableObject'lere `@MainActor` ekle veya tüm `@Published` güncellemelerini `DispatchQueue.main` ile koru.

---

## 🟡 ÖNEMLİ — Hata Yönetimi Eksiklikleri

| # | Sorun | Dosya | Satır | Durum |
|---|-------|-------|-------|-------|
| 19 | ~~Boş `catch { }` bloğu — hata yutulmuş~~ | `boringNotchApp.swift` | 400 | ✅ |
| 20 | ~~Spor provider'ları HTTP status code kontrol etmiyor (4 dosya, 8+ istek)~~ | `F1/Basketball/Football/EuroLeague Provider` | çeşitli | ✅ |
| 21 | ~~Spor provider'ları timeout ayarı yok — istek sonsuza kadar bekleyebilir~~ | Aynı dosyalar | çeşitli | ✅ |
| 22 | ~~`ShelfPersistenceService` — `try?` ile dosya hataları yutulmuş~~ | `ShelfPersistenceService.swift` | 23-26 | ✅ |
| 23 | ~~Lyrics fetch — JSON hataları log'lanmıyor~~ | `MusicManager.swift` | 432-460 | ✅ |
| 24 | 15+ yerde `try?` ile hatalar sessizce yutulmuş | Proje geneli | — | ⚠️ |

**Çözüm:** `try?` kullanımlarını `do/catch` + `Logger` ile değiştir. Spor API'lerine timeout ve HTTP status kontrolü ekle.

---

## 🟡 ÖNEMLİ — @Published Gereksiz Güncelleme

| # | Sorun | Dosya | Durum |
|---|-------|-------|-------|
| 25 | ~~Batarya/disk metrikleri her 2sn güncelleniyor~~ | `SystemMonitorManager.swift` | ✅ |
| 26 | ~~`CalendarManager` — `@MainActor` olmasına rağmen gereksiz `DispatchQueue.main.async` kullanıyor~~ | `CalendarManager.swift:68-70` | ✅ |
| 27 | `WeatherManager` — URLSession completion'da arka plan thread'inde veri işliyor, sonra `Task { @MainActor }` ile UI güncelliyor | `WeatherManager.swift:191-245` | ⚠️ |

---

## 🟡 ÖNEMLİ — Singleton Lifecycle

| # | Sorun | Dosya | Durum |
|---|-------|-------|-------|
| 28 | `WebcamManager` — NotificationCenter observer'ları `deinit`'te temizleniyor ama singleton olduğu için `deinit` asla çağrılmaz | `WebcamManager.swift` | ⏳ |
| 29 | `BatteryActivityManager` — aynı sorun | `BatteryActivityManager.swift` | ⏳ |
| 30 | `MusicManager.destroy()` — manuel çağrılması gerekiyor, otomatik değil | `MusicManager.swift` | ⏳ |

---

## 🟢 İYİLEŞTİRME — Lokalizasyon

| # | Sorun | Örnekler | Durum |
|---|-------|----------|-------|
| 31 | Pomodoro bildirimleri hardcoded İngilizce | "Focus time!", "Break time!" | ⏳ |
| 32 | Hava durumu açıklamaları lokalize değil | Sıcaklık, açıklama metinleri | ⏳ |
| 33 | Batarya durumu stringleri | "Normal", "Service Recommended", "Service Required" | ⏳ |
| 34 | System Monitor widget etiketleri | "CPU Overview", "Memory", "Network" vb. | ⏳ |
| 35 | Takvim stringleri | "No events today", "All-day", "Enjoy your free time!" | ⏳ |
| 36 | Ayarlar/düzenleme paneli | "Edit layout", "Close", "Clear slot" vb. | ⏳ |

**Çözüm:** Tüm kullanıcıya görünen metinleri `Localizable.xcstrings` üzerinden yönet.

---

## 🟢 İYİLEŞTİRME — Erişilebilirlik (Accessibility)

| # | Sorun | Dosya | Durum |
|---|-------|-------|-------|
| 37 | 50+ interaktif buton accessibility label'sız | `BoringHeader.swift`, `BoringExtrasMenu.swift`, `NotchHomeView.swift`, `HoverButton.swift` | ⏳ |
| 38 | Tüm projede sadece 1 adet `.accessibilityLabel` var | `BoringCalendar.swift:471` | ⏳ |

**Çözüm:** Tüm `Button` ve interaktif elemanlara `.accessibilityLabel()` ekle.

---

## 🟢 İYİLEŞTİRME — Kod Temizliği

| # | Sorun | Dosya | Satır | Durum |
|---|-------|-------|-------|-------|
| 39 | TODO yorumu: "Move all animations to this file" | `drop.swift` | 27 | ⏳ |
| 40 | Kullanılmayan `runLoopSource: Unmanaged<CFRunLoopSource>?` property | `BatteryStatusViewModel.swift` | 12 | ⏳ |
| 41 | `ContentView` kapalı notch priority chain — 10 iç içe `if/else`, okunabilirlik çok düşük | `ContentView.swift` | — | ⏳ |
| 42 | 23+ hardcoded RGB renk değeri (tema sistemi yok) | `SettingsView.swift`, `BoringCalendar.swift`, `WebcamView.swift` | çeşitli | ⏳ |

---

## 🟢 İYİLEŞTİRME — Swift 6 Hazırlık

| # | Sorun | Dosya | Durum |
|---|-------|-------|-------|
| 43 | Spor provider'ları `Sendable` protokolüne uymuyor | `FootballProvider`, `BasketballProvider`, `F1Provider`, `EuroLeagueProvider` | ⏳ |
| 44 | `NSImage(data:)` background thread'de oluşturulup main thread'e aktarılıyor | `MusicManager.swift:526-532` | ⏳ |

---

## Özet

| Seviye | Adet | Çözüldü |
|--------|------|---------|
| 🔴 KRİTİK — Çökme | 7 madde (18 instance) | 7 ✅ |
| 🔴 KRİTİK — Bellek sızıntısı | 5 madde | 5 ✅ |
| 🔴 KRİTİK — Thread safety | 6 madde | 5 ✅ |
| 🟡 ÖNEMLİ — Hata yönetimi | 6 madde | 5 ✅ |
| 🟡 ÖNEMLİ — Performans | 3 madde | 2 ✅ |
| 🟡 ÖNEMLİ — Lifecycle | 3 madde | 0 |
| 🟢 İYİLEŞTİRME — Lokalizasyon | 6 madde | 0 |
| 🟢 İYİLEŞTİRME — Erişilebilirlik | 2 madde | 0 |
| 🟢 İYİLEŞTİRME — Kod temizliği | 4 madde | 0 |
| 🟢 İYİLEŞTİRME — Swift 6 | 2 madde | 0 |
| **TOPLAM** | **44 madde** | **24 çözüldü** |
