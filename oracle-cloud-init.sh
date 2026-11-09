#!/bin/bash
# Fragile Haul server: one-time setup for an Oracle Cloud Always Free instance.
# Paste this whole file into "Initialization script" when you create the instance.
# The only line you must change is REPO below.

REPO="your-name/your-repo"   # <- your GitHub repository, e.g. alex123/fragile-haul (must be public)
PORT=8080                    # the port players connect to (leave as 8080 unless you know why)

# ---------------------------------------------------------------------------
exec >>/var/log/fragile-haul-setup.log 2>&1
echo "=== Fragile Haul setup started $(date) ==="
set -u

# 1. A little swap so the 1 GB free server doesn't run out of memory while installing
if [ "$(swapon --show --noheadings | wc -l)" -eq 0 ]; then
  fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024
  chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. Java and curl (works on the Ubuntu and Oracle Linux images)
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  for i in 1 2 3; do
    apt-get -o DPkg::Lock::Timeout=600 update && \
    apt-get -o DPkg::Lock::Timeout=600 install -y openjdk-17-jre-headless curl && break
    sleep 30
  done
elif command -v dnf >/dev/null; then
  for i in 1 2 3; do dnf install -y java-17-openjdk-headless curl && break; sleep 30; done
fi
command -v java >/dev/null || echo "WARNING: Java did not install"

# 3. A user and folders for the server
id fragilehaul >/dev/null 2>&1 || useradd --system --no-create-home --shell "$(command -v nologin || echo /bin/false)" fragilehaul
mkdir -p /opt/fragile-haul /var/lib/fragile-haul
chown fragilehaul: /var/lib/fragile-haul

# 4. The updater: fetches the newest server file from GitHub every time the server starts
cat > /opt/fragile-haul/update.sh <<EOF
#!/bin/bash
# Downloads server/fragile-haul-server.jar from GitHub. Keeps the old copy if the download fails.
REPO="$REPO"
JAR=/opt/fragile-haul/server.jar
TMP=\$(mktemp)
for BRANCH in main master; do
  URL="https://github.com/\$REPO/raw/\$BRANCH/server/fragile-haul-server.jar"
  if curl -fsSL --retry 3 --max-time 120 -o "\$TMP" "\$URL" && [ "\$(head -c 2 "\$TMP")" = "PK" ]; then
    install -m 644 "\$TMP" "\$JAR"; rm -f "\$TMP"
    echo "Downloaded \$URL"
    exit 0
  fi
done
rm -f "\$TMP"
if [ -f "\$JAR" ]; then echo "Download failed, keeping the server file already here"; exit 0; fi
echo "Could not download the server file. Is REPO right and is the repository public?"
exit 1
EOF
chmod 755 /opt/fragile-haul/update.sh

# 5. Run it as a service: starts on boot, restarts if it ever stops
cat > /etc/systemd/system/fragile-haul.service <<EOF
[Unit]
Description=Fragile Haul game server
After=network-online.target
Wants=network-online.target

[Service]
User=fragilehaul
WorkingDirectory=/var/lib/fragile-haul
Environment=PORT=$PORT
Environment=FH_DATA=/var/lib/fragile-haul/mail.txt
ExecStartPre=+/opt/fragile-haul/update.sh
ExecStart=/usr/bin/java -Xmx256m -jar /opt/fragile-haul/server.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. Open the port in the server's own firewall (Oracle's images block everything except SSH)
RULES=/etc/iptables/rules.v4
if [ -f "$RULES" ]; then
  if ! grep -q -- "--dport $PORT -j ACCEPT" "$RULES"; then
    if grep -q '^-A INPUT -j REJECT' "$RULES"; then
      sed -i "0,/^-A INPUT -j REJECT/s//-A INPUT -p tcp -m state --state NEW -m tcp --dport $PORT -j ACCEPT\n&/" "$RULES"
    else
      sed -i "/^COMMIT/i -A INPUT -p tcp -m state --state NEW -m tcp --dport $PORT -j ACCEPT" "$RULES"
    fi
  fi
  iptables-restore < "$RULES"
elif command -v firewall-cmd >/dev/null; then
  firewall-cmd --permanent --add-port=$PORT/tcp
  firewall-cmd --reload
else
  iptables -C INPUT -p tcp --dport $PORT -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -p tcp --dport $PORT -j ACCEPT
fi

# 7. Start it
systemctl daemon-reload
systemctl enable --now fragile-haul.service
sleep 5
systemctl --no-pager status fragile-haul.service
echo "=== Fragile Haul setup finished $(date) ==="
