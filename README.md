# PCF Automation Scripts and Tools

This repository contains scripts that can be used to automate Pivotal CloudFoundry (PCF) deployments.

## Automation Jobs

The ```rundeck-jobs``` folder contain rundeck job specifications that are meant to be run from within a Pivotal OpsManager instance. The jobs download this repository and runs the scripts locally as the default Pivotal OpsManager user named ```ubuntu```. The jobs create a workspace directory within the user's home directory where all scripts, configuration and data is maintained.

```
/home/ubuntu/
    workspace/
        downloads/
        scripts/
        configs/
        backups/              <-- Folder where all backups will be written to. 
                                  If possible set this up as a remote NFS mount.
```

To setup rundeck you will need to configure your Pivotal OpsManager VM as a node. If necessary setup an ssh-key to enable Rundeck to ssh into the node without a password challenge. Configure the node to have the following node variables.

* *download-url* - url where the automation script archive can be downloaded from
* *opsman-host* - the host name (or IP) of the OpsManager VM. This needs to be the name/IP used when OpsManager's UAA was initially setup.
* *opsman-user* - the OpsManager's admin user
* *opsman-ssh-user* - the SSH user used to login to the OpsManager VM
* *pcf-config* - the name of the configuration archive that contains the configuration for the ERT deployed by the OpsManager.

Each of the Rundeck jobs also has job specific option variables that need to be set before running the job.

* input variables for *pcf-config.yml*
    - *option.clean* - if set to "1" then the scripts and config workspace folders will be deleted and refreshed
    - *option.opsman-password* - the OpsManager admin user's password
    - *option.opsman-key* - the encryption key required to unlock OpsManager after reboot
    - *option.ldap-bind-password* - the LDAP password if users are sourced from an LDAP backend

* input variables for *pcf-backup.yml*
    - *option.clean* - if set to "1" then the scripts and config workspace folders will be deleted and refreshed
    - *option.opsman-password* - the OpsManager admin user's password
    - *option.opsman-ssh-password* - the OpsManager SSH user's password.
    - *option.opsman-key* - the encryption key required to unlock OpsManager after reboot
    - *option.backup-age* - the maximum age in days of a backup. Older backups will be deleted.

* input variables for *pcf-restore.yml*
    - *option.clean* - if set to "1" then the scripts and config workspace folders will be deleted and refreshed
    - *option.opsman-password* - the OpsManager admin user's password
    - *option.opsman-ssh-password* - the OpsManager SSH user's password.
    - *option.opsman-key* - the encryption key required to unlock OpsManager after reboot
    - *option.timestamp* - the timestamped folder name to be restored. This needs to be copied to the OpsManager VM's ```$HOME/workspace/backups``` folder before the job is run.

Each Rundeck job executes a corresponding runner ```run-*``` shell script, which can be found in the root folder of this repository. These scripts can be run on demand provided the script environment variables have been set. You can inspect the script to determine the required environment variables.

## Restoring a Deployment

Due to a bug in the ```cfops``` utility, which is used to restore the various parts of the PCF deployment, the OpsManager VM needs to be restored manually before running the Rundeck restore job. First the vSphere (IaaS) environment needs to be restored to the same configuration PCF was originally deployed to before it can be restored. Once vSphere has been restored, follow the steps below to restore PCF.

> The following steps have been verified with Pivotal Cloud Foundry OpsManager 1.7.x and may need to change with subsequent major releases.

1. Deploy OpsManager OVA using the same network settings as before.

2. Setup Rundeck SSH keys on deployed OpsManager VM and configure node in Rundeck.

3. Copy the backup to be restored to ```$HOME/workspace/backups```, or if backups were written to shared storage mount it to the OpsManager VM.

4. Import ```$HOME/workspace/backups/$TIMESTAMP/opsmanager/installation.zip``` from the command line as follows.

    ```
    curl -v -k https://$OPSMAN_HOST/api/v0/installation_asset_collection -X POST -F 'installation[file]=@/home/ubuntu/workspace/backups/$TIMESTAMP/opsmanager/installation.zip' -F 'passphrase=$OPSMAN_KEY'
    ```

    or import it via the OpsManager Web UI. Make sure you use the same passphrase that was used for the backed up deployment.

5. Delete the /var/tempest/workspaces/default/deployments/bosh-state.json file on the OpsManager VM. 
    
    > This will force the Bosh director to be redeployed when you hit "Apply Changes" to rebuild the PCF environment.

