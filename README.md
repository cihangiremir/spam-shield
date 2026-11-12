# Spam Shield

Tanımadığın göndericilerden gelen spam SMS'leri iPhone'da filtreleyen ücretsiz iOS uygulaması.
Mesajlar cihazdan çıkmaz; kural listesi açık ve GitHub'dan güncellenir.

- Bahis, kredi ve dolandırıcılık mesajlarını **Gereksiz**'e, kampanyaları **Promosyonlar**'a; kodları, kargo,
  kart, fatura, randevu ve ödeme bildirimlerini **İşlemler**'e ayırır.
- Kaçan spami Mesajlar'da **Paylaş › Spam Shield** ile bildirip ondan kural oluşturabilirsin.
- Hazır kurallar uygulama güncellemesi beklemeden indirilir; senin kuralların ve değişikliklerin korunur.
- İstersen açabileceğin **öğrenen filtre**, hiçbir kuralın yakalamadığı mesajlardan spam ve kampanyaları Promosyonlar'a,
  bildirimleri İşlemler'e taşır; emin olmadığında gelen kutusunda bırakır.
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

## Öğrenen filtre

`FilterCore/Sources/FilterCore/SpamClassifier.swift` dört sınıflı bir naive Bayes sınıflandırıcı. Sadece hiçbir kural
eşleşmediğinde sorulur. Spam ya da kampanya derse mesaj Gereksiz'e değil Promosyonlar'a, bildirim derse İşlemler'e gider.
Bir mesajı ancak kişisel olmadığından açıkça eminse taşır, bildirim olabilecek bir mesajı Promosyonlar'a atmaz
(`hidingMargin`, `promotionMargin`). Varsayılan olarak açık; Kurallar sekmesinden kapatılabilir, Kontrol et sekmesinden
"Spam" / "Kampanya" / "Bildirim" / "Kişisel" diye öğretilir. Telefonda öğretilen mesajların kendisi değil, kelimeleri ve
sayıları saklanır. Eski sürümde "Spam değil" diye öğretilenler kişisel sayılır.

Hazır model (`Resources/classifier.json`) yalnızca kelime sayılarını içerir; 3'ten az mesajda geçen kelimeler atılır,
linklerin içindeki kelimeler ("https", "www", "com") sayılmaz. `FilterCore/TrainingData` içindeki iki dosyadan üretilir:
gerçek mesajlar `messages.json`'da, üretilmiş (sentetik) mesajlar `synthetic.json`'da. Her mesajın `label` alanı
telefonda gitmesi gereken yeri söyler: `junk` (spam), `promotion` (kampanya), `transaction` (kod, kargo, kart, fatura,
randevu, ödeme bildirimi) veya `personal` (gelen kutusu; kurumların "şu mesajlara itibar etmeyin" ve güvenlik uyarıları da).

`split` alanı mesajın eğitim (`train`, %80), doğrulama (`validation`, %10) ya da test (`test`, %10) için olduğunu
söyler. Model `train` ile eğitilir, eşikler `validation`'a bakılarak seçilir, `test` yalnızca sonucu raporlamak için
kullanılır; uygulamaya giden model sonra tüm mesajlarla eğitilir. Bölme rastgele satır bazında değil: rakamlar ve linkler
dışında büyük ölçüde aynı olan aynı etiketli mesajlar hep aynı bölümde durur, bir mesajın küçük değişiklikli kopyası hem
eğitimde hem testte olmasın diye. Yeni mesaj ekledikten sonra `python3 scripts/split_training_data.py` çalıştır: yeni
mesajlara bölüm verir, eskilerinkini değiştirmez. Başarı gerçek mesajlarda ayrıca ölçülür; sentetik mesajlardaki sonuç
ayrı raporlanır (`TrainingDataTests` de ikisini ayrı denetler).

`source` mesajın nereden geldiğini söyler:

- `mac-junk`: Gereksiz klasörüne düşmüş Türkçe spam SMS'ler, geliş sırasıyla.
- `ds-commercial`, `ds-betting`, `ds-spam`, `ds-personal`: [Turkish SMS Collection](https://www.kaggle.com/datasets/onurkarasoy/turkish-sms-collection)
  (Karasoy ve Ballı, 2021) ve [turkishSMS-ds](https://huggingface.co/datasets/akuysal/turkishSMS-ds) (Uysal ve diğerleri, 2013).
  Bu setlerdeki "spam" mesajların çoğu bilinen markaların kampanyaları olduğu için `promotion` sayıldı (`ds-commercial`);
  kaçak bahis ve benzeri ilanlar spam sayıldı (`ds-betting`). Cinsel ürün ilanları, "kazandınız, hemen arayın"
  ödülleri, tanışma siteleri, kredi/borç aracıları, 11899 sorgu hatları ve üçüncü taraf ücretli içerik abonelikleri
  (burç, iddaa tahmini, itiraf...) de spam sayıldı (`ds-spam`); operatörlerin kendi paketleri kampanya olarak kaldı.
  Setlerin "normal" mesajları (`ds-personal`) arasındaki banka, operatör, kargo ve havayolu bildirimleri `transaction`,
  oraya karışmış kampanyalar `promotion` olarak etiketlendi. Aynı kaynakta rakamlar dışında aynı olan mesajların
  yalnızca biri tutulur.
- `legit-samples`: `Resources/legitimate-samples.json`.
- `synthetic-claude-*`, `synthetic-kimi-*` (`synthetic.json`): Claude ve Kimi ile üretilmiş 4.000'er Türkçe/İngilizce
  mesaj, her sınıftan eşit sayıda; kaynak adı dili ve etiketi de söyler (`synthetic-kimi-en-junk`). İçe alırken:
  küçük/büyük harf dışında aynı olan mesajlar atıldı; Kimi'nin bazı spam mesajlarına eklediği "ONAY KODU:" öneki
  (gerçek onay kodlarını spam'e benzetmesin diye) silindi; kuralların İşlemler'e ayırdığı `personal` etiketli 145 mesaj
  (tek kullanımlık kodlar, randevu hatırlatmaları) bu projenin etiketlerine uysun diye `transaction` yapıldı; linkler
  silindi, çünkü bu setlerde link neredeyse yalnızca spam mesajlarında var ve model "link varsa spam" diye öğreniyordu.
  Sentetik mesajlar daha düzgün ve birbirine benzer olduğu için gerçek dünyadaki başarıyı göstermez.

Kişisel veriler çıkarıldı: 7 haneden uzun sayılar sıfırlandı, e-posta adreslerinin kullanıcı adı, hitaptan sonraki
adlar, şifreler ve kısa linklerdeki kişiye özel kodlar değiştirildi.

Modeli yeniden üretmek, doğrulama mesajlarında farklı eşikleri ve test mesajlarındaki başarısını görmek için:

```bash
cd FilterCore && swift run TrainClassifier
```

## Lisans

[MIT](LICENSE)
