require 'sinatra'
require 'ostruct'

set :public_folder, File.join(File.dirname(__FILE__), '/../lib')
set logs: StringIO.new('', 'r+')

$node = nil
 
# Remember, these URLs are actually /upload/'
get '/' do
  erb :uploader
end

post '/do' do 
  invalid = []
  # should validate, if not, redirect back (without erasing, hopefully)
  # {"es-host"=>"loafs", 
  #  "index-title"=>"asdfasdf", 
  #  "index-description"=>"adfs", 
  #  "files"=>"adfsfdsa", 
  #  "frontend-location"=>"asfdasdfsfd"
  # }

  OPTIONS = OpenStruct.new

  OPTIONS.index = ES_INDEX =  params["index-name"]
  invalid << ["index-name", params["index-name"]] if ES_INDEX.nil? || ES_INDEX.empty?


  # if the files are already on S3, extract the bucket name from params["files"]
  # if they're not, extract the bucket name from params["frontend-location"] 
  FOLDER = $search_files = params["files"]
  OPTIONS.s3path = params["files"].gsub(/s3:\/\//i, '').split("/", 2).last

  if params["local"] == "local"
    OPTIONS.host = ES_HOST = "localhost:9200"
    OPTIONS.is_local = true
    OPTIONS.no_front_end = true
  else
    # get the bucket where we're going to put the search frontend's files
    OPTIONS.frontend_location = params["frontend-location"]
    FRONTEND_S3_BUCKET = OPTIONS.frontend_location.gsub(/s3:\/\//i, '').split("/", 2).first
    invalid << ['frontend-location', params["frontend-location"]] if FRONTEND_S3_BUCKET.nil? || FRONTEND_S3_BUCKET.empty?

    OPTIONS.host = ES_HOST = params["es-host"]
    OPTIONS.is_local = false
    invalid << ['es-host', params["es-host"]] if ES_HOST.nil?
  end
  require_relative './upload'


  puts "Invalid: #{invalid.inspect}"
  halt JSON.dump({success: false, invalid: invalid}) unless invalid.empty?
  
  filetype = params["filetype"] == "OTHER" ? params["other-filetype"] : params["filetype"] 

  begin
    f = Stevedore::ESUploader.new()
    f.setup!
    f.do! settings.logs

  rescue StandardError => e
    halt JSON.dump({success: false, error: e.message + "\n" + e.backtrace.join("\n") })
  end


  if f.errors.size > 0  
    STDERR.puts "#{f.errors.size} failed documents:"
    STDERR.puts f.errors.inspect 
  end


  settings.logs.puts "Uploading front end"
  f.upload_front_end({
            "index_name" => ES_INDEX,
            "name" => params["index-title"].to_s,
            "private?" => "FALSE",
            "data_type" => filetype.empty? ? "blob" : filetype,
            "description" => params["index-description"].to_s
    }) unless OPTIONS.no_front_end
  settings.logs.puts "Finished at #{Time.now}"

  if params["local"] != "local"
    frontend_url = File.join(FRONTEND_S3_BASEPATH.gsub("https:", 'http:'), "/stevedore/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{ES_INDEX}")
    settings.logs.puts "Uploaded to #{ES_INDEX}; go check out the search engine at: \n #{frontend_url}\n "
  else
    frontend_url = "/search.html?first&template=#{filetype.empty? ? "blob" : filetype}##{ES_INDEX}"
  end
  settings.logs.flush
  JSON.dump({success: true, frontend_url: frontend_url})
end


# not actually a stream ;-)
# because sinatra/streaming mysteriously breaks
# in Warbler/Jetty. :(
# Remember, these URLs are actually /upload/stream
get '/stream', provides: 'text/event-stream' do
  str = settings.logs.string
  msg = (str[-10000..-1] || str).gsub("\n", "<br />")
  "data: #{msg}\n\n"
end

at_exit{
  $node.stop if $node
}
