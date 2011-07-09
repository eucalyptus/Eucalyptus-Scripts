#!/bin/bash
#
# Script to install postgres, and make it point to a volume (sdb) where
# the database resides. The assumption is to have a Debian installation,
# thus we'll look for Debian's style configuration and modify it
# accordingly. 

MOUNT_DEV="/dev/sdb"
MOUNT_POINT="/postgres"
CONF_FILE="/etc/postgresql/8.4/main/postgresql.conf"

# update the instance
aptitude -y update
aptitude -y upgrade

# install postgres
aptitude install -y postgresql

# stop the database
/etc/init.d/postgresql stop

# wait for the EBS volume and mount it
mkdir -p $MOUNT_POINT
while ! mount $MOUNT_DEV $MOUNT_POINT ; do
	echo "waiting for EBS volume ($MOUNT_DEV) ..."
	sleep 10
done
if [ ! -e $MOUNT_POINT/pg_hba.conf ]; then
	echo "Perhaps not the right EBS volume?"
	exit 1;
fi

# change where the data directory is
sed -i "1,$ s;^\(data_directory\).*;\1 = '$MOUNT_POINT/db';" $CONF_FILE

# change where the hba file is
sed -i "1,$ s;^\(hba_file\).*;\1 = '$MOUNT_POINT/pg_hba.conf';" $CONF_FILE

# listen to all interfaces
sed -i "1,$ s;^#\(listen_addresses\).*;\1 = '*';" $CONF_FILE

# start the database
/etc/init.d/postgresql start
