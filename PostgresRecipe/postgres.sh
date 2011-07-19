#!/bin/bash
#
# Script to install postgres, and make it point to a volume (sdb) where
# the database resides. The assumption is to have a Debian installation,
# thus we'll look for Debian's style configuration and modify it
# accordingly. 

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="my_walrus"                 # arbitrary name 
WALRUS_IP="173.205.188.8"               # IP of the walrus to use
WALRUS_KEY="xxxxxxxxxxxxxxxxxxxx"       # EC2_ACCESS_KEY
WALRUS_ID="xxxxxxxxxxxxxxxxxxxx"        # EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/postgres"	# conf bucket

# use MOUNT_DEV to wait for an EBS volume, otherwise we'll be using
# ephemeral: WARNING when using ephemeral you may be loosing data uping
# instance termination
#MOUNT_DEV="/dev/sdb"		# EBS device
MOUNT_DEV=""			# use ephemeral
MOUNT_POINT="/postgres"
PG_VERSION="8.4"
CONF_DIR="/etc/postgresql/$PG_VERSION/main/"
DATA_DIR="/var/lib/postgresql/$PG_VERSION/"

# user to use when working with the database
USER="postgres"

# Modification below this point are needed only to customize the behavior
# of the script.

# the modified s3curl to interact with the above walrus
S3CURL="/usr/bin/s3curl-euca.pl"

# get the s3curl script
curl -f -o ${S3CURL} --url http://173.205.188.8:8773/services/Walrus/s3curl/s3curl-euca.pl
chmod 755 ${S3CURL}

# now let's setup the id for accessing walrus
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

# let's make sure we have the mountpoint
mkdir -p $MOUNT_POINT

# if using ephemeral we need to make sure it is mounted
if [ -z "$MOUNT_DEV" ]; then
	# let's see where ephemeral is mounted, and either mount it in the
	# final place ($MOUNT_POINT) or mount -o bind
	EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral0`"
	if [ -z "${EPHEMERAL}" ]; then
		# workaround for a bug in EEE 2
		EPHEMERAL="`curl -f -m 20 http://169.254.169.254/latest/meta-data/block-device-mapping/ephemeral`"
	fi
	if [ -z "${EPHEMERAL}" ]; then
		echo "Cannot find ephemeral partition!"
	else
		# let's see if it is mounted
		if ! mount | grep ${EPHEMERAL} ; then
			mount /dev/${EPHEMERAL} $MOUNT_POINT
		else
			mount -o bind `mount | grep ${EPHEMERAL} | cut -f 3 -d ' '` $MOUNT_POINT
		fi
	fi
else
	# wait for the EBS volume and mount it
	while ! mount $MOUNT_DEV $MOUNT_POINT ; do
		echo "waiting for EBS volume ($MOUNT_DEV) ..."
		sleep 10
	done
fi

# update the instance
aptitude -y update
aptitude -y upgrade

# install postgres
aptitude install -y postgresql

# stop the database
/etc/init.d/postgresql stop

# change where the data directory is and listen to all interfaces
sed -i "1,$ s;^\(data_directory\).*;\1 = '$MOUNT_POINT/db';" $CONF_DIR/postgresql.conf
sed -i "1,$ s;^#\(listen_addresses\).*;\1 = '*';" $CONF_DIR/postgresql.conf

# we need to set postgres to trust access from the network: euca-authorize
# will do the rest
cat >>$CONF_DIR/pg_hba.conf <<EOF
# trust everyone: the user will set the firewall via ec2-authorize
hostssl all         all         0.0.0.0/0             md5
EOF

# now let's see if we have an already existing database on the target
# directory
if [ ! -d $MOUNT_POINT/db ]; then
	# nope: let's recover from the bucket: let's get the default
	# structure in
	(cd $DATA_DIR; tar czf - *)|(cd $MOUNT_POINT; tar xzf -)

	# start the database
	/etc/init.d/postgresql start

	# and recover from bucket
	${S3_CURL} --id ${WALRUS_NAME} --get -- ${WALRUS_URL}/backup > /$MOUNT_POINT/backup
	psql -f /$MOUNT_POINT/backup postgres
else
	# database is in place: just start 
	/etc/init.d/postgresql start
fi

# set up a cron-job to save the database to a bucket
cat >/usr/local/bin/pg_backup.sh <<EOF
#!/bin/sh
pg_dumpall > /root/backup
${S3_CURL} --id ${WALRUS_NAME} --put /root/backup -- ${WALRUS_URL}/backup
rm /root/backup
EOF
chmod +x /usr/local/bin/pg_backup.sh

# and turn it into a cronjob
cat >/root/crontab <<EOF
2,17,32,47 * * * * /usr/local/bin/pg_backup.sh
EOF

# change permissions and then start the cronjob
chown ${USER} /usr/local/bin/pg_backup.sh
crontab -u ${USER} /usr/local/bin/pg_backup.sh

