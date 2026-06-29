# Beyond All Reason (BAR) HTTP API Server Widget

Ten projekt zawiera prosty serwer HTTP wbudowany w widget Lua do gry **Beyond All Reason (BAR)**. Serwer nasłuchuje lokalnie na porcie `8540` i zwraca szczegółowe dane o stanie gry, zaznaczonych jednostkach oraz surowcach w formacie JSON.

## Zawartość Projektu

1. [gui_http_server_v2.lua](file:///C:/Users/dariu/agy/bor/gui_http_server_v2.lua) - Główny widget LuaUI, który należy umieścić w folderze widgetów gry.
2. [socket.lua](file:///C:/Users/dariu/agy/bor/socket.lua) - Poprawiona, bezpieczna dla piaskownicy wersja pliku pomocniczego LuaSocket.

---

## Co trzeba było zrobić, aby to zadziałało? (Krok po kroku)

### Krok 1: Włączenie obsługi gniazd sieciowych (Sockets) w silniku gry
Silnik Recoil/Spring domyślnie blokuje obsługę sieci w widgetach ze względów bezpieczeństwa. 
W pliku konfiguracyjnym gry:
`%localappdata%\Programs\Beyond-All-Reason\data\springsettings.cfg`
dodano wpis:
```ini
LuaSocketEnabled = 1
```

### Krok 2: Naprawienie błędu silnika w `socket.lua`
Wbudowany w silnik gry plik `socket.lua` (odpowiedzialny za moduł LuaSocket) wysypywał się na starcie gry z błędem `attempt to index global '_G' (a nil value)`. Piaskownica silnika gry całkowicie blokuje dostęp do globalnej tabeli `_G` (zwraca `nil`).
* **Rozwiązanie:** Stworzono poprawioną wersję pliku `socket.lua`, która nie używa `_G`, lecz bezpiecznego lokalnego słownika z wymaganymi funkcjami systemowymi Lua (`type`, `error`, `tostring` itp.).
* Plik ten został umieszczony w głównej ścieżce zapisu danych gry `%localappdata%\Programs\Beyond-All-Reason\data\socket.lua`, aby nadpisać wersję spakowaną w archiwum silnika.

### Krok 3: Rozwiązanie problemu przesłaniania zmiennych w widgecie
W pliku widgetu wywołanie `local socket = socket` na samym początku pliku (w fazie kompilacji pliku) powodowało przypisanie wartości `nil`, ponieważ silnik wstrzykuje globalne zmienne środowiskowe dopiero tuż przed wywołaniem `widget:Initialize()`. Dodatkowo zmienna lokalna `local socket` przesłaniała zmienną globalną.
* **Rozwiązanie:** Odwoływanie się do biblioteki socket zostało przeniesione do wewnątrz funkcji `widget:Initialize()`, a sam obiekt jest pobierany za pomocą `getfenv(1).socket` lub `getfenv(1).Socket`, co omija problem przesłaniania zmiennych.

### Krok 4: Wymuszenie włączenia widgetu w konfiguracji profilu
Silnik gry po wykryciu błędu podczas pierwszego ładowania widgetu automatycznie wyłącza go i zapisuje jego stan jako `0` (wyłączony) w konfiguracji profilu użytkownika:
`%localappdata%\Programs\Beyond-All-Reason\data\LuaUI\Config\BYAR.lua`
* **Rozwiązanie:** Wartości zamówienia (order) dla widgetu zostały zmodyfikowane w pliku konfiguracyjnym:
  ```lua
  ["HTTP API Server v2"] = 200,
  ```
  Aby zapobiec nadpisaniu pliku przez grający silnik z pamięci RAM podczas przeładowania, plik `BYAR.lua` został tymczasowo ustawiony jako **Tylko do odczytu (Read-Only)** przed wykonaniem `/luaui reload`, a po pomyślnym załadowaniu przywrócono mu pełne uprawnienia zapisu.

---

## Jak zainstalować ponownie na innym komputerze?

1. Skopiuj plik `gui_http_server_v2.lua` do:
   `%localappdata%\Programs\Beyond-All-Reason\data\LuaUI\Widgets\`
2. Skopiuj plik `socket.lua` do:
   `%localappdata%\Programs\Beyond-All-Reason\data\`
3. Otwórz `%localappdata%\Programs\Beyond-All-Reason\data\springsettings.cfg` i dodaj:
   `LuaSocketEnabled = 1`
4. Uruchom grę, naciśnij **F11**, znajdź widget **HTTP API Server v2** i upewnij się, że jest włączony (zielony).

---

## Historia Optymalizacji i Zmian (Wydanie v1.2.1)

W celu wyeliminowania mikro-przycięć (stuttering) gry w trybie wieloosobowym wdrożono następujące usprawnienia:
* **UnitDef Cache (Buforowanie definicji):** Statyczne atrybuty jednostek (np. koszty, kategorie, tiery, dopasowania nazw) są obliczane tylko raz przy napotkaniu typu jednostki i buforowane. Zapobiega to ciągłemu narzutowi procesora na dopasowywanie stringów i przeszukiwanie tabel silnika gry.
* **Socket Polling Throttling (Ograniczenie częstotliwości sieci):** Nasłuchiwanie gniazda TCP (`socket.select`) zostało ograniczone do co 8 klatki gry (zamiast w każdej klatce), co oszczędza do 85% czasu procesora traconego na bezczynne odpytywanie sieci w wątku gry.
* **Early Filtering (Wczesne filtrowanie):** Szczegółowe dane (pozycja, komendy, zdrowie) są serializowane wyłącznie dla jednostek gracza lokalnego. Dla wrogów i sojuszników pobierany jest tylko koszt metalu, co redukuje rozmiar JSON-a z 1MB do 3-5KB.
