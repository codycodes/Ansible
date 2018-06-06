#!/bin/bash
#installing NFS utilities
yum -y install nfs-utils

#create the directory that will be shared
mkdir -p /NFS/sharedfiles

#change the permission to share this directory
chmod -R 777 /NFS/sharedfiles

#eanble and start the nfs services
systemctl enable nfs-server
systemctl enable nfs-idmap
systemctl enable nfs-lock
systemctl enable rpcbind
systemctl start rpcbind
systemctl start nfs-server
systemctl start nfs-idmap
systemctl start nfs-lock

#create a exports file in /etc/ to create entries to our server
sh -c 'cat > /etc/exports' << EF
/NFS/sharedfiles    *(rw,sync,no_all_squash)
EF

#export the shared directory
exportfs -r

#Allow Root login on ssh for ansible
sed -i 's/PermitRootLogin no/PermitRootLogin yes/' /etc/ssh/sshd_config

#restart ssh service
systemctl restart sshd

#add the NFS service to the firewall to allow the access from the extern 
firewall-cmd --permanent --zone public --add-service nfs
firewall-cmd --permanent --zone public --add-service rpc-bind
firewall-cmd --permanent --zone public --add-service mountd
firewall-cmd --reload
