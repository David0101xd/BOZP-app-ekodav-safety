# Nastavení GitHub Pages – Flutter Web Deploy

Aplikace je nyní nastavená pro automatický build a deploy na **GitHub Pages** pomocí GitHub Actions.

## Postup aktivace (jedním klikem)

### 1. Aktivuj GitHub Pages v repo settings

1. Jdi na **Settings > Pages** (v GitHubu repo)
2. Pod **"Build and deployment"** vyber:
   - **Source**: `GitHub Actions`
3. Ulož

### 2. Spusť workflow

Workflow se automaticky spustí na každý `push` do `main` nebo `claude/**` branchí.

Pokud chceš spustit hned (bez pushování):
1. Jdi na **Actions** v repo
2. Vyber **"Deploy Flutter Web to GitHub Pages"**
3. Klikni na **"Run workflow"**

### 3. Ověř deploy

Po ~2-3 minutách aplikace běží na:

🌐 **https://David0101xd.github.io/BOZP-app-ekodav-safety/**

## Co workflow dělá

1. Checkout code
2. Setup Flutter SDK (`stable`)
3. `flutter pub get` – stáhne dependencies
4. `flutter build web --release` – builduje web app do `build/web/`
5. Deploy `build/web/` na GitHub Pages

## Troubleshooting

### Workflow selhat – "Flutter not found"
- GitHub Actions by měly automaticky stáhnout Flutter SDK
- Zkontroluj **Actions > workflow run** → **Details** → **Logs**

### Pages ukazuje starou verzi
- GitHub Pages cache: Ctrl+Shift+Del v prohlížeči (hard refresh)
- Nebo čekej 5 minut na CDN invalidaci

### CORS chyba při ARES API

Pokud Flutter Web vyhledávání v ARES vrací CORS error:
- **Důvod**: ARES API blokuje cross-origin requesty z webu
- **Řešení**: Potřebná CORS proxy (např. `https://cors-anywhere.herokuapp.com/` jako relay)

```dart
// Příklad řešení v kódu:
final Uri proxyUrl = Uri.parse(
  'https://cors-anywhere.herokuapp.com/https://ares.gov.cz/ekonomicke-subjekty-v-be/rest/ekonomicke-subjekty/$cleanIco'
);
```

Případně nastavit vlastní backend proxy.

## Poznámky k Web verzí

- **SharedPreferences** → localStorage (funguje bez problémů)
- **GPS (Geolocator)** → Web LocationAPI (funguje na HTTPS + s user permission)
- **Tisk PDF** → Web print dialog (ale ne přímý download PDF)
- **Foto (ImagePicker)** → Web file input (funguje)

## Automatizace

Workflow se spouští automaticky na:
- `push` do `main`
- `push` do kterékoliv `claude/**` branche

Pokud chceš změnit trigger, uprav `.github/workflows/deploy-web.yml`:

```yaml
on:
  push:
    branches: ['main']  # Jenom main
  schedule:
    - cron: '0 9 * * *'  # Každý den v 9:00 UTC
```
