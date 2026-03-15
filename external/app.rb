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
  # set :host_authorization, permitted_hosts: [
  #   '127.0.0.1',
  #   'localhost',
  #   '127.0.0.1:8282',
  #   'localhost:8282',
  #   'fairdata.services',          # for proxied requests
  #   'fairdata.services:80',       # if port explicit
  #   'fairdata.services:443'       # if HTTPS
  # ]
end
# OR fully disable HostAuthorization while keeping others:
# set :protection, host_authorization: { permitted_hosts: ['fairdata.services', 'localhost'] }

QUEUE_DIR = ENV.fetch('QUEUE_DIR', '/data/queue')
RESULTS_DIR = ENV.fetch('RESULTS_DIR', '/data/results')
ENCRYPTION_KEY = [ENV.fetch('ENCRYPTION_KEY_HEX')].pack('H*')
CONTENT_TYPE = ENV['RESULT_FORMAT'] == 'csv' ? 'text/csv' : 'application/sparql-results+json'

FileUtils.mkdir_p([QUEUE_DIR, RESULTS_DIR])

# ============== Strong AES-256-GCM helpers ==============
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
  tag   = encrypted[12, 16]
  ct    = encrypted[28..]
  cipher.iv = nonce
  cipher.auth_tag = tag
  cipher.update(ct) + cipher.final
end

# ============== Token stub (uncomment to enforce) ==============
before do
  # by default, allowed IPs are all localhost clones.  Should set in the docker-compose, though
  allowed_ips = (ENV['ALLOWED_INTERNAL_IPS'] || '127.0.0.1,172.17.0.0/16,10.0.0.0/8').split(',')
  client_ip = request.ip

  # these are the paths that are called from the Inner component
  # Handle them differently - no authentication, but IP filter
  if request.path_info.start_with?('/bthere/queue/pull') ||
     request.path_info.start_with?('/bthere/jobs/') &&
     request.request_method == 'POST'
    warn 'this is an internal request'
    # Basic CIDR check (or use 'ipaddr' gem, but we're trying to be thin)
    unless allowed_ips.any? { |ip| client_ip.start_with?(ip.strip) || client_ip == ip.strip }
      halt 403, "Access denied to #{client_ip}- internal IP required"
    end
    # all checks pass, it is a call from Internal - bypass authentication
    return
  end

  # Only apply auth to everything else (user/Hub facing)
  if ENV['AUTH_TOKEN']
    auth_header = request.env['HTTP_AUTHORIZATION']
    expected = "Bearer #{ENV['AUTH_TOKEN']}"
    halt 401, "Unauthorized auth:#{auth_header}- Bearer token required" unless auth_header == expected
  end
end

# =========== Limit IP range for polling and pushing results ===
before do
end

# ============== Submit (POST or GET) ==============
post '/bthere/queries' do
  submit_job
end

get '/bthere/queries' do
  submit_job
end

get '/bthere' do
  'Nothing to see here yet. Should probably redirect somewhere useful... Registry Hub??'
end

def submit_job
  data = if request.content_type&.include?('json') || request.post?
           JSON.parse(request.body.read)
         else
           { 'query_id' => params['query_id'], 'bindings' => params.except('query_id') }
         end

  uuid = SecureRandom.uuid
  job = { query_id: data['query_id'], bindings: data['bindings'], submitted_at: Time.now.to_i }.to_json

  File.write("#{QUEUE_DIR}/#{uuid}.pending.json", job)

  status 201
  headers 'Location' => "#{request.base_url}/bthere/jobs/#{uuid}"
  body ''
end

# ============== Polling from gateway Hub ==============
get '/bthere/jobs/:uuid' do |uuid|
  pending = "#{QUEUE_DIR}/#{uuid}.pending.json"
  processing = "#{QUEUE_DIR}/#{uuid}.processing.json"
  result_file = "#{RESULTS_DIR}/#{uuid}.enc"

  if File.exist?(pending) || File.exist?(processing)
    status 202
    headers 'Retry-After' => '10'
    body '{"status":"processing"}'
  elsif File.exist?(result_file)
    begin
      encrypted = File.binread(result_file)
      # puts "[DEBUG] Encrypted file size: #{encrypted.bytesize} bytes" # log size
      data = decrypt(encrypted)
      # puts "[DEBUG] Decrypted size: #{data.bytesize} bytes, first 50 chars: #{data[0..50].inspect}"
      content_type CONTENT_TYPE
      File.delete(result_file)
      File.delete(processing) if File.exist?(processing)
      body data
    rescue OpenSSL::Cipher::CipherError => e
      warn "[ERROR] Decryption failed for #{uuid}: #{e.message}"
      status 500
      body "Decryption error: #{e.message}"
    rescue StandardError => e
      warn "[ERROR] Unexpected error serving #{uuid}: #{e.message}"
      status 500
      body 'Server error'
    end
  end
end

# ============== Internal results push ==============
post '/bthere/jobs/:uuid/result' do |uuid|
  body = request.body.read.force_encoding('UTF-8')
  # warn "[External] Received body length after encoding: #{body.bytesize}\n#{body}"
  result_file = "#{RESULTS_DIR}/#{uuid}.enc"
  processing = "#{QUEUE_DIR}/#{uuid}.processing.json"

  encrypted_data = encrypt(body)
  # warn "[ENCRYPT] Encrypted length: #{encrypted_data.bytesize} bytes"
  File.binwrite(result_file, encrypted_data)
  File.delete(processing) if File.exist?(processing)

  status 200
  body ''
end

# ============== Called from Internal poll (one job at a time) ==============
get '/bthere/queue/pull' do
  pending_files = Dir["#{QUEUE_DIR}/*.pending.json"].sort
  if pending_files.empty?
    status 204
    body ''
  else
    file = pending_files.first
    uuid = File.basename(file, '.pending.json')
    job = File.read(file)
    File.rename(file, "#{QUEUE_DIR}/#{uuid}.processing.json")
    content_type 'application/json'
    body job # ← OLD: missing uuid
    # NEW: include uuid in JSON so Internal knows it
    body JSON.parse(job).merge('uuid' => uuid).to_json
  end
end
