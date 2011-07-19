#!/bin/bash
#
# Script to install redmine and make it use a remote database. The
# database instance uses the PostgresRecipe. 
# This script uses s3curl (modified to work with Eucalyptus).

# variables associated with the cloud/walrus to use: CHANGE them to
# reflect your walrus configuration
WALRUS_NAME="my_walrus"			# arbitrary name 
WALRUS_IP="173.205.188.8"		# IP of the walrus to use
WALRUS_KEY="xxxxxxxxxxxxxxxxxxxx"	# EC2_ACCESS_KEY
WALRUS_ID="xxxxxxxxxxxxxxxxxxxx"	# EC2_SECRET_KEY
WALRUS_URL="http://${WALRUS_IP}:8773/services/Walrus/redmine"	# conf bucket

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

# update the instance
aptitude -y update
aptitude -y upgrade

# install redmine and supporting packages 
aptitude install -y redmine librmagick-ruby libapache2-mod-passenger libdbd-pg-ruby

# since we are using apache2, let's stop it, disable the default web site
# and enable the needed modules (passenger, ssl and rewrite)
service apache2 stop
a2dissite default
a2dissite default-ssl
a2enmod passenger
a2enmod ssl
a2enmod rewrite

# we need the cert and key for ssl configuration
${S3CURL} --id ${WALRUS_NAME} --get -- $WALRUS_URL/ssl-cert.crt > /etc/ssl/certs/ssl-cert.crt
${S3CURL} --id ${WALRUS_NAME} --get -- $WALRUS_URL/ssl-cert.key > /etc/ssl/private/ssl-cert.key

# let's setup redmine's email access and database
${S3CURL} --id ${WALRUS_NAME} --get -- $WALRUS_URL/email.yml > /etc/redmine/default/email.yml
${S3CURL} --id ${WALRUS_NAME} --get -- $WALRUS_URL/database.yml > /etc/redmine/default/database.yml

# get redmine's configuration file and enable it
${S3CURL} --id ${WALRUS_NAME} --get -- $WALRUS_URL/redmine > /etc/apache2/sites-available/redmine
a2ensite redmine

# start apache
service apache2 start
