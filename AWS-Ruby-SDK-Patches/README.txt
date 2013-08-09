This is a simple patch for the AWS Ruby SDK that makes it compatible with Eucalyptus 3.3.  


INSTALLING AND PATCHING THE AWS RUBY SDK
----------------------------------------
First, install the AWS Ruby SDK, all dependencies, and the Unix patch command.  The following commands work on CentOS 6.4, for example:

yum install -y ruby ruby-devel rubygems libxml2 rubygem-nokogiri libxml2-devel libxslt-devel patch
gem install aws-sdk -v 1.8.5

Next, as root, go into the directory where the ruby gem lives. On CentOS 6.4, for example:

cd /usr/lib/ruby/gems/1.8/gems/aws-sdk-1.8.5-patchtest

Then apply the patchfile.  In this example, we presume you've copied it into /tmp:

patch -p1 < /tmp/euca-aws-ruby-sdk.1.8.5.patch


USING THE PATCHED SDK WITH EUCA AND AWS
---------------------------------------
The patch basically changes the URLs with which the SDK communicates, adding the service path and port to the URLs.  The resultant patched SDK can be used with both AWS and Eucalyptus, but new parameters for endpoint, port, and service path must be set according to the service used.  For example, endpoints for S3:

# Eucalyptus style
conn = Walrus.new({
	:s3_endpoint => 'your.walrus.server.com',
	:s3_port => 8773,
	:s3_service_path => '/services/Walrus/'
})

# AWS style
conn = Walrus.new({
	:s3_endpoint => 's3.amazonaws.com',
	:s3_port => 443,
	:s3_service_path => '/'
})

