require 'net/http'
require 'json'
require 'fileutils'
require_relative 'annotation_parser'

include QueryAnnotationParser

EXTERNAL_URL = ENV.fetch('EXTERNAL_URL')
TRIPLESTORE_URL = ENV.fetch('TRIPLESTORE_URL')
QUERY_DIR      = ENV.fetch('QUERY_DIR')
POLL_INTERVAL  = ENV.fetch('POLL_INTERVAL', 10).to_i
RESULT_FORMAT  = ENV['RESULT_FORMAT'] == 'csv' ? 'csv' : 'json'

ACCEPT_HEADER = RESULT_FORMAT == 'csv' ? 'text/csv' : 'application/sparql-results+json'

# ------------------------------------------------------------------
# Helper: Escape value for safe insertion into SPARQL
# ------------------------------------------------------------------
# Replace grlc-style parameters with proper SPARQL escaping + IRI wrapping
def substitute_grlc_bindings(query, bindings, variable_types = {})
  return query if bindings.nil? || bindings.empty?

  bindings.each do |k, v|
    next if v.nil?

    # Determine if this variable is declared as iri
    is_iri = variable_types[k.to_s]&.downcase == 'iri'

    escaped_value = if is_iri
                      # Auto-wrap IRIs in < >
                      if v.to_s.strip.start_with?('<') && v.to_s.strip.end_with?('>')
                        v.to_s.strip
                      else
                        "<#{v.to_s.strip}>"
                      end
                    else
                      escape_for_sparql(v)
                    end

    # Match both ?_key_type and ?__key_type
    pattern = /(?:\?__|\?_)#{Regexp.escape(k.to_s)}_[\w:]+/i

    query.gsub!(pattern) do |_match|
      escaped_value
    end

    warn "→ Substituted ?_#{k}_*  →  #{escaped_value}"
  end

  query
end

def escape_for_sparql(value)
  case value
  when TrueClass, FalseClass then value.to_s
  when Numeric               then value.to_s
  when String
    escaped = value.gsub('\\', '\\\\').gsub('"', '\\"')
    "\"#{escaped}\""
  else
    "\"#{value.to_s.gsub('\\', '\\\\').gsub('"', '\\"')}\""
  end
end

def validate_query(_query)
  true # ← stub – replace with real validation later
end

# ========================================================================
# ========================================================================
# ========================================================================
# ========================       MAIN     ================================
# ========================================================================
# ========================================================================
# ========================================================================
# ========================================================================
# On startup - push all the queries to External (with metadata) so they can be listed in the UI and pulled by ID later
# queries = process_folder('/queries') # mounted into the container, read-only
# ========================================================================
# On startup: Push all query metadata to Outie
# ========================================================================
# ========================================================================
# On startup: Push ALL query metadata to Outie in ONE single call
# ========================================================================
begin
  queries = QueryAnnotationParser::Parser.process_folder(QUERY_DIR)

  # Build the final list that Outie expects (and that the UI will read)
  available_queries = queries.map do |metadata|
    # Compute smart bindings from defaults + enumerate (what the UI probably wants)
    bindings = metadata['defaults'].dup || {}

    # If there are enumerated values, add them as arrays (so UI can offer dropdowns)
    (metadata['enumerate'] || {}).each do |key, values|
      bindings[key] = values if values.is_a?(Array) && !values.empty?
    end

    {
      'query_id' => metadata['query_id'],
      'title' => metadata['title'],
      'summary' => metadata['summary'],
      'description' => metadata['description'],
      'tags' => metadata['tags'],
      'variables' => metadata['variables'],
      'variable_types' => metadata['variable_types'],
      'bindings' => bindings, # ← now populated!
      'pagination' => metadata['pagination'],
      'method' => metadata['method'],
      'endpoint' => metadata['endpoint'],
      'endpoint_in_url' => metadata['endpoint_in_url']
    }.compact # remove nil keys
  end

  # ONE single POST with the full list
  push_uri = URI("#{EXTERNAL_URL}/severance/available_queries")
  push_req = Net::HTTP::Post.new(push_uri)
  push_req['Content-Type'] = 'application/json; charset=utf-8'
  push_req.body = JSON.generate(available_queries)

  http = Net::HTTP.new(push_uri.hostname, push_uri.port)
  http.use_ssl = (push_uri.scheme == 'https')
  res = http.request(push_req)

  if res.is_a?(Net::HTTPSuccess)
    warn "✓ Registered #{available_queries.size} queries"
    available_queries.each do |q|
      warn "   • #{q['query_id']} (#{q['title'] || 'no title'})"
    end
  else
    warn "⚠ Failed to register queries: #{res.code} #{res.message}"
  end

  warn "Registration completed for #{available_queries.size} queries"
rescue StandardError => e
  warn "❌ Failed to push queries on startup: #{e.class} - #{e.message}"
end

loop do
  poll_uri = URI("#{EXTERNAL_URL}/severance/queue/pull")
  http = Net::HTTP.new(poll_uri.hostname, poll_uri.port)
  http.use_ssl = (poll_uri.scheme == 'https')
  response = http.request(Net::HTTP::Get.new(poll_uri))
  if response.code == '204'
    sleep POLL_INTERVAL
    next
  end

  job = JSON.parse(response.body)
  uuid = job['uuid']
  raise 'No UUID in job response!' unless uuid

  query_id = job['query_id']
  bindings = job['bindings'] || {}

  query_path = "#{QUERY_DIR}/#{query_id}.rq"

  unless File.exist?(query_path)
    warn "Query file missing: #{query_path}"
    sleep POLL_INTERVAL
    next
  end

  query = File.read(query_path, encoding: 'UTF-8')
  warn "Found query #{query_id} (#{query_path})"

  # === Bind grlc-style placeholders (?_key_type) ===
  query = substitute_grlc_bindings(query, bindings)

  # Optional: you can also add the new 'id' field to metadata later if needed
  # For now we keep the runtime job processing simple.

  validate_query(query) # your stub

  # === Execute against triplestore ===
  uri = URI(TRIPLESTORE_URL)
  req = Net::HTTP::Post.new(uri)
  req['Accept'] = ACCEPT_HEADER
  req['Content-Type'] = 'application/sparql-query'
  req.body = query

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end

  warn "HTTP result status: #{res.code}"
  result_body = res.body.strip

  # === Push result back to External ===
  push_uri = URI("#{EXTERNAL_URL}/severance/jobs/#{uuid}/result")
  http = Net::HTTP.new(push_uri.hostname, push_uri.port)
  http.use_ssl = (push_uri.scheme == 'https')

  push_req = Net::HTTP::Post.new(push_uri)
  push_req['Content-Type'] = 'text/plain; charset=utf-8'
  push_req.body = result_body.force_encoding('UTF-8')

  push_res = http.request(push_req)
  warn "Job #{uuid} completed (push status: #{push_res.code})"
  puts "[#{Time.now}] Job #{uuid} for query #{query_id} finished"

  # Small delay before next poll
  sleep POLL_INTERVAL
end
