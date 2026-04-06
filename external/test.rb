require 'sinatra'

set :environment, :production # or rely on env var
# set :protection, false   # try this too

get '/' do
  "Hello from Sinatra! Auth header: #{request.env['HTTP_AUTHORIZATION'] || 'none'}"
end
