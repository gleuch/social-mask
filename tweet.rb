require 'rubygems'
require 'sinatra'
require 'twitter'
require 'configatron'
require 'haml'
# require 'dm-core'
# require 'dm-types'
# require 'dm-timestamps'
# require 'dm-aggregates'
# require 'dm-ar-finders'


configure do
  ROOT = File.expand_path(File.dirname(__FILE__))
  configatron.configure_from_yaml("#{ROOT}/settings.yml", :hash => Sinatra::Application.environment.to_s)

  # Load default site text
  configatron.configure_from_yaml("#{ROOT}/language.#{configatron.site_language}.yml", :hash => Sinatra::Application.environment.to_s)

  # DataMapper.setup(:default, configatron.db_connection.gsub(/ROOT/, ROOT))
  # DataMapper.auto_upgrade!

  set :sessions, true
  set :views, File.dirname(__FILE__) + '/views/'+ configatron.template_name
  set :public, File.dirname(__FILE__) + '/public/'+ configatron.template_name
end


helpers do
  def dev?; (Sinatra::Application.environment.to_s != 'production'); end

  def twitter_connect(user={})
    # Requires separate gem (until this is refactored...)
    # @twitter_client = TwitterOAuth::Client.new(:consumer_key => configatron.twitter_oauth_token, :consumer_secret => configatron.twitter_oauth_secret, :token => (!user.blank? ? user.oauth_token : nil), :secret => (!user.blank? ? user.oauth_secret : nil)) rescue nil
  end

  def twitter_fail(msg=false)
    @title = configatron.title_500
    @error = (!msg.blank? ? msg : configatron.twitter_conn_fail)
    haml :fail and return
  end

  def partial(name, options = {})
    item_name, counter_name = name.to_sym, "#{name}_counter".to_sym
    options = {:cache => true, :cache_expiry => 300}.merge(options)

    if collection = options.delete(:collection)
      collection.enum_for(:each_with_index).collect{|item, index| partial(name, options.merge(:locals => { item_name => item, counter_name => index + 1 }))}.join
    elsif object = options.delete(:object)
      partial(name, options.merge(:locals => {item_name => object, counter_name => nil}))
    else
      # unless options[:cache].blank?
      #   cache "_#{name}", :expiry => (options[:cache_expiry].blank? ? 300 : options[:cache_expiry]), :compress => false do
      #     haml "_#{name}".to_sym, options.merge(:layout => false)
      #   end
      # else
        haml "_#{name}".to_sym, options.merge(:layout => false)
      # end
    end
  end

  # Modified from Rails ActiveSupport::CoreExtensions::Array::Grouping
  def in_groups_of(item, number, fill_with = nil)
    if fill_with == false
      collection = item
    else
      padding = (number - item.size % number) % number
      collection = item.dup.concat([fill_with] * padding)
    end

    if block_given?
      collection.each_slice(number) { |slice| yield(slice) }
    else
      returning [] do |groups|
        collection.each_slice(number) { |group| groups << group }
      end
    end
  end


  def user_profile_url(screen_name, at=true)
    "<a href='http://www.twitter.com/#{screen_name || ''}' target='_blank'>#{at ? '@' : ''}#{screen_name || '???'}</a>"
  end

  def parse_tweet(tweet)
    tweet = tweet.gsub(/(http|https)(\:\/\/)([A-Z0-9\.\-\_\:]+)(\/?)([\w\=\+\-\.\?\&\%\#\~\/\[\]]+)/i, '<a href="\1\2\3\4\5" target="_blank" rel="nofollow">\1\2\3\4\5</a>')
    tweet = tweet.gsub(/(@)([A-Z0-9\_]+)/i, '<a href="http://www.twitter.com/\2" target="_blank" rel="nofollow">\1\2</a>')
    tweet = tweet.gsub(/(#[A-Z0-9\_]+)/i, '<a href="http://twitter.com/search?q=\1" target="_blank" rel="nofollow">\1</a>')
    tweet
  end

end #helpers

before do

end


# 404 errors
not_found do
  # cache "error/404", :expiry => 600, :compress => true do
    @title = configatron.title_404
    @error = configatron.error_404
    haml :fail
  # end
end


# 500 errors
error do
  # cache "error/500", :expiry => 600, :compress => true do
    @title = configatron.title_500
    @error = configaton.error_500
    haml :fail
  # end
end





# Homepage
get '/' do
  # Show tweet sent page
  if session && session[:sent] === true
    @title = configatron.title_sent
    haml :sent
  else
    @title = configatron.title_home
    haml :home
  end
end

post '/' do
  @title = configatron.title_send

  if !params[:tweet] || (params[:tweet].length > 140 || params[:tweet].length < 5)
    @error = configatron.tweet_invalid
    haml :home
  else
    httpauth = Twitter::HTTPAuth.new(configatron.twitter_account_name, configatron.twitter_account_pass)
    client = Twitter::Base.new(httpauth)
    client.update(params[:tweet])
    session[:sent] = true
    redirect '/' and return
  end

end


# Initiate the conversation with Twitter
# Requires separate gem (until this is refactored...)
# get '/connect' do
#   @title = configatron.title_connect
#   twitter_connect
# 
#   begin
#     request_token = @twitter_client.request_token(:oauth_callback => "http://#{request.env['HTTP_HOST']}/auth")
#     session[:request_token] = request_token.token
#     session[:request_token_secret] = request_token.secret
#     redirect request_token.authorize_url.gsub('authorize', 'authenticate')
#   rescue
#     # cache 'error/connect', :expiry => 600, :compress => false do
#       twitter_fail(configatron.twitter_auth_fail)
#     # end
#   end
# end
# 
# 
# # Callback URL to return to after talking with Twitter
# Requires separate gem (until this is refactored...)
# get '/auth' do
#   @title = configatron.title_auth
# 
#   unless params[:denied].blank?
#     # cache 'error/auth/denied', :expiry => 600, :compress => false do
#       @error = configatron.twitter_decline.gsub(/\%t/, configatron.site_name)
#       haml :fail
#     # end
#   else
#     twitter_connect
#     @access_token = @twitter_client.authorize(session[:request_token], session[:request_token_secret], :oauth_verifier => params[:oauth_verifier])
# 
#     if @twitter_client.authorized?
#       begin
#         info = @twitter_client.info
#       rescue
#         twitter_fail and return
#       end
# 
#       @user = User.first_or_create(:account_id => info['id'])
#       @user.update_attributes(:active => true, :account_id => info['id'], :screen_name => info['screen_name'], :oauth_token => @access_token.token, :oauth_secret => @access_token.secret)
# 
#       # Set and clear session data
#       session[:user] = @user.id
#       session[:account] = @user.account_id
#       session[:request_token] = nil
#       session[:request_token_secret] = nil
# 
#     redirect '/'
#   end
# end