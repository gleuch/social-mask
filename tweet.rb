require 'rubygems'
require 'sinatra'

gem 'twitter', '~> 0.7.6'
require 'twitter' # http://github.com/jnunemaker/twitter

require 'configatron'
require 'haml'


configure do
  ROOT = File.expand_path(File.dirname(__FILE__))
  configatron.configure_from_yaml("#{ROOT}/settings.yml", :hash => Sinatra::Application.environment.to_s)

  set :sessions, true
  set :views, File.dirname(__FILE__) + '/views/'+ configatron.template_name
  set :public, File.dirname(__FILE__) + '/public/'+ configatron.template_name

  # Load default language text
  configatron.configure_from_yaml("#{ROOT}/language.#{configatron.site_language}.yml", :hash => Sinatra::Application.environment.to_s)

  # Load database information for OAuth login
  if configatron.require_oauth_login
    %w(dm-core dm-types dm-timestamps dm-aggregates dm-ar-finders user).each{|lib| require lib}
    DataMapper.setup(:default, configatron.db_connection.gsub(/ROOT/, ROOT))
    DataMapper.auto_upgrade!
  end

  require 'sinatra/memcache'
  set :cache_enable, (configatron.enable_memcache && Sinatra::Application.environment.to_s == 'production')
  set :cache_logging, false # causes problems if using w/ partials! :/
end


