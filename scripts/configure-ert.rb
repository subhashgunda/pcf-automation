#!/usr/bin/env ruby

require 'set'
require 'json'
require 'yaml'

def validate()

	if !Dir.exist?('config') ||
		!Dir.exist?('security-groups') ||
		!Dir.exist?('quotas') ||
		!Dir.exist?('organizations')

		puts 'ERROR: The configuration script needs to be run from within a configuration repository folder.'
		exit 1
	end
end

def show_usage()

	puts "USAGE: configure_ert [arguments]"
	puts
	puts "Options:"
	puts "	--help               Show usage options and arguments"
	puts
	puts "Arguments:"
	puts "	-o, --opsman-host    PCF Ops Manager host"
	puts "	-u, --opsman-user    PCF Ops Manager login user"
	puts "	-p, --opsman-passwd  PCF Ops Manager login user's password"
	puts "	-k, --opsman-key     PCF Ops Manager decryption key only required after restart [optional]"
	puts "  -t, --test           Run in test mode without making any actual updates"
	puts "  -v, --verbose        Output detail logs of commands being executed"
	puts
	puts "	The following optional arguments can also be provided via config.yml"
	puts "	-l, --ldap-url       LDAP url"
	puts "	-d, --ldap-bind-dn   LDAP bind distinguished name"
	puts "	-w, --ldap-password  LDAP bind password"
	puts

	exit 0
end

def has_option(key_short, key_long)
	!ARGV.index { |a| a == key_short || a == key_long }.nil?
end

def get_arg_value(key_short, key_long, required = false)
	i = ARGV.index { |a| a == key_short || a == key_long }
	value = ARGV[i + 1] if !i.nil?
	if required and value.nil?
		show_usage
	end
	value
end

def generate_password(length = 8)
	@pwd_chars ||= [('a'..'z'), ('A'..'Z'), ('0'..'9')].map { |i| i.to_a }.flatten
	(0...length).map { @pwd_chars[rand(@pwd_chars.length)] }.join
end

