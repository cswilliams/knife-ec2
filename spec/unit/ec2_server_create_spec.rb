# Author:: Prabhu Das (<prabhu.das@clogeny.com>)
# Copyright:: Copyright (c) 2013 Opscode, Inc.

require File.expand_path('../../spec_helper', __FILE__)
require 'chef/knife/ec2_server_create'
require 'support/shared_examples_for_servercreatecommand'
require 'support/shared_examples_for_command'

describe Chef::Knife::Cloud::Ec2ServerCreate do
  ami = Object.new
  ami.define_singleton_method(:root_device_type){}
  ami.define_singleton_method(:platform){""}

  create_instance = Chef::Knife::Cloud::Ec2ServerCreate.new
  create_instance.define_singleton_method(:ami){ami}
  create_instance.define_singleton_method(:post_connection_validations){}

  it_behaves_like Chef::Knife::Cloud::Command, Chef::Knife::Cloud::Ec2ServerCreate.new

  ec2_service = Chef::Knife::Cloud::Ec2Service.new
  create_instance.define_singleton_method(:service){ec2_service}

  create_instance.config[:winrm_user] = "test_winrm_user"
  create_instance.config[:ssh_user] = "test_ssh_user"

  context "Windows instance" do
    before do
      allow(create_instance.ui).to receive(:error)
      create_instance.service.define_singleton_method(:is_image_windows?)  do |img, *arg|
        true
      end
    end
    it_behaves_like Chef::Knife::Cloud::ServerCreateCommand, create_instance
  end

  context "Linux instance" do
    before do
      allow(create_instance.ui).to receive(:error)
      create_instance.service.define_singleton_method(:is_image_windows?)  do |img, *arg|
        false
      end
    end
    it_behaves_like Chef::Knife::Cloud::ServerCreateCommand, create_instance
  end

  describe "#create_service_instance" do
    it "return Ec2Service instance" do
      instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      expect(instance.create_service_instance).to be_an_instance_of(Chef::Knife::Cloud::Ec2Service)
    end
  end

  describe "#validate_params!" do
    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      allow(@instance.ui).to receive(:error)
      Chef::Config[:knife][:bootstrap_protocol] = "ssh"
      Chef::Config[:knife][:identity_file] = "identity_file"
      Chef::Config[:knife][:image_os_type] = "linux"
      Chef::Config[:knife][:ssh_key_name] = "ssh_key_name"
    end

    after(:all) do
      Chef::Config[:knife].delete(:bootstrap_protocol)
      Chef::Config[:knife].delete(:identity_file)
      Chef::Config[:knife].delete(:image_os_type)
      Chef::Config[:knife].delete(:ssh_key_name)
      Chef::Config[:knife].delete(:ebs_provisioned_iops)
      Chef::Config[:knife].delete(:ebs_volume_type)
      Chef::Config[:knife].delete(:ebs_encrypted)
    end

    it "run sucessfully on all params exist" do
      expect { @instance.validate_params! }.to_not raise_error
    end

    it "raise error if ssh key is missing" do
      Chef::Config[:knife].delete(:ssh_key_name)
      expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " You must provide SSH Key..")
    end

    it "disallows ebs provisioned iops option when not using ebs volume type" do
      Chef::Config[:knife][:ebs_provisioned_iops] = "123"
      Chef::Config[:knife][:ebs_volume_type] = nil

      expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --provisioned-iops option is only supported for volume type of 'io1'.")
    end

    it "disallows ebs provisioned iops option when not using ebs volume type 'io1'" do
      Chef::Config[:knife][:ebs_provisioned_iops] = "123"
      Chef::Config[:knife][:ebs_volume_type] =  "standard"

      expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --provisioned-iops option is only supported for volume type of 'io1'.")
    end

    it "disallows ebs volume type if its other than 'io1' or 'gp2' or 'standard'" do
      Chef::Config[:knife][:ebs_provisioned_iops] = "123"
      Chef::Config[:knife][:ebs_volume_type] =  'invalid'

      expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --provisioned-iops option is only supported for volume type of 'io1'. --ebs-volume-type must be 'standard' or 'io1' or 'gp2'.")
    end

    it "disallows 'io1' ebs volume type when not using ebs provisioned iops" do
      Chef::Config[:knife][:ebs_provisioned_iops] = nil
      Chef::Config[:knife][:ebs_volume_type] = 'io1'

      expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --provisioned-iops option is required when using volume type of 'io1'.")
    end

    context 'when ebs_encrypted option specified' do
      before(:each) do
        Chef::Config[:knife][:ebs_encrypted] =  true
      end

      it 'raise error if --flavor and --ebs-size option is not specified with ebs_encrypted option' do
        Chef::Config[:knife][:ebs_volume_type] = nil
        @instance.config[:flavor] = nil
        expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --ebs_encrypted option requires valid flavor to be specified. --ebs-encrypted option requires valid --ebs-size to be specified.")
      end

      it 'raise invalid flavor error if its not included in valid flavor list for ebs_encrypted option' do
        Chef::Config[:knife][:ebs_volume_type] = nil
        Chef::Config[:knife][:ebs_size] = 8
        @instance.config[:flavor] = 't1.large'
        expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --ebs_encrypted option is not supported for t1.large flavor.")
      end

      it 'raise error if invalid ebs_size specified for \'standard\' VolumeType' do
        Chef::Config[:knife][:ebs_volume_type] = 'standard'
        Chef::Config[:knife][:ebs_size] = '1055'
        Chef::Config[:knife][:flavor] = 'm3.medium'
        expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --ebs-size should be in between 1-1024 for 'standard' ebs volume type.")
      end

      it 'raise error on invalid ebs_size specified for \'gp2\' VolumeType' do
        Chef::Config[:knife][:ebs_volume_type] = 'gp2'
        Chef::Config[:knife][:ebs_size] = '16500'
        Chef::Config[:knife][:flavor] = 'm3.medium'
        expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --ebs-size should be in between 1-16384 for 'gp2' ebs volume type.")
      end

      it 'raise error on invalid ebs_size specified for \'io1\' VolumeType' do
        Chef::Config[:knife][:ebs_volume_type] = 'io1'
        Chef::Config[:knife][:ebs_size] = '3'
        Chef::Config[:knife][:flavor] = 'm3.medium'
        Chef::Config[:knife][:ebs_provisioned_iops] = '200'
        expect { @instance.validate_params! }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError,  " --ebs-size should be in between 4-16384 for 'io1' ebs volume type.")
      end

    end
  end

  describe "#before_exec_command" do
    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      @instance.service = double
      expect(@instance.service).to receive(:create_server_dependencies)
      expect(@instance.service).to receive(:is_image_windows?)
      allow(@instance.service).to receive_message_chain(:connection, :images, :get, :root_device_type)
      allow(@instance.ui).to receive(:error)
      allow(@instance.ui).to receive(:warn)
      @instance.config[:chef_node_name] = "chef_node_name"
      Chef::Config[:knife][:image] = "image"
      Chef::Config[:knife][:flavor] = "flavor"
      Chef::Config[:knife][:ec2_security_groups] = "ec2_security_groups"
      Chef::Config[:knife][:security_group_ids] = "test_ec2_security_groups_id"
      Chef::Config[:knife][:availability_zone] = "test_zone"
      Chef::Config[:knife][:server_create_timeout] = "600"
      Chef::Config[:knife][:ssh_key_name] = "ec2_ssh_key_name"
      Chef::Config[:knife][:subnet_id] = "test_subnet_id"
      Chef::Config[:knife][:private_ip_address] = "test_private_ip_address"
      Chef::Config[:knife][:dedicated_instance] = "dedicated_instance"
      Chef::Config[:knife][:placement_group] = "test_placement_group"
      Chef::Config[:knife][:iam_instance_profile] = "iam_instance_profile_name"
      @instance.config[:associate_public_ip] = "test_associate_public_ip"
      allow(@instance).to receive(:ami).and_return(double)
      expect(@instance.ami).to receive(:root_device_type)
      expect(@instance).to receive(:post_connection_validations)
      allow(@instance).to receive(:set_image_os_type)
    end

    after(:each) do
      Chef::Config[:knife].delete(:image)
      Chef::Config[:knife].delete(:flavor)
      Chef::Config[:knife].delete(:ssh_key_name)
      Chef::Config[:knife].delete(:ec2_security_groups)
      Chef::Config[:knife].delete(:security_group_ids)
      Chef::Config[:knife].delete(:availability_zone)
      Chef::Config[:knife].delete(:server_create_timeout)
    end

    it "set create_options" do
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:tags]["Name"]).to be == "chef_node_name"
      expect(@instance.create_options[:server_def][:image_id]).to be == "image"
      expect(@instance.create_options[:server_def][:flavor_id]).to be == "flavor"
      expect(@instance.create_options[:server_def][:key_name]).to be == "ec2_ssh_key_name"
      expect(@instance.create_options[:server_def][:groups]).to be == "ec2_security_groups"
      expect(@instance.create_options[:server_def][:security_group_ids]).to be == "test_ec2_security_groups_id"
      expect(@instance.create_options[:server_def][:availability_zone]).to be == "test_zone"
      expect(@instance.create_options[:server_create_timeout]).to be == "600"
      expect(@instance.create_options[:server_def][:placement_group]).to be == "test_placement_group"
      expect(@instance.create_options[:server_def][:iam_instance_profile_name]).to be == "iam_instance_profile_name"
    end

    it "set create_options when vpc_mode? is true." do
      allow(@instance).to receive(:vpc_mode?).and_return true
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:subnet_id]).to be == "test_subnet_id"
      expect(@instance.create_options[:server_def][:private_ip_address]).to be == "test_private_ip_address"
      expect(@instance.create_options[:server_def][:tenancy]).to be == "dedicated"
      expect(@instance.create_options[:server_def][:associate_public_ip]).to be == "test_associate_public_ip"
      expect(@instance.create_options[:server_def][:groups]).to be == "ec2_security_groups"
    end

    it "set user_data when aws_user_data is provided." do
      Chef::Config[:knife][:aws_user_data] = "aws_user_data_file_path"
      allow(File).to receive(:read).and_return("aws_user_data_values")
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:user_data]).to be == "aws_user_data_values"
    end

    it "throws ui warning when aws_user_data is not readable." do
      Chef::Config[:knife][:aws_user_data] = "aws_user_data_file_path"
      expect(@instance.ui).to receive(:warn).once
      @instance.before_exec_command
    end

    it "sets create_option ebs_optimized to true when provided with some value." do
      @instance.config[:ebs_optimized] = "some_value"
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:ebs_optimized]).to be == "true"
    end

    it "sets create_option ebs_optimized to false when not provided." do
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:ebs_optimized]).to be == "false"
    end

    it "adds the specified ephemeral device mappings" do
      @instance.config[:ephemeral] = [ "/dev/sdb", "/dev/sdc", "/dev/sdd", "/dev/sde" ]
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:block_device_mapping]).to be == [{ "VirtualName" => "ephemeral0", "DeviceName" => "/dev/sdb" },
                                                   { "VirtualName" => "ephemeral1", "DeviceName" => "/dev/sdc" },
                                                   { "VirtualName" => "ephemeral2", "DeviceName" => "/dev/sdd" },
                                                   { "VirtualName" => "ephemeral3", "DeviceName" => "/dev/sde" }]
    end

    it "doesn't set an IAM server role by default" do
      Chef::Config[:knife].delete(:iam_instance_profile)
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:iam_instance_profile_name]).to be nil
    end

    it "sets the IAM server role when one is specified" do
      @instance.config[:iam_instance_profile] = ['iam-role']
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:iam_instance_profile_name]).to be == ['iam-role']
    end

    it 'Set Tenancy Dedicated when both VPC mode and Flag is True' do
      Chef::Config[:knife][:dedicated_instance] = "dedicated_instance"
      allow(@instance).to receive(:vpc_mode?).and_return true
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:tenancy]).to be == "dedicated"
    end

    it 'Tenancy should be default with no vpc mode is specified' do
      @instance.config[:dedicated_instance] = true
      allow(@instance).to receive(:vpc_mode?).and_return false
      @instance.before_exec_command
      expect(@instance.create_options[:server_def][:tenancy]).to be nil
    end

    context 'when using ebs_encrypted option' do
      before do
        @instance.config[:ebs_encrypted] = true
        allow(@instance).to receive_message_chain(:ami, :root_device_type).and_return('ebs')
      end

      it 'sets block device mapping for volume encryption' do
        allow(@instance).to receive_message_chain(:ami, :block_device_mapping).and_return([{'deviceName' => '/dev/sd1' },
          {'deviceName' => '/dev/sdb'}])
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.Encrypted']).to eql(true)
      end
    end

    context "when using ebs volume type and ebs provisioned iops rate options" do
      before do
        allow(@instance).to receive_message_chain(:ami, :root_device_type).and_return("ebs")
        allow(@instance).to receive_message_chain(:ami, :block_device_mapping).and_return([{"iops" => 123}])
      end

      it "sets the specified 'standard' ebs volume type" do
        @instance.config[:ebs_volume_type] = 'standard'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.VolumeType']).to be == 'standard'
      end

      it "sets the specified 'io1' ebs volume type" do
        @instance.config[:ebs_volume_type] = 'io1'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.VolumeType']).to be == 'io1'
      end

      it "sets the specified 'gp2' ebs volume type" do
        @instance.config[:ebs_volume_type] = 'gp2'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.VolumeType']).to be =='gp2'
      end

      it "sets the specified ebs provisioned iops rate" do
        @instance.config[:ebs_provisioned_iops] = '1234'
        @instance.config[:ebs_volume_type] = 'io1'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.Iops']).to be =='1234'
      end

      it "sets the iops rate from ami" do
        @instance.config[:ebs_volume_type] = 'io1'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:block_device_mapping].first['Ebs.Iops']).to be == '123'
      end
    end

    context "when using spot price option" do
      it "sets the spot price" do
        @instance.config[:spot_price] = '1.99'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:price]).to be == '1.99'
      end

      it "sets spot request type" do
        @instance.config[:spot_request_type] = 'persistent'
        @instance.before_exec_command
        expect(@instance.create_options[:server_def][:request_type]).to be == 'persistent'
      end
    end
  end

  describe "#execute_command" do
    before(:each) do

      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      allow(@instance).to receive(:service).and_return(double)
    end

    it "create server sucessfully." do
      expect(@instance.service).to receive(:create_server)
      expect(@instance.service).to receive(:server_summary)
      @instance.execute_command
    end

    it "raise error on invalid flavor used with ebs optimized." do
      fog_err = "Unsupported => EBS-optimized instances are not supported for your requested configuration. Please check the documentation for supported configurations"
      allow(@instance.service).to receive(:create_server).and_raise(Chef::Knife::Cloud::CloudExceptions::ServerCreateError, fog_err)
      allow(@instance.service).to receive(:delete_server_dependencies)
      error_msg = "Please check if default flavor is supported for EBS-optimized instances."
      expect(@instance.ui).to receive(:error).with(error_msg)
      allow(@instance.ui).to receive(:fatal)
      expect { @instance.execute_command }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ServerCreateError, fog_err)
    end

    it "raise error on invalid flavor used with placement group." do
      fog_err = "InvalidParameterCombination => Placement groups may not be used with instances of type"
      allow(@instance.service).to receive(:create_server).and_raise(Chef::Knife::Cloud::CloudExceptions::ServerCreateError, fog_err)
      allow(@instance.service).to receive(:delete_server_dependencies)
      error_msg = "Please check if default flavor is supported for Placement groups."
      expect(@instance.ui).to receive(:error).with(error_msg)
      allow(@instance.ui).to receive(:fatal)
      expect { @instance.execute_command }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ServerCreateError, fog_err)
    end
  end

  describe "Spot instance creation" do
    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      @ec2_connection = double(Fog::Compute::AWS)

      @instance.config[:spot_price] = 0.666
      @instance.config[:spot_request_type] = 'persistent'
      @new_spot_request = double

      @spot_request_attribs = { :id => 'test_spot_request_id',
                                :price => 0.666,
                                :request_type => 'persistent',
                                :created_at => '2015-07-14 09:53:11 UTC',
                                :instance_count => nil,
                                :instance_id => 'test_spot_instance_id',
                                :state => 'open',
                                :key_name => 'ssh_key_name',
                                :availability_zone => nil,
                                :flavor_id => 'm1.small',
                                :image_id => 'image' }

      @spot_request_attribs.each_pair do |attrib, value|
        allow(@new_spot_request).to receive(attrib).and_return(value)
      end
    end

    it "creates a spot instance request with spot request type persistent" do
      allow(@instance.service).to receive(:connection).and_return(@ec2_connection)
      allow(@ec2_connection).to receive_message_chain(:servers, :get)
      expect(@instance).to receive(:create_spot_request).and_return(@new_spot_request)
      expect(@new_spot_request.request_type).to eq('persistent')
      @instance.execute_command
    end
  end
  describe "#after_exec_command" do
    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      allow(@instance).to receive(:msg_pair)
      allow(@instance).to receive_message_chain(:service, :connection, :addresses, :detect).and_return(double)
      @instance.server = double
    end

    after(:all) do
      Chef::Config[:knife].delete(:ec2_floating_ip)
    end

    it 'prints server summary.' do
      allow(@instance.service).to receive(:get_server_name)
      allow(@instance.server).to receive(:id).and_return('instance_id')
      allow(@instance.server).to receive_message_chain(:groups, :join).and_return('groups')
      allow(@instance.server).to receive_message_chain(:security_group_ids, :join).and_return('security_group_ids')
      allow(@instance).to receive_message_chain(:service, :connection, :tags, :create).with(:key => 'Name',
                                                        :value => 'instance_id',
                                                        :resource_id => 'instance_id')
      allow(@instance.server).to receive(:root_device_type).and_return('ebs')
      allow(@instance.server).to receive_message_chain(:block_device_mapping, :first).and_return('block_device_mapping')
      allow(@instance.server).to receive_message_chain(:volumes, :first).and_return(TestResource.new({:type => 'gp2', :iops => '100'}))
      allow(@instance.server).to receive_message_chain(:block_device_mapping, :each).and_return('block_device_mapping')
      allow(@instance.service).to receive(:server_summary)
      expect(@instance).to receive(:bootstrap)
      @instance.after_exec_command
    end
  end

  describe "#before_bootstrap" do
    before(:all) do
      @tempfile = Tempfile.new('validation_key')
    end

    after(:all) do
      # Clear the temp directory upon exit
      FileUtils::remove_dir(@tempfile) if Dir.exists?(@tempfile)
    end

    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      @instance.server = double
      @instance.config[:server_connect_attribute] = :public_ip_address
      @validation_key_url = "s3://bucket/foo/bar"
      @validation_key_file = '/tmp/a_good_temp_file'
    end

    after do
      @instance.config.delete(:server_connect_attribute)
      Chef::Config[:knife].delete(:validation_key_url)
      Chef::Config[:knife].delete(:s3_secret)
    end

    it "set bootstrap_ip" do
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      @instance.before_bootstrap
      expect(@instance.config[:bootstrap_ip_address]).to be == "127.0.0.1"
    end

    it "raise error on nil bootstrap_ip" do
      allow(@instance.ui).to receive(:error)
      allow(@instance.server).to receive(:public_ip_address).and_return(nil)
      expect { @instance.before_bootstrap }.to raise_error(Chef::Knife::Cloud::CloudExceptions::BootstrapError, "No IP address available for bootstrapping.")
    end

    it "set hint config" do
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      @instance.before_bootstrap
      expect(Chef::Config[:knife][:hints]).to be == {"ec2"=>{}}
    end

    it "sets validation_key if validation_key_url is present" do
      Chef::Config[:knife][:validation_key_url] = @validation_key_url
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      allow(@instance).to receive(:validation_key_path).and_return(@validation_key_file)
      allow(@instance).to receive(:download_validation_key)
      @instance.before_bootstrap
      expect(Chef::Config[:validation_key]).to be == @validation_key_file
    end

    it "sets s3-based secret" do
      Chef::Config[:knife][:s3_secret] = 's3://test.bucket/folder/encrypted_data_bag_secret'
      @secret_content = "TEST DATA BAG SECRET\n"
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      allow(Chef::Knife::S3Source).to receive(:fetch).and_return(@secret_content)
      @instance.before_bootstrap
      expect(@instance.config[:secret]).to be == @secret_content
    end

    it "downloads validation_key and actually writes to the temp location" do
      Chef::Config[:knife][:validation_key_url] = @validation_key_url
      allow(Chef::Log).to receive(:debug)
      allow(@instance).to receive(:s3_validation_key)
      allow(File).to receive(:write)
      expect(File).to receive(:open).with(@tempfile, 'w')
      @instance.download_validation_key(@tempfile)
    end

    it 'should use public_ip_address when dns name not exist' do
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      allow(@instance).to receive(:dns_name).and_return(nil)
      @instance.before_bootstrap
      expect(@instance.config[:bootstrap_ip_address]).to eq('127.0.0.1')
    end
  end

  describe "bootstrap ip address" do
    before do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      @instance.server = double
      @instance.config.delete(:bootstrap_ip_address)
    end

    it "uses public ip address" do
      @instance.config[:server_connect_attribute] = :public_ip_address
      allow(@instance.server).to receive(:public_ip_address).and_return("127.0.0.1")
      @instance.before_bootstrap
      expect(@instance.config[:bootstrap_ip_address]).to be == "127.0.0.1"
    end

    it "uses private ip address" do
      @instance.config[:server_connect_attribute] = :private_ip_address
      allow(@instance.server).to receive(:private_ip_address).and_return("127.0.0.1")
      @instance.before_bootstrap
      expect(@instance.config[:bootstrap_ip_address]).to be == "127.0.0.1"
    end

    it "uses private ip address in vpc mode and when associate public ip is nil" do
      @instance.config.delete(:server_connect_attribute)
      @instance.config.delete(:associate_public_ip)
      allow(@instance).to receive(:vpc_mode?).and_return(true)
      allow(@instance.server).to receive(:private_ip_address).and_return("192.168.1.1")
      @instance.before_bootstrap
      expect(@instance.config[:bootstrap_ip_address]).to be == "192.168.1.1"
    end
  end

  describe "#validate_ebs" do
    before(:each) do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
    end

    it "validate ebs size" do
      allow(@instance.ui).to receive(:error)
      allow(@instance).to receive(:ami).and_return(double)
      @instance.config[:ebs_size] = "15"
      allow(@instance.ami).to receive(:block_device_mapping).and_return([{"volumeSize" => 8}])
      expect { @instance.validate_ebs }.to_not raise_error
    end

    it "raise error on specified ebs-size is less than ami volume size" do
      allow(@instance.ui).to receive(:error)
      allow(@instance).to receive(:ami).and_return(double)
      @instance.config[:ebs_size] = "5"
      allow(@instance.ami).to receive(:block_device_mapping).and_return([{"volumeSize" => 8}])
      expect { @instance.validate_ebs }.to raise_error(Chef::Knife::Cloud::CloudExceptions::ValidationError, "EBS-size is smaller than snapshot '', expect size >= 8")
    end
  end

  describe "when reading aws_credential_file" do
    before do
      @instance = Chef::Knife::Cloud::Ec2ServerCreate.new
      @aws_access_key_id = Chef::Config[:knife][:aws_access_key_id]
      @aws_secret_access_key = Chef::Config[:knife][:aws_secret_access_key]
      @aws_credential_file = Chef::Config[:knife][:aws_credential_file]

      Chef::Config[:knife].delete(:aws_access_key_id)
      Chef::Config[:knife].delete(:aws_secret_access_key)

      Chef::Config[:knife][:aws_credential_file] = '/apple/pear'
      @access_key_id = 'access_key_id'
      @secret_key = 'secret_key'
    end

    after do
      Chef::Config[:knife][:aws_credential_file] = @aws_credential_file
      Chef::Config[:knife][:aws_access_key_id] = @aws_access_key_id
      Chef::Config[:knife][:aws_secret_access_key] = @aws_secret_access_key
    end

    it "reads UNIX Line endings" do
      allow(File).to receive(:read).
        and_return("AWSAccessKeyId=#{@access_key_id}\nAWSSecretKey=#{@secret_key}")
      @instance.validate!
      expect(Chef::Config[:knife][:aws_access_key_id]).to be == @access_key_id
      expect(Chef::Config[:knife][:aws_secret_access_key]).to be == @secret_key
    end

    it "reads DOS Line endings" do
      allow(File).to receive(:read).
        and_return("AWSAccessKeyId=#{@access_key_id}\r\nAWSSecretKey=#{@secret_key}")
      @instance.validate!
      expect(Chef::Config[:knife][:aws_access_key_id]).to be == @access_key_id
      expect(Chef::Config[:knife][:aws_secret_access_key]).to be == @secret_key
    end

    it "reads UNIX Line endings for new format" do
      allow(File).to receive(:read).
        and_return("aws_access_key_id=#{@access_key_id}\naws_secret_access_key=#{@secret_key}")
      @instance.validate!
      expect(Chef::Config[:knife][:aws_access_key_id]).to be == @access_key_id
      expect(Chef::Config[:knife][:aws_secret_access_key]).to be == @secret_key
    end

    it "reads DOS Line endings for new format" do
      allow(File).to receive(:read).
        and_return("aws_access_key_id=#{@access_key_id}\r\naws_secret_access_key=#{@secret_key}")
      @instance.validate!
      expect(Chef::Config[:knife][:aws_access_key_id]).to be == @access_key_id
      expect(Chef::Config[:knife][:aws_secret_access_key]).to be == @secret_key
    end
  end

  describe "when creating the connection" do
    describe "when use_iam_profile is true" do
      before do
        Chef::Config[:knife].delete(:aws_access_key_id)
        Chef::Config[:knife].delete(:aws_secret_access_key)

        @ec2_connection = double(Fog::Compute::AWS)
        allow(@ec2_connection).to receive_message_chain(:tags).and_return double('create', :create => true)
        allow(@ec2_connection).to receive_message_chain(:images, :get).and_return double('ami', :root_device_type => 'not_ebs', :platform => 'linux')
        allow(@ec2_connection).to receive_message_chain(:addresses).and_return [double('addesses', {
                :domain => 'standard',
                :public_ip => '111.111.111.111',
                :server_id => nil,
                :allocation_id => ''})]

        Chef::Config[:knife][:use_iam_profile] = true
        @ec2_service = Chef::Knife::Cloud::Ec2Service.new
      end

      it "creates a connection without access keys" do
        expect(Fog::Compute::AWS).to receive(:new).with(hash_including(:use_iam_profile => true)).and_return(@ec2_connection)
        @ec2_service.connection
      end

      after do
        Chef::Config[:knife].delete(:use_iam_profile)
      end
    end

    describe 'when aws_session_token is present' do
      before(:each) do
        Chef::Config[:knife].delete(:use_iam_profile)
        Chef::Config[:knife][:aws_secret_access_key] = 'aws_secret_access_key'
        Chef::Config[:knife][:aws_access_key_id] = 'aws_access_key_id'
        Chef::Config[:knife][:aws_session_token] = 'session-token'
      end

      it 'creates a connection using the session token' do
        @ec2_connection = double(Fog::Compute::AWS)
        @ec2_service = Chef::Knife::Cloud::Ec2Service.new
        expect(Fog::Compute::AWS).to receive(:new).with(hash_including(:aws_session_token => 'session-token')).and_return(@ec2_connection)
        @ec2_service.connection
      end
    end
  end
end
