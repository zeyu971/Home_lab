# Home_lab


Le but pouvoir déployé ou rédéployé une infrastructure en tapant quelque ligne





docker run -it --name alpine-iso -v "$PWD/out:/out" alpine:latest sh


apk update
apk add alpine-sdk alpine-conf syslinux xorriso squashfs-tools \
        grub grub-efi doas mtools dosfstools git



adduser -D build -G abuild
echo "permit nopass :abuild" > /etc/doas.d/doas.conf
chown -R build /out 2>/dev/null
su - build



abuild-keygen -i -a -n

# Prends la branche qui correspond à ta version (cat /etc/alpine-release)
# ex. pour 3.22 : -b 3.22-stable ; sinon master pour edge
git clone --depth=1 https://github.com/alpinelinux/aports.git
cd aports/scripts


cat > mkimg.custom.sh << 'EOF'
profile_custom() {
	profile_standard
	title="Mon Alpine perso"
	desc="ISO Alpine personnalisée"
	kernel_cmdline="console=tty0 console=ttyS0,115200"
	syslinux_serial="0 115200"
	# Paquets ajoutés à l'ISO
	apks="$apks nano htop curl git openssh bash docker"
	# Overlay de configuration (optionnel, voir étape 5)
	apkovl="genapkovl-custom.sh"
}
EOF

cp genapkovl-dhcp.sh genapkovl-custom.sh
chmod +x genapkovl-custom.sh



mkdir -p /out
sh mkimage.sh \
  --tag 3.22 \
  --outdir /out \
  --arch x86_64 \
  --repository https://dl-cdn.alpinelinux.org/alpine/v3.22/main \
  --repository https://dl-cdn.alpinelinux.org/alpine/v3.22/community \
  --profile custom



docker cp alpine-iso:/out/ ./out/


mémo pour créé l'iso à partir du docker alpine 
