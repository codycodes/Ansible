#!/bin/bash

#playbook that create the groups
ansible-playbook -v ./groups.yml

#playbook that create instances
ansible-playbook -v ./Server-Clients.yml
sleep 2m

#ssh to each server to verify connectivity
#and run the following command
ansible all -m ping

#playbook that configure the clients
ansible-playbook -v ./clients.yml

#reboot all instances
ansible-playbook -v ./reboot.yml
sleep 1m
