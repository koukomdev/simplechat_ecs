# myapp.rb
require 'sinatra/base'
require 'sinatra/reloader'
require 'sinatra/json'
require 'mysql2'
require 'mysql2-cs-bind'
require 'fileutils'
require 'rack-flash'
require 'openssl'
require 'active_support/all'

class MyApp < Sinatra::Base
  configure :development do
    register Sinatra::Reloader
  end

  # Not Found error
  error 404 do
    'page not found'
  end

  set :bind, '0.0.0.0'
  #enable :sessions
  use Rack::Session::Cookie
  use Rack::Session::Pool, :expire_after => 2592000
  # use Rack::Protection::RemoteToken
  # use Rack::Protection::SessionHijacking
  use Rack::Protection
  use Rack::Flash

  helpers do
    def db_connect()
      if ENV['RACK_ENV'] == "test" || ENV['RACK_ENV'] == "development"
        host = 'localhost'
      else
        host = ENV['DB_HOST']
      end

      client = Mysql2::Client.new(
        :host     => host,
        :port     => '3306',
        :username => ENV['DB_USER'],
        :password => ENV['DB_PASS'],
        :database => 'simplechat',
        :encoding => 'utf8mb4',
        :datatbase_timezone => "Asia/Tokyo"
      )
      return client
    end
    def check_user(username, row_password, client)
      sql  = "SELECT * FROM users WHERE name=?"
      user = client.xquery(sql, username).first()
      unless user
        return false
      end
      digest     = OpenSSL::Digest.new('sha256')
      created_at = user["created_at"].strftime("%Y-%m-%d %H:%M:%S")
      digest.update(row_password + created_at)
      encrypted_password = digest.hexdigest()
      if user["password"] == encrypted_password
        return user
      else
        return false
      end
    end
    def h(text)
      Rack::Utils.escape_html(text).gsub(/\R/, "<br>")
    end
    def get_comments
      sql = "
            SELECT comments.id AS comment_id, image, text, users.id AS user_id, users.name AS user_name, DATE_FORMAT(comments.created_at, '%Y/%m/%d %H:%i:%s') AS comment_created_at
            FROM comments
            INNER JOIN users
            ON comments.user_id = users.id
            ORDER BY comments.id DESC
            LIMIT 50
            "
      res = $client.xquery(sql)
      return res
    end
  end

  before do
    $client ||= db_connect()
  end

  get '/' do
    @comments = get_comments.map(&:symbolize_keys)
    erb :index
  end

  post '/comment' do
    begin
      # Validate params
      if params[:file].blank? && params[:text].blank?
        # 何もしない
        return
      end
      # Get params
      user_id = session[:user_id]
      image = ''
      if params[:file]
        image_ext  = params[:file][:type].split("/")[1]
        # Validate ext
        unless ["png", "jpeg", "gif"].include?(image_ext)
          data = {status: "error", message: "拡張子は .png, .jpg, .gif のいずれかにしてください"}
          return json data
        end
        image = Base64.strict_encode64(params[:file][:tempfile].read)
      end
      text = params[:text]
      created_at = Time.now.strftime("%Y-%m-%d %H:%M:%S")
      # Save Contents (DB)
      sql = "INSERT INTO comments (user_id, image, text, created_at) VALUES (?, ?, ?, ?)"
      $client.xquery(sql, user_id, image, text, created_at)
    rescue
      data = {status: "error", message: "コメントに失敗しました"}
      return json data
    end

    data = {status: "success"}
    comments = get_comments
    comments.map{|h_c| h_c['text'] = Rack::Utils.escape_html(h_c['text']).gsub(/\R/, "<br>")}
    data[:comments] = comments
    data[:user_id] = session[:user_id]
    return json data
  end

  get '/comment' do
    data = {status: "success"}
    comments = get_comments
    comments.map{|h_c| h_c['text'] = Rack::Utils.escape_html(h_c['text']).gsub(/\R/, "<br>")}
    data[:comments] = comments
    data[:user_id] = session[:user_id]
    return json data
  end

  get '/signin' do
    if session[:user_id]
      redirect "/"
    end
    erb :signin, :layout => :layout_sign
  end

  post '/signin' do
    # checkuser
    user = check_user(params[:username], params[:password], $client)
    if user
      session[:user_id]  = user["id"]
      session[:username] = user["name"]
      redirect '/'
    else
      flash[:style]   = "danger"
      flash[:message] = "ユーザ名またはパスワードが間違っています"
      redirect "/signin"
    end
  end

  get '/signup' do
    erb :signup, :layout => :layout_sign
  end

  post '/signup' do
    username     = params[:username]
    row_password = params[:password]
    if username == '' || row_password == ''
      flash[:style]   = "danger"
      flash[:message] = "ユーザ名またはパスワードを入力してください"
      redirect '/signup'
    end
    if row_password.length < 6
      flash[:style]   = "danger"
      flash[:message] = "パスワードは6文字以上にしてください"
      redirect '/signup'
    end
    sql = "SELECT * FROM users WHERE name=?"
    user = $client.xquery(sql, username)
    if user.first()
      flash[:style]   = "danger"
      flash[:message] = "すでに存在するユーザーです"
      redirect '/signup'
    end
    created_at   = Time.now.strftime("%Y-%m-%d %H:%M:%S")
    digest       = OpenSSL::Digest.new('sha256')
    digest.update(row_password + created_at)
    encrypted_password = digest.hexdigest()
    sql = "INSERT INTO users (name, password, created_at) VALUES (?, ?, ?)"
    $client.xquery(sql, username, encrypted_password, created_at)
    session[:username] = username
    session[:user_id]  = $client.last_id
    redirect '/'
  end

  get '/signout' do
    session.clear
    redirect '/signin'
  end

  run! if app_file == $0
end
