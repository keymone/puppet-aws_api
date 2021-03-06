require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', 'puppet_x', 'bobtfish', 'ec2_api.rb'))

Puppet::Type.type(:aws_rds_instance).provide(:api, :parent => Puppet_X::Bobtfish::Ec2_api) do
  mk_resource_methods
  remove_method :tags= # We want the method inherited from the parent

  def self.instances_for_region(region)
    rds(region).client.describe_db_instances.data[:db_instances]
  end
  def instances_for_region(region)
    self.class.instances_for_region region
  end
  def self.new_from_aws(region_name, item)
    status = case item[:db_instance_status]
    when 'available'
      :present
    else
      :absent
    end

    endpoint = if item[:endpoint]
      "#{item[:endpoint][:address]}:#{item[:endpoint][:port]}"
    end


    security_groups = item[:vpc_security_groups].collect do |sg|
      ec2.regions[region_name].security_groups[sg[:vpc_security_group_id]].name
    end

    subnets = if item[:db_subnet_group]
      item[:db_subnet_group][:subnets].collect do |sn|
        ec2.regions[region_name].subnets[sn[:subnet_identifier]].tags['Name']
      end
    else
      []
    end

    new(
      :name             => item[:db_instance_identifier],
      :ensure           => status,
      :region           => region_name,
      :db_instance_class=> item[:db_instance_class],
      :engine           => item[:engine],
      :engine_version   => item[:engine_version],
      :master_username  => item[:master_username],
      :allocated_storage=> item[:allocated_storage].to_s,
      :multi_az         => item[:multi_az],
      :endpoint         => endpoint,
      :security_groups  => security_groups,
      :subnets          => subnets
    )
  end

  def aws_item
    rds(region).db_instances[@property_hash[:name]]
  end

  def self.instances
    regions.collect do |region_name|
      instances_for_region(region_name).collect { |item|
        new_from_aws(region_name, item)
      }
    end.flatten
  end

  read_only(:region, :db_instance_class, :engine, :engine_version, :master_username, :multi_az, :endpoint)

  def subnets=(subnets)
    sn_group_opts = {
      :db_subnet_group_name => resource[:name],
      :db_subnet_group_description => "Subnet(s) for #{resource[:name]}: #{resource[:subnets].join(', ')}",
      :subnet_ids => subnets.collect do |sn|
        lookup(:aws_subnet, sn).id
      end
    }
    rds(resource[:region]).client.modify_db_subnet_group(sn_group_opts)
  rescue AWS::RDS::Errors::DBSubnetGroupNotFoundFault
    rds(resource[:region]).client.create_db_subnet_group(sn_group_opts)
  end

  def security_groups=(sgs)
    aws_item.modify(:vpc_security_group_ids=>sgs.collect{|sg|
      lookup(:aws_security_group, sg).id
    })
  end



  def create
    self.subnets = resource[:subnets]
    security_groups = resource[:security_groups].collect do |sg|
      lookup(:aws_security_group, sg).id
    end

    db = rds(resource[:region]).db_instances.create(resource[:name],
      :db_name            => resource[:name].gsub('-', '_'),
      :allocated_storage  => resource[:allocated_storage].to_i,
      :db_instance_class  => resource[:db_instance_class],
      :engine             => resource[:engine],
      :engine_version     => resource[:engine_version],
      :master_username    => resource[:master_username],
      :master_user_password => resource[:master_user_password],
      :multi_az           => resource[:multi_az],
      :vpc_security_group_ids => security_groups,
      :db_subnet_group_name => resource[:name],
    )
  end
  def destroy
    client = rds(resource[:region]).client
    client.delete_db_subnet_group(:db_subnet_group_name => resource[:name])
    client.delete_db_instance(:db_instance_identifier => resource[:name])
    @property_hash[:ensure] = :absent
  end
end

