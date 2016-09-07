source "https://rubygems.org"

platform :jruby do 
  gem 'bundler'
  gem 'elasticsearch'
  gem 'manticore'
  # gem "jruby-openssl"
  gem 'aws-sdk', '~> 2'
  gem 'guess_html_encoding'

  # a small fork of https://github.com/ricn/rika at http://github.com/jeremybmerrill/tika
  # but with my own custom version of Tika, http://github.com/jeremybmerrill/tika
  # because Warbler can't handle gems sourced from git, I had to make a whole new gem.
  gem 'stevedore-uploader', "~> 1.0.3"
  
  gem "sinatra"
  gem "warbler", "2.0.0.rc2"
  gem "jruby-jars", "9.0.5.0"

  # these are just for the social media scraping functionality
  gem "instagram"
  gem "twitter"
  gem "koala"

  gem "therubyrhino" # for an uberhackish way of checking if we're doing slash-based, nginx-style routing (not S3-style routing with querystring params)

end
