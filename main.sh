#!/bin/bash

unset DISPLAY
echo "set -g mouse on" > ~/.tmux.conf

# Kill old tmux sessions
tmux kill-session -t server 2>/dev/null
tmux kill-session -t placeholder 2>/dev/null

BASEDIR="$PWD"
FORCE1="bruh"

JAVA_BIN=$(command -v java)
export GIT_TERMINAL_PROMPT=0

# Clean up old client/gateway info to force rebuild
rm -f client_version gateway_version buildconf.json
rm -rf web/*

# Clone repo if missing
if [ ! -d "eaglercraftx" ]; then
  git clone https://gitlab.com/lax1dude/eaglercraftx-1.8 eaglercraftx --depth 1
fi

# Accept EULA
if ! grep -q "^eula=$REPL_OWNER/$REPL_SLUG\$" "eula.txt" 2>/dev/null; then
  rm -f eula.txt
  $JAVA_BIN -jar LicensePrompt.jar
  echo "eula=$REPL_OWNER/$REPL_SLUG" > eula.txt
fi

# Set new UUID if needed
if [ -f "base.repl" ] && ! { [ "$REPL_OWNER" == "ayunami2000" ] && [ "$REPL_SLUG" == "eaglercraftx" ]; }; then
  rm base.repl
  rm -rf server/world* server/logs server/plugins/PluginMetrics server/usercache.json
  rm -rf cuberite bungee/logs
  rm -f bungee/eaglercraft_*.db
  sed -i '/^stats: /d' bungee/config.yml
  sed -i "s/^server_uuid: .*/server_uuid: $(cat /proc/sys/kernel/random/uuid)/" bungee/plugins/EaglercraftXBungee/settings.yml
  chmod +x selsrv.sh
  ./selsrv.sh
fi

mkdir -p bungee/plugins eaglercraftx web

# Clone/update eaglercraftx
cd eaglercraftx
git remote update 2>/dev/null
git pull
cd ..

# Prepare build config
sed "s#BASEDIR#$BASEDIR#" buildconf_template.json > buildconf.json

# Build client
cd eaglercraftx
tmux new -d -s placeholder "$JAVA_BIN -Xmx128M PlaceHTTPer 8080 Compiling the latest client.... Please wait!"
"$JAVA_BIN" -Xmx512M -cp "buildtools/BuildTools.jar" net.lax1dude.eaglercraft.v1_8.buildtools.gui.headless.CompileLatestClientHeadless -y ../buildconf.json
tmux kill-session -t placeholder

cp -r /tmp/output/* ../web/

# Copy latest gateway plugin
if [ -f "gateway/EaglercraftXBungee/EaglerXBungee-Latest.jar" ]; then
  cp gateway/EaglercraftXBungee/EaglerXBungee-Latest.jar ../bungee/plugins/EaglercraftXBungee.jar
fi

cd ../bungee

# Download Waterfall proxy
rm -f bungee-new.jar
WF_VERSIONS=$(curl -s "https://api.papermc.io/v2/projects/waterfall")
WF_VERSION=$(echo "$WF_VERSIONS" | jq -r '.versions[-1]')
WF_BUILDS=$(curl -s "https://api.papermc.io/v2/projects/waterfall/versions/$WF_VERSION/builds")
WF_BUILD_ID=$(echo "$WF_BUILDS" | jq -r '.builds[-1].build')
WF_FILENAME=$(echo "$WF_BUILDS" | jq -r '.builds[-1].downloads.application.name')
WF_URL="https://api.papermc.io/v2/projects/waterfall/versions/$WF_VERSION/builds/$WF_BUILD_ID/downloads/$WF_FILENAME"
wget -O bungee-new.jar "$WF_URL"
mv bungee-new.jar bungee.jar

# Fix config port for Render
PORT=${PORT:-25577}
sed -i "s/host: .*:[0-9]\+/host: 0.0.0.0:$PORT/" config.yml

# Start Bungee server
tmux new -d -s server "$JAVA_BIN -Xmx128M -jar bungee.jar; tmux kill-session -t server"

cd ../server

# Start Minecraft server (or Cuberite)
if [ ! -f "server.jar" ] && [ -d "../cuberite" ]; then
  cd ../cuberite
  tmux splitw -t server -v "BIND_ADDR=127.0.0.1 LD_PRELOAD=../bindmod.so ./Cuberite; tmux kill-session -t server"
else
  tmux splitw -t server -v "$JAVA_BIN -Djline.terminal=jline.UnsupportedTerminal -Xmx512M -jar server.jar nogui; tmux kill-session -t server"
fi

cd ..

# Attach session
while tmux has-session -t server; do
  tmux a -t server
done
