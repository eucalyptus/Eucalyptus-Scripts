#!/bin/bash
#
# Script to install mailman

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="my_walrus"                 # arbitrary name 
WALRUS_IP="173.205.188.8"               # IP of the walrus to use
WALRUS_ID="xxxxxxxxxxxxxxxxxxxxx"       # EC2_ACCESS_KEY
WALRUS_KEY="xxxxxxxxxxxxxxxxxxx"        # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/mailman"	# conf bucket
WALRUS_MASTER="mailman-archive.tgz"	# master copy of the database

# mailman related configuration
MAILNAME="lists.eucalyptus.com"         # the public hostname
POSTMASTER="community@eucalyptus.com"   # email to receive exim errors
PASSWD="pippo"                          # password for administer lists
MOUNT_POINT="/mailman"                  # archives and data are on ephemeral

# do backup on walrus?
WALRUS_BACKUP="Y"

# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
echo "Getting ${S3CURL}"
curl -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
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

# make sure the mailname is correct
echo "${MAILNAME}" > /etc/mailname

# mailman and exim requires some preseed to prevent questions
cat >/root/preseed.cfg <<EOF
exim4-daemon-light      exim4-daemon-light/drec error   
exim4-config    exim4/dc_other_hostnames        string  
exim4-config    exim4/dc_eximconfig_configtype  select  internet site;
mail is sent and received directly using SMTP
exim4-config    exim4/no_config boolean true
exim4-config    exim4/hide_mailname     boolean 
exim4-config    exim4/dc_postmaster     string  ${POSTMASTER}
exim4-config    exim4/dc_smarthost      string  
exim4-config    exim4/dc_relay_domains  string  
exim4-config    exim4/dc_relay_nets     string  
exim4-base      exim4/purge_spool       boolean false
exim4-config    exim4/mailname  string  ${MAILNAME}
exim4-config    exim4/dc_readhost       string  
# Reconfigure exim4-config instead of this package
exim4-base      exim4-base/drec error   
exim4-config    exim4/use_split_config  boolean false
exim4-config    exim4/dc_localdelivery  select  mbox format in /var/mail/
exim4-config    exim4/dc_local_interfaces       string  
exim4-config    exim4/dc_minimaldns     boolean false

mailman mailman/gate_news       boolean false
mailman mailman/site_languages  multiselect     en
mailman mailman/queue_files_present     select  abort installation
mailman mailman/used_languages  string  
mailman mailman/default_server_language select  en
mailman mailman/create_site_list        note    
EOF
debconf-set-selections /root/preseed.cfg
rm -f /root/preseed.cfg

# install mailman
apt-get install --force-yes -y mailman

# let's make sure we have the mountpoint
echo "Creating and prepping $MOUNT_POINT"
mkdir -p $MOUNT_POINT

# don't mount $MOUNT_POINT more than once (mainly for debugging)
if ! mount |grep $MOUNT_POINT; then
        # let's see where ephemeral is mounted, and either mount
        # it in the final place ($MOUNT_POINT) or mount -o bind
        EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
        if [ -z "${EPHEMERAL}" ]; then
                # workaround for a bug in EEE 2
                EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
        fi
        if [ -z "${EPHEMERAL}" ]; then
                echo "Cannot find ephemeral partition!"
                exit 1
        else
                # let's see if it is mounted
                if ! mount | grep ${EPHEMERAL} ; then
                        mount /dev/${EPHEMERAL} $MOUNT_POINT
                else
                        mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` $MOUNT_POINT
                fi
        fi
fi

# now let's get the archives from the walrus bucket
${S3CURL} --id ${WALRUS_NAME} -- ${WALRUS_URL}/${WALRUS_MASTER} > /$MOUNT_POINT/master_copy.tgz
mkdir /$MOUNT_POINT/mailman
tar -C /$MOUNT_POINT/mailman -xzf /$MOUNT_POINT/master_copy.tgz
mv /var/lib/mailman /var/lib/mailman.orig
ln -s /$MOUNT_POINT/mailman /var/lib/mailman

# and the aliases
${S3CURL} --id ${WALRUS_NAME} -- ${WALRUS_URL}/aliases > /etc/aliases
newaliases


# set up a cron-job to save the archives and config to a bucket: it will
# run as root
cat >/usr/local/bin/mailman_backup.sh <<EOF
#!/bin/sh
tar -C /var/lib/mailman -czf /$MOUNT_POINT/archive.tgz . 
# WARNING: the bucket in ${WALRUS_URL} *must* have been already created
# keep one copy per day of the month
${S3CURL} --id ${WALRUS_NAME} --put /$MOUNT_POINT/archive.tgz -- ${WALRUS_URL}/${WALRUS_MASTER}-day_of_month
# and push it to be the latest backup too for easy recovery
${S3CURL} --id ${WALRUS_NAME} --put /$MOUNT_POINT/archive.tgz -- ${WALRUS_URL}/${WALRUS_MASTER}
# and save the aliases too
${S3CURL} --id ${WALRUS_NAME} --put /etc/aliases -- ${WALRUS_URL}/aliases
rm /$MOUNT_POINT/archive.tgz
EOF
# substitute to get the day of month
sed -i 's/-day_of_month/-$(date +%d)/' /usr/local/bin/mailman_backup.sh

# change execute permissions and ownership
chmod +x /usr/local/bin/mailman_backup.sh

if [ "$WALRUS_BACKUP" != "Y" ]; then
	# we are done here
	exit 0
fi

# and turn it into a cronjob to run every hour
cat >/tmp/crontab <<EOF
30 * * * * /usr/local/bin/mailman_backup.sh
EOF
crontab /tmp/crontab

