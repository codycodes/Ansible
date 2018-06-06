#!/bin/bash
#this shell script will install and configure LDAP
#remember that all configuration will be preset with my domains and user

#installing all packages
yum -y install openldap-servers openldap-clients
yum -y install httpd epel-release 
yum -y install phpldapadmin

#enabling all services
systemctl enable slapd.service
systemctl start slapd.service
systemctl enable httpd.service
systemctl start httpd.service

#modify the access in phpldapadmin configuration
sed -i 's,Require local,#Require local\n    Require all granted,g' /etc/httpd/conf.d/phpldapadmin.conf
sed -i -e "397s/.*/\$servers->setValue(\'login\'\,\'attr\'\,\'dn\');/" /etc/phpldapadmin/config.php
sed -i  -e "398s/.*/\/\/ \$servers->setValue(\'login\'\,\'attr\'\,\'uid\');/" /etc/phpldapadmin/config.php

#restarting HTTP service
systemctl restart httpd.service

#notify the system
setsebool -P httpd_can_connect_ldap on

#creating a directory to store .ldif files
mkdir ~/LDAP_config

#creatin a SSHA password for LDAP root
password=torrez
passw=$(slappasswd -s $password -h {SSHA})

#creating .ldif files
sh -c 'cat > ~/LDAP_config/db.ldif' << EF
dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcSuffix
olcSuffix: dc=NTI,dc=local

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootDN
olcRootDN: cn=admin,dc=NTI,dc=local

dn: olcDatabase={2}hdb,cn=config
changetype: modify
replace: olcRootPW
olcRootPW: $passw
EF

sh -c 'cat > ~/LDAP_config/monitor.ldif' << EF
dn: olcDatabase={1}monitor,cn=config
changetype: modify
replace: olcAccess
olcAccess: {0}to * by dn.base="gidNumber=0+uidNumber=0,cn=peercred,cn=external, cn=auth" read by dn.base="cn=admin,dc=NTI,dc=local" read by * none
EF

#creating a certification file
sh -c 'cat > ~/LDAP_config/certs.ldif' << EF
dn: cn=config
changetype: modify
replace: olcTLSCertificateFile
olcTLSCertificateFile: /etc/openldap/certs/NTIcert.pem

dn: cn=config
changetype: modify
replace: olcTLSCertificateKeyFile
olcTLSCertificateKeyFile: /etc/openldap/certs/NTIkey.pem
EF

sh -c 'cat > ~/LDAP_config/base.ldif' << EF
dn: dc=NTI,dc=local
dc: NTI
objectClass: top
objectClass: domain

dn: cn=admin,dc=NTI,dc=local
objectClass: organizationalRole
cn: admin
description: LDAP Manager

dn: ou=ITPeople,dc=NTI,dc=local
objectClass: organizationalUnit
ou: ITPeople

dn: ou=ITGroup,dc=NTI,dc=local
objectClass: organizationalUnit
ou: ITGroup
EF

#creating LDAP certificate
openssl req -new -x509 -nodes -out /etc/openldap/certs/NTIcert.pem -keyout /etc/openldap/certs/NTIkey.pem -days 365 -subj "/C=US/ST=WA/L=Seattle/O=ITcor/OU=ITinfraestructure/CN=server.NTI.local"

