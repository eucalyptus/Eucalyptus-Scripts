#!/bin/bash
#
# Script to install eucabot

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="community"                 # arbitrary name 
WALRUS_IP="173.205.188.8"               # IP of the walrus to use
WALRUS_ID="xxxxxxxxxxxxxxxxxxxxx"       # EC2_ACCESS_KEY
WALRUS_KEY="xxxxxxxxxxxxxxxxxxx"        # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/eucabot"	# conf bucket
WALRUS_MASTER="eucabot-archive.tgz"	# master copy of the database

MOUNT_POINT="/eucabot"                  # archives and data are on ephemeral

# do backup on walrus?
WALRUS_BACKUP="Y"

# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
echo "Getting ${S3CURL}"
curl -s -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
chmod 755 ${S3CURL}

# now let's setup the id for accessing walrus
echo "Setting credentials for ${S3CURL}"
cat >${HOME}/.s3curl <<EOF
%awsSecretAccessKeys = (
	${WALRUS_NAME} => {
		url => '${WALRUS_IP}',
		id => '${WALRUS_ID}',
		key => '${WALRUS_KEY}',
	},
);
EOF
chmod 600 ${HOME}/.s3curl

# update the instance
echo "Upgrading and installing packages"
apt-get --force-yes -y update
apt-get --force-yes -y upgrade

# needed preseed to make it non-interactive
echo "Preseeding debconf"
cat /root/preseed.cfg <<EOF
EOF
debconf-set-selections /root/preseed.cfg
rm -f /root/preseed.cfg

# install deps
echo "Installing dependencies"
apt-get install --force-yes -y apache2 darcs git python-twisted-name

# just sync the date first
ntpdate -s

# let's make sure we have the mountpoint
echo "Creating and prepping ${MOUNT_POINT}"
mkdir -p ${MOUNT_POINT}

# don't mount ${MOUNT_POINT} more than once (mainly for debugging)
if ! mount |grep ${MOUNT_POINT}; then
        # let's see where ephemeral is mounted, and either mount
        # it in the final place (${MOUNT_POINT}) or mount -o bind
        EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
        if [ -z "${EPHEMERAL}" ]; then
                # workaround for a bug in EEE 2
                EPHEMERAL="`curl -s -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
        fi
        if [ -z "${EPHEMERAL}" ]; then
                echo "Cannot find ephemeral partition!"
                exit 1
        else
                # let's see if it is mounted
                if ! mount | grep ${EPHEMERAL} ; then
                        mount /dev/${EPHEMERAL} ${MOUNT_POINT}
                else
                        mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` ${MOUNT_POINT}
                fi
        fi
fi

# Install supybot
tempdir=`mktemp -d`
git clone --depth 1 git://github.com/ProgVal/Limnoria.git $tempdir/supybot
pushd $tempdir/supybot
python setup.py install
popd
rm -rf $tempdir

# Install the MeetBot plugin
darcs get http://anonscm.debian.org/darcs/collab-maint/MeetBot/ /usr/local/python2.6/dist-packages/supybot/plugins/MeetBot

# Install remaining plugins
tempdir=`mktemp -d`
git clone -depth 1 git://github.com/gholms/supybot-rtquery.git $tempdir/supybot-rtquery
mv -nT $tempdir/supybot-rtquery/RTQuery /usr/local/python2.6/dist-packages/supybot/plugins/RTQuery
git clone -depth 1 git://github.com/gholms/supybot.redmine.git $tempdir/supybot-redmine
mv -nT $tempdir/supybot-redmine/Redmine /usr/local/python2.6/dist-packages/supybot/plugins/Redmine
git clone -depth 1 git://github.com/ProgVal/supybot.plugins.git $tempdir/supybot-plugins
mv -nT $tempdir/supybot-plugins/AttackProtector /usr/local/python2.6/dist-packages/supybot/plugins/AttackProtector
rm -rf $tempdir

# Supybot instances' data go in subdirectories of this
install -d -m 0710 /var/lib/supybot -g www-data

# Instance 1 lives on chat.freenode.net:6697
useradd -g www-data -M -N -r -s /usr/sbin/nologin supybot1
install -d -m 0710 /var/lib/supybot/1              -o supybot1 -g www-data
install -d -m 0750 /var/lib/supybot/1/meeting-logs -o supybot1 -g www-data
#W Write /var/lib/supybot/1/supybot.conf
mkdir /var/lib/supybot/1/conf
## Write /var/lib/supybot/1/conf/users.conf
chown -R supybot1:www-data /var/lib/supybot/1

# Instance 2 lives on irc.eucalyptus-systems.com:6667
useradd -g www-data -M -N -r -s /usr/sbin/nologin supybot2
install -d -m 0710 /var/lib/supybot/2              -o supybot2 -g www-data
install -d -m 0750 /var/lib/supybot/2/meeting-logs -o supybot2 -g www-data
#W Write /var/lib/supybot/2/supybot.conf
mkdir /var/lib/supybot/2/conf
## Write /var/lib/supybot/2/conf/users.conf
chown -R supybot2:www-data /var/lib/supybot/2

## Write /etc/init.d/supybot (see contents below)
update-rc.d supybot defaults
service supybot start

## TODO:  set up SSL and LDAP schtick

# let's setup apache's configuration
echo "Configuring apache"
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/supybot > /etc/apache2/sites-available/supybot
if [ "`head -c 4 /etc/apache2/sites-available/supybot`" = "<Err" ]; then
        echo "Couldn't get apache configuration!"
        exit 1
fi
a2dissite default
a2ensite supybot
service apache2 restart

# now let's get the archives from the walrus bucket
echo "Retrieving eucabot archives and configuration"
${S3CURL} --id ${WALRUS_NAME} -- -s ${WALRUS_URL}/${WALRUS_MASTER} > /${MOUNT_POINT}/master_copy.tgz
mkdir /${MOUNT_POINT}/eucabot
if [ "`head -c 4 /${MOUNT_POINT}/master_copy.tgz`" = "<Err" ]; then
        echo "Couldn't get archives!"
        exit 1
else
        tar -C /${MOUNT_POINT}/eucabot -xzf /${MOUNT_POINT}/master_copy.tgz
fi

# set up a cron-job to save the archives and config to a bucket: it will
# run as root
echo "Preparing local script to push backups to walrus"
cat >/usr/local/bin/eucabot_backup.sh <<EOF
#!/bin/sh
tar -C /var/lib/mailman -czf /${MOUNT_POINT}/archive.tgz . 
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put /${MOUNT_POINT}/archive.tgz -- -s ${WALRUS_URL}/${WALRUS_MASTER}
# and save the aliases too
${S3CURL} --id ${WALRUS_NAME} --put /etc/aliases -- -s ${WALRUS_URL}/aliases
# finally the apache config file
${S3CURL} --id ${WALRUS_NAME} --put /etc/apache2/sites-available/supybot -- -s ${WALRUS_URL}/supybot
rm /${MOUNT_POINT}/archive.tgz
EOF
# substitute to get the day of month
sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/eucabot_backup.sh

# change execute permissions and ownership
chmod +x /usr/local/bin/eucabot_backup.sh

if [ "$WALRUS_BACKUP" != "Y" ]; then
	# we are done here
	exit 0
fi

# and turn it into a cronjob to run every hour
echo "Setting up cron-job"
cat >/tmp/crontab <<EOF
30 * * * * /usr/local/bin/eucabot_backup.sh
EOF
crontab /tmp/crontab

