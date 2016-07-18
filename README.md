# PCF Automation Scripts and Tools

This repository contains scripts that can be used to automate Pivotal CloudFoundry deployments.

## *configure-ert* script

This script should be used to automate the configuration of organizations and spaces within the Elastic Runtime or CloudFoundry deployment. It's goal is to treat all aspects of the CloudFoundry tenant configuration as code. It should be run from within a source repository that contains the configuration as follows. The "example-config" folder within this repository contains a sample configuration.

> Once you start automating the configuration of the Elastic Runtime using this script any manual configuration of Org/Space role and User assignments should be avoided. This script will ensure any manual changes are reverted back. It is important that all commits to the configurations are well commented in order to maintain an audit trail.

```
root/
    config/
        config.yml            <-- i.e. ldap configuration for ldapsearch query
    security_groups/
        asg1.json             <-- application security group rule file.
        asg2.json
        .
        .
    quotas/
    	default.yml            <-- quotas that can be associated with orgs
    	runaway.yml
    	.
    	.
    	org1/
    		space-quota1.yml   <-- quotas that can be associated with spaces in 'org1'.
    		.
    		.
    organizations/
        org1.yml               <-- organization detail including spaces.
        org2.yml
        .
        .
```

The "config.yml" file should have the following structure

```
---

# Domains within the default-shared-domains list
# will not be reset when synchronizing the list in
# shared-domains
default-shared-domains: [ 'apps.acme.com' ]
shared-domains: [ 'shared1.acme.com', 'shared2.acme.com' ]

# The default staging and running security groups. If you 
# do not provide this these security groups will be reset.
security-groups:
    staging-security-groups: [ 'default_security_group' ]
    running-security-groups: [ 'default_security_group' ]
    
# Deletes any entities that are missing from source.
# Set this to "false" if you want to keep any changes
# done manually.
delete_missing_entities: true

# Configured entities that will be ignored by the script 
# if delete_missing_entities is set to "true".
ignore:
    security-groups: [ 'default_security_group', 'metrics-api' ]
    quotas: [ 'cloud-native-quota', 'p-spring-cloud-services', 'apigee-cf-service-broker-org-quota' ]
    orgs: [ 'system', 'p-spring-cloud-services', 'apigee-cf-service-broker-org', 'cloud-native' ]
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
name: automation-demo
quota: 'runaway'
domains: [ 'staging-auto-demo.acme.com', 'production-auto-demo.acme.com' ]
org-managers: [ 'dev-manager@acme.com' ]
org-auditors: [ 'app-auditor@acme.com' ]
spaces:
- name: Sandbox
  quota: 'development'
  security-groups: [ 'pcf-network' ]
  space-managers: [ 'team-lead@acme.com' ]
  space-developers: [ 'team-lead@acme.com', 'dev1@acme.com', 'dev2@acme.com', 'intern-dev1@acme.com' ]
  space-auditors:  [ 'app-auditor@acme.com' ]
- name: Development
  quota: 'development'
  space-managers: [ 'team-lead@acme.com' ]
  space-developers: [ 'team-lead@acme.com', 'dev1@acme.com', 'dev2@acme.com' ]
  space-auditors:  [ 'app-auditor@acme.com' ]
- name: Staging
  security-groups: [ 'mysql','rabbitmq' ]
  space-managers: [ 'prod-support@acme.com' ]
  space-auditors:  [ 'app-auditor@acme.com' ]
- name: Production
  security-groups: [ 'mysql','rabbitmq' ]
  space-managers: [ 'prod-support@acme.com' ]
  space-auditors:  [ 'app-auditor@acme.com' ]
```

The script will call the UAA API via the "uaac" CLI to determine if a user exists before assigning him/her an org or space role. Missing users will be uploaded to UAA and added to the CC. If an LDAP configuration is provided, only users that can be queried will be added with the correct UAA attributes. This would enable LDAP users to have immediate access to their respective tenants when they login to CloudFoundry.

This script must be run from within the root of source controlled configuration folder as follows:

```
$ configure-ert --help
USAGE: configure_ert [arguments]

Options:
    --help                Show usage options and arguments

Arguments:
    -o, --opsman-host     PCF Ops Manager host
    -u, --opsman-user     PCF Ops Manager login user
    -p, --opsman-passwd   PCF Ops Manager login user's password
    -k, --opsman-key      PCF Ops Manager decryption key only required after restart [optional]

    The following optional arguments can also be provided via config.yml
    -l, --ldap-host       LDAP host
    -t, --ldap-port       LDAP port
    -d, --ldap-bind-dn    LDAP bind distinguished name
    -w, --ldap-password   LDAP bind password
    
$ configure-ert --opsman-host OPS_MANAGER_HOST --opsman-user OPS_MANAGER_USER --opsman-passwd OPS_MANAGER_USER
```
