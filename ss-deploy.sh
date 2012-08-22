#!/bin/bash

# <UDF name="sshkeyurl" label="The publicly accessible URL of your SSH Key">
# SSHKEYURL=
# <UDF name="hostname" label="Set your system's hostname">
# HOSTNAME=
# <UDF name="fqdn" label="Set your system's fully qualified domain name">
# FQDN=
# <UDF name="db_password" Label="Database root password" />

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
echo "deb-src http://debian.aegirproject.org/ squeeze main" >> /etc/apt/sources.list/aegir.list

apt-get update
apt-get --yes upgrade
apt-get --yes dist-upgrade
#dpkg-reconfigure locales

if [ -n $DB_PASSWORD ]
then
	echo "mariadb-server-5.5 mysql-server/root_password password ${DB_PASSWORD}" | debconf-set-selections
	echo "mariadb-server-5.5 mysql-server/root_password_again password ${DB_PASSWORD}" | debconf-set-selections
fi

apt-get -f --yes install apachetop build-essential apache2 apache2-threaded-dev apache2.2-common curl htop rsync patch diffutils cron git git-core wget openssh-blacklist-extra denyhosts libmcrypt4 mariadb-server-5.5 mariadb-server-core-5.5 mariadb-client-5.5 mariadb-client-core-5.5 libmariadbclient18 libmysqlclient18 memcached jenkins daemon openjdk-6-jre procmail jmeter jmeter-http

# installing PHP separately resolves a libmysqlclient18 lib conflict with MariaDB

wget -q -O - http://www.dotdeb.org/dotdeb.gpg | apt-key add -
echo "deb http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list.d/dotdeb.list
echo "deb-src http://packages.dotdeb.org squeeze all" >> /etc/apt/sources.list.d/dotdeb.list
apt-get update

apt-get -f --yes install php5 php5-apc php5-cgi php5-cli php5-common php5-curl php5-dev php5-gd php5-mcrypt php5-memcache php5-memcached php5-mysql php5-xmlrpc php-pear libapache2-mod-php5 aegir

pear channel-discover pear.drush.org
pear install drush/drush

if [ "`uname -m | grep 64`" ]
then
	wget --no-check-certificate https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-beta_current_amd64.deb --output-document=/opt/mod-pagespeed-beta_current_amd64.deb
	dpkg -i /opt/mod-pagespeed-beta_current_amd64.deb
else
	wget --no-check-certificate https://dl-ssl.google.com/dl/linux/direct/mod-pagespeed-beta_current_i386.deb --output-document=/opt/mod-pagespeed-beta_current_i386.deb
	dpkg -i /opt/mod-pagespeed-beta_current_i386.deb
fi

a2enmod rewrite
a2enmod expires
a2enmod pagespeed

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