#change the permissions to LDAP
chown -R ldap:ldap /etc/openldap/certs/*.pem

#copy the sample database configuration
cp /usr/share/openldap-servers/DB_CONFIG.example /var/lib/ldap/DB_CONFIG
chown ldap:ldap /var/lib/ldap/*

#set up LDAP server
ldapmodify -Y EXTERNAL  -H ldapi:/// -f ~/LDAP_config/db.ldif
ldapmodify -Y EXTERNAL  -H ldapi:/// -f ~/LDAP_config/monitor.ldif
ldapmodify -Y EXTERNAL  -H ldapi:/// -f ~/LDAP_config/certs.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/cosine.ldif
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/nis.ldif 
ldapadd -Y EXTERNAL -H ldapi:/// -f /etc/openldap/schema/inetorgperson.ldif
ldapadd -x -w $password -D "cn=admin,dc=NTI,dc=local" -f ~/LDAP_config/base.ldif

#verify the configuration
slaptest -u

#User password
Upassword=123456
Upass=$(slappasswd -s $Upassword -h {SSHA})

#creating ldif files for group and users
sh -c 'cat > ~/LDAP_config/groups.ldif' << EF
dn: cn=Server,ou=ITGroup,dc=NTI,dc=local
cn: Server
gidnumber: 500
objectclass: posixGroup
objectclass: top
EF

sh -c 'cat > ~/LDAP_config/users.ldif' << EF
dn: cn=ldapuser1,ou=ITPeople,dc=NTI,dc=local
cn: ldapuser1
gidnumber: 500
givenname: ldapuser
homedirectory: /home/ldapuser1
objectclass: inetOrgPerson
objectclass: posixAccount
objectclass: top
sn: 1
uid: ldapuser1
uidnumber: 1000
userpassword: $Upass
EF

ldapadd -x -w $password -D cn=admin,dc=NTI,dc=local -f ~/LDAP_config/groups.ldif

ldapadd -x -w $password -D cn=admin,dc=NTI,dc=local -f ~/LDAP_config/users.ldif

firewall-cmd --permanent --add-service=ldap
firewall-cmd --reload

#disable the anonymous login
sed -i -e "s/\/\/ \$servers->setValue('login','anon_bind',true);/\$servers->setValue('login','anon_bind',false);/" /etc/phpldapadmin/config.php

#configuring Ldap secure
sed -i -e "s/SLAPD_URLS=\"ldapi:\/\/\/ ldap:\/\/\/\"/SLAPD_URLS=\"ldapi:\/\/\/ ldap:\/\/\/ ldaps:\/\/\/\"/" /etc/sysconfig/slapd

#instal SSL
yum -y install mod_ssl

#create a new directory to store the key
mkdir /etc/ssl/private

#change the permission of the new directory
chmod 700 /etc/ssl/private

#creating the certification and key
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/ssl/private/apache.key -out /etc/ssl/certs/apache.crt -subj "/C=US/ST=WA/L=Seattle/O=ITcor/OU=ITinfraestructure/CN=server.NTI.local"
openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048

#include the detail of the phpldapadmin webside to the port 443
sed -i "57s/.*/Alias \/phpldapadmin \/usr\/share\/phpldapadmin\/htdocs\nAlias \/ldapadmin \/usr\/share\/phpldapadmin\/htdocs\nDocumentRoot \"\/usr\/share\/phpldapadmin\/htdocs\"/" /etc/httpd/conf.d/ssl.conf

#comment out and replace the certification and key
sed -i -e "s/SSLProtocol all -SSLv2/#SSLProtocol all -SSLv2/" /etc/httpd/conf.d/ssl.conf
sed -i -e "s/SSLCipherSuite HIGH:MEDIUM:\!aNULL:\!MD5:\!SEED:\!IDEA/#SSLCipherSuite HIGH:MEDIUM:\!aNULL:\!MD5:\!SEED:\!IDEA/" /etc/httpd/conf.d/ssl.conf
sed -i -e "s/SSLCertificateFile \/etc\/pki\/tls\/certs\/localhost.crt/SSLCertificateFile \/etc\/ssl\/certs\/apache.crt/" /etc/httpd/conf.d/ssl.conf
sed -i -e "s/SSLCertificateKeyFile \/etc\/pki\/tls\/private\/localhost.key/SSLCertificateKeyFile \/etc\/ssl\/private\/apache.key/" /etc/httpd/conf.d/ssl.conf

echo '# Begin copied text \
# from https://cipherli.st/ \
# and https://raymii.org/s/tutorials/Strong_SSL_Security_On_Apache2.html \
SSLCipherSuite EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH \
SSLProtocol All -SSLv2 -SSLv3 \
SSLHonorCipherOrder On \
# Disable preloading HSTS for now.  You can use the commented out header line that includes \
# the \"preload\" directive if you understand the implications. \
#Header always set Strict-Transport-Security \"max-age=63072000; includeSubdomains; preload\" \
Header always set Strict-Transport-Security \"max-age=63072000; includeSubdomains\" \
Header always set X-Frame-Options DENY \
Header always set X-Content-Type-Options nosniff \
# Requires Apache >= 2.4 \
SSLCompression off \
SSLUseStapling on \
SSLStaplingCache \"shmcb:logs/stapling-cache(150000)\" \
# Requires Apache >= 2.4.11 \
# SSLSessionTickets Off' >> /etc/httpd/conf.d/ssl.conf

#Restart Ldap service
systemctl restart slapd.service

#Restart the hhtpd service
systemctl restart httpd.service