def exec_cmd(cmd, message, simulate = false)
	puts "DEBUG: Exec => #{cmd.split.join(' ')}" if @verbose_mode
	if !simulate
		out = %x(#{cmd})
		if !$?.success?
			puts "ERROR: #{message}"
			puts out
			exit 1
		end
		puts "DEBUG: Output => #{out}" if @verbose_mode
		out
	else
		puts "SKIPPING: #{cmd.split.join(' ')}"
		""
	end
end

def quota_detail(entity)
	{
		'allow-paid-service-plans' => entity['non_basic_services_allowed'],
		'instance-memory' => entity['instance_memory_limit'],
		'total-app-instances' => entity['app_instance_limit'],
		'total-memory' => entity['memory_limit'],
		'total-routes' => entity['total_routes'],
		'total-services' => entity['total_services'],
		'total_route_ports' => entity['total_reserved_route_ports']
	}
end

def update_quotas(cf_quota_group_list, cf_quota_map, org_name = nil)

	quota_dir = org_name.nil? ? 'quotas' : 'quotas/' + org_name
	create_cmd = org_name.nil? ? 'create-quota' : 'create-space-quota'
	update_cmd = org_name.nil? ? 'update-quota' : 'update-space-quota'

	Dir.glob("#{quota_dir}/*.yml") do |quota_file|

		name = File.basename(quota_file, ".yml")
		cf_quota_new = YAML.load_file(quota_file)

		if cf_quota_group_list.include?(name)

			cf_quota = cf_quota_map[name]
			cf_quota.delete('total_route_ports') if !org_name.nil?

			if cf_quota_new != cf_quota
				puts "Updating quota '#{name}'."
				exec_cmd( "#{@cf_cli} #{update_cmd} #{name} \
					-a #{cf_quota_new['total-app-instances']} \
					-i #{cf_quota_new['instance-memory']}M \
					-m #{cf_quota_new['total-memory']}M \
					-r #{cf_quota_new['total-routes']} \
					-s #{cf_quota_new['total-services']} \
					#{cf_quota_new['allow-paid-service-plans'] ? '--allow-paid-service-plans' : '--disallow-paid-service-plans'}",
					"Unable to update quota '#{name}'.", @test_mode )
			end
		else
			puts "Creating quota '#{name}'."
			exec_cmd( "#{@cf_cli} #{create_cmd} #{name} \
				-a #{cf_quota_new['total-app-instances']} \
				-i #{cf_quota_new['instance-memory']}M \
				-m #{cf_quota_new['total-memory']}M \
				-r #{cf_quota_new['total-routes']} \
				-s #{cf_quota_new['total-services']} \
				#{cf_quota_new['allow-paid-service-plans'] ? '--allow-paid-service-plans' : ''}",
				"Unable to create quota '#{name}'.", @test_mode )
		end

		cf_quota_group_list.delete_if { |n| n == name }
	end

	cf_quota_group_list
end

def user_exists?(user)
	%x(#{@uaac} user get '#{user}')
	$?.success?
end

def add_user(user)

	puts "Adding user '#{user}'."

	user_data = {
		'userName' => user,
		'origin' => 'uaa',
		'emails' => [
			{ 'value' => user }
		]
	}

	if !@ldap_url.nil?

		if @ldap_password.nil?
			puts "ERROR: The password for ldap bind user #{@ldap_bind_dn} was not provided."
			exit 1
		end

		user_data['origin'] = 'ldap'

		user_search_query = eval("\"" + @ldap_config['user-search-query'] + "\"")

		user_data['externalId'] = exec_cmd( "#{@ldapsearch_cli} -H #{@ldap_url} \
			-D '#{@ldap_bind_dn}' -w '#{@ldap_password}' \
			-b '#{@ldap_config['user-search-base']}' '#{user_search_query}' dn | awk '/dn: /{ print substr($0, 5, length($0)-5) }'",
			"LDAP query for user '#{user}' failed." )

		if user_data['externalId'].empty?
			puts "Unable to find LDAP user with mail attributed '#{user}'. This user will be skipped."
			return false
		end

		user_detail = JSON.parse(exec_cmd("#{@uaac} curl -H 'Content-Type: application/json' -k /Users -X POST -d '#{user_data.to_json}'",
			'Unable to create user in UAA.').split(/RESPONSE BODY:/)[1])

		exec_cmd( "#{@cf_cli} curl /v2/users -d '{ \"guid\": \"#{user_detail['id']}\" }' -X POST",
			'Unable to add user to CC.', @test_mode )
	else
		exec_cmd( "#{@cf_cli} create-user #{user} 'ChangeMe'",
			'Unable to create user to #{user}.', @test_mode )
	end

	return true
end

def set_org_role(user_list, existing_list, org, role, delete_missing_entities)

	user_list = user_list.map(&:downcase)
	existing_list = existing_list.map(&:downcase)

	user_list.each { |u|
		if !existing_list.include?(u) &&
            (user_exists?(u) || add_user(u))
            puts "Setting #{role} role for user #{u} in org '#{org}'."
            exec_cmd( "#{@cf_cli} set-org-role #{u} '#{org}' #{role}",
                "Unable to set org role.", @test_mode )
		end
		existing_list.delete_if { |n| n==u }
	}
	existing_list.each{ |u|
		puts "Removing #{role} role for user #{u} in org '#{org}'."
		exec_cmd( "#{@cf_cli} unset-org-role #{u} '#{org}' #{role}",
			"Unable to unset org role.", @test_mode )
	} if delete_missing_entities
end

def set_space_role(user_list, existing_list, org, space, role, delete_missing_entities)

	user_list = user_list.map(&:downcase)
	existing_list = existing_list.map(&:downcase)

	user_list.each { |u|
		if !existing_list.include?(u) &&
            (user_exists?(u) || add_user(u))
            puts "Setting #{role} role for user #{u} in org '#{org}' and space '#{space}'."
            exec_cmd( "#{@cf_cli} set-space-role #{u} '#{org}' '#{space}' #{role}",
                "Unable to set space role.", @test_mode )
		end
		existing_list.delete_if { |n| n==u }
	}
	existing_list.each{ |u|
		puts "Removing #{role} role for user #{u} in org '#{org}' and space '#{space}'."
		exec_cmd( "#{@cf_cli} unset-space-role #{u} '#{org}' '#{space}' #{role}",
			"Unable to unset org role.", @test_mode )
	} if delete_missing_entities
end

show_usage if has_option('-h', '--help')

validate()

opsman_host = get_arg_value('-o', '--opsman-host', true)
opsman_user = get_arg_value('-u', '--opsman-user', true)
opsman_passwd = get_arg_value('-p', '--opsman-passwd', true)
opsman_key = get_arg_value('-k', '--opsman-key')

@test_mode = has_option('-t', '--test')
@verbose_mode = has_option('-v', '--verbose')

@config = File.exist?('config/config.yml') ? YAML.load_file('config/config.yml') : []
@ldap_config = @config['ldap'] || {}

@ldap_url = get_arg_value('-l', '--ldap-url') || @ldap_config['url']
@ldap_bind_dn = get_arg_value('-d', '--ldap-bind-dn') || @ldap_config['bind-dn']
@ldap_password = get_arg_value('-w', '--ldap-password') || @ldap_config['password']

@enable_ssh = @config['enable-ssh']
@delete_missing_entities = @config['delete-missing-entities']
ignore_security_groups = @config['ignore']['security-groups']
ignore_quotas = @config['ignore']['quotas']
ignore_orgs = @config['ignore']['orgs']
ignore_users = @config['ignore']['users']

if File.exist?('/home/tempest-web/tempest/web/vendor/bosh/Gemfile')
	@uaac='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/uaac/Gemfile bundle exec uaac'
	@bosh='BUNDLE_GEMFILE=/home/tempest-web/tempest/web/vendor/bosh/Gemfile bundle exec bosh'
else
	@uaac='uaac'
	@bosh='bosh'
end

os = ( RUBY_PLATFORM =~ /darwin/ ? 'darwin'
	: RUBY_PLATFORM =~ /linux/ ? 'linux' : '' )

curdir = File.expand_path(File.dirname(__FILE__) + "/..")
@cf_cli = curdir + '/tools/' + os + '/cf'
@ldapsearch_cli = curdir + '/tools/' + os + '/ldapsearch'

if !File.exist?(@cf_cli)
	puts "ERROR: Unsupported operating system."
	exit 1
end

#
# Login to OpsManager
#

exec_cmd( "#{@uaac} target https://#{opsman_host}/uaa --skip-ssl-validation",
	'Unable to target Ops Manager\'s UAA' )

if !opsman_key.nil?

	puts "Unlocking Ops Manager."
	exec_cmd( "curl -k https://#{opsman_host}/api/v0/unlock \
		-X PUT \
		-H 'Content-Type: application/x-www-form-urlencoded' \
		-d 'passphrase=#{opsman_key}' 2> /dev/null",
		'Unable to unlock Ops Manager.')

	retries = 6
	while retries>0
		puts "Logging into PCF Ops Manager."
		res = %x(#{@uaac} token owner get opsman #{opsman_user} -s '' -p '#{opsman_passwd}')
		if $?.success?
			break
		end
		puts "Waiting 10s for Ops Manager authentication system to come up."
		sleep 10
		retries -= 1
	end
	if retries==0
		puts "ERROR: Unable to log into PCF Ops Manager as " +
			"authentication system is taking too long to initialize."
		exit 1
	end
else
	puts "Logging into PCF Ops Manager."
	exec_cmd("#{@uaac} token owner get opsman #{opsman_user} -s '' -p '#{opsman_passwd}'",
		'Unable to get uaac token from Ops Manager UAA.')
end

access_token = exec_cmd("#{@uaac} context | awk '/access_token:/{ print $2 }'",
	'Unable to get uaac access token value from context.')

#
# Retrieve Bosh and Elastic Runtime credentials
#

puts "Retrieving credentials."

installation_settings = JSON.parse( 
	exec_cmd( "curl -k https://#{opsman_host}/api/installation_settings \
		-X GET -H 'Authorization: Bearer #{access_token}' 2> /dev/null",
		'Unable to retrieve the installation settings.' ) )

installed_products = JSON.parse( 
	exec_cmd( "curl -k https://#{opsman_host}/api/v0/staged/products \
		-X GET -H 'Authorization: Bearer #{access_token}' 2> /dev/null",
		'Unable to retrieve list of installed products' ) )

cf_product_id = installed_products.select{ |p| p['type']=='cf'}.first['guid']

bosh_director_credentials = JSON.parse(
	exec_cmd( "curl -k https://#{opsman_host}/api/v0/deployed/director/credentials/director_credentials \
		-X GET -H 'Authorization: Bearer #{access_token}' 2> /dev/null",
		'Unable to retrieve Bosh Directory credentials' ) )['credential']['value']

cf_admin_credentials = JSON.parse(
	exec_cmd( "curl -k https://#{opsman_host}/api/v0/deployed/products/#{cf_product_id}/credentials/.uaa.admin_credentials \
		-X GET -H 'Authorization: Bearer #{access_token}' 2> /dev/null",
		'Unable to retrieve ERT admin credentials' ) )['credential']['value']

cf_uaa_admin_client_credentials = JSON.parse(
	exec_cmd( "curl -k https://#{opsman_host}/api/v0/deployed/products/#{cf_product_id}/credentials/.uaa.admin_client_credentials \
		-X GET -H 'Authorization: Bearer #{access_token}' 2> /dev/null",
		'Unable to retrieve ERT admin credentials') )['credential']['value']

cloud_controller_settings = installation_settings['products'].select{ |p| p['guid']==cf_product_id }
	.first['jobs'].select{ |j| j['installation_name']=='cloud_controller' }.first

cf_system_domain = cloud_controller_settings['properties'].select{ |p| p['identifier']=='system_domain' }.first['value']
cf_apps_domain = cloud_controller_settings['properties'].select{ |p| p['identifier']=='apps_domain' }.first['value']

cf_base_shared_domain = cf_apps_domain[/[-_a-zA-Z0-9]+\.(.*)/, 1]

#
# Login to Elastic Runtime
#

puts "Logging into CloudFoundry."
exec_cmd( "#{@cf_cli} login -a https://api.#{cf_system_domain} \
	-u #{cf_admin_credentials['identity']} \
	-p #{cf_admin_credentials['password']} \
	-o system -s system --skip-ssl-validation",
	'Unable login to the CloudController API.' )

puts "Logging into CloudFoundry UAA."
exec_cmd( "#{@uaac} target --skip-ssl-validation https://uaa.#{cf_system_domain}",
	"Unable to set the CloudFoundry UAA target" )
exec_cmd( "#{@uaac} token client get #{cf_uaa_admin_client_credentials['identity']} \
    -s #{cf_uaa_admin_client_credentials['password']}",
	'Unable login to the CloudController UAA.' )

#
# Update shared domains
#

if @config.has_key?('shared-domains')

	default_shared_domains = (@config['default-shared-domains'] || []) + [ cf_apps_domain ]
	cf_shared_domains = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/shared_domains",
		'Unable to retrieve shared domains.'))['resources']
		.map{ |d| d['entity']['name'] }
		.select{ |n| !default_shared_domains.include?(n) }

	(@config['shared-domains'] || []).each { |d|

		if d=~/^[-_a-zA-Z0-9]+$/
			d += '.' + cf_base_shared_domain
		end

		if !cf_shared_domains.include?(d)
			puts "Creating shared domain #{d}."
			exec_cmd( "#{@cf_cli} create-shared-domain #{d}",
				"Unable create shared domain #{d}.", @test_mode )
		end
		cf_shared_domains.delete_if { |n| n == d }
	}
	cf_shared_domains.each{ |n|
		puts "Deleting shared domain #{n}."
		exec_cmd( "#{@cf_cli} delete-shared-domain -f #{n}",
			"Unable delete shared domain #{n}.", @test_mode )
	} if @delete_missing_entities
end

#
# Update security groups
#

cf_security_groups = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/security_groups",
	'Unable to retrieve security groups.'))['resources']

