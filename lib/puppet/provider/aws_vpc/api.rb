require 'puppet/provider/ec2_api'

Puppet::Type.type(:aws_vpc).provide(:api, :parent => Puppet::Provider::Ec2_api) do
  mk_resource_methods
  def self.instances
    regions.collect do |region|
      ec2.regions[region].vpcs.collect do |item|
        tags = item.tags.to_h
        name = tags.delete('Name') || item.id
        new(
          :name             => name,
          :id               => item.id,
          :ensure           => :present,
          :cidr             => item.cidr_block,
          :dhcp_options_id  => item.dhcp_options_id,
          :instance_tenancy => item.instance_tenancy,
          :region           => region,
          :tags             => tags
        )
      end
    end.flatten
  end
  [:cidr, :region, :dhcp_options_id, :instance_tenancy].each do |ro_method|
    define_method("#{ro_method}=") do |v|
      fail "Cannot manage #{ro_method} is read-only once a vpc is created"
    end
  end
  def exists?
    @property_hash[:ensure] == :present
  end
  def create
    raise("Cannot create yet")
  end
  def destroy
    raise("Cannot destroy yet")
  end
end

