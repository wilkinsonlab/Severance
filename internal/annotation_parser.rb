#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'pathname'

module QueryAnnotationParser
  class Parser
    def self.parse(file_path)
      content = File.read(file_path, encoding: 'UTF-8')
      lines = content.lines

      metadata = {
        'query_id' => File.basename(file_path, '.*'),
        'title' => nil,
        'summary' => nil,
        'description' => nil,
        'endpoint' => nil,
        'pagination' => nil,
        'method' => nil,
        'endpoint_in_url' => nil,
        'tags' => [],
        'defaults' => {},
        'enumerate' => {},
        'variables' => [],
        'variable_types' => {},
        'query' => ''
      }

      decorator_lines = []
      query_lines = []

      lines.each do |line|
        if line.strip.start_with?('#+')
          decorator_lines << line
        else
          query_lines << line
        end
      end

      # NEW: proper multi-line decorator parser
      parse_all_decorators(decorator_lines, metadata)

      metadata['query'] = query_lines.join("\n").strip

      # Extract grlc-style parameters (?_name_type)
      vars, types = extract_parameters(metadata['query'])
      metadata['variables'] = vars
      metadata['variable_types'] = types

      # Fallback query_id
      metadata['query_id'] = File.basename(file_path, '.*') if metadata['query_id'].nil? || metadata['query_id'].empty?

      metadata
    end

    # ------------------------------------------------------------------
    # NEW parser that correctly handles tags, defaults, enumerate,
    # endpoint_in_url, and all simple key:value lines
    # ------------------------------------------------------------------
    def self.parse_all_decorators(decorator_lines, metadata)
      current_key = nil
      current_list = nil

      decorator_lines.each do |line|
        clean = line.sub(/^#+\s*/, '').strip
        next if clean.empty?

        # Section header like "tags:", "defaults:", "enumerate:"
        if clean.end_with?(':')
          key = clean.chomp(':').strip
          case key
          when 'tags'
            metadata['tags'] = []
          when 'defaults'
            metadata['defaults'] = {}
          when 'enumerate'
            metadata['enumerate'] = {}
          end
          current_key = key
          current_list = nil
          next
        end

        # List item "- value" or "- key: value"
        if clean.start_with?('- ')
          item = clean.sub(/^- \s*/, '').strip

          case current_key
          when 'tags'
            metadata['tags'] << item

          when 'defaults'
            if item.include?(':')
              k, v = item.split(':', 2).map(&:strip)
              metadata['defaults'][k] = parse_value(v)
            end

          when 'enumerate'
            if item.include?(':') && item.end_with?(':')
              # "- country:" → start a new enumerate list
              enum_key = item.chomp(':').strip
              metadata['enumerate'][enum_key] ||= []
              current_list = metadata['enumerate'][enum_key]
            elsif current_list
              # subsequent "- value" lines belong to the current list
              current_list << parse_value(item)
            end
          end

        # Simple one-line key: value (query_id, title, endpoint, endpoint_in_url, etc.)
        elsif clean.include?(':')
          key, val = clean.split(':', 2).map(&:strip)
          metadata[key] = parse_value(val)
          current_key = nil
        end
      end
    end

    # Helper to turn "18", "true", "\"John\"", "False" into proper Ruby types
    def self.parse_value(val_str)
      return nil if val_str.nil? || val_str.empty?

      v = val_str.strip

      if (v.start_with?('"') && v.end_with?('"')) || (v.start_with?("'") && v.end_with?("'"))
        v[1..-2]
      elsif v.match?(/^\d+$/)
        v.to_i
      elsif v.match?(/^\d+\.\d+$/)
        v.to_f
      elsif v.downcase == 'true'
        true
      elsif v.downcase == 'false'
        false
      else
        v
      end
    end

    # (unchanged – your original grlc parameter extractor)
    def self.extract_parameters(query_text)
      variables = []
      variable_types = {}

      query_text.scan(/\?(__?)(\w+)_([\w:]+)\b/) do |_, name, type_suffix|
        next if name.empty?

        param_name = name
        variables << param_name unless variables.include?(param_name)
        variable_types[param_name] = normalize_type(type_suffix)
      end

      [variables.uniq, variable_types]
    end

    def self.normalize_type(suffix)
      case suffix.downcase
      when 'iri', 'uri' then 'iri'
      when 'integer', 'int' then 'integer'
      when 'float', 'double', 'decimal' then 'float'
      when 'boolean', 'bool' then 'boolean'
      when 'date', 'datetime' then 'date'
      else 'string'
      end
    end

    def self.process_folder(folder_path)
      folder = Pathname.new(folder_path)
      raise "Folder not found: #{folder_path}" unless folder.directory?

      results = []
      Dir[folder.join('**/*.{rq,sparql}')].sort.each do |file|
        puts "Processing: #{File.basename(file)}"
        metadata = parse(file)
        results << metadata
      end
      results
    end
  end
end
