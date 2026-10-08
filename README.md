# 📚 Pronote Client 2026 sous Linux

Installation de **Pronote Client 2026** sous Linux grâce à **Wine**.

> **Version du script : 4.10.2 — 07/10/2026**

Le script permet d'installer les versions **32 bits et 64 bits** de Pronote Client 2026 et crée automatiquement les raccourcis nécessaires dans le menu des applications lorsque l'environnement de bureau le permet.

---

Cette nouvelle version 4.10 associe les pièces jointes de votre cahier de textes aux applications Linux permettant de les lire (formats PDF, DOCX, ODT, PPTX etc). 
Une mise à l'échelle est proposée par le script sur les écrans ayant une résolution supérieure au 1080p (QHD et 4K), afin d'agrandir la police par défaut de Pronote.

---

## ✅ Distributions testées

| Distribution           | Version       | 32 bits | 64 bits | Version testée |    Date    |
| ---------------------- | ------------- | :-----: | :-----: | :------------: | :--------: |
| 🟢 CachyOS             | `20260809`    |    ✅    |    ✅    |     4.10.2     | 04/10/2026 |
| 🟢 Linux Mint Cinnamon | `22.3`        |    ✅    |    ✅    |     4.10.2    | 04/10/2026 |
| 🟢 Linux Mint XFCE     | —             |    ✅    |    ✅    |     4.10.2     | 04/10/2026 |
| 🟢 Zorin OS            | `18` / `18.1` |    ✅    |    ✅    |       4.9      | 20/09/2026 |
| 🟢 Fedora              | `44`          |    ✅    |    ✅    |       4.9      | 20/09/2026 |
| 🟢 Kubuntu             | `26.04`       |    ✅    |    ✅    |       4.6      | 07/09/2026 |
| 🟢 Ubuntu MATE         | `24.04`       |    ✅    |    ✅    |       4.6      | 07/09/2026 |
| 🟢 Ubuntu              | `22.04 LTS`   |    ✅    |    ✅    |     4.10.2     | 08/10/2026 |
| 🟢 NixOS               | —             |    ✅    |    ✅    |       4.9      | 20/09/2026 |

### Familles de distributions probablement compatibles

Le script devrait également fonctionner sur les distributions appartenant aux mêmes familles, notamment :

* **Arch Linux** : SteamOS, CachyOS, Artix, Garuda, EndeavourOS, etc.
* **Fedora** : Nobara, Bazzite, RHEL, Rocky Linux, etc.
* **Debian / Ubuntu** : Linux Mint, Zorin OS, Kubuntu, Ubuntu MATE, etc.

> ⚠️ Ces compatibilités supplémentaires sont indiquées à titre indicatif et ne signifient pas qu'elles ont toutes été testées individuellement.

---

# 🚀 Installation

## ⚠️ Avant de commencer

Ouvrez un terminal Linux.

Il est **préférable de désinstaller une ancienne version de Wine** avant l'installation, sauf si votre version installée est déjà **Wine 10 ou supérieure**.

> ⚠️ **Attention :** les commandes de désinstallation ci-dessous peuvent supprimer votre installation et votre configuration Wine (`~/.wine`).
> Vérifiez auparavant qu'aucun autre logiciel Windows que vous utilisez ne dépend d'une configuration Wine existante.

---

## 1. Vérifier la version de Wine

Dans un terminal :

```bash
wine --version
```

### Selon le résultat :