6. Sign in to the OpsManager Web UI using same admin user and password as backed up environment. 

7. You will observe that some tiles are orange. To fix this simply re-import the stemcells of the tiles that are orange.
    
    > It seems like the import process does not import the stemcell references correctly. 

8. In the JMX Bridge tile navigate to the resources configuration and scale the "OpenTSDB Firehose Nozzle" to 0 instances. 
    
    > This component fails the installation as Ops Manager insists on applying changes to this tile before the ER tile.

9. Click "Apply Changes" to deploy the changes made via Ops Manager UI.

10. Run the restore rundeck job on the restored OpsManager node providing the TIMESTAMP of the backup to restore.

    > This should restore you CloudFoundry configuration as well as deployed applications and services.

11. Restore JMX Bridge Tile's "OpenTSDB Firehose Nozzle" to 1 instance and apply changes.

## Upgrading PCF Ops Manager

The instructions to upgrade PCF OpsManager can be found [here](http://docs.pivotal.io/pivotalcf/1-7/customizing/upgrading-pcf.html#choose-az). You can follow steps 1-4 given above to deploy the new OpsManager OVA and set it up for automation after shutting down the old OpsManager VM. Since you are only upgrading the OpsManager, Bosh and its deployments will be untouched. You may still have to upload missing stemcells and apply changes to synchronize the OpsManager state with that of Bosh, but this should not have any impact on the existing Bosh deployments.

## Configuration

This ```configure-ert``` script is used to automate the configuration of organizations and spaces within the Elastic Runtime or CloudFoundry deployment. It's goal is to treat all aspects of the CloudFoundry tenant configuration as code. The ```example-config``` folder within this repository contains a sample configuration. The script should be run from within a source repository that contains such a configuration.

> Once you start automating the configuration of the Elastic Runtime using this script any manual configuration of Org/Space role and User assignments should be avoided. This script will ensure any manual changes are reverted back unless explicitly disabled in the configuration. It is important that all commits to the configurations are well commented in order to maintain an audit trail.

```
my_config/
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

# LDAP as configured in the ERT security tab. The LDAP bind
# password can be passed in as an argument to the script.
ldap:
    host: ...
    port: ...
    bind_dn: ...
    password: ...
    user_search_base: ...
```

The organization yml file could have one of the following structures. Configuration of an organization can be modified manually and the source config will not be enforced unless the ```delete_missing_entities``` flag is set to true at the organization level.

> It should be noted that if an org or space is renamed manually it will be considered out of sync and could potentially be deleted. In such a case the org may be deleted if the ```delete_missing_entities```is set to true in the ```config.yml``` file and the same will happen to the space if this flag is set to true at the organization level. This means all renaming of organizations and spaces *must* be done within the source configuration.

1. Single Organization

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

2. Multiple Organizations - repeat above as an array of "organizations".

    ```
    ---
    organizations:
    - name: org1
      .
      .
      .
    - name: org2
      .
      .
      .
      
    ```

3. User Organizations - an org will be created for each of the given users having the same name as the user's login name. The default quota and space will be applied to each user's org.

    ```
    ---
    users:
    - john.smith@acme.com
    - laura.peterson@acme.com
    - sam.deva@acme.com

    default_quota: small
    default_space: sandbox
    ```

The script will call the UAA API via the "uaac" CLI to determine if a user exists before assigning him/her to an org or space role. Missing users will be uploaded to UAA and added to the Cloud Controller database. If LDAP configuration is provided, only users that can be queried will be added with the correct UAA attributes. This would enable LDAP users to have immediate access to their respective tenants when they login to CloudFoundry.

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

## Testing if a user has been added to the LDAP search group

To test if a particular user is available in the LDAP search group to source users from. The 'ldapsearch' utility must be installed in the machine the query is run from. A binary for you is available in the ```workspace/scripts/tools``` folder.

```
USER_MAIL=<user's email>
LDAP_SEARCH_QUERY="(&(objectClass=user)(memberOf=cn=WW-PCF,ou=WW,ou=Security Groups,ou=x_NewStructure,dc=int,dc=acme,dc=com)(mail=$USER_MAIL))"

LDAP_HOST=<ldap hostname>
BIND_USER=<ldap user>
BIND_PASSWD=*****
ldapsearch -H $BIND_USER:3268 -D "$BIND_USER" -w "$BIND_PASSWD" -b 'dc=acme,dc=com' "$LDAP_SEARCH_QUERY"
```