cf_security_group_list = cf_security_groups.map{ |s| s['entity']['name'] }
	.select { |n| !ignore_security_groups.include?(n) }

Dir.glob('security-groups/*.json') do |rule_file|

	name = File.basename(rule_file, ".json")

	if cf_security_group_list.include?(name)

		existing_rule = cf_security_groups.select{ |r| r['entity']['name']==name }.first['entity']['rules']
		new_rule = JSON.parse(IO.read(rule_file))
		if !existing_rule.eql?(new_rule)
			puts "Updating security group rule '#{name}'."
			exec_cmd( "#{@cf_cli} update-security-group #{name} #{rule_file}",
				"Unable to update security group #{name}.", @test_mode )
		end
	else
		puts "Adding security group rule '#{name}'."
		exec_cmd( "#{@cf_cli} create-security-group #{name} #{rule_file}",
			"Unable to create security group #{name}.", @test_mode )
	end

	cf_security_group_list.delete_if { |n| n == name }
end

#
# Update staging and running security groups
#

if @config.has_key?('default-security-groups')
	[ 'staging', 'running' ].each { |type|

		cf_asg_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/config/#{type}_security_groups",
			"Unable to retrieve the list of #{type} security groups."))['resources']
			.map{ |asg| asg['entity']['name'] }

		(@config['default-security-groups']["#{type}"] || []).each { |asg_name|

			if !cf_asg_list.include?(asg_name)
				puts "Binding ASG '#{asg_name}' to #{type} security groups."
				exec_cmd( "#{@cf_cli} bind-#{type}-security-group #{asg_name}",
					"Unable to bind ASG '#{asg_name}' to #{type} security group.", @test_mode )
			end
			cf_asg_list.delete_if { |n| n == asg_name }
		}

		cf_asg_list.each{ |n|
			puts "Unbinding ASG '#{n}' from #{type} security groups."
			exec_cmd( "#{@cf_cli} unbind-#{type}-security-group #{n}",
				"Unable to unbind ASG '#{n}' from #{type} security groups.", @test_mode )
		}
	}
