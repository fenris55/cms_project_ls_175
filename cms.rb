require 'sinatra'
require 'sinatra/reloader'
require 'tilt/erubis'
require 'redcarpet'
require 'yaml'
require 'bcrypt'

configure do
  enable :sessions
  set :session_secret, '86aaf908baa685a1f172e83d115ab48b19ef28bf26cedb6d5042c11a6b3bada6'
end


def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def render_markdown(file)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(file)
end

def load_file_content(path)
  content = File.read(path)

  case File.extname(path)
  when '.txt'
    headers["Content-Type"] = "text/plain"
    content
  when '.md'
    erb render_markdown(content)
  end
end

def admin?
  session[:username] == 'admin'
end

def deny_access
  unless admin?
    session[:message] = "You must be signed in to do that"
    redirect '/'
  end
end

def load_user_credentials
  credentials_path = if ENV["RACK_ENV"] == 'test'
      File.expand_path("../test/users.yml", __FILE__)
    else
      File.expand_path("../users.yml", __FILE__)
    end
    YAML.load_file(credentials_path)
end

def valid_credentials?(username, password)
  credentials = load_user_credentials

  if credentials.key?(username)
    bcrypt_password = BCrypt::Password.new(credentials[username])
    bcrypt_password == password
  else
    false
  end
end

# updated solution to contain full path
root = File.expand_path("..", __FILE__)

get "/" do
  pattern = File.join(data_path, "*")
  @files = Dir.glob(pattern).map do |path|
    File.basename(path)
  end

  erb :index
end

get '/users/signin' do 
  erb :signin
end

post '/users/signin' do 
  username = params[:username]

  if valid_credentials?(username, params[:password])
    session[:username] = username
    session[:message] = 'Welcome!'
    redirect '/'
  else
    session[:message] = "Invalid credentials"
    status 422
    erb :signin
  end
end

post "/users/signout" do  
  session.delete(:username)
  session[:message] = "You have been signed out"
  redirect '/'
end

def no_ext?(filename)
  filename.split('.').size == 1
end

def invalid_ext?(filename)
  ext = filename.split('.').last
  !%w(md txt).include?(ext)
end

def existing_name?(filename)
  file_path = File.join(data_path, filename)
  File.exist?(file_path)
end

def validate_filename(filename)
  case 
  when filename.size == 0
    "Must enter a name for the new file."
  when no_ext?(filename)
    "Enter a valid file extension (.txt or .md)"
  when invalid_ext?(filename)
    "File extension must be 'md' or 'txt'."
  when existing_name?(filename)
    "File name must be unique"
  else
    false
  end
end

# create a new file
get '/new' do
  deny_access
  erb :new
end

post '/create' do 
  deny_access

  filename = params[:filename].to_s
  error_message = validate_filename(filename)

  if error_message
    session[:message] = error_message
    status 422
    erb :new
  else
    file_path = File.join(data_path, filename)

    File.write(file_path, '')
    session[:message] = "#{filename} has been created."
  
    redirect '/'
  end
end

# per solution, updated to reference full path
get "/:filename" do
  file_path = File.join(data_path, params[:filename])

  if File.exist?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# edit existing file
get '/:filename/edit' do 
  deny_access
  
  file_path = File.join(data_path, params[:filename])
  
  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit
end

post '/:filename' do 
  deny_access
  
  file_path = File.join(data_path, params[:filename])
  
  File.write(file_path, params[:content])

  session[:message] = "#{params[:filename]} has been updated."

  redirect '/'
end

post '/:filename/delete' do 
  deny_access

  filename = params[:filename]
  file_path = File.join(data_path, filename)

  File.delete(file_path)

  session[:message] = "#{filename} has been deleted."
  redirect '/'
end