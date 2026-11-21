# W-gdb-e0-capacity-request-02

Status: CAPACITY REQUEST ONLY. NO EXECUTION. New request, not a retry or GO for W-gdb-e0-qualification-01.

Route: same W- intake as W-gdb-e0-qualification-01. Please route to an existing free Linux lab that can enforce the controls below. No paid resources, installation, capacity reservation, public swarm, product source, owner data, private repository inputs or external endpoint access are requested. This packet contains generic capability questions only. No performance improvement or execution proof is claimed.

Return CAPABLE, DECLINE or BLOCKED in replies/W-gdb-e0-capacity-request-02.md or the existing lab response surface. If blocked, name the missing capability. CAPABLE is not acceptance and never permits execution. A complete exact new runnable packet with hashes, explicit lab ACCEPT and a separate integrator GO will be required before one attempt. No substitute run and no automatic retry. Do not execute the old qualification under this request.

The proposed future envelope is one small generic loopback capability qualification, not WT A/B. The 256MiB hard memory maximum applies to an isolated whole-job cgroup; the independent watchdog remains outside it. Polling RSS or limiting only V8 heap is not equivalent. If the controls cannot be enforced, return DECLINE/BLOCKED rather than proposing or running a weaker experiment.

Criteria source SHA256: 9ca5f2d846024e283d7a2af24a45d90db3d8e3e90f1ca0a7c9ccf9db252dd096. The full criteria follow unchanged. They are not executable fixture code.

---

# Ücretsiz lab yetkinlik soruları ve kabul kanıtı

Yeni teklif hazırlığı. Eski H0689 reddini veya önceki teklifi değiştirmez. Bu metin bir çalıştırma emri değildir. Önce yetkinlik yanıtı, sonra parent üzerinden ayrı ACCEPT ve GO gerekir.

## Lab'a sorulacaklar

1. Mevcut, ücretsiz Linux ve mevcut Node/Python ile kurulum yapmadan bir denemeye ayrılmış cgroup v2 oluşturup yönetebilir misiniz? Yeni ücret, subscription, Actions veya owner Mac kullanımı istenmiyor.
2. Ayrı iş cgroup'unda `memory.max=268435456` (256MiB), `memory.swap.max=0`, `memory.oom.group=1` ve düşük `pids.max` uygulayabiliyor musunuz? Ön değer önerisi16process; mevcut Node thread/process ihtiyacı buna uymuyorsa koşmadan bildirin. Sınırı yükseltmeyin.
3. İşin Python supervisor'ı ve başlatacağı bütün çocukları bu cgroup'a, fixture çalışmadan önce alabilir misiniz? Job dışında kalan bağımsız watchdog,15s duvar süresinde bütün job'ı durdurabilir ve boşaldığını doğrulayabilir mi?
4. İş kullanıcı alanındaki supervisor'ı ölse bile dış watchdog hayatta kalıyor mu? `cgroup.kill` yetkisi ve dosyası var mı? Yoksa eşdeğer bütün descendant'ları kapatma mekanizmanız nedir? Henüz kabul edilmiş bir alternatif yoktur.
5. Fixture'ın ağını OS düzeyinde yalnız loopback'e kısıtlayabilir misiniz? En temiz yol dış arayüz/default route olmayan ayrı network namespace. HTTP loopback testi için lo kullanılabilir olmalı. Namespace kullanılamıyorsa mekanizmayı açıklayın, eşdeğerliği ayrıca incelenecek. Yalnız kodun127.0.0.1'e bağlanması izolasyon kanıtı değildir.
6. Genel iş için15s hard wall, iç stop12s,2CPU-s sampled ceiling, child128MiB RSS / supervisor+child192MiB sampled stop,8MiB directional payload,64KiB captured stdout,128KiB toplam yeni çıktı, minimum16MiB free scratch sınırları sığıyor mu? Bir deneme, retry yok, paket/kütüphane kurulumu yok, disk payload dosyası yok.
7. Başlamadan mevcut Node/Python sürümleri, free scratch ve memory headroom'u bildirebilir misiniz? Ortamın başka işleri tehlikeye girecekse DECLINE.
8. Exact generic iki input dosyası için SHA256 readback ve koşu sonrası exit, elapsed, ölçüm ve cleanup makbuzu verebilir misiniz? Özel repo/ürün kodu/owner data/public swarm/dış endpoint istenmiyor.

