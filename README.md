# Beyond All Reason (BAR) HTTP API Server & HUD Analytics Dashboard

Ten projekt pozwala na wyświetlanie pięknych statystyk i analityki w czasie rzeczywistym z Twojej rozgrywki w grze **Beyond All Reason (BAR)**. Dane są pobierane bezpośrednio z silnika gry za pomocą wbudowanego serwera HTTP w Lua, a następnie serwowane i wizualizowane na nowoczesnym panelu HUD napisanym we Flasku i HTML5 (z użyciem biblioteki Chart.js).

---

## Jak to działa?

Projekt składa się z dwóch głównych komponentów współpracujących ze sobą:
1. **Lua HTTP API Server Widget (`gui_http_server_v2.lua`)**:
   - Działa bezpośrednio w silniku gry BAR.
   - Uruchamia lokalne gniazdo sieciowe (socket) i nasłuchuje na porcie `8540` w formacie JSON.
   - Zwraca surowe dane o gospodarce, strukturze jednostek gracza oraz statystykach sojuszników.
2. **Serwer Flask (`app.py` & `templates/index.html`)**:
   - Uruchamia lokalną aplikację webową na porcie `5000`.
   - Odpytuje serwer w grze (proxy na porcie `8540`) i przesyła dane do przeglądarki, zapobiegając problemom z CORS.
   - Renderuje interaktywny interfejs w stylu Sci-Fi HUD z wykresami metalu, energii, wiatru, drzewem jednostek i konsolą logów.

---

## Wymagania wstępne

Aby uruchomić aplikację Flask, musisz mieć zainstalowany **Python 3**.

---

## Instrukcja Uruchomienia Krok po Kroku

### Krok 1: Instalacja i konfiguracja widgetu w grze BAR
Jeśli konfiguracja gry nie została jeszcze przeprowadzona na tym komputerze:

1. Skopiuj plik [gui_http_server_v2.lua](file:///C:/Users/dariu/agy/agy-bar/gui_http_server_v2.lua) do folderu widgetów gry BAR:
   `%localappdata%\Programs\Beyond-All-Reason\data\LuaUI\Widgets\`
2. Skopiuj plik [socket.lua](file:///C:/Users/dariu/agy/agy-bar/socket.lua) do głównego folderu danych gry BAR (aby naprawić domyślny błąd silnika Recoil):
   `%localappdata%\Programs\Beyond-All-Reason\data\`
3. Otwórz plik `%localappdata%\Programs\Beyond-All-Reason\data\springsettings.cfg` i dodaj/zmień linię:
   ```ini
   LuaSocketEnabled = 1
   ```
4. Uruchom grę, naciśnij **F11**, znajdź widget **HTTP API Server v2** i upewnij się, że jest włączony (oznaczony na zielono).

### Krok 2: Aktywacja środowiska wirtualnego i instalacja zależności
Projekt wykorzystuje środowisko wirtualne `.venv` znajdujące się w głównym katalogu. Przed uruchomieniem serwera musisz je aktywować i zainstalować wymagane zależności.

1. **Aktywuj środowisko wirtualne** w zależności od Twojego systemu i powłoki (terminala):
   - **Windows (PowerShell - zalecane)**:
     ```powershell
     .\.venv\Scripts\activate
     ```
     *(Jeśli napotkasz błąd bezpieczeństwa skryptów, uruchom najpierw: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process`)*
   - **Windows (Klasyczny Wiersz Poleceń - CMD)**:
     ```cmd
     .venv\Scripts\activate.bat
     ```
   - **Linux / macOS (Bash/Zsh)**:
     ```bash
     source .venv/bin/activate
     ```

2. **Zainstaluj wymagane biblioteki** wewnątrz aktywnego środowiska:
   ```bash
   pip install Flask requests
   ```

### Krok 3: Uruchomienie serwera Flask
Po pomyślnej aktywacji środowiska wirtualnego (nazwa powłoki w terminalu będzie poprzedzona tagiem `(.venv)`), uruchom serwer Flask:
```powershell
python app.py
```
Serwer uruchomi się lokalnie pod adresem:
`* Running on http://127.0.0.1:5000`


### Krok 4: Wyświetlenie pięknych statystyk
1. Otwórz przeglądarkę internetową i przejdź pod adres:
   [http://127.0.0.1:5000/](http://127.0.0.1:5000/)
2. Uruchom grę Beyond All Reason i wejdź do dowolnego meczu (np. potyczka z botami lub gra multiplayer).
3. Panel automatycznie połączy się z grą i zacznie w czasie rzeczywistym rysować wykresy oraz aktualizować sekcje:
   - **METAL_SYSTEM** & **ENERGY_SYSTEM** (wykresy przychodu vs wydatków)
   - **WIND_SYSTEM** (wykres aktualnej siły wiatru z naniesionymi liniami optymalności dla elektrowni wiatrowych)
   - **MY_UNIT_REGISTRY** (struktura Twoich jednostek z podziałem na Tiery i role)
   - **ALLY_TEAM_INTELLIGENCE** (porównanie zasobów i zagrożenia sojuszników)
   - **LOG_CONSOLE_FEED** (ostatnie logi bezpośrednio z silnika gry)

---

## Historia Optymalizacji i Szczegóły Techniczne (Wersja v1.2.4)

W celu wyeliminowania mikro-przycięć (stuttering) gry w trybie wieloosobowym oraz zapewnienia płynnego automatycznego uruchamiania wdrożono następujące usprawnienia w widgecie Lua:
* **Autostart & Pre-game Connection Handling (Obsługa pre-game):** Aby uniknąć specyficznych dla Windowsa problemów z współdzieleniem portów (`SO_REUSEADDR` port-sharing/stealing) na ekranie ładowania gry, inicjalizacja serwera i bindowanie gniazda TCP są opóźnione do czasu, aż lokalny gracz zostanie w pełni połączony i załadowany w meczu (`Spring.GetMyPlayerID() >= 0`). Dodatkowo zaimplementowano dedykowaną funkcję `json_escape()`, która bezpiecznie koduje znaki specjalne, backslashe ze ścieżek Windows oraz ukryte znaki kontrolne w logach konsoli, zapobiegając błędom parsowania JSON we Flasku (`JSONDecodeError: Invalid \escape`). Rozwiązuje to problem niedziałającego widgetu po starcie gry i eliminuje potrzebę ręcznego przeładowywania interfejsu komendą `/luaui reload`.
* **UnitDef Cache (Buforowanie definicji):** Statyczne atrybuty jednostek (np. koszty, kategorie, tiery, dopasowania nazw) są obliczane tylko raz przy napotkaniu typu jednostki i buforowane. Zapobiega to ciągłemu narzutowi procesora na dopasowywanie stringów i przeszukiwanie tabel silnika gry.
* **Socket Polling Throttling (Ograniczenie częstotliwości sieci):** Nasłuchiwanie gniazda TCP (`socket.select`) zostało ograniczone do co 8 klatki gry (zamiast w każdej klatce), co oszczędza do 85% czasu procesora traconego na bezczynne odpytywanie sieci w wątku gry.
* **Early Filtering (Wczesne filtrowanie):** Szczegółowe dane (pozycja, komendy, zdrowie) są serializowane wyłącznie dla jednostek gracza lokalnego. Dla wrogów i sojuszników pobierany jest tylko koszt metalu, co redukuje rozmiar JSON-a z 1MB do 3-5KB.