* **Aucune réponse / Wine non installé** → passez directement à [l'étape 5](#5-installer-pronote-client-2026).
* **Wine 10 ou Wine 11** → passez directement à [l'étape 5](#5-installer-pronote-client-2026).
* **Wine inférieur à 10** (Wine 8, 9, etc.) → désinstallez l'ancienne version avec l'étape correspondant à votre distribution.

---

## 2. Ubuntu / Linux Mint / Debian / Zorin OS

Pour supprimer une ancienne installation de Wine ainsi que ses fichiers de configuration :

```bash
sudo apt remove --purge wine wine64 wine32 wine-binfmt && \
sudo apt autoremove --purge && \
rm -rf ~/.wine
```

> ⚠️ Cette commande supprime également le préfixe Wine `~/.wine`.

---

## 3. Arch / SteamOS / CachyOS / Nobara / Omarchy, etc.

Pour supprimer une ancienne installation de Wine :

```bash
sudo pacman -Rns wine && \
rm -rf ~/.wine \
       ~/.config/wine \
       ~/.cache/wine \
       ~/.local/share/applications/wine* \
       ~/.local/share/mime/packages/wine* \
       ~/.local/share/icons/hicolor/*/apps/wine* \
       ~/.local/share/wine
```

---

## 4. Fedora / Bazzite / RHEL / Rocky Linux / Nobara, etc.

Pour supprimer une ancienne installation de Wine :

```bash
sudo dnf remove 'wine*' && \
rm -rf ~/.wine \
       ~/.local/share/applications/wine \
       ~/.config/wine
```

---

# 5. Installer Pronote Client 2026

### Script d'installation — version 4.10.1

Copiez-collez cette commande dans votre terminal :

```bash
wget -q -O "$(xdg-user-dir DESKTOP)/pronote.sh" \
https://raw.githubusercontent.com/christophemarc/pronote/main/pronote.sh && \
bash "$(xdg-user-dir DESKTOP)/pronote.sh"
```

Le script `pronote.sh` sera téléchargé sur votre **bureau Linux**, puis exécuté automatiquement.

Le script prend ensuite en charge l'installation de Pronote Client 2026.

> 💡 Le fichier `pronote.sh` peut être supprimé une fois l'installation terminée. Voir [l'étape 8](#8-optionnel--supprimer-le-script-dinstallation).

---

## 🐧 Cas particulier : NixOS

Sous **NixOS**, `wget` n'est pas nécessairement installé par défaut.

Avant l'étape 5, exécutez :

```bash
nix-shell -p wget
```

Puis lancez la commande d'installation de l'étape 5.

---

# 6. ▶️ Lancer Pronote

Après l'installation, Pronote peut être lancé depuis un terminal avec :

```bash
~/.local/bin/pronote-2026
```

Un raccourci devrait également être ajouté automatiquement au **menu des applications**, notamment dans les catégories :

* **Bureautique**
* **Éducation**

Cela fonctionne notamment avec les environnements de bureau **KDE Plasma, XFCE et Cinnamon**.

---

# 7. 🗑️ Désinstaller Pronote

Une fois l'année scolaire terminée, Pronote peut être désinstallé à l'aide du programme fourni avec le script.

### Désinstallation standard

```bash
~/.local/bin/pronote-desinstaller
```

### Désinstallation de la version 64 bits

```bash
~/.local/bin/pronote-desinstaller-64
```

### Désinstallation de la version 32 bits

```bash
~/.local/bin/pronote-desinstaller-32
```

Ces commandes désinstallent **Pronote ainsi que son module de mise à jour**.

---

# 8. 🧹 Optionnel — Supprimer le script d'installation

Une fois l'installation terminée, le fichier `pronote.sh` présent sur le bureau peut être supprimé sans risque.

Sous un bureau configuré en français :

```bash
cd ~/Bureau && rm -f pronote.sh
```

Selon votre configuration, le bureau peut également correspondre à `~/Desktop`.

---

# 9. 🖥️ Optionnel — Créer manuellement un raccourci

Dans certains cas, aucun raccourci Pronote n'apparaît automatiquement sur le bureau ou dans le menu des applications.

Vous pouvez alors en créer un manuellement.

Ouvrez un éditeur de texte simple (**gedit**, **Kate**, **Xed** sous Linux Mint, etc.) et copiez le contenu suivant :

```ini
[Desktop Entry]
Name=Pronote 2026
GenericName=Client Pronote
Comment=Client Pronote 2026 via Wine
Exec=/home/nomdutilisateur/.local/bin/pronote-2026
Terminal=false
Type=Application
Icon=/home/nomdutilisateur/.local/share/icons/hicolor/256x256/apps/pronote-2026.png
Categories=Education;Office;
StartupNotify=true
Keywords=pronote;education;ecole;college;lycee;
```

### ⚠️ Important

Remplacez :

```text
nomdutilisateur
```

par le nom d'utilisateur de votre session Linux dans les lignes :

```ini
Exec=
Icon=
```

Enregistrez ensuite le fichier sur le bureau sous le nom :

```text
Pronote.desktop
```

---

## Rendre le raccourci exécutable

Dans un terminal :

```bash
cd ~/Bureau/
```

Puis :

```bash
chmod +x Pronote.desktop
```

> Si vous avez donné un autre nom au fichier, utilisez exactement ce nom dans la commande.

---

# 📌 Résumé

| Action               | Commande                               |
| -------------------- | -------------------------------------- |
| Vérifier Wine        | `wine --version`                       |
| Installer Pronote    | `wget ... && bash ...`                 |
| Lancer Pronote       | `~/.local/bin/pronote-2026`            |
| Désinstaller         | `~/.local/bin/pronote-desinstaller`    |
| Désinstaller 64 bits | `~/.local/bin/pronote-desinstaller-64` |
| Désinstaller 32 bits | `~/.local/bin/pronote-desinstaller-32` |

---

## 🛠️ Compatibilité Wine

Le script est prévu pour fonctionner avec des versions récentes de **Wine**, et les tests documentés ici ont principalement été réalisés avec **Wine 10+**.

Pour éviter les problèmes liés à une ancienne configuration, l'utilisation d'une version de Wine **10 ou supérieure** est recommandée.

---

## 📅 Historique des tests

* **04/10/2026** — script `4.10.1` : CachyOS, Linux Mint Cinnamon 22.3, Linux Mint XFCE.
* **20/09/2026** — script `4.9` : Fedora 44, Zorin OS 18.1, NixOS.
* **07/09/2026** — script `4.6` : Kubuntu 26.04, Ubuntu MATE 24.04.

---

## ⚖️ Remarque

Ce projet fournit un **script d'installation pour Linux** permettant d'utiliser Pronote Client 2026 avec Wine.

Pronote est un logiciel et une marque appartenant à leurs ayants droit respectifs. Ce script n'est pas présenté comme un produit officiel de Pronote.

---