end

#
# Update Org Quotas
#

cf_quotas = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/quota_definitions",
	'Unable to retrieve organization quota definitions.'))['resources']

cf_quota_map = {}
cf_quotas.each{ |q|
	quota_name = q['entity']['name']
	cf_quota_map[quota_name] = quota_detail(q['entity']) if !ignore_quotas.include?(quota_name)
}

cf_quota_group_list = update_quotas(cf_quota_map.keys, cf_quota_map)

#
# Create orgs and spaces and set their quotas, security groups and users
#

cf_orgs = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/organizations",
	'Unable to retrieve organizations.'))['resources']
cf_org_list = cf_orgs.map{ |s| s['entity']['name'] }
	.select { |n| !ignore_orgs.include?(n) }

cf_spaces = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/spaces",
	'Unable to retrieve spaces.'))['resources']
cf_spaces_map = {}
cf_spaces.each{ |s|
	cf_spaces_map[s['entity']['organization_guid']] =
		(cf_spaces_map[s['entity']['organization_guid']] || []) + [ s['entity']['name'] ]
}

cf_space_quotas = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/space_quota_definitions",
	'Unable to retrieve space quota definitions.'))['resources']
cf_space_quota_map = {}
cf_space_quotas.each{ |q|
	org_id = q['entity']['organization_guid']
	cf_space_quota_map[org_id] = {} if !cf_space_quota_map.has_key?(org_id)
	cf_space_quota_map[org_id][q['entity']['name']] = quota_detail(q['entity'])
}

