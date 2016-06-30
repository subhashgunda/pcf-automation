# PCF Automation Scripts and Tools

This repository contains scripts that can be used to automate Pivotal CloudFoundry deployments.

## ```configure-ert``` script

This script should be used to automate the configuration of organizations and spaces within the Elastic Runtime or CloudFoundry deployment. It's goal is to treat all aspects of the CloudFoundry tenant configuration as code. It should be run from within a source repository that contains the configuration as follows.

> Once you start automating the configuration of the Elastic Runtime using this script any manual configuration of Org/Space role and User assignments should be avoided. This script will ensure any manual changes are reverted back. It is important that all commits to the configurations are well commented in order to maintain an audit trail.

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

The "config.yml" file should have the following structure

```
---
# Configured entities that will be ignored by the script
ignore:
    security_groups: [ 'default_security_group', 'metrics-api' ]
    orgs: [ 'system', 'p-spring-cloud-services', 'apigee-cf-service-broker-org' ]
    users: [ 'admin' ]
# LDAP as configured in the ERT security tab
ldap:
    host: ...
    port: ...
    bind_dn: ...
    password: ...
    user_search_base: ...
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

This script must be run from within the root of source controlled configuration folder as follows:

```
$ configure-ert --help
USAGE: configure_pcf [options]

Options:
    -h, --opsman_host     PCF Ops Manager host
    -u, --opsman_user     PCF Ops Manager login user
    -p, --opsman_passwd   PCF Ops Manager login user's password
    -k, --opsman_key      PCF Ops Manager decryption key only required after restart

$ configure-ert --opsman_host OPS_MANAGER_HOST --opsman_user OPS_MANAGER_USER --opsman_passwd OPS_MANAGER_USER
```
