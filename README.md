# Spam Shield

Tanımadığın göndericilerden gelen spam SMS'leri iPhone'da filtreleyen ücretsiz iOS uygulaması.
Mesajlar cihazdan çıkmaz; kural listesi açık ve GitHub'dan güncellenir.

- Bahis, kredi ve dolandırıcılık mesajlarını **Gereksiz**'e, kampanyaları **Promosyonlar**'a, kodları ve kargo
  bildirimlerini **İşlemler**'e ayırır.
- Kaçan spami Mesajlar'da **Paylaş › Spam Shield** ile bildirip ondan kural oluşturabilirsin.
- Hazır kurallar uygulama güncellemesi beklemeden indirilir; senin kuralların ve değişikliklerin korunur.
- Türkçe ve İngilizce.

## Kurulum

1. [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile projeyi oluştur ve `SpamShield.xcodeproj`'yi aç:

   ```bash
   xcodegen generate
   ```

2. `SpamShield`, `MessageFilter` ve `ShareExtension` hedeflerinde **Signing & Capabilities › Team** olarak kendi takımını seç.
3. iPhone'u bağla ve **Run** (⌘R). İlk seferde iPhone'da geliştiriciye güven
   (**Ayarlar › Genel › VPN ve Aygıt Yönetimi**) ve **Geliştirici Modu**'nu aç.
4. **Ayarlar › Uygulamalar › Mesajlar › Bilinmeyen ve Spam › SMS Filtreleme** altında **Spam Shield**'ı seç.

Bundle ID başkasına aitse `project.yml` içindeki `com.emirchngr` ve `RuleStore.appGroupIdentifier` değerini değiştir.
Ücretsiz Apple ID ile yüklenen uygulama 7 gün sonra yeniden yüklenmelidir.

> iOS, rehberdeki kişilerden, daha önce cevap yazdığın numaralardan ve iMessage'dan gelen mesajları filtreye göndermez.
> Denemek için seninle hiç yazışmamış birinden SMS iste.

## Kural listesini güncelleme

1. [`rules.json`](FilterCore/Sources/FilterCore/Resources/rules.json) dosyasını düzenle ve `"version"` değerini bir artır.
2. `cd FilterCore && swift test` ile dene, `main`'e push'la.

GitHub Actions testler geçerse listeyi <https://cihangiremir.github.io/spam-shield/rules.json> adresinde yayınlar.
Uygulama listeyi en fazla 2 günde bir kendiliğinden ya da **Şimdi güncelle** ile kontrol eder. Bozuk regex içeren veya
[normal mesaj örneklerinden](FilterCore/Sources/FilterCore/Resources/legitimate-samples.json) birini Gereksiz'e atan liste
reddedilir. Liste imzalanmadığı için bu repoya yazabilen biri kural ekleyebilir.

```json
{
  "version": 2,
  "fragments": { "suspiciousTLDs": "xyz|top|icu" },
  "rules": [
    {
      "id": "suspicious-tld",
      "name": "Şüpheli alan adı uzantıları",
      "category": "links",
      "details": "Kurallar ekranında görünen açıklama.",
      "translations": { "en": { "name": "Suspicious domain endings", "details": "English explanation." } },
      "matchType": "regex",
      "pattern": "\\.({{suspiciousTLDs}})\\b",
      "action": "junk"
    }
  ]
}
```

| Alan | Değerler |
|---|---|
| `id` | Kalıcı kimlik; kullanıcının açık/kapalı tercihi buna bağlı, değiştirme. |
| `category` | `scam`, `ads`, `links`, `sorting`, `strict` |
| `matchType` | `contains`, `prefix`, `regex` (regex küçük harfli, Türkçe karaktersiz metne uygulanır) |
| `action` | `allow`, `junk`, `promotion`, `transaction` |
| İsteğe bağlı | `target` (`body` / `sender`), `isEnabled`, `translations`, `note` |

JSON'da regex'teki `\` iki kez yazılır. `{{ad}}`, `fragments` içindeki aynı adlı parçayla değiştirilir.

## Geliştirme

| Klasör | İçerik |
|---|---|
| `FilterCore/` | Kural motoru ve hazır kurallar (Swift paketi) |
| `MessageFilter/` | iOS'un bilinmeyen SMS'lerde çağırdığı filtre eklentisi |
| `ShareExtension/` | Paylaş menüsünden kural öneren eklenti |
| `App/` | SwiftUI uygulaması |

```bash
cd FilterCore && swift test
```

Arayüz çevirileri `App/Localizable.xcstrings` içinde; yeni bir metnin hem `en` hem `tr` karşılığını doldur.

## Lisans

[MIT](LICENSE)
