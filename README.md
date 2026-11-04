# Spam Shield

Rehberinde kayıtlı olmayan göndericilerden gelen spam SMS'leri cihaz üzerinde filtreleyen iOS uygulaması.
Apple'ın Message Filter Extension'ını (IdentityLookup) kullanır; mesajlar hiçbir sunucuya gönderilmez.

## Yapı

| Klasör | İçerik |
|---|---|
| `FilterCore/` | Kural motoru (Swift paketi). Uygulama ve eklenti birlikte kullanır. |
| `FilterCore/Sources/FilterCore/Resources/rules.json` | Hazır kurallar. Uygulamaya gömülür ve GitHub Pages'te yayınlanır. |
| `MessageFilter/` | iOS'un her bilinmeyen SMS'te çağırdığı filtre eklentisi. |
| `ShareExtension/` | Mesajlar'da "Paylaş › Spam Shield" ile açılan, mesajdan kural öneren eklenti. Kontrol et formunu uygulamayla paylaşır. |
| `App/` | Uygulama (SwiftUI): Koruma, Kontrol et ve Kurallar sekmeleri, ilk açılış rehberi. |
| `project.yml` | Xcode projesinin tanımı (XcodeGen). |
| `.github/workflows/rules.yml`, `scripts/check_rules_version.py` | Her commit'te testler; `main`'de kural listesini yayınlar. |
| `scripts/make_app_icon.swift` | Uygulama ikonunu çizer: `swift scripts/make_app_icon.swift App/Assets.xcassets/AppIcon.appiconset/AppIcon.png` |

Uygulama ve Paylaş eklentisi kuralları App Group içindeki `rules.json` dosyasına yazar, filtre eklentisi oradan okur.
Uygulama ön plana her geldiğinde dosyayı yeniden okur, böylece Paylaş eklentisinin eklediği kuralların üzerine yazmaz.
Dosya yoksa veya okunamazsa eklenti varsayılan kurallarla çalışmaya devam eder.

## Kurulum

