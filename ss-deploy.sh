#!/bin/bash

# <UDF name="sshkeyurl" label="The publicly accessible URL of your SSH Key">
# SSHKEYURL=
# <UDF name="hostname" label="Set your system's hostname">
# HOSTNAME=
# <UDF name="fqdn" label="Set your system's fully qualified domain name">
# FQDN=
# <UDF name="db_password" Label="Database root password" />
# <UDF name="hostmaster_email" Label="Contact email address for the Aegir hostmaster" />

PUBLICIP=$(ifconfig | grep -m 1 'inet addr:' | cut -d: -f2 | awk '{ print $1}');
echo "$PUBLICIP $HOSTNAME $FQDN" >> /etc/hosts

mkdir /root/.ssh/
touch /root/.ssh/authorized_keys
wget --no-check-certificate $SSHKEYURL --output-document=/tmp/ss-ssh.pub
cat /tmp/ss-ssh.pub >> /root/.ssh/authorized_keys

echo $HOSTNAME > /etc/hostname
hostname $HOSTNAME

wget -q -O - http://pkg.jenkins-ci.org/debian/jenkins-ci.org.key | apt-key add -
apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
wget -q http://debian.aegirproject.org/key.asc -O- | apt-key add -

echo "deb http://pkg.jenkins-ci.org/debian binary/" >> /etc/apt/sources.list.d/jenkins.list
echo "deb http://ftp.osuosl.org/pub/mariadb/repo/5.5/debian squeeze main" >> /etc/apt/sources.list.d/mariadb.list
echo "deb-src http://ftp.osuosl.org/pub/mariadb/repo/5.5/debian squeeze main" >> /etc/apt/sources.list.d/mariadb.list
echo "deb http://debian.aegirproject.org/ squeeze main" >> /etc/apt/sources.list.d/aegir.list
echo "deb-src http://debian.aegirproject.org/ squeeze main" >> /etc/apt/sources.list.d/aegir.list
echo "deb http://backports.debian.org/debian-backports squeeze-backports main" >> /etc/apt/sources.list.d/backports.list

apt-get update
apt-get --yes upgrade
apt-get --yes dist-upgrade
#dpkg-reconfigure locales

if [ -n $DB_PASSWORD ]
then
	echo "mariadb-server-5.5 mysql-server/root_password password ${DB_PASSWORD}" | debconf-set-selections
	echo "mariadb-server-5.5 mysql-server/root_password_again password ${DB_PASSWORD}" | debconf-set-selections
fi

apt-get -f --yes install apachetop build-essential apache2 apache2-threaded-dev apache2.2-common curl htop rsync patch diffutils cron git git-core wget openssh-blacklist-extra denyhosts libmcrypt4 mariadb-server-5.5 mariadb-server-core-5.5 mariadb-client-5.5 mariadb-client-core-5.5 libmariadbclient18 libmysqlclient18 memcached jenkins daemon openjdk-6-jre procmail jmeter jmeter-http debconf-utils

# installing PHP separately resolves a libmysqlclient18 lib conflict with MariaDB

# Provides more recent versions of PHP
wget -q -O - http://www.dotdeb.org/dotdeb.gpg | apt-key add -
echo "deb http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list.d/dotdeb.list
echo "deb-src http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list.d/dotdeb.list
apt-get update

apt-get -f --yes install php5 php5-apc php5-cgi php5-cli php5-common php5-curl php5-dev php5-gd php5-mcrypt php5-memcache php5-memcached php5-mysql php5-xmlrpc php-pear libapache2-mod-php5
apt-get --yes -t squeeze-backports install drush drush-make

echo "aegir-hostmaster aegir/db_password password ${DB_PASSWORD}" | debconf-set-selections
echo "aegir-hostmaster aegir/db_user string root" | debconf-set-selections
echo "aegir-hostmaster aegir/email string ${HOSTMASTER_EMAIL}" | debconf-set-selections
echo "aegir-hostmaster aegir/db_host string localhost" | debconf-set-selections
echo "aegir-hostmaster aegir/site string ${HOSTNAME}" | debconf-set-selections

apt-get -f --yes install aegir aegir-hostmaster aegir-provision

pear channel-discover pear.drush.org
#pear install drush/drush
pear update-channels
pear upgrade-all
pecl install uploadprogress

if [ "`uname -m | grep 64`" ]
then
	wget --no-check-certificate https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-beta_current_amd64.deb --output-document=/opt/mod-pagespeed-beta_current_amd64.deb
	dpkg -i /opt/mod-pagespeed-beta_current_amd64.deb
else
	wget --no-check-certificate https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-beta_current_i386.deb --output-document=/opt/mod-pagespeed-beta_current_i386.deb
	dpkg -i /opt/mod-pagespeed-beta_current_i386.deb
fi

# Enables clean URLs in Drupal
a2enmod rewrite

# Allows Drupal to leverage client-side browser caches to store static content for a default of 2 weeks
a2enmod expires

# Google PageSpeed module to filter output in realtime as part of content optimization
a2enmod pagespeed

# Apache complains on start and restart if it doesn't have a complete server name. Debian doesn't attempt to set one by default.
echo "ServerName $FQDN" > /etc/apache2/httpd.conf

# Handles fancier progress meter in Drupal file uploads, but we will use uploadprogress PECL instead
echo "apc.rfc1867 = Off" >> /etc/php5/apache2/php.ini

# Increases default 32M to more easily handle more multiple Drupal installs
echo "apc.shm_size = 64M" >> /etc/php5/apache2/php.ini

# Checks the file time on every page load to see if the cache needs to be reset
echo "apc.stat_ctime = On" >> /etc/php5/apache2/php.ini

# Helps Drupal show a progres bar on file uploads
echo "extension=uploadprogress.so" >> /etc/php5/apache2/php.ini

# Allows .htaccess in the default /var/www virtualhost
perl -pi -e 's/(\s+AllowOverride)\s+None$/\1 All/g' /etc/apache2/sites-available/default
perl -pi -e 's/(\s+CustomLog \/var\/log\/apache2\/access\.log combined)$/#\1/g' /etc/apache2/sites-available/default
perl -pi -e 's/(memory_limit =)\s+\d+M(.*?)$/\1 256M\2/g' /etc/php5/apache2/php.ini
perl -pi -e 's/(short_open_tag =)\s+On$/\1 Off/g' /etc/php5/apache2/php.ini
perl -pi -e 's/(expose_php =)\s+On$/\1 Off/g' /etc/php5/apache2/php.ini
perl -pi -e 's/(mysql\.allow_persistent =)\s+On$/\1 Off/g' /etc/php5/apache2/php.ini
perl -pi -e 's/(memory_limit =)\s+\d+M(.*?)$/\1 256M\2/g' /etc/php5/cli/php.ini
perl -pi -e 's/(short_open_tag =)\s+On$/\1 Off/g' /etc/php5/cli/php.ini
perl -pi -e 's/(expose_php =)\s+On$/\1 Off/g' /etc/php5/cli/php.ini
perl -pi -e 's/(mysql\.allow_persistent =)\s+On$/\1 Off/g' /etc/php5/cli/php.ini
/etc/init.d/apache2 force-reload