Dir.glob('organizations/*.yml') do |org_file|

	orgs = []
	org_data = YAML.load_file(org_file)

	if org_data.has_key?('users')

		org_data['users'].each do |user|
			orgs += [ {

				'name' => user,
				'quota' => org_data['default_quota'],
				'org-managers' => [ user ],
				'spaces' => [ {
					'name' => org_data['default_space'],
					'space-managers' => [ user ],
					'space-developers' => [ user ]
				} ]
			} ]
		end

	elsif org_data.has_key?('organizations')
		orgs = org_data['organizations']
	else
		orgs += [ org_data ]
	end

	orgs.each do |org_details|

		org_name = org_details['name']
		org_delete_missing_entities = org_details['delete-missing-entities'] || false

		puts "Configuring organization '#{org_name}'."

		#
		# Create org
		#

		if !cf_org_list.include?(org_name)
			puts "Creating organization '#{org_name}'."
			exec_cmd( "#{@cf_cli} create-org '#{org_name}'",
				"Unable to create organization '#{org_name}'.", @test_mode )

			if @test_mode
				puts "Skipping configuration of new org '#{org_name}' in test mode."
				next
			end
		end

		exec_cmd( "#{@cf_cli} target -o '#{org_name}'",
			"Unable to target org '#{org_name}'.").chomp
		org_id = exec_cmd( "#{@cf_cli} org '#{org_name}' --guid",
			"Unable to retrieve id of org '#{org_name}'.").chomp

		#
		# Set org quota
		#

		current_quota = exec_cmd( "#{@cf_cli} org '#{org_name}' | awk '/quota:/{ print $2 }'", 
			"Unable to determine current quota for organization '#{org_name}'." ).chomp

		if org_details.has_key?('quota') && current_quota != org_details['quota']

			exec_cmd( "#{@cf_cli} set-quota '#{org_name}' '#{org_details['quota']}'",
				"Unable to set quota for organization '#{org_name}'.", @test_mode )
		end 

		#
		# Create space quotas
		#

		if cf_space_quota_map.has_key?(org_id)
			cf_space_quota_group_list = update_quotas(cf_space_quota_map[org_id].keys, cf_space_quota_map[org_id], org_name)
		else
			cf_space_quota_group_list = update_quotas([], {}, org_name)
		end

		#
		# Set org owned private domains
		#

		org_domain_list =  JSON.parse( exec_cmd("#{@cf_cli} curl /v2/organizations/#{org_id}/domains",
			"Unable to retrieve private domains for org #{org_name}.") )['resources']
			.select{ |d| d['entity']['owning_organization_guid']==org_id }
			.map{ |d| d['entity']['name'] }

		(org_details['domains'] || []).each { |d|

			if !org_domain_list.include?(d)
				puts "Creating domain #{d} for org #{org_name}."
				exec_cmd( "#{@cf_cli} create-domain '#{org_name}' '#{d}'",
					"Unable domain #{d} for org #{org_name}.", @test_mode)
			end
			org_domain_list.delete_if { |n| n == d }
		}
		org_domain_list.each{ |n|
			puts "Deleting domain #{n} from org #{org_name}."
			exec_cmd( "#{@cf_cli} delete-domain -f #{n}",
				"Unable to domain #{n}.", @test_mode )
		} if org_delete_missing_entities

		#
		# Add users to org and set roles
		#

		cf_org_manager_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/organizations/#{org_id}/managers",
			'Unable to retrieve the list of users who are org managers.'))['resources']
			.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
		set_org_role(org_details['org-managers'] || [], cf_org_manager_list,
			org_name, 'OrgManager', org_delete_missing_entities)

		cf_org_billing_manager_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/organizations/#{org_id}/billing_managers",
			'Unable to retrieve the list of users who are billing managers.'))['resources']
			.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
		set_org_role(org_details['billing-managers'] || [], cf_org_billing_manager_list,
			org_name, 'BillingManager', org_delete_missing_entities)

		cf_org_auditor_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/organizations/#{org_id}/auditors",
			'Unable to retrieve the list of users who are org auditors.'))['resources']
			.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
		set_org_role(org_details['org-auditors'] || [], cf_org_auditor_list,
			org_name, 'OrgAuditor', org_delete_missing_entities)

		cf_space_list = cf_spaces_map[org_id] || []

		org_details['spaces'].each{ |s|

			space_name = s['name']

			#
			# Create space
			#

			if cf_space_list.nil? || !cf_space_list.include?(space_name)
				puts "Creating space '#{s}'."
				exec_cmd( "#{@cf_cli} create-space #{space_name} -o '#{org_name}'",
					"Unable to create space '#{space_name}' in organization '#{org_name}'.", @test_mode )

				if @test_mode
					puts "Skipping configuration of new space '#{space_name}' in test mode."
					next
				end
			end

			space_id = exec_cmd( "#{@cf_cli} space '#{space_name}' --guid",
				"Unable to retrieve id of space #{space_name}." ).chomp

			#
			# Set space ssh access
			#
			%x(#{@cf_cli} space-ssh-allowed #{space_name} | grep 'enabled' >/dev/null 2>&1)
			if (@enable_ssh && !s.has_key?('enable-ssh')) || s['enable-ssh'] 
				exec_cmd( "#{@cf_cli} allow-space-ssh #{space_name}",
					"Unable to enable ssh access to space '#{space_name}' in organization '#{org_name}'.", 
					@test_mode ) if !$?.success?
			else				
				exec_cmd( "#{@cf_cli} disallow-space-ssh #{space_name}'",
					"Unable to disable ssh access '#{space_name}' in organization '#{org_name}'.", 
					@test_mode ) if $?.success?
			end

			#
			# Set space quota
			#

			current_quota_name = exec_cmd( "#{@cf_cli} space '#{space_name}' | awk '/Space Quota/{ print $3 }'",
				"Unable to parse current quota for '#{space_name}' in organization '#{org_name}'." ).chomp
			new_quota_name = s['quota'] || ''

			if current_quota_name != new_quota_name
				puts "Update quota for space '#{space_name}'."
				exec_cmd( "#{@cf_cli} unset-space-quota '#{space_name}' '#{current_quota_name}'",
					"Unable to unset space quota for space '#{space_name}' in organization '#{org_name}'.", @test_mode ) if !current_quota_name.empty?
				exec_cmd( "#{@cf_cli} set-space-quota '#{space_name}' '#{new_quota_name}'",
					"Unable to set space quota for space '#{space_name}' in organization '#{org_name}'.", @test_mode ) if !new_quota_name.empty?
			end

			#
			# Associated ASGs with space
			#

			cf_space_asg_list = JSON.parse( exec_cmd("#{@cf_cli} curl /v2/spaces/#{space_id}/security_groups",
				'Unable to retrieve the list of security groups for space #{space_name}.') )['resources']
				.select{ |asg| !asg['entity']['running_default'] && !asg['entity']['staging_default'] }
				.map{ |asg| asg['entity']['name'] }

			(s['security-groups'] || []).each { |asg_name|

				if !cf_space_asg_list.include?(asg_name)
					puts "Binding ASG '#{asg_name}' to space '#{space_name}'."
					exec_cmd( "#{@cf_cli} bind-security-group #{asg_name} #{org_name} #{space_name}",
						"Unable to bind ASG '#{asg_name}' from space '#{space_name}'.", @test_mode )
				end

				cf_space_asg_list.delete_if { |n| n == asg_name }
			}
			cf_space_asg_list.each{ |n|
				puts "Unbinding ASG '#{n}' from space '#{space_name}'."
				exec_cmd( "#{@cf_cli} unbind-security-group #{n} #{org_name} #{space_name}",
					"Unable to unbind ASG '#{n}' from space '#{space_name}'.", @test_mode )
			} if org_delete_missing_entities

			#
			# Add users to space and set roles
			#

			cf_space_manager_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/spaces/#{space_id}/managers",
				'Unable to retrieve the list of users who are space managers.'))['resources']
				.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
			set_space_role(s['space-managers'] || [], cf_space_manager_list,
				org_name, space_name, 'SpaceManager', org_delete_missing_entities)

			cf_space_developer_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/spaces/#{space_id}/developers",
				'Unable to retrieve the list of users who are space developers.'))['resources']
				.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
			set_space_role(s['space-developers'] || [], cf_space_developer_list,
				org_name, space_name, 'SpaceDeveloper', org_delete_missing_entities)

			cf_space_auditor_list = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/spaces/#{space_id}/auditors",
				'Unable to retrieve the list of users who are space auditors.'))['resources']
				.map{ |s| s['entity']['username'] }.select { |n| !ignore_users.include?(n) }
			set_space_role(s['space-auditors'] || [], cf_space_auditor_list,
				org_name, space_name, 'SpaceAuditor', org_delete_missing_entities)

			cf_space_list.delete_if { |n| n == space_name }
		}
		cf_space_list.each{ |n|
			puts "Deleting space '#{n}'."
			exec_cmd( "#{@cf_cli} target -o '#{org_name}'; #{@cf_cli} delete-space -f #{n}",
				"Unable to delete space '#{n}' in org '#{org_name}'.", @test_mode )
		} if org_delete_missing_entities
		cf_space_quota_group_list.each{ |n|
			puts "Deleting space quota '#{n}."
			exec_cmd( "#{@cf_cli} delete-space-quota #{n} -f",
				"Unable to delete space quota #{n}.", @test_mode )
		} if org_delete_missing_entities

		cf_org_list.delete_if { |n| n == org_name }
	end
