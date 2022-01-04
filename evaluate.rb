require "minitest/autorun"
require 'yaml'
require 'json'

$playbook_answers = [
    [{"name":"Get filename","hosts":"localhost","vars":{"file_path":"/etc/hosts"},"tasks":[{"name":"Get filename","debug":{"msg":"File Name = {{file_path | basename}}"}}]}]
]

class InventoryParser

  def initialize(inventory_path)
    @inventory_path = inventory_path
    @data = {
        "_meta" => {
            "hostvars" => {}
        }
    }
  end

  def inventory_path
    @inventory_path
  end

  def data
    @data
  end

  def ignored_variables
    [
        'ansible_ssh_user'
    ]
  end

  def file_lines
    File.read( inventory_path ).split("\n")
  end

  def parse
    current_section = nil

    file_lines.each do |line|
      parts = line.split(' ')
      next if parts.length == 0
      next if parts.first[0] == "#"
      next if parts.first[0] == "/"
      if parts.first[0] == '['
        current_section = parts.first.gsub('[','').gsub(']','')
        if data[current_section].nil? && !current_section.include?(':vars')
          data[current_section] = []
        end
        next
      end

      # varaible block
      if !current_section.nil? && current_section.include?(':vars')
        parts = line.split('=')
        key   = parts[0]
        value = parts[1]
        col   = current_section.split(':')
        col.pop
        group = col.join(':')
        fill_hosts_with_group_var(group, key, value)
        # host block (could still have in-line variables)
      else
        hostname = parts.shift
        ensure_host_variables(hostname)
        d = {}

        while parts.length > 0
          part = parts.shift
          words = part.split('=')
          d[words.first] = words.last unless ignored_variables.include? words.first
        end

        data[current_section].push(hostname) if current_section
        d.each do |k,v|
          data["_meta"]["hostvars"][hostname][k] = v
        end

      end
    end

    return data
  end

  def ensure_host_variables(hostname)
    if data["_meta"]["hostvars"][hostname].nil?
      data["_meta"]["hostvars"][hostname] = {}
    end
  end

  def fill_hosts_with_group_var(group, key, value)
    return if ignored_variables.include? key

    if value.include?("'") || value.include?('"')
      value = eval(value)
    end

    data[group].each do |hostname|
      ensure_host_variables(hostname)
      data["_meta"]["hostvars"][hostname][key] = value
    end
  end

end

class Evaluate < Minitest::Test
  def remove_keys_from_plays plays, name, enable_remove_names_from_array
    plays = JSON.parse(JSON.generate(plays).gsub(/\'/,'\"'))
    plays = JSON.parse(JSON.generate(plays).gsub(/\s/,''))

    if !enable_remove_names_from_array
      return plays
    end
    for play in plays
      remove_keys_from_hash play, name
      if play['tasks']
        for task in play['tasks']
          remove_keys_from_hash task, name
        end
      end
    end
    plays
  end

  def remove_keys_from_hash x, key_name
    x.delete(key_name)
    x
  end

  def matches_any_of_answers input_formatted_without_names, answers, check_message, remove_keys_from_play

    for answer in answers
      answer_formatted = JSON.parse(JSON.generate(answer))
      answer_formatted_without_names = remove_keys_from_plays answer_formatted, "name", remove_keys_from_play

      condition = condition || answer_formatted_without_names == input_formatted_without_names
    end

    assert_equal TRUE,
                 condition,
                 check_message

  end


  def check_yaml_files filename, answers, check_message, remove_keys_from_play
    # Check variable file
    replacements = {
        'á' => "a",
        'ë' => 'e',
    }

    encoding_options = {
        :invalid   => :replace,     # Replace invalid byte sequences
        :replace => "",             # Use a blank for those replacements
        :universal_newline => true, # Always break lines with \n
        # For any character that isn't defined in ASCII, run this
        # code to find out how to replace it
        :fallback => lambda { |char|
          # If no replacement is specified, use an empty string
          replacements.fetch(char, "")
        },
    }

    file_data = File.read(filename, encoding: 'ISO-8859-1')
    file_data_encoded = file_data.encode(Encoding.find('ASCII'), encoding_options)
    begin
      yaml_data = YAML.load(file_data_encoded, 'ASCII')
    rescue StandardError => bang
      puts bang
      assert(false, ("Unable to parse the YAML file. Please ensure the YAML file structure is correct. Check output for more details on error."))
    end

    input_formatted = JSON.parse(JSON.generate(yaml_data))

    input_formatted_without_names = remove_keys_from_plays input_formatted, "name",remove_keys_from_play

    puts JSON.generate(input_formatted)

    matches_any_of_answers(input_formatted_without_names, answers, check_message, remove_keys_from_play)
  end

  def test_yaml

    # Check playbook
    check_yaml_files 'playbook.yml',  $playbook_answers, 'msg must be updated to print required message', true

  end
end
