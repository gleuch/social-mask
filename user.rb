class User
  include DataMapper::Resource

  property :id,               Serial
  property :account_id,       Integer
  property :screen_name,      String
  property :oauth_token,      String
  property :oauth_secret,     String
  property :weight,           Integer,    :default => 0
  property :tweeted_at,       DateTime
  property :active,           Boolean,    :default => true
  property :created_at,       DateTime
  property :updated_at,       DateTime

end




# Initiate the conversation with Twitter
# Requires separate gem (until this is refactored...)
get '/connect' do
  redirect '/' and return unless configatron.require_oauth_login
  
  @title = configatron.title_connect

  begin
    twitter_auth
    @twitter_auth.set_callback_url("http://#{request.env['HTTP_HOST']}/auth")
    
    session[:request_token] = @twitter_auth.request_token.token
    session[:request_token_secret] = @twitter_auth.request_token.secret
    
    redirect @twitter_auth.request_token.authorize_url
  rescue
  #   # cache 'error/connect', :expiry => 600, :compress => false do
      twitter_fail(configatron.twitter_auth_fail)
  #   # end
  end
end


# Callback URL to return to after talking with Twitter
# Requires separate gem (until this is refactored...)
get '/auth' do
  redirect '/' and return unless configatron.require_oauth_login
  
  @title = configatron.title_auth
  
  unless params[:denied].blank?
    # cache 'error/auth/denied', :expiry => 600, :compress => false do
      @error = configatron.twitter_decline.gsub(/\%t/, configatron.site_name)
      haml :fail
    # end
  else
    twitter_auth
    @access_token = @twitter_auth.authorize_from_request(session[:request_token], session[:request_token_secret], params[:oauth_verifier]) rescue nil  

    info = Twitter::Base.new(@twitter_auth).verify_credentials rescue nil

    if info
      @user = User.first_or_create(:account_id => info['id'])
      @user.update_attributes(:active => true, :account_id => info['id'], :screen_name => info['screen_name'], :oauth_token => @twitter_auth.access_token.token, :oauth_secret => @twitter_auth.access_token.secret)
  
      # Set and clear session data
      session[:user], session[:account] = @user.id, @user.account_id
      session[:request_token] = session[:request_token_secret] = nil

      flash[:notice] = 'Account synced.'
      redirect '/'
    else
      twitter_fail
    end

  end
end

get '/logout' do
  session[:user] = session[:account] = nil
  redirect '/'
end