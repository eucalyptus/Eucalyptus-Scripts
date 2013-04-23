#!/bin/sh

# This is a Vagrant Bootstrap File for getting a CentOS 6.4 + AWS Ruby SDK set up running.
# The base Vagrant box to which this recipe applies can be found here:
#  http://developer.nrel.gov/downloads/vagrant-boxes/CentOS-6.4-x86_64-v20130309.box

echo "BOOM! Welcome to your AWS Ruby SDK environment!" > /etc/motd

# Blast the nameserver to shortcut any DHCP shenanigans
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# Install euca2ools repo and euca2ools
# (NOTE: creds files should be kept in /vagrant shared dir)
yum install -y http://downloads.eucalyptus.com/software/eucalyptus/3.2/centos/6/x86_64/epel-release-6.noarch.rpm
yum install -y http://downloads.eucalyptus.com/software/euca2ools/2.1/centos/6/x86_64/euca2ools-release-2.1.noarch.rpm
yum install -y euca2ools

# Set up ntp for euca2ools
yum install -y ntp
ntpdate pool.ntp.org
# NOTE: don't actually start ntp, since ntp on variable-clock-cycle VMs makes
# for crazytime; just force hourly time sync via cron
# service ntpd start

# Set up eutester and requirements
# (NOTE: eutester git repo is kept in /vagrant shared dir)
yum install -y python-setuptools gcc python-devel git
easy_install eutester

# Install Ruby, Rubygems, and other deps for AWS SDK 
yum install -y ruby ruby-devel rubygems libxml2 rubygem-nokogiri libxml2-devel libxslt-devel patch
gem install aws-sdk -v 1.8.5

# Make a copy of the AWS SDK so you've got a clean copy handy
cp -r /usr/lib/ruby/gems/1.8/gems/aws-sdk-1.8.5 /usr/lib/ruby/gems/1.8/gems/aws-sdk-1.8.5-original

# Go pull the raw patch from Eucalyptus-scripts and stick it in /tmp
wget https://raw.github.com/eucalyptus/Eucalyptus-Scripts/master/AWS-Ruby-SDK-Patches/euca-aws-ruby-sdk.1.8.5.patch -O /tmp/euca-aws-ruby-sdk.1.8.5.patch

# Apply the patch
cd /usr/lib/ruby/gems/1.8/gems/aws-sdk-1.8.5 && patch -p1 < /tmp/euca-aws-ruby-sdk.1.8.5.patch
