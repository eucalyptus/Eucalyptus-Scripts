#!/bin/bash
# This script will configure Eucalyptus to use a specified certificate for SSL connections to the Eucalyptus and Walrus service endpoints.
# NOTE: it will NOT configure SSL certificates for the Web-base Admin UI.

echo "Please enter the filename of the certificate to load:"
read cert_file
echo "got $cert_file"

if [ -f "$cert_file" ]
then
	echo "Found file $cert_file"
else
	echo "File not found $cert_file"
	exit 1
fi

echo "Please enter the file name of the private key corresponding to the certificate you just entered:"
read priv_key
echo "Got: $priv_key"

if [ -f "$priv_key" ]
then
	echo "Found file $priv_key"
else
	echo "File not found: $priv_key"
	exit 1
fi


echo "Please enter the alias you would like to use to refer to the certificate:"
read cert_alias
echo "Got: $cert_alias"

if [ -z "$cert_alias" ]
then
	echo "You must enter an alias. Cannot continue"
	exit 1
fi

echo "Please enter a password for the private key export (this is a new password, not an existing one):"
read export_pass
echo "Got: $export_pass"

if [ -z "$export_pass" ]
then
	echo "You must enter an export password. Cannot continue"
	exit 1
fi

echo "If you have a CA certificate or bundle and would like to add the entire certificate chain, enter the filename:"
read ca_cert
echo "Got: $ca_cert"

if [ -z "$ca_cert" ]
then
	echo "No CA cert entered. Not adding during import. Proceeding normally."
else
	if [ -f "$ca_cert" ]
	then
		echo "Found ca file: $ca_cert"

		echo "Please enter the alias to refer to this CA cert:"
		read ca_alias
		if [ -z "$ca_alias" ]
		then
			echo "CA Alias required. Aborting."
			exit 1
		fi
	else	
		echo "File not found: $ca_cert. Cannot proceed"
		exit 1
	fi
fi

echo "Using config:"
echo "Certificate file: $cert_file"
echo "Private key: $priv_key"
echo "Certificate Alias: $cert_alias"
echo "Export Password: $export_pass"
echo "CA Cert: $ca_cert"
echo "CA Alias: $ca_alias"

echo "Continue? (Y|N)"
read resp
if [ "$resp" != "Y" ] && [ $resp != "y" ]
then
	echo "Quiting setup."
	exit 0
else
	echo "Continuing setup."
fi

#Old checks when the script was not interactive
#if (($# < 4 ))
#then
#	echo $usage
#	exit 1
#fi
#cert_file=$1
#priv_key=$2
#cert_alias=$3
#export_pass=$4

echo "Configuring Eucalyptus to use ${cert_file} and ${priv_key} for SSL for Eucalyptus and Walrus API endpoints"
echo "Will import into eucalyptus keystore as $cert_alias"

backup_keystore="euca.p12.backup"
temp_keystore="tempkeystore.p12"
working_eucastore="euca.p12.working"
euca_keystore="euca.p12"

function cleanup_on_error() {
	echo "Cleaning up after error. Restoring backup."
	cp $backup_keystore $euca_keystore
	exit 1
}

echo "Backing up Eucalyptus Keystore: ${euca_keystore} to ${backup_keystore}"
cp $euca_keystore $backup_keystore

echo "Creating a working copy of the eucalyptus keystore $working_eucastore"
cp $euca_keystore $working_eucastore

echo "Exporting certificate and key into a temp pkcs12 store"
if (! openssl pkcs12 -export -in $cert_file -inkey $priv_key -out $temp_keystore -name $cert_alias -password pass:$export_pass )
then
	echo "Error creating $temp_keystore"
	cleanup_on_error
fi

if [ -n "$ca_cert" ]
then
	echo "Looking for jvm ca cert location"
	centos_ca_loc="/usr/lib/jvm/java-1.6.0/jre/lib/security/cacerts"
	ubuntu_ca_loc="/usr/lib/jvm/java-1.6.0-openjdk/jre/lib/security/cacert"
	if [ -f centos_ca_loc ]
	then
		jvm_cafile=$centos_ca_loc
	elif [ -f ubuntu_ca_loc ]
	then
		jvm_cafile=$ubuntu_ca_loc
	else
		echo "JVM cacerts file not found in $centos_ca_loc or $ubuntu_ca_loc. Skipping CA cert import"
	fi
	echo "Adding ca cert and chain to java cacert store"
	if [ -n "$jvm_cafile" ] && (! keytool -importcert -keystore $jvm_cafile -file $ca_cert -alias $ca_alias )
	then
		echo "Error creating $temp_keystore"
		cleanup_on_error
	fi
fi

echo "Importing the temp certficate store into the working copy of the eucalyptus keystore, $working_eucastore"
if (! keytool -importkeystore -srckeystore $temp_keystore -srcstoretype pkcs12 -srcstorepass $export_pass -destkeystore $working_eucastore -deststoretype pkcs12 -deststorepass eucalyptus -alias $cert_alias -srckeypass $export_pass -destkeypass $export_pass )
then
	echo "Error importing $temp_keystore into $working_eucastore"
	cleanup_on_error
fi

echo "Verifing working keystore. You should see $alias in the following output as well as 6 other certs:"
keytool -list -keystore $working_eucastore -storetype pkcs12 -storepass eucalyptus

if (! keytool -list -keystore $working_eucastore -storetype pkcs12 -storepass eucalyptus | grep $cert_alias )
then
	echo "Did not find $cert_alias in the output of the keytool listing... assuming an error occurred."
	cleanup_on_error
else
	echo "Found the $cert_alias cert in the working keystore! Success!"
fi

#echo "Copying the working store, $working_eucastore, to main eucalyptus store $euca_keystore"
if (! cp $working_eucastore $euca_keystore )
then
	echo "Error copying $working_eucastore to $euca_keystore"
	cleanup_on_error
fi

echo "Modifying eucalyptus properties to use new alias/cert for Eucalyptus and Walrus SSL"
if [ -n "$EUCALYPTUS" ]
then
	$EUCALYPTUS/usr/sbin/euca-modify-property -p bootstrap.webservices.ssl.server_alias=$cert_alias
	$EUCALYPTUS/usr/sbin/euca-modify-property -p bootstrap.webservices.ssl.server_password=$export_pass

else
	echo "\nNo '$EUCALYPTUS' setting found. Cannot configure eucalyptus to use new cert automatically.\n"
	echo "Please run 'euca-modify-property -p boostrap.webservices.ssl.server_alias=$cert_alias\n"
	echo "Then run: 'euca-modify-property -p bootstrap.webservices.ssl.server_password=$export_pass\n"
fi

echo "Removing the temp keystore created during import: $temp_keystore"
rm $temp_keystore

echo "Certificate installation complete. Please restart the CLC for the changes to be applied." 
echo "If you have two CLCs in HA-mode you must copy this CLC's euca.p12 file to the secondary CLC, but be sure to back-up the euca.p12 file on the secondary CLC first. Then after copying the euca.p12 file from this CLC to the other CLC and restarting this CLC, restart the secondary CLC as well"

