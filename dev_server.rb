require 'sinatra'
module Stevedore
  class NginxSimulator < Sinatra::Application
    if $0 == __FILE__
      puts "you probably shouldn't run this directly! use rackup instead"
      exit 1
    end


    ###
    # This is for dev only, it mimics the nginx config on the actual prd server.
    # But, like, who wants to run nginx on their computer for dev? that's silly.
    # This is NOT an accurate simulation of the S3 hosted option.
    ###
    URI::DEFAULT_PARSER = 
      URI::Parser.new(:UNRESERVED => URI::REGEXP::PATTERN::UNRESERVED + '|')
    set :public_folder, File.dirname(__FILE__)
    get '/:project*' do 
      open('search.html').read
    end
    get '/:project*/' do 
      open('search.html').read
    end    
    get '/' do 
      open('index.html').read
    end
  end
end
