#!/usr/bin/env bash
#
# This recipe will update a debian/centos instance automatically after being launched. And can 
# be adapted to install packages for different purposes.
#
# author: Jan Collijs - jan.collijs@inuits.eu
#

# Inititialize parameters
FULL_HOSTNAME="HOSTNAME.DOMAIN"
SHORT_HOST=`echo ${FULL_HOSTNAME} | cut -d'.' -f1`

# Set the hostname with the generic command
hostname ${FULL_HOSTNAME}

# Steps on a CentOS machine
if [ -f /etc/redhat-release ]; then
	
	# Setting the distro specific parameters
	YUM=`which yum`
	RPM=`which rpm`

	# Set the hostname for the system
	sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts
	sed -i "s/localhost.localdomain/${FULL_HOSTNAME}/g" /etc/sysconfig/network

	# Configuration of a custom repo
	cat >>/etc/yum.repos.d/NAME.repo <<EOF
[NAME]
name=NAME
baseurl=http://URL
enabled=1
gpgcheck=0
EOF

	# Update the instance and install a package
	${YUM} -y update
	#${YUM} -y install PACKAGENAME

	# Start the installed service
	service PACKAGENAME start
            
# Steps on a Debian machine            
elif [ -f etc/debian_version ]; then
	      
        # Setting the distro specific parameters
        APTITUDE=`which aptitude`
	APT_KEY=`which apt-key`

	# Set the hostname for the system
        sed -i -e "s/\(localhost.localdomain\)/${SHORT_HOST} ${FULL_HOSTNAME} \1/" /etc/hosts

	# Need to add in the aptitude workarounds for instances.
	# * First disable dialog boxes for dpkg
	# * Add the PPA for ec2-consistent-snapshot or else the update will hang.
	export DEBIAN_FRONTEND=noninteractive
	export DEBIAN_PRIORITY=critical

	${APT_KEY} adv --keyserver keyserver.ubuntu.com --recv-keys BE09C571

	# Update the instance and install a package
	${APTITUDE} update
	${APTITUDE} -y safe-upgrade
	${APTITUDE} -y install PACKAGENAME

	# Download and deploy a custom deb package
	wget http://url of the package
	dpkg -i PACKAGENAME.deb

	# End of script cleanup.
	export DEBIAN_FRONTEND=dialog
	export DEBIAN_PRIORITY=high
	
	# Sends a message when the OS is not CentOS or Debian
	else
		echo "YOU'RE USING A NON SUPPORTED LINUX VERSION FOR THIS RECIPE"
		exit 1
fi
