#!/bin/bash
#
# Simple script to setup planet (feed aggregator)
#

WALRUS_URL="http://173.205.188.8:8773/services/Walrus/planet/"

# update the instance
aptitude -y update
aptitude -y upgrade

# install planet-venus
aptitude install -y planet-venus nginx

# create planet's structure
mkdir -pv /mnt/planet/cache /mnt/planet/output /mnt/planet/output/images /mnt/planet/theme /mnt/planet/theme/images
echo "<html></html>" >/mnt/planet/output/index.html
cp -pv /usr/share/planet-venus/theme/common/* /mnt/planet/theme
cp -pvr /usr/share/planet-venus/theme/default/* /mnt/planet/theme
cp -pv /usr/share/planet-venus/theme/common/images/* /mnt/planet/output/images

# let's create a script to update the skinning of the planet
cat >/mnt/planet/execute <<EOF
#!/bin/sh
curl -f -o /mnt/planet/planet.ini --url $WALRUS_URL/planet.ini
curl -f -o /mnt/planet/theme/index.html.tmpl --url $WALRUS_URL/index.html.tmpl
curl -f -o /mnt/planet/output/images/logo.png --url $WALRUS_URL/logo.png
curl -f -o /mnt/planet/output/planet.css --url $WALRUS_URL/planet.css
cd /mnt/planet && planet --verbose planet.ini
EOF

# let's run it now
chmod +x /mnt/planet/execute
/mnt/planet/execute

# and turn it into a cronjob
cat >/mnt/planet/crontab <<EOF
2,17,32,47 * * * * /mnt/planet/execute
EOF

# change permissions and then start the cronjob
chown -R ubuntu:ubuntu /mnt/planet
crontab -u ubuntu /mnt/planet/crontab

# finally let's setup nginx
cat >/etc/nginx/sites-available/default <<EOF
server {
	listen   80; ## listen for ipv4
	listen   [::]:80 default ipv6only=on; ## listen for ipv6
	access_log /var/log/nginx/access.log;
	location / {
		root	/mnt/planet/output;
		index	index.html;
	}
}
EOF

service nginx start

