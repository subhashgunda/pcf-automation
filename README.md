# PCF Automation Scripts and Tools

This repository contains scripts that can be used to automate commercial Pivotal CloudFoundry deployments.

## ```configure-ert``` script

This script should be used to automate the configuration of organizations and spaces within CloudFoundry. It's goal is to treat all aspects of the CloudFoundry tenant configuration as code. It should be run from within a source repository that contains the configurations as follows.

```
root/
    config/
        config.yml      <-- i.e. ldap configuration for ldapsearch query
    security_groups/
        asg1.json       <-- application security group rule file.
        asg2.json
        .
        .
    organizations/
        org1.yml        <-- organization detail including spaces, users and asgs.
        org2.yml
        .
        .
        .
```

The organization yml file should have the following structure

```
---
name: <ORGANIZATION NAME>
org-managers: [ <USER_NAME>, ... ]
org-auditors: [ <USER_NAME>, ... ]
spaces:
- name: <SPACE_NAME>
  space-managers: [ <USER_NAME>, ... ]
  space-developers: [ <USER_NAME>, ... ]
  space-auditors: [ <USER_NAME>, ... ]
  security-groups: [ <ASG_NAME>, ... ]  <-- should be one of the security groups
-
-
```

The script will call the UAA API via the "uaac" CLI to determine if a user exists before assigning him/her an org or space role. Missing users will be uploaded to UAA and added to the CC. If an LDAP configuration is provided, only users that can be queried will be added with the correct UAA attributes. This would enable LDAP users to have immediate access to their respective tenants when they login to CloudFoundry.
