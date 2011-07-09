#!/bin/bash
#
# Script to install redmine and make it use a remote database (postgres)

# update the instance
aptitude -y update
aptitude -y upgrade

# install redmine
aptitude install -y redmine librmagick-ruby libapache2-mod-passenger libdbd-pg-ruby


# configure passenger as default
a2dissite deafult
cp redmine ...
virtualhost *:80
a2ensite redmine

#
