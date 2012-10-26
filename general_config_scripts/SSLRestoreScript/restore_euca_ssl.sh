#!/bin/bash

usage="restore_euca_ssl.sh <backup euca.p12 file>"

if [ -z "$1" ]
then
	echo $usage
	exit 1
fi

backup_file=$1
euca_keystore="euca.p12"
new_backup="${euca_keystore}.restore.backup"

echo "Creating backup of current eucalyptus keystore: $euca_keystore to $new_backup"
cp $euca_keystore $new_backup

echo "Restoring eucalyptus ssl state to use self-signed eucalyptus certificate"
cp $backup_file $euca_keystore

if [ -z "$EUCALYPTUS" ]
then
	echo "'$EUCALYPTUS' not set. Please finish configuration manually"
	echo "run euca-modify-property -p bootstrap.webservices.ssl.server_alias=eucalyptus"
	echo "run euca-modify-property -p bootstrap.webservices.ssl.server_password=eucalyptus"
	exit 0
else
	echo "Setting eucalyptus properties for ssl back to defaults"
	$EUCALYPTUS/usr/sbin/euca-modify-property -p bootstrap.webservices.ssl.server_alias=eucalyptus
	$EUCALYPTUS/usr/sbin/euca-modify-property -p bootstrap.webservices.ssl.server_password=eucalyptus

	echo "Please restart the CLC using 'service eucalyptus-cloud restart' to make changes take effect."
	#echo "Restarting eucalyptus-cloud"
	#service eucalyptus-cloud restart
	#echo "Restart complete"
fi

echo "Restoration of default SSL certificates complete"

