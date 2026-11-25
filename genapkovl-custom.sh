#!/bin/sh -e

HOSTNAME="$1"
[ -n "$HOSTNAME" ] || { echo "usage: $0 hostname"; exit 1; }

cleanup() { rm -rf "$tmp"; }

makefile() {
	OWNER="$1"; PERMS="$2"; FILENAME="$3"
	cat > "$FILENAME"
	chown "$OWNER" "$FILENAME"
	chmod "$PERMS" "$FILENAME"
}

rc_add() {
	mkdir -p "$tmp"/etc/runlevels/"$2"
	ln -sf /etc/init.d/"$1" "$tmp"/etc/runlevels/"$2"/"$1"
}

tmp="$(mktemp -d)"
trap cleanup EXIT

# ---------- Système de base ----------
mkdir -p "$tmp"/etc "$tmp"/etc/network "$tmp"/etc/apk

makefile root:root 0644 "$tmp"/etc/hostname <<EOF
$HOSTNAME
EOF

makefile root:root 0644 "$tmp"/etc/network/interfaces <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
EOF

# Paquets installés au boot (depuis le dépôt embarqué dans l'ISO)
makefile root:root 0644 "$tmp"/etc/apk/world <<EOF
alpine-base
nano
htop
curl
git
openssh
docker
docker-cli-compose
EOF

# Disque de données persistant (optionnel) : étiquette "docker"
makefile root:root 0644 "$tmp"/etc/fstab <<EOF
LABEL=docker /var/lib/docker ext4 noatime 0 2
EOF

# ---------- Docker ----------
mkdir -p "$tmp"/etc/docker
makefile root:root 0644 "$tmp"/etc/docker/daemon.json <<EOF
{ "log-driver": "local", "log-opts": { "max-size": "5m", "max-file": "2" } }
EOF

# ---------- Scripts de déploiement ----------
mkdir -p "$tmp"/etc/deploy "$tmp"/etc/local.d "$tmp"/etc/crontabs

makefile root:root 0644 "$tmp"/etc/deploy/config <<'EOF'
REPO="https://github.com/zeyu971/Home_lab/Docker"
BRANCH="dev"
DIR="/var/lib/docker/depot"
EOF

# Mise à jour git + redéploiement
makefile root:root 0755 "$tmp"/etc/deploy/deploy.sh <<'EOF'
#!/bin/sh
. /etc/deploy/config
if [ -d "$DIR/.git" ]; then
	git -C "$DIR" fetch -q origin "$BRANCH" || exit 1
	[ "$(git -C "$DIR" rev-parse HEAD)" = "$(git -C "$DIR" rev-parse "origin/$BRANCH")" ] && [ "$1" != "--force" ] && exit 0
	git -C "$DIR" reset -q --hard "origin/$BRANCH"
else
	git clone -q -b "$BRANCH" "$REPO" "$DIR" || exit 1
fi
cd "$DIR" && docker compose up -d --build --remove-orphans
docker image prune -f >/dev/null
EOF

# Lancé une fois au démarrage
makefile root:root 0755 "$tmp"/etc/local.d/deploy.start <<'EOF'
#!/bin/sh
exec >>/var/log/deploy-boot.log 2>&1
echo "=== boot $(date) ==="

# Attendre que Docker soit prêt (max 60 s)
i=0
until docker info >/dev/null 2>&1; do
	i=$((i+1)); [ $i -gt 60 ] && { echo "Docker indisponible"; exit 1; }
	sleep 1
done

# Charger les images préembarquées (une seule fois si disque persistant)
MARK=/var/lib/docker/.images-loaded
if [ ! -f "$MARK" ]; then
	for f in /media/*/docker-images/*.tar; do
		[ -f "$f" ] || continue
		echo "load $f"; docker load -i "$f"
	done
	touch "$MARK"
fi

# Attendre le réseau, puis déployer (en arrière-plan pour ne pas bloquer le boot)
( i=0
  until ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; do
	i=$((i+1)); [ $i -gt 30 ] && break; sleep 2
  done
  /etc/deploy/deploy.sh --force ) &
EOF

# Vérification git toutes les 5 minutes
makefile root:root 0600 "$tmp"/etc/crontabs/root <<'EOF'
*/5 * * * * /etc/deploy/deploy.sh >> /var/log/deploy.log 2>&1
EOF

# ---------- Accès SSH par clé (remplace par ta clé publique) ----------
mkdir -p "$tmp"/root/.ssh
chmod 700 "$tmp"/root/.ssh
makefile root:root 0600 "$tmp"/root/.ssh/authorized_keys <<'EOF'
ssh-ed25519 AAAA... moi@monpc
EOF

# ---------- Services ----------
rc_add devfs sysinit
rc_add dmesg sysinit
rc_add mdev sysinit
rc_add hwdrivers sysinit
rc_add modloop sysinit

rc_add hwclock boot
rc_add modules boot
rc_add sysctl boot
rc_add hostname boot
rc_add bootmisc boot
rc_add syslog boot
rc_add networking boot
rc_add localmount boot

rc_add docker default
rc_add sshd default
rc_add crond default
rc_add local default

rc_add mount-ro shutdown
rc_add killprocs shutdown
rc_add savecache shutdown

tar -c -C "$tmp" etc root | gzip -9n > "$HOSTNAME".apkovl.tar.gz