end

#
# Delete organizations not found in configuration
#

cf_org_list.each{ |n|
	puts "Deleting org '#{n}."
	exec_cmd( "#{@cf_cli} delete-org -f '#{n}'",
		"Unable to delete org #{n}.", @test_mode )
} if @delete_missing_entities

#
# Delete security groups not found in configuration
#

cf_security_group_list.each{ |n|
	puts "Deleting security group '#{n}'."
	exec_cmd("#{@cf_cli} delete-security-group -f #{n}",
		"Unable to delete security group #{n}.", @test_mode )
} if @delete_missing_entities

#
# Delete quotas not found in configuration
#

cf_quota_group_list.each{ |n|
	puts "Deleting org quota '#{n}."
	exec_cmd( "#{@cf_cli} delete-quota #{n} -f",
		"Unable to delete org quota #{n}.", @test_mode )
} if @delete_missing_entities

#
# Create users
#

default_roles = [
	"approvals.me", 
	"cloud_controller.read", 
	"cloud_controller.write", 
	"cloud_controller_service_permissions.read", 
	"notification_preferences.read", 
	"notification_preferences.write", 
	"oauth.approvals", 
	"openid", 
	"password.write", 
	"profile", 
	"roles", 
	"scim.me", 
	"uaa.user",
	"user_attributes" ]

