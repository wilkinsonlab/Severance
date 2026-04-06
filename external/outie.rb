require 'sinatra'
require 'json'
require 'securerandom'
require 'openssl'
require 'fileutils'

configure do
  set :server, 'puma'
  set :bind, '0.0.0.0'
  set :port, ENV.fetch('PORT', 4567).to_i
  set :protection, except: :host_authorization
end

# Use absolute paths from environment or sensible defaults
QUEUE_DIR = ENV.fetch('QUEUE_DIR', '/data/queue')
RESULTS_DIR = ENV.fetch('RESULTS_DIR', '/data/results')

# Debug - print ALL important variables
warn '=== Environment Debug ==='
warn "QUEUE_DIR = #{QUEUE_DIR.inspect}"
warn "RESULTS_DIR = #{RESULTS_DIR.inspect}"
warn "ENCRYPTION_KEY_HEX present = #{ENV['ENCRYPTION_KEY_HEX'] ? 'YES' : 'NO'}"
warn "AUTH_TOKEN = #{ENV['AUTH_TOKEN'] ? '*** (present)' : 'NOT SET'}"
warn "RESULT_FORMAT = #{ENV['RESULT_FORMAT'].inspect}"
warn '========================='

ENCRYPTION_KEY = [ENV.fetch('ENCRYPTION_KEY_HEX')].pack('H*')
CONTENT_TYPE = ENV['RESULT_FORMAT'] == 'csv' ? 'text/csv' : 'application/sparql-results+json'

# Create directories using absolute paths
begin
  FileUtils.mkdir_p([QUEUE_DIR, RESULTS_DIR])
  warn "✓ Successfully created directories: #{QUEUE_DIR} and #{RESULTS_DIR}"
rescue Errno::EACCES => e
  warn "❌ Permission error creating directories: #{e.message}"
  warn ' Make sure the volume is mounted and the user has write access.'
  raise
end

# ============== AES-256-GCM helpers ==============
def encrypt(data)
  cipher = OpenSSL::Cipher.new('aes-256-gcm')
  cipher.encrypt
  cipher.key = ENCRYPTION_KEY
  nonce = cipher.random_iv
  ciphertext = cipher.update(data) + cipher.final
  tag = cipher.auth_tag
  nonce + tag + ciphertext
end

def decrypt(encrypted)
  cipher = OpenSSL::Cipher.new('aes-256-gcm')
  cipher.decrypt
  cipher.key = ENCRYPTION_KEY
  nonce = encrypted[0, 12]
  tag = encrypted[12, 16]
  ct = encrypted[28..]
  cipher.iv = nonce
  cipher.auth_tag = tag
  cipher.update(ct) + cipher.final
end

# ============== Security: Internal IP filtering for sensitive endpoints ==============
before do
  # === Internal calls from Innie (no auth required) ===
  internal_paths = ['/severance/queue/pull', '/severance/jobs/', '/severance/available_queries']

  if internal_paths.any? { |p| request.path_info.start_with?(p) }
    allowed_ips = (ENV['ALLOWED_INTERNAL_IPS'] || '127.0.0.1,::1,localhost').split(',').map(&:strip)

    client_ip = request.ip

    # Allow if client IP is in the list or it's localhost
    is_allowed = allowed_ips.include?(client_ip) ||
                 (allowed_ips.include?('localhost') && ['127.0.0.1', '::1'].include?(client_ip))

    halt 403, "Access denied from #{client_ip} - internal IP required" unless is_allowed

    # Internal call → bypass Bearer token check
    return
  end

  # === External/user-facing calls - require Bearer token ===
  if ENV['AUTH_TOKEN']
    auth_header = request.env['HTTP_AUTHORIZATION']
    expected = "Bearer #{ENV['AUTH_TOKEN']}"

    unless auth_header && auth_header.casecmp?(expected)
      warn "Auth failed. Received: #{auth_header.inspect} | Expected: #{expected}"
      halt 401, 'Unauthorized'
    end
  end
end

