ENV['RACK_ENV'] = 'test'

require 'fileutils'
require 'minitest/autorun'
require 'rack/test'
require 'yaml'

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def session
    last_request.env["rack.session"]
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def admin_session
    { "rack.session" => {username: 'admin'} }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get '/'

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response['Content-Type']
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_file
    create_document "history.txt", "Ruby 0.95 released"

    get "/history.txt"
    assert_equal 200, last_response.status
    assert_equal 'text/plain', last_response['Content-Type']
    assert_includes last_response.body, "Ruby 0.95 released"
  end

  def test_nonexistant_path
    get '/whatever.txt'

    assert_equal 302, last_response.status
   
    assert_equal "whatever.txt does not exist.", session[:message]
  end

  def test_markdown_file
    create_document "about.md", "# Ruby is..."

    get '/about.md'
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_editing
    create_document "changes.txt"

    get '/changes.txt/edit', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_updating_document
    post '/changes.txt', {content: "new content"}, admin_session

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get '/changes.txt'
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_view_new_file_form
    get '/new', {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_create_valid_file
    post '/create', {filename: "test.txt"}, admin_session
    assert_equal 302, last_response.status
    assert_equal "test.txt has been created.", session[:message]

    get '/'
    assert_includes last_response.body, 'test.txt'
  end
  
  def test_create_file_no_ext
    post '/create', {filename: 'test'}, admin_session
    assert_equal 422, last_response.status
    
    assert_includes last_response.body, "Enter a valid file extension (.txt or .md)"
  end

  def test_create_file_no_name
    post '/create', {filename: ''}, admin_session
    assert_equal 422, last_response.status
    
    assert_includes last_response.body, "Must enter a name for the new file."
  end


  def test_create_file_repeat_name
    create_document "cat.txt"

    post '/create', {filename: 'cat.txt'}, admin_session
    assert_equal 422, last_response.status
    
    assert_includes last_response.body,  "File name must be unique"
  end

  def test_delete_file
    create_document "cat.txt"

    post '/cat.txt/delete', {}, admin_session
    assert_equal 302, last_response.status
    assert_equal "cat.txt has been deleted.", session[:message]

    get '/'
    refute_includes last_response.body, %q(href="/cat.txt")
  end

  def test_signin_form
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, %q(<button type="submit")
  end

  def test_signin
    post '/users/signin', username: 'admin', password: 'secret'
    assert_equal 302, last_response.status
    assert_equal 'Welcome!', session[:message]
    assert_equal 'admin', session[:username]

    get last_response['Location']
    assert_includes last_response.body, 'Signed in as admin.'
  end 

  def test_signin_with_bad_credentials
    post '/users/signin', username: 'bob', password: 'code'
    assert_equal 422, last_response.status

    assert_includes last_response.body, 'Invalid credentials' 
  end

  def test_signout
    get '/', {}, {"rack.session" => {username: 'admin'}}
    assert_includes last_response.body, 'Signed in as admin'

    post '/users/signout'
    assert_equal "You have been signed out", session[:message]

    get last_response['Location']
    assert_nil session[:username]
    assert_includes last_response.body, 'Sign In'
  end

  def test_nonadmin_delete
    post '/history.txt/delete'

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that", session[:message]
  end
end

