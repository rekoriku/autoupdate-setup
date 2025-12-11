# README: Automaattiset Päivitykset (Unattended-Upgrades)

## 🇫🇮 Yleiskatsaus

Tämä skripti on kehitetty automaattisen päivitysjärjestelmän (`unattended-upgrades`) turvalliseen ja toistettavaan konfigurointiin Debian- ja Ubuntu-pohjaisissa järjestelmissä. Sen päätavoitteena on varmistaa, että järjestelmä pysyy ajan tasalla tietoturvapäivitysten ja haluttujen lisäpakettien osalta ilman manuaalista puuttumista.

## ⚙️ Vaatimukset

* **Käyttöjärjestelmä:** Debian tai Ubuntu (APT-pohjainen).
* **Komponentit:** `bash` (v4+), GNU Coreutils (`stat`, `readlink`, `mktemp`, `cmp`), `apt`, `visudo`.
* **Käyttöoikeudet:** Skripti on ajettava **root-käyttäjänä** (`sudo` on pakollinen), ellei erikseen aseteta testimuuttujaa `SKIP_ROOT_CHECK=true`.

## ✨ Toimintaperiaate

Skripti noudattaa tiukkaa, vaiheittaista prosessia, joka on **idempotentti** (eli sen voi ajaa uudelleen ilman haittavaikutuksia, jos kokoonpano ei muutu).

1. **Esitarkistukset:** Varmistaa, että skriptiä ajetaan root-käyttäjänä (ellei `SKIP_ROOT_CHECK=true` testikäyttöön), tarvittavat työkalut ovat asennettuina ja skriptin tiedostopolku on turvallinen (root-omistuksessa ja ilman kirjoitusoikeuksia muille).
2. **Syötteen validointi:** Tarkistaa ympäristömuuttujat (esim. `REBOOT_TIME`).
3. **Sudoers-määritys (valinnainen):** Jos `ENABLE_NOPASSWD=true`, luo `sudoers.d`-tiedoston, joka sallii `TARGET_USER`-käyttäjän ajaa skriptin ilman salasanaa. Polku escapataan sudoers-yhteensopivasti.
4. **APT-välimuistin päivitys:** `apt-get update` ajetaan ennen pakettien asennusta.
5. **Pakettien asennus:** Asentaa `unattended-upgrades` ja `apt-listchanges`.
6. **Konfigurointi:**
   - Kirjoittaa `50unattended-upgrades` ja `20auto-upgrades` tiedostot kohteeseen `APT_CONF_DIR` (oletus `/etc/apt/apt.conf.d`).
   - Asettaa mm. hyväksytyt Originsit, automaattisen uudelleenkäynnistyksen ja ajastuksen.
7. **Lisäpaketit (valinnainen):** Asentaa `EXTRA_PACKAGES`-listan paketit, jos saatavilla.
8. **Varmistus:** Ajaa `unattended-upgrade --dry-run --debug` ja tallentaa lokiin.

Skripti kirjoittaa pysyvän lokin polkuun `${LOG_DIR}/setup.log` ja dry-run-lokin polkuun `${LOG_DIR}/dryrun.log`.

## 🚀 Käyttö

### Vaihtoehto A: asennusskripti (suositus)
```bash
sudo bash ./install.sh   # asentaa /usr/local/sbin/autoupdate.sh ja ajaa sen; ei tarvitse chmod +x
# jos et halua ajaa heti asennuksen jälkeen:
# sudo RUN_AFTER_INSTALL=false bash ./install.sh
```

### Vaihtoehto B: manuaalinen asennus
1) Kopioi skripti Linux-omisteiseen polkuun (vältä /mnt/c):
   ```bash
   sudo cp /mnt/c/tools/TEST/autoupdate.sh /usr/local/sbin/autoupdate.sh
   sudo chown root:root /usr/local/sbin/autoupdate.sh
   sudo chmod 755 /usr/local/sbin/autoupdate.sh   # ei ryhmä/muu kirjoitusoikeutta
   ```
2) Aja se (jos asensit manuaalisesti):
   ```bash
   sudo /usr/local/sbin/autoupdate.sh
   ```

### Ympäristömuuttujat