Dir.glob('users/*.yml') do |user_file|

	users = []
	user_data = YAML.load_file(user_file)

	if user_data.has_key?('users')
		users = user_data['users']
	else
		users += [ user_data ]
	end

	users.each do |user|

		name = user['name'] 
		roles = Set.new((user['roles'] || []) + default_roles)

		if !user_exists?(name)

			if user['is-ldap-user']
				add_user(name)
			else
				passwd = user['password']
				if passwd.nil?
					passwd = generate_password 
					puts "Creating CF only user '#{name}' with password '#{passwd}'."
				else
					puts "Creating CF only user '#{name}'."
				end
				exec_cmd( "#{@cf_cli} create-user #{name} '#{passwd}'",
					'Unable to create user to #{name}.', @test_mode )
			end

			if @test_mode
				assigned_roles = default_roles
			else
				assigned_roles = Set.new(%x(#{@uaac} user get '#{name}' | awk '/display:/{ print $2 }').split)
			end
		else
			assigned_roles = Set.new(%x(#{@uaac} user get '#{name}' | awk '/display:/{ print $2 }').split)
		end

		roles.each do |role|
			if !assigned_roles.include?(role)
				exec_cmd( "#{@uaac} member add #{role} #{name}",
					"Unable to add role '#{role}' to user '#{name}'.", @test_mode )
			end
		end
		assigned_roles.each do |role|
			if !roles.include?(role)
				exec_cmd( "#{@uaac} member delete #{role} #{name}",
					"Unable to delete role '#{role}' from user '#{name}'.", @test_mode )
			end
		end
	end
end

# Clean up LDAP users that no long exist in LDAP

if !@ldap_url.nil?

	ldap_users = JSON.parse(exec_cmd( "#{@cf_cli} curl /v2/users",
		"Unable to retrieve list of all users."))['resources']
		.map{ |d| d['entity']['username'] }
		.select{ |u|

			if !u.nil?

				origin = exec_cmd( "#{@uaac} user get #{u} | awk '/origin:/{ print $2 }'",
					"Unable to retrieve user #{u} from uaa.").chomp == 'ldap'
			else
				false
			end
		}

	ldap_users.each do |user|

		user_search_query = eval("\"" + @ldap_config['user-search-query'] + "\"")

		dn = %x(#{@ldapsearch_cli} -H #{@ldap_url} \
			-D '#{@ldap_bind_dn}' -w '#{@ldap_password}' \
			-b '#{@ldap_config['user-search-base']}' '#{user_search_query}' dn | awk '/dn: /{ print substr($0, 5, length($0)-5) }')

		if $?.success? && dn.empty?
			puts "Deleting user #{user}."
			exec_cmd( "#{@cf_cli} delete-user #{user} -f",
				"Unable to delete user #{user}.", @test_mode )
		end
	end
end
