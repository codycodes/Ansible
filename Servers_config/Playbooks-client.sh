#!/bin/bash

# Build a YAML configuration file for Ansible arbitrary num of clients
filepath="~/ansible.yml"

echo "---
 - name: Create instance(s)
   hosts: localhost
   connection: local
   gather_facts: no

   vars:
     service_account_email: account@developer.gserviceaccount.com
     credentials_file: /path/certification.json
     project_id: project-x-154804
     zone: us-west1-a
     machine_type: n1-standard-1
     image1: centos-7
     image2: ubuntu-1604-lts
     " >> $filepath
     
function create_clients {
 echo "- name: Launch Client
   gce:
      instance_names: client$1
      zone: \"{{ zone }}\"
      machine_type: \"{{ machine_type }}\"
      image: \"{{ image2 }}\"
      image_family: \"{{ image2 }}\"
      service_account_email: \"{{ service_account_email }}\"
      credentials_file: \"{{ credentials_file }}\"
      project_id: \"{{ project_id }}\"
      tags: clients
      metadata: '{\"startup-script\" : \"curl https://raw.githubusercontent.com/yolmant/Ansible/master/Servers_config/Clients.bash > config.sh; chmod +x ./config.sh; ./config.sh\"}'
   register: gce

 - debug: msg=\" Client IP = {{ gce.instance_data[0].private_ip }}\"

 - name: adding instance to the groups
   lineinfile:
     dest: /etc/ansible/hosts
     insertafter: '^\[clients\]'
     line: \"{{ gce.instance_data[0].private_ip }}\"
     state: present" >> $filepath

}

echo how many clients would you like Ansible to create?
read number_of_clients # stores the user input in a variable
for client_machine in $(seq 1 $number_of_clients);
do
 create_clients $client_machine;
done     
