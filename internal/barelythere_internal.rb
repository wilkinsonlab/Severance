require 'net/http'
require 'json'
require 'fileutils'

EXTERNAL_URL   = ENV.fetch('EXTERNAL_URL')
TRIPLESTORE_URL = ENV.fetch('TRIPLESTORE_URL')
QUERY_DIR      = ENV.fetch('QUERY_DIR')
POLL_INTERVAL  = ENV.fetch('POLL_INTERVAL', 10).to_i
RESULT_FORMAT  = ENV['RESULT_FORMAT'] == 'csv' ? 'csv' : 'json'

ACCEPT_HEADER = RESULT_FORMAT == 'csv' ? 'text/csv' : 'application/sparql-results+json'

def escape_for_sparql(value)
  v = value.to_s
  if v.match?(/\Ahttps?:\/\//)
    "<#{v.gsub('>', '%3E')}>"
  else
    "\"#{v.gsub('"', '\\"').gsub("\n", '\\n')}\""
  end
end

def validate_query(_query)
  true # ← stub – replace with real validation later
end

loop do
  # === Poll External ===
  poll_uri = URI("#{EXTERNAL_URL}/queue/pull")
  response = Net::HTTP.get_response(poll_uri)

  if response.code == '204'
    sleep POLL_INTERVAL
    next
  end

  job = JSON.parse(response.body)
  uuid      = job['uuid'] || File.basename(poll_uri.path) # fallback
  query_id  = job['query_id']
  bindings  = job['bindings'] || {}

  query_path = "#{QUERY_DIR}/#{query_id}.rq"
  unless File.exist?(query_path)
    warn "Query file missing: #{query_path}"
    sleep POLL_INTERVAL
    next
  end

  query = File.read(query_path)

  # === Bind placeholders {{key}} ===
  bindings.each do |k, v|
    placeholder = "{{#{k}}}"
    query.gsub!(placeholder, escape_for_sparql(v))
  end

  validate_query(query) # stub

  # === Execute against triplestore ===
  uri = URI(TRIPLESTORE_URL)
  req = Net::HTTP::Post.new(uri)
  req['Accept'] = ACCEPT_HEADER
  req['Content-Type'] = 'application/sparql-query'
  req.body = query

  res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
    http.request(req)
  end

  result_body = res.body

  # === Push result back to External ===
  push_uri = URI("#{EXTERNAL_URL}/jobs/#{uuid}/result")
  push_req = Net::HTTP::Post.new(push_uri)
  push_req.body = result_body
  Net::HTTP.start(push_uri.hostname, push_uri.port) { |http| http.request(push_req) }

  puts "[#{Time.now}] Job #{uuid} completed"
end