* `LOG_DIR` – lokien sijainti (oletus: `/var/log/unattended-upgrades`).
* `SUDOERS_TARGET` – sudoers-tiedoston kohde, kun NOPASSWD käytössä (oletus: `/etc/sudoers.d/autoupdate`).
* `REBOOT_TIME` – automaattisen rebootin kellonaika HH:MM (oletus: `03:30`).
* `EXTRA_PACKAGES` – välilyönnillä eroteltu lista asennettavista paketeista (oletus: `ytl-linux-digabi2`).
* `ENABLE_NOPASSWD` – `true` lisää NOPASSWD-säännön `TARGET_USER`-käyttäjälle.
* `TARGET_USER` – käyttäjä, jolle NOPASSWD annetaan (vaaditaan, jos `ENABLE_NOPASSWD=true`).
* `APT_CONF_DIR` – apt-konfiguraatioiden kohdehakemisto (oletus: `/etc/apt/apt.conf.d`).
* `PATH_OVERRIDE` – korvaa PATH:in, esim. stub-komentojen testausta varten (tyhjä = normaali PATH).
* `SKIP_ROOT_CHECK` – testikäyttöön; jos `true`, ohittaa root-tarkistuksen (älä käytä tuotannossa).
* `SKIP_WAIT_ONLINE` – jos `true` (oletus), poistaa systemd-networkd-wait-online esikäytön apt-timereilta, välttäen ajojen kaatumisen verkon odotukseen.
* `ALLOWED_EXTRA_ORIGINS` – ylimääräiset Allowed-Origins-merkinnät (yksi per rivi, muoto `origin:suite`), oletuksena Abitti-repot.
* `ALLOWED_EXTRA_PATTERNS` – Origins-Pattern-merkinnät (esim. `site=linux.abitti.fi`) repoille, joissa Origin/Archive puuttuu.
# README: Automaattiset Päivitykset (Unattended-Upgrades)

## 🇫🇮 Yleiskatsaus

Tämä skripti on kehitetty automaattisen päivitysjärjestelmän (`unattended-upgrades`) turvalliseen ja toistettavaan konfigurointiin Debian- ja Ubuntu-pohjaisissa järjestelmissä. Sen päätavoitteena on varmistaa, että järjestelmä pysyy ajan tasalla tietoturvapäivitysten ja haluttujen lisäpakettien osalta ilman manuaalista puuttumista.

## ⚙️ Vaatimukset

* **Käyttöjärjestelmä:** Debian tai Ubuntu (APT-pohjainen).
* **Komponentit:** `bash` (v4+), GNU Coreutils (`stat`, `readlink`, `mktemp`, `cmp`), `apt`, `visudo`.
* **Käyttöoikeudet:** Skripti on ajettava **root-käyttäjänä** (`sudo` on pakollinen).

## ✨ Toimintaperiaate

Skripti noudattaa tiukkaa, vaiheittaista prosessia, joka on **idempotentti** (eli sen voi ajaa uudelleen ilman haittavaikutuksia, jos kokoonpano ei muutu).



1.  **Esitarkistukset:** Varmistaa, että skriptiä ajetaan root-käyttäjänä, tarvittavat työkalut ovat asennettuina ja skriptin tiedostopolku on turvallinen (root-omistuksessa ja ilman kirjoitusoikeuksia muille).
2.  **Syötteen Validointi:** Tarkistaa, että ympäristömuuttujat (esim. `REBOOT_TIME`) ovat oikeassa muodossa.
3.  **Sudoers-määritys (valinnainen):** Jos `ENABLE_NOPASSWD=true`, skripti luo turvallisen `sudoers.d`-tiedoston, joka antaa määritellylle käyttäjälle (`TARGET_USER`) oikeuden ajaa skriptin uudelleen ilman salasanaa.
4.  **Pakettien Asennus:** Asentaa `unattended-upgrades` ja `apt-listchanges`. Sen jälkeen päivittää APT-pakettilistat (`apt-get update`).
5.  **Konfigurointi:**
    * Kirjoittaa `/etc/apt/apt.conf.d/50unattended-upgrades`-tiedoston. Tämä määrittää, mistä lähteistä (Origins) päivitykset hyväksytään (oletuksena *security*, *updates*).
    * Kirjoittaa `/etc/apt/apt.conf.d/20auto-upgrades`-tiedoston, joka asettaa päivitysten ajastuksen (päivittäiset tarkistukset ja automaattinen asennus).
6.  **Lisäpaketti (Valinnainen):** Tarkistaa ja asentaa ympäristömuuttujassa `EXTRA_PACKAGES` määritellyt paketit (esim. `ytl-linux-digabi2`). Skripti tarkistaa ensin, onko paketti saatavilla, jotta se ei kaatuisi puuttuvan repolistan takia.
7.  **Varmistus:** Ajaa lopuksi `unattended-upgrade --dry-run` testin onnistuneen konfiguraation varmistamiseksi.

## 🚀 Käyttö

Tallenna skripti nimellä esim. `autoupdate.sh` ja anna sille suoritusoikeudet.

### Peruskäyttö (Vain Konfigurointi)

Tämä asettaa automaattiset päivitykset käyttööön ilman erillisiä sudoers-sääntöjä.

```bash
sudo ./autoupdate.sh