1. App Store'dan **Xcode**'u kur, bir kez açıp ek bileşenleri yüklemesine izin ver.
2. Xcode projesini oluştur (`.xcodeproj` dosyası git'e girmez, her seferinde buradan üretilir):

   ```bash
   xcodegen generate
   ```

3. `SpamShield.xcodeproj`'yi aç. **Settings › Accounts** kısmından Apple ID'ni ekle.
4. `SpamShield`, `MessageFilter` ve `ShareExtension` hedeflerinin hepsinde **Signing & Capabilities › Team** olarak kendi takımını seç.
5. Bundle ID'ler (`com.emirchngr.spamshield`) Apple'da başkası tarafından alınmışsa
   `project.yml` içindeki `com.emirchngr` kısımlarını ve
   `FilterCore/Sources/FilterCore/RuleStore.swift` içindeki `appGroupIdentifier` değerini değiştirip `xcodegen generate`'i tekrar çalıştır.
6. iPhone'u kabloyla bağla, hedef olarak seç ve **Run** (⌘R).
   İlk seferde iPhone'da **Ayarlar › Genel › VPN ve Aygıt Yönetimi** kısmından geliştiriciye güven,
   ayrıca **Ayarlar › Gizlilik ve Güvenlik › Geliştirici Modu**'nu aç.
7. iPhone'da **Ayarlar › Uygulamalar › Mesajlar › Bilinmeyen ve Spam › SMS Filtreleme** altında **Spam Shield**'ı seç.
   Uygulamanın ilk açılış rehberi de bu adımları gösterir. Rehberdeki "Mesajlar ayarlarını aç" butonu Apple'ın belgelemediği
   `App-prefs:com.apple.MobileSMS` adresini kullanır (herkese açık adres sadece uygulamanın kendi ayarlarını açıyor);
   iOS kabul etmezse uygulamanın ayar sayfasına düşer. App Store incelemesinde sorun çıkarabilir.

> iOS, rehberdeki kişilerin yanında daha önce cevap yazdığın numaralardan gelen mesajları da filtreye göndermez;
> numarayı rehberden silmek bunu değiştirmez. Test için seninle hiç yazışmamış birinden SMS (yeşil balon) iste.

> Ücretsiz Apple ID ile yüklenen uygulama 7 gün sonra açılmaz hale gelir; tekrar ⌘R ile yüklemen gerekir.
> Apple Developer Program (yıllık 99$) ile süre 1 yıla çıkar ve App Store / TestFlight yolu açılır.

## Kurallar

- **Eylemler:** İzin ver, Gereksiz, Promosyonlar, İşlemler. Birden fazla kural eşleşirse bu sırayla öncelik alır.
  Bir göndericiyi kurtarmak için "İzin ver" kuralı ekle.
- **Eşleşme:** İçerir, Şununla başlar (gönderici numaraları için) ve Regex.
- Metin karşılaştırmadan önce küçük harfe çevrilir, Türkçe karakterler ve Latin harfine benzeyen Kiril harfler
  sadeleştirilir (`ı→i`, `ş→s`, `а→a`...), görünmez karakterler silinir ve harf harf ayrılmış kelimeler birleştirilir
  (`B.A.H.İ.S` → `bahis`; en az 4 harf, böylece `A.Ş.`, `T.C.` gibi kısaltmalar etkilenmez).
  Regex desenlerini de bu yüzden küçük harfli ve Türkçe karaktersiz yaz.
- Hazır kurallar `FilterCore/Sources/FilterCore/Resources/rules.json` içinde (bkz. [Kural listesini güncelleme](#kural-listesini-güncelleme)).
  Yeni bir liste geldiğinde (GitHub'dan ya da uygulama güncellemesiyle) yeni hazır kurallar listeye eklenir,
  düzenlenmemiş olanlar en son hâline güncellenir (açık/kapalı durumu korunur), listeden çıkarılanlar silinir.
  Kullanıcının düzenlediği hazır kurallara ve kendi kurallarına dokunulmaz.
  Hazır kurallar silinemez, sadece kapatılabilir. "Varsayılanlara dön" listeyi tamamen sıfırlar.

### Spam bildirme

iOS, Mesajlar'daki "Gereksiz olarak bildir" bilgisini uygulamalarla paylaşmıyor
([raporlama eklentisi uygulamaya veri yazamıyor](https://developer.apple.com/forums/thread/802197)).
Bunun yerine Mesajlar'da spam mesaja uzun basıp **Paylaş › Spam Shield** denir (ya da mesaj kopyalanıp uygulamadaki
**Kontrol et** ekranına yapıştırılır). Mesajın nereye gideceği gösterilir, mesajdaki link alan adları, gönderici ve
seçilen bir ifade için kural önerilir, onaylananlar eklenir. Mesajlar paylaşırken göndericiyi vermez; istersen elle yazılır.
Paylaş menüsünde Spam Shield görünmüyorsa listenin sonundaki **Düzenle** ile eklenebilir.

### Ölçüm

Dolandırıcılık kuralları [Oltanom Turkish Phishing (Synthetic)](https://huggingface.co/datasets/Oltanom/turkish-phishing-synthetic)
veri setinin `train` bölümüne bakılarak yazıldı ve hiç bakılmamış `test` bölümünde ölçüldü
(şablonları train'den farklı, sadece SMS kanalı):

| | Dolandırıcılık yakalama (recall) | Normal mesajı Gereksiz'e atma |
|---|---:|---:|
| İlk kurallar | %17 (87 / 501) | 0 / 800 |
| \+ dolandırıcılık kuralları | %87 (435 / 501) | 0 / 800 |
| \+ kod paylaşma tuzağı | %97 (485 / 501) | 0 / 800 |
| \+ yanlış pozitif düzeltmeleri | %97 (484 / 501) | 0 / 800 |

Kod paylaşma kuralı, önceki ölçümde bu mesajların İşlemler klasörüne düştüğü görüldükten sonra eklendi.
Kural yalnızca `train` örneklerine bakılarak yazıldı, ama son iki satır artık tamamen kör bir ölçüm sayılmaz.

Veri setindeki normal mesajlar, gerçek banka ve kargo SMS'lerindeki bazı ifadeleri içermiyor.
Kod incelemesinde elle yazılan örnekler ("0850 211 1500'ü arayınız", "Takip: https://www.yurticikargo.com/...",
"Abi ben kuryeyim", "%10 Bonus!") Gereksiz'e düşüyordu; bunlar testlere eklendi ve kurallar daraltıldı.
Bilinçli takas: "Link ile bilgi isteyen" ve "Sahte kargo, ceza ve iade" kuralları artık `.tr` ile biten adresleri
(turkiye.gov.tr, garantibbva.com.tr) şüpheli saymıyor. Bu yüzden `turkcells.com.tr` gibi `.com.tr` taklitleri
bu kurallarla yakalanmıyor; `train` bölümünde yakalama %95,5'ten %93,2'ye indi.

Harf gizleme ("B.A.H.İ.S", Kiril harfler) ve `t.me` linkleri veri setinin SMS'lerinde hiç geçmediği için
bu ölçüme etkileri yok; testlerdeki elle yazılmış örneklerle doğrulandı. "Telegram linkleri" kuralı veri setinin
WhatsApp kanalındaki 90 `t.me` dolandırıcılık mesajını da yakalıyor (bu kanal yukarıdaki tabloya dahil değil).

Veri seti sentetik (şablonlardan üretilmiş) olduğu için bu sayılar gerçek SMS trafiğindeki başarıyı tam göstermez.
Reklam/bahis spamini de içermez; o kurallar bu ölçüme dahil değil.

## Kural listesini güncelleme

Hazır kurallar uygulama güncellemesi beklemeden GitHub'dan dağıtılır:

1. `FilterCore/Sources/FilterCore/Resources/rules.json` dosyasını düzenle.
2. Dosyanın başındaki `"version"` değerini bir artır. Uygulama yalnızca elindekinden yüksek sürümlü listeyi alır;
   sürümü artırılmamış bir değişikliği CI reddeder.
3. `cd FilterCore && swift test` ile dene, `main`'e commit'le ve push'la.

GitHub Actions (`.github/workflows/rules.yml`) testleri çalıştırır; geçerse dosyayı
<https://cihangiremir.github.io/spam-shield/rules.json> adresinde yayınlar. Testler geçmezse yayınlanan liste değişmez.
Uygulama listeyi her açılışta (en fazla 6 saatte bir), iOS izin verdikçe arka planda ve Koruma ekranındaki
**Şimdi güncelle** ile (Kurallar ekranında aşağı çekerek de) kontrol eder. İndirilen listeyi kullanmadan önce kendisi de
doğrular: okunamayan, derlenmeyen regex içeren veya gömülü normal mesaj örneklerinden
(`Resources/legitimate-samples.json`) birini Gereksiz'e atan liste reddedilir ve mevcut kurallarla devam edilir.
Uygulama güncellemesiyle gelen liste indirilenden yeniyse o kullanılır.

Dosya biçimi:

```json
{
  "version": 2,
  "fragments": { "suspiciousTLDs": "xyz|top|icu" },
  "rules": [
    {
      "id": "suspicious-tld",
      "name": "Şüpheli uzantılı linkler",
      "category": "links",
      "details": "Kurallar ekranında regex yerine görünen açıklama.",
      "note": "Bakımcı için not, uygulamada görünmez.",
      "matchType": "regex",
      "pattern": "\\.({{suspiciousTLDs}})\\b",
      "action": "junk"
    }
  ]
}
```

- `id` kuralın kalıcı kimliğidir; kullanıcının açık/kapalı tercihi buna bağlı, sonradan değiştirme.
- `category`: `scam`, `ads`, `links`, `sorting`, `strict` (bilinmeyen bir değer "Diğer korumalar" altında görünür).
- `matchType`: `contains`, `prefix`, `regex`. `action`: `allow`, `junk`, `promotion`, `transaction`.
  İsteğe bağlı alanlar: `target` (`body` ya da `sender`, varsayılan `body`), `isEnabled` (varsayılan `true`).
- JSON içinde regex'teki her `\` iki kez yazılır (`\\b`, `\\.`).
- `{{ad}}` yazılan yere `fragments` içindeki aynı adlı parça konur; parçalar başka parça kullanabilir.

Dosya imzalanmıyor: yayınlanan listeyi değiştirebilen biri (GitHub hesabına erişen) kural ekleyebilir.
Uygulamanın doğrulaması normal mesaj örneklerini korur ama bunu tamamen engellemez.

## Testler

Kural motoru Xcode olmadan da test edilebilir:

```bash
cd FilterCore && swift test
```

Sadece Command Line Tools kuruluyken ikinci çalıştırmada `TestingMacros ... not found` hatası alırsan
(SwiftPM'in makro eklentisini bulamaması), eklenti yolunu ver:

```bash
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
```

## Faz 2

Uygulama telefonda denendikten sonra ele alınacaklar:

- **Bildirimlerden öğrenen sınıflandırıcı:** Kontrol et ekranında biriken spam örnekleriyle cihazda eğitilen küçük bir model,
  hiçbir kurala uymayan mesajlar için yüksek eşikle karar versin.
- **Apple Foundation Models ile kural önerisi:** Uygulama içinde (filtre eklentisinde kullanılamıyor),
  Apple Intelligence destekli cihazlarda yapıştırılan mesajdan kural önerisi çıkarsın.

## Lisans

[MIT](LICENSE)
