# alpine-doco

Génère une ISO Alpine Linux (x86_64) qui, au démarrage :

1. monte un disque de données persistant (et le formate s'il est vierge, si activé) ;
2. lance Docker et SSH ;
3. démarre **Doco-CD**, qui récupère le dépôt Git d'infrastructure et déploie
   les stacks Docker Compose qu'il décrit, puis les met à jour à chaque push.

Objectif : **déployer ou redéployer une machine en quelques lignes.**
L'ISO se construit dans un conteneur Docker, sans rien installer sur l'hôte.

## Prérequis

- Docker sur la machine de build
- Un dépôt Git d'infrastructure contenant un fichier `.doco-cd.yaml` à la racine
  et les fichiers Compose à déployer

## Démarrage rapide

```sh
git clone <ce-depot> alpine-doco && cd alpine-doco
cp config.env.example config.env
nano config.env          # dépôt Git, clé SSH, nom d'hôte...
./build.sh               # → out/alpine-doco-<version>-x86_64.iso
```

## Configuration (`config.env`)

| Variable | Rôle |
|---|---|
| `ALPINE_VERSION` | Version d'Alpine (image de build, branche aports, dépôts) |
| `DOCO_HOSTNAME` | Nom d'hôte de la machine |
| `DOCO_GIT_REPO` | Dépôt Git d'infrastructure surveillé par Doco-CD |
| `DOCO_GIT_BRANCH` | Branche à suivre |
| `DOCO_GIT_TOKEN` | Token d'accès (vide si dépôt public) |
| `DOCO_POLL_INTERVAL` | Intervalle de vérification du dépôt, en secondes (min. 10) |
| `DOCO_TZ` | Fuseau horaire des conteneurs |
| `DOCO_SSH_PUBKEY` | Clé publique autorisée pour `root` en SSH |
| `DOCO_DATA_DISK` | Disque à formater automatiquement s'il est vierge (ex. `/dev/sdb`), vide pour désactiver |

`config.env` contient des secrets : il est exclu de Git par `.gitignore`.

## Déployer une machine

1. Graver l'ISO sur une clé USB (ou l'attacher à une VM) :
   ```sh
   dd if=out/alpine-doco-*.iso of=/dev/sdX bs=4M status=progress && sync
   ```
2. Prévoir un **disque de données** :
   - soit un disque formaté avec l'étiquette `data` : `mkfs.ext4 -L data /dev/sdY`
   - soit un disque vierge désigné par `DOCO_DATA_DISK` (formaté au premier boot)
3. Démarrer sur l'ISO, avec un câble réseau (DHCP).
4. Vérifier :
   ```sh
   ssh root@<ip>
   cat /var/log/doco-boot.log
   docker logs -f doco-cd
   ```

## Redéployer

- **Changer l'infrastructure** : modifier le dépôt Git et pousser.
  Doco-CD applique les changements au prochain cycle de polling.
- **Changer la machine elle-même** (paquets, config, version d'Alpine) :
  modifier `config.env` ou `scripts/`, relancer `./build.sh`, redémarrer sur la nouvelle ISO.
- **Réinstaller de zéro** : redémarrer sur l'ISO. Le système tourne en RAM
  (mode *diskless*), seul le disque `data` conserve l'état (images et volumes Docker).

## Fonctionnement

| Fichier | Rôle |
|---|---|
| `build.sh` | Lance un conteneur `alpine:<version>` qui construit l'ISO |
| `scripts/inside.sh` | Installe les outils de build et crée l'utilisateur `build` (root) |
| `scripts/build-iso.sh` | Clone aports et lance `mkimage.sh` (utilisateur `build`) |
| `scripts/mkimg.doco.sh` | Profil `mkimage` : paquets inclus dans l'ISO |
| `scripts/genapkovl-doco.sh` | Overlay : réseau, SSH, compose Doco-CD, script de démarrage |

## Mise à jour de version d'Alpine

Changer `ALPINE_VERSION` dans `config.env` puis relancer `./build.sh`.
L'image de build, la branche aports et les dépôts suivent automatiquement.

## Dépannage

- **Le build échoue dans le conteneur** : relancer avec `--privileged` ajouté à la
  commande `docker run` de `build.sh`.
- **Pas de réseau au boot** : vérifier le nom de l'interface (`ip a`) ; la config
  utilise `eth0` en DHCP.
- **Doco-CD ne déploie rien** : vérifier `.doco-cd.yaml` dans le dépôt et `docker logs doco-cd`.
- **Pas d'affichage sur une VM** : la console série est activée (`ttyS0`, 115200 bauds).