## Kabul için kaynak kanıtı

Yetkinlik yanıtı ve açık ACCEPT tek başına koşu izni değildir. Parent önce kanıtı inceler, sonra ayrıca GO verir.

| Kontrol | Başlamadan kanıt | Koşu sonrası kanıt |
|---|---|---|
| Ayrı job alanı | cgroup v2 türü; o işe ayrılmış cgroup kimliği; parent controllers/delegation yetkisi | Aynı kimlikte counters ve child membership kaydı |
| Bellek | Doğrudan `memory.max`, `memory.swap.max`, `memory.oom.group` dosya readback değerleri; yok/denied ise BLOCKED | `memory.events` önce/sonra farkı; `memory.peak` varsa; job'daki tüm task'ların dahil olduğunun kanıtı |
| Process sınırı | `pids.max` doğrudan readback; Node'un mevcut thread ihtiyacı hakkında uyumluluk cevabı | `pids.events` farkı; beklenmeyen spawn yok |
| Timeout ve supervisor | İş dışındaki watchdog mekanizması,15s wall ayarı, yetkili bütün-job stop yolu | Gerçek elapsed, exit/signal, süre aşımı olursa STOP; bütün child'lar reap |
| Ağ | Namespace kimliği, yalnız lo arayüzü, route tablosunda dış route olmaması veya ayrıca kabul edilen eşdeğer mekanizma | Job aynı namespace'te çalışmış; dış bağlantı gözlenirse FAIL |
| Disk/çıktı | Scratch free ve sadece bu işe ayrılmış yeni yol | Oluşan dosya/byte listesi; output limit; mevcut kanıtlara dokunulmadı |
| Exact input | Dosyaların SHA256'sı parent'ın gönderdiği paketle eşit | Makbuzda aynı hash'ler ve gerçek komutun kimliği |
| Temizlik | İşe ait cgroup ve çocukları kapatma yetkisi; iş dışı dosyalar korunur | `cgroup.events populated=0` veya doğrulanmış eşdeğer; kalan task yok; evidence/receipt saklanır, silme yapılmaz |

## Yanlış kabul edilmeyecek cevaplar

- Sadece `--max-old-space-size` verilmiş: V8 heap sınırı, aggregate hard memory sınırı değil.
- Sadece ps/RSS polling ve kill: ölçümlü stop, hard cap değil.
- Bütün host'un mevcut büyük memory.max limiti: bu işe özel256MiB sınır değil.
- Sadece supervisor ayakta olduğunda çalışan timeout: bağımsız watchdog değil.
- Sadece kaynak kodunda loopback adresi: network isolation değil.
- Hiç çalıştırılmamış ayar komutları: readback değil.
- Üstünde ücret/kurulum/başka kullanıcının hesabı gereken öneri: mevcut kapsam dışında.

## Güvenli negatif kontroller

Allocation sweep/OOM basınç denemesi istenmiyor. İlkqualification mevcut küçük loopback ve sampled RSS/CPU/wall negatif kontrolleriyle kalır. Cgroup hard-limit enforcement mekanizması ayar/membership/readback kanıtıyla doğrulanır,256MiB'ye kadar bellek doldurarak denenmez. İş kendiliğinden OOM veya beklenmeyen dış bağlantı verirse durur ve FAIL döner, otomatik retry yok.

## Sonuç sözlüğü

- CAPABLE: teknik önkoşullar kanıtlandı, ancak çalıştırma hâlâ yetkisiz.
- ACCEPT: lab bu exact yeni paketi/limitleri kabul etti, parent GO'su yine gerekli.
- BLOCKED/DECLINE: eksik yetki/araç/kapasite; eksik madde açık yazılır, alternatif iş başlatılmaz.
- GO: yalnız parent'ın kaynak-grounded onayından sonra bir deneme.
- PASS: yalnız bu generic capability işi. Gerçek WT A/B, Linux transport doğruluğu, owner Mac ısısı veya film oynatımı hakkında sonuç değildir.
