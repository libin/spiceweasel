#
# Author:: Matt Ray (<matt@opscode.com>)
#
# Copyright:: 2011-2012, Opscode, Inc <legal@opscode.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

class Spiceweasel::Nodes

  PROVIDERS = %w{bluebox clodo cs ec2 gandi hp lxc openstack rackspace slicehost terremark voxel}

  attr_reader :create, :delete

  def initialize(nodes, cookbooks, environments, roles, options = {})
    @create = @delete = ''
    if nodes
      STDOUT.puts "DEBUG: nodes: #{nodes}" if Spiceweasel::DEBUG
      nodes.each do |node|
        name = node.keys.first
        STDOUT.puts "DEBUG: node: '#{node[name]}'" if Spiceweasel::DEBUG
        if node[name]
          #convert spaces to commas, drop multiple commas
          run_list = node[name]['run_list'].gsub(/ /,',').gsub(/,+/,',')
          STDOUT.puts "DEBUG: node: '#{node[name]}' run_list: '#{run_list}'" if Spiceweasel::DEBUG
          validateRunList(name, run_list, cookbooks, roles) unless Spiceweasel::NOVALIDATION
          noptions = node[name]['options']
          STDOUT.puts "DEBUG: node: '#{node[name]}' options: '#{noptions}'" if Spiceweasel::DEBUG
          validateOptions(name, noptions, environments) unless Spiceweasel::NOVALIDATION
        end
        #provider support
        provider = name.split()
        if PROVIDERS.member?(provider[0])
          count = 1
          if provider.length == 2
            count = provider[1]
          end
          if Spiceweasel::PARALLEL
            @create += "seq #{count} | parallel -j 0 -v \""
            @create += "knife #{provider[0]}#{options['knife_options']} server create #{noptions}".gsub(/\{\{n\}\}/, '{}')
            if run_list
              @create += " -r '#{run_list}'\"\n"
            end
          else
            count.to_i.times do |i|
              @create += "knife #{provider[0]}#{options['knife_options']} server create #{noptions}".gsub(/\{\{n\}\}/, (i + 1).to_s)
              if run_list.length > 0
                @create += " -r '#{run_list}'\n"
              end
            end
          end
          @delete += "knife node#{options['knife_options']} list | xargs knife #{provider[0]} server delete -y\n"
        elsif name.start_with?("windows") #windows node bootstrap support
          nodeline = name.split()
          provider = nodeline.shift.split('_') #split on 'windows_ssh' etc
          nodeline.each do |server|
            @create += "knife bootstrap #{provider[0]} #{provider[1]}#{options['knife_options']} #{server} #{noptions}"
            if run_list
              @create += " -r '#{run_list}'\n"
            else
              @create += "\n"
            end
            @delete += "knife node#{options['knife_options']} delete #{server} -y\n"
            @delete += "knife client#{options['knife_options']} delete #{server} -y\n"
          end
          @delete += "knife node#{options['knife_options']} list | xargs knife #{provider[0]} server delete -y\n"
        else #node bootstrap support
          name.split.each_with_index do |server, i|
            @create += "knife bootstrap#{options['knife_options']} #{server} #{noptions}".gsub(/\{\{n\}\}/, (i + 1).to_s)
            if run_list
              @create += " -r '#{run_list}'\n"
            else
              @create += "\n"
            end
            @delete += "knife node#{options['knife_options']} delete #{server} -y\n"
            @delete += "knife client#{options['knife_options']} delete #{server} -y\n"
          end
        end
      end
    end
    @delete += "knife node#{options['knife_options']} bulk delete .* -y\n"
  end

  #ensure run_list contents are listed previously.
  def validateRunList(node, run_list, cookbooks, roles)
    run_list.split(',').each do |item|
      if item.start_with?("recipe[")
        #recipe[foo] or recipe[foo::bar]
        cb = item.split(/\[|\]/)[1].split(':')[0]
        unless cookbooks.member?(cb)
          STDERR.puts "ERROR: '#{node}' run list cookbook '#{cb}' is missing from the list of cookbooks in the manifest."
          exit(-1)
        end
      elsif item.start_with?("role[")
        #role[blah]
        role = item.split(/\[|\]/)[1]
        unless roles.member?(role)
          STDERR.puts "ERROR: '#{node}' run list role '#{role}' is missing from the list of roles in the manifest."
          exit(-1)
        end
      else
        STDERR.puts "ERROR: '#{node}' run list '#{item}' is an invalid run list entry in the manifest."
        exit(-1)
      end
    end
  end

  #for now, just check that -E is legit
  def validateOptions(node, options, environments)
    if options =~ /-E/ #check for environments
      env = options.split('-E')[1].split()[0]
      unless environments.member?(env)
        STDERR.puts "ERROR: '#{node}' environment '#{env}' is missing from the list of environments in the manifest."
        exit(-1)
      end
    end
  end

end