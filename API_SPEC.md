# Specyfikacja HTTP API - Beyond All Reason Widget

Serwer HTTP wbudowany w widget BAR (Recoil) nasłuchuje lokalnie na porcie **`8540`** (`http://127.0.0.1:8540/`). Wszystkie odpowiedzi są zwracane w formacie **JSON** z nagłówkiem `Access-Control-Allow-Origin: *` (obsługa zapytań CORS z dowolnej witryny/aplikacji).

---

## Struktura Zwracanego Obiektu JSON

Poniżej znajduje się opis wszystkich pól głównych zawartych w odpowiedzi serwera:

### 1. `game` (Stan Gry)
Podstawowe dane o tempie rozgrywki i mapie.
* `frame` (liczba) - Aktualna klatka gry (30 klatek = 1 sekunda czasu gry).
* `seconds` (liczba) - Czas trwania meczu w sekundach.
* `speed` (liczba) - Prędkość gry (np. `1` to standardowa prędkość, `0` oznacza pauzę).
* `paused` (bool) - Czy gra jest aktualnie wstrzymana.
* `mapName` (string) - Pełna nazwa aktualnej mapy (np. `"Baryon Tar Lake v1.1"`).
* `modName` (string) - Dokładna wersja modyfikacji gry BAR.

### 2. `localPlayer` (Dane Lokalnego Gracza)
Identyfikatory gracza, który uruchomił widget.
* `playerId` (liczba) - Twoje ID gracza w silniku.
* `teamId` (liczba) - Twoje ID drużyny (kontroluje jednostki).
* `allyTeamId` (liczba) - Twoje ID sojuszu (współdzielona widoczność/drużyny).

### 3. `resources` (Ekonomia Twojej Drużyny)
Aktualny stan zasobów metalu i energii dla Twojego `teamId`.
* `metal` / `energy` (obiekty) zawierające pola:
  * `storage` (liczba) - Aktualna ilość zgromadzonego surowca.
  * `capacity` (liczba) - Maksymalna pojemność magazynów.
  * `excess` (liczba) - Nadwyżka surowca marnowana z powodu braku magazynów.
  * `income` (liczba) - Przychód surowca na sekundę.
  * `expense` (liczba) - Zużycie surowca na sekundę.
  * `pull` (liczba) - Zapotrzebowanie Twoich fabryk/budowniczych na surowiec.

### 4. `environment` (Środowisko Mapy)
* `wind` (obiekt) - Aktualne warunki wiatrowe (kluczowe dla elektrowni wiatrowych):
  * `min` (liczba) - Minimalna siła wiatru na mapie.
  * `max` (liczba) - Maksymalna siła wiatru na mapie.
  * `current` (liczba) - Aktualna siła wiatru.
* `mapSize` (obiekt) - Rozmiar mapy w jednostkach silnika:
  * `x` (liczba) - Szerokość mapy.
  * `z` (liczba) - Długość mapy.

### 5. `players` (Słownik Graczy)
Lista wszystkich graczy uczestniczących w rozgrywce. Kluczem jest ID gracza jako string.
* `name` (string) - Nick gracza.
* `active` (bool) - Czy gracz jest połączony.
* `spectator` (bool) - Czy gracz jest widzem (spectator).
* `teamId` (liczba) - ID drużyny gracza.
* `allyTeamId` (liczba) - ID sojuszu gracza.
* `ping` (liczba) - Ping gracza w milisekundach.
* `cpu` (liczba) - Obciążenie CPU przez gracza (ułamek sekundy na klatkę).

### 6. `teams` (Słownik Drużyn)
Lista drużyn w grze (sterowanych przez graczy lub AI). Kluczem jest ID drużyny jako string.
* `color` (tabela `[r, g, b, a]`) - Kolor drużyny na mapie (wartości od `0` do `1`).
* `leader` (liczba) - ID gracza będącego liderem drużyny.
* `active` (bool) - Czy drużyna jest aktywna w grze.
* `spectator` (bool) - Czy to jest drużyna widzów.
* `share` (liczba) - Udział w ekonomii.
* `handicap` (liczba) - Modyfikator handicapu (osłabienie/wzmocnienie).
* `resources` (obiekt) - Poziomy metalu i energii drużyny (jeśli są dla Ciebie widoczne).

### 7. `units` (Lista Własnych Jednostek - Zoptymalizowana)
Tablica obiektów reprezentujących wyłącznie wybudowane jednostki należące do Twojej drużyny (`teamId` lokalnego gracza). Dane wrogich i sojuszniczych jednostek są odrzucane na poziomie silnika gry w celu zminimalizowania obciążenia CPU oraz redukcji narzutu Garbage Collectora na parser JSON.
* `unitId` (liczba) - Unikalny identyfikator jednostki w danej sesji.
* `defName` (string) - Nazwa techniczna typu jednostki (np. `"corvp"`, `"armcom"`).
* `humanName` (string) - Nazwa jednostki wyświetlana w UI.
* `position` (obiekt `{x, y, z}`) - Współrzędne 3D jednostki na mapie.
* `health` (liczba) - Aktualne punkty życia (HP).
* `maxHealth` (liczba) - Maksymalne punkty życia (HP).
* `team` (liczba) - ID drużyny (zawsze równe ID lokalnego gracza).
* `command` (string) - Pierwszy rozkaz z kolejki zadań jednostki (np. `"Move"`, `"Attack"`, `"Build"`, lub `"Idle"`).
* `metalCost` (liczba) - Koszt metalu jednostki (od v1.1.2).
* `buildSpeed` (liczba) - Prędkość budowy jednostki (od v1.1.2).

### 8. `selectedUnits` (Lista Zaznaczonych Jednostek)
Tablica zawierająca same liczby będące ID jednostek (`unitId`), które aktualnie zaznaczyłeś myszką w grze.

### 9. `console` (Logi Konsoli i Czatu)
Tablica ostatnich 50 wpisów z konsoli gry. Przydatna do wyciągania wiadomości z czatu na żywo.
* `text` (string) - Treść komunikatu/wiadomości czatu.
* `level` (liczba) - Poziom ważności logu w silniku Spring.
* `time` (liczba) - Sekunda gry, w której pojawił się wpis.