helpers do
  def dev?; (Sinatra::Application.environment.to_s != 'production'); end

  def get_user; @user = User.first(:id => session[:user]) rescue nil; end

  def get_recipient_stream
    return unless configatron.require_oauth_login && configatron.view_account_stream && @recipient_stream.nil?
    begin
      @recipient ||= User.first(:screen_name => configatron.twitter_account_name) rescue nil
      twitter_connect(@recipient)
      @recipient_stream ||= @twitter_client.home_timeline if @twitter_client
    rescue Timeout::Error
      STDERR.puts "Timeout with get_recipient_stream."
      @recipient_stream = {}
    rescue
      STDERR.puts "Problem with get_recipient_stream. (#{$!})"
      @recipient_stream = {}
    end
  end

  def get_recipient_info
    return unless configatron.require_oauth_login && configatron.view_account_stream && @recipient_info.nil?
    begin
      @recipient ||= User.first(:screen_name => configatron.twitter_account_name) rescue nil
      twitter_connect(@recipient)
      name = @recipient.screen_name rescue nil
      name ||= configatron.twitter_account_name
      @recipient_info ||= @twitter_client.user(name) if @twitter_client
    rescue Timeout::Error
      STDERR.puts "Timeout with get_recipient_info."
      @recipient_info = {}
    rescue
      STDERR.puts "Problem with get_recipient_info. (#{$!})"
      @recipient_info = {}
    end
  end

  def get_recipient_friends
    return unless configatron.require_oauth_login && configatron.view_account_stream && @recipient_friends.nil?
    begin
      @recipient ||= User.first(:screen_name => configatron.twitter_account_name) rescue nil
      twitter_connect(@recipient)
      @recipient_friends ||= @twitter_client.friends if @twitter_client
    rescue Timeout::Error
      STDERR.puts "Timeout with get_recipient_friends."
      @recipient_friends = {}
    rescue
      STDERR.puts "Problem with get_recipient_friends. (#{$!})"
      @recipient_friends = {}
    end
  end

  def get_recipient_lists
    return unless configatron.require_oauth_login && configatron.view_account_stream && @recipient_lists.nil?
    begin
      @recipient ||= User.first(:screen_name => configatron.twitter_account_name) rescue nil
      twitter_connect(@recipient)
      @recipient_lists ||= @twitter_client.lists(configatron.twitter_account_name) if @twitter_client
    rescue Timeout::Error
      STDERR.puts "Timeout with get_recipient_lists."
      @recipient_lists = {}
    rescue
      STDERR.puts "Problem with get_recipient_lists. (#{$!})"
      @recipient_lists = {}
    end
  end

  def has_valid_tweet_session
    if configatron.tweet_per_session
      if configatron.require_oauth_login
        time = @user.tweeted_at.to_i rescue 0
      else
        time = session[:sent]
      end

      return ((configatron.tweet_per_session === true && session[:sent] === true) || (configatron.tweet_per_session.to_i > 0 && time > (Time.now-configatron.tweet_per_session.to_i)))
    else
      return false
    end
  end

  def twitter_auth(user={})
    begin
      @twitter_auth = Twitter::OAuth.new(configatron.twitter_oauth_token, configatron.twitter_oauth_secret, :sign_in => true) rescue nil
      @twitter_auth.authorize_from_access(user.oauth_token, user.oauth_secret) unless user.blank?
    rescue Timeout::Error
    rescue
    end
  end
  
  def twitter_connect(user={})
    begin
      twitter_auth(user)
      @twitter_client = Twitter::Base.new(@twitter_auth)
    rescue Timeout::Error
    rescue
    end
  end

  def twitter_fail(msg=false)
    @title = configatron.title_500
    @error = (!msg.blank? ? msg : configatron.twitter_conn_fail)
    haml :fail
  end

  def partial(name, options = {})
    item_name, counter_name = name.to_sym, "#{name}_counter".to_sym
    options = {:cache => true, :cache_expiry => 300}.merge(options)

    if collection = options.delete(:collection)
      collection.enum_for(:each_with_index).collect{|item, index| partial(name, options.merge(:locals => { item_name => item, counter_name => index + 1 }))}.join
    elsif object = options.delete(:object)
      partial(name, options.merge(:locals => {item_name => object, counter_name => nil}))
    else
      unless options[:cache].blank?
        cache "_#{name}", :expiry => (options[:cache_expiry].blank? ? 300 : options[:cache_expiry]), :compress => false do
          haml "_#{name}".to_sym, options.merge(:layout => false)
        end
      else
        haml "_#{name}".to_sym, options.merge(:layout => false)
      end
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


  def user_profile_url(screen_name, at=true); "<a href='http://www.twitter.com/#{screen_name || ''}' target='_blank'>#{at ? '@' : ''}#{screen_name || '???'}</a>"; end
  def parse_tweet(tweet)
    tweet = tweet.gsub(/(http|https)(\:\/\/)([A-Z0-9\.\-\_\:]+)(\/?)([\w\=\+\-\.\?\&\%\#\~\/\[\]]+)/i, '<a href="\1\2\3\4\5" target="_blank" rel="nofollow">\1\2\3\4\5</a>')
    tweet = tweet.gsub(/(@)([A-Z0-9\_]+)/i, '<a href="http://www.twitter.com/\2" target="_blank" rel="nofollow">\1\2</a>')
    tweet = tweet.gsub(/(#[A-Z0-9\_]+)/i, '<a href="http://twitter.com/search?q=\1" target="_blank" rel="nofollow">\1</a>')
    tweet
  end
  def flash; @_flash ||= {}; end
  def redirect(uri, *args)
    session[:_flash] = flash unless flash.empty?
    status 302
    response['Location'] = uri
    halt(*args)
  end
  def possessiveify(str); str.match(/s$/i) ? "#{str}'" : "#{str}'s"; end

  def commify(n, max=false, title='', char='%.01f', plus=true) # Courtesy of Magma <http://mag.ma>
    n.to_s =~ /([^\.]*)(\..*)?/
    int, dec = $1.reverse, $2 ? $2 : ""
    while int.gsub!(/(,|\.|^)(\d{3})(\d)/, '\1\2,\3'); end
    int = int.reverse + dec

    if (max && (max === true || max <= n.to_i) && n.to_i >= 1000)
      if (n.to_i >= 1000000000)
        num = sprintf(char, (n.to_i/100000000.to_f))
        ext = 'b'
      elsif (n.to_i >= 1000000)
        num = sprintf(char, (n.to_i/1000000.to_f))
        ext = 'm'
      else (n.to_i >= 1000)
        num = sprintf(char, (n.to_i/1000.to_f))
        ext  = 'k'
      end
    
      num.to_s =~ /([^\.]*)(\..*)?/
      num, dec = $1.reverse, $2 ? $2 : ""
      while num.gsub!(/(,|\.|^)(\d{3})(\d)/, '\1\2,\3')
      end
      num = num.reverse + dec
    
      str = "#{num}<span class='num_ext'>#{ext}</span>#{plus ? "<span class='num_plus'>+</span>" : ''}"
    else
      str = int
    end
    "<span title='#{int} #{title}'>#{str}</span>"
  end
end #helpers



before do
  # Don't execute for image, css, or js paths.
  unless (request.env['REQUEST_PATH'] || '').match(/^\/(css|js|image)/i)
    get_user if configatron.require_oauth_login
    @_flash, session[:_flash] = session[:_flash], nil if session[:_flash]
  end
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
  if has_valid_tweet_session
    @title = configatron.title_sent
    haml :sent
  else
    @title = configatron.title_home
    haml :home
  end
end


# Post a tweet
post '/' do
  @title = configatron.title_send

  if !params[:tweet] || (params[:tweet].length > 140 || params[:tweet].length < 5)
    flash[:error] = configatron.tweet_invalid
    redirect '/'
  else

    # Can this be OAuth if said account was done like this?
    if configatron.require_oauth_login
      return twitter_fail(configatron.error_require_login) if @user.nil? # User login in check...
      @recipient ||= User.first(:screen_name => configatron.twitter_account_name) rescue nil
    else
      @recipient = nil
    end

    begin
      # Use OAuth if recipeint account has connected to app before.
      unless @recipient.nil? # We assume OAuth is enabled and @user is set via check done above
        twitter_connect(@recipient)

        thru_recipient = @twitter_client.update(params[:tweet])
        @user.update(:tweeted_at => Time.now) # Update tweeted_at timestamp

        if configatron.send_though_sender
          twitter_connect(@user)
          thru_sender = @twitter_client.update(params[:tweet])
        end

      # Otherwise connect through HTTP Auth
      else
        httpauth = Twitter::HTTPAuth.new(configatron.twitter_account_name, configatron.twitter_account_pass)
        client = Twitter::Base.new(httpauth)
        thru_recipient = client.update(params[:tweet], :source => '') # Sent tweet, make source '' so it does not say API (weird hack, inorite!?)
      end

      session[:sent] = Time.now.to_i
      session[:tweet] = params[:tweet]

      flash[:notice] = (thru_sender.blank? ? configatron.tweet_sucesss : configatron.tweet_thru_sucesss).gsub(/\%t/, user_profile_url(configatron.twitter_account_name))
      redirect '/' and return
    rescue
      twitter_fail(configatron.twitter_auth_fail)
    end

  end
end


get '/about' do
  @hide_stream = true
  haml :about
end