def submit_job
  # Safely parse input whether it's JSON or form data
  data = if request.content_type&.include?('application/json')
           JSON.parse(request.body.read)
         else
           # For form-encoded or query params
           { 'query_id' => params['query_id'], 'bindings' => params.except('query_id') }
         end

  # Ensure we have a hash and extract query_id safely
  query_id = data.is_a?(Hash) ? data['query_id'] : nil

  halt 400, { error: 'query_id is required' }.to_json if query_id.nil? || query_id.to_s.strip.empty?

  uuid = SecureRandom.uuid
  job = {
    'query_id' => query_id.to_s.strip,
    'bindings' => (data.is_a?(Hash) ? data['bindings'] || {} : {}),
    'submitted_at' => Time.now.to_i
  }

  File.write("#{QUEUE_DIR}/#{uuid}.pending.json", JSON.generate(job))

  status 201
  headers 'Location' => "#{request.base_url}/severance/jobs/#{uuid}"
  body ''
end

# ============== Catalog or retrieve valid queries from innie ==============
# ============== Receive available queries from Innie (full list) ==============
# ============== Receive available queries from Innie (full list) ==============
# ============== Receive list of available queries from Innie ==============
# ============== Receive list of available queries from Innie ==============
post '/severance/available_queries' do
  queries = JSON.parse(request.body.read)

  metadata_dir = ENV.fetch('METADATA_DIR', '/metadata')
  active_queries_path = "#{metadata_dir}/active_queries.json"

  File.write(active_queries_path, JSON.pretty_generate(queries))

  warn "✓ Received and saved #{queries.size} available queries to #{active_queries_path}"
  status 200
  content_type 'application/json'
  body({ success: true, count: queries.size }.to_json)
rescue JSON::ParserError => e
  warn "❌ Invalid JSON in /available_queries: #{e.message}"
  status 400
  content_type 'application/json'
  body({ error: 'Invalid JSON' }.to_json)
rescue StandardError => e
  warn "❌ Error saving available queries: #{e.message}"
  status 500
  content_type 'application/json'
  body({ error: 'Internal server error' }.to_json)
end

get '/severance/available_queries' do
  metadata_dir = ENV.fetch('METADATA_DIR', '/metadata')
  active_queries_path = "#{metadata_dir}/active_queries.json"

  if File.exist?(active_queries_path)
    content_type 'application/json'
    File.read(active_queries_path)
  else
    status 404
    content_type 'application/json'
    body({ error: 'No queries available yet' }.to_json)
  end
end

# ============== Status / Result retrieval ==============
get '/severance/jobs/:uuid' do |uuid|
  pending    = "#{QUEUE_DIR}/#{uuid}.pending.json"
  processing = "#{QUEUE_DIR}/#{uuid}.processing.json"
  result_file = "#{RESULTS_DIR}/#{uuid}.enc"

  if File.exist?(pending) || File.exist?(processing)
    status 202
    headers 'Retry-After' => '10'
    body '{"status":"processing"}'
  elsif File.exist?(result_file)
    begin
      encrypted = File.binread(result_file)
      data = decrypt(encrypted)
      content_type CONTENT_TYPE
      File.delete(result_file)
      File.delete(processing) if File.exist?(processing)
      body data
    rescue OpenSSL::Cipher::CipherError => e
      warn "[ERROR] Decryption failed for #{uuid}: #{e.message}"
      status 500
      body 'Decryption error'
    rescue StandardError => e
      warn "[ERROR] Serving result #{uuid}: #{e.message}"
      status 500
      body 'Server error'
    end
  else
    status 404
    body '{"error":"not found"}'
  end
end

# ============== Internal: Push result from "innie" ==============
post '/severance/jobs/:uuid/result' do |uuid|
  body_content = request.body.read.force_encoding('UTF-8')
  result_file = "#{RESULTS_DIR}/#{uuid}.enc"
  processing  = "#{QUEUE_DIR}/#{uuid}.processing.json"

  encrypted_data = encrypt(body_content)
  File.binwrite(result_file, encrypted_data)
  File.delete(processing) if File.exist?(processing)

  status 200
  body ''
end

# ============== Internal: Poll for next job ==============
get '/severance/queue/pull' do
  pending_files = Dir["#{QUEUE_DIR}/*.pending.json"].sort
  if pending_files.empty?
    status 204
    body ''
  else
    file = pending_files.first
    uuid = File.basename(file, '.pending.json')
    job_json = File.read(file)

    # Move to processing
    File.rename(file, "#{QUEUE_DIR}/#{uuid}.processing.json")

    # Add uuid to the response
    job = JSON.parse(job_json)
    job['uuid'] = uuid

    content_type 'application/json'
    body JSON.generate(job)
  end
end

# Optional helper routes
get '/severance' do
  'Outie service ready. Use /severance/queries to submit jobs.'
end
