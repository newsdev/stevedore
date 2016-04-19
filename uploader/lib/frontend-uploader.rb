module Stevedore
  # puts the frontend on S3 for ya.
  # alternatively, you can put everything matched by THINGS_TO_WRITE somewhere it'll be served by nginx
  class FrontendUploader
    THINGS_TO_WRITE = ["app/**/*", "lib/**/*", "templates/**/*", "document_sets.json", "index.html", "search.html", "LICENSE"]
    
    def initialize(es_host, es_index, s3_bucket=nil, s3_path=nil)
      @es_host =     es_host
      @es_index =    es_index
      @frontend_s3_bucket =   s3_bucket || FOLDER.downcase.match(/^s3:\/\/([^\/]+)\/.*/i)[1]
      raise ArgumentError, "you need to specify an S3 bucket" if @frontend_s3_bucket.nil?
      @frontend_s3_path = s3_path || es_index
      @frontend_s3_basepath = "https://#{@frontend_s3_bucket}.s3.amazonaws.com/#{@frontend_s3_path}"
    end

    def frontend_config_details
      es_uri = URI(@es_host)
      document_sets_path = "document_sets.json" #TODO
<<-CONFIG
// the details for how to connect to your ElasticSearch instance
// and where to get metadata from 
// get AUTOMATICALLY written here.
// If you edit this file, it will get overwritten and your changes erased if
// you ever reupload the frontend..

Stevedore.config = {
  prdHost: "#{es_uri.host}",
  prdPort: "#{es_uri.port}",
  prdScheme: "#{es_uri.scheme}",
  prdPath: "#{es_uri.path}",
  document_set_meta_json: "#{document_sets_path}"
  use_slash_based_routing: false
}
// if a document set has multiple data types in it,
// you can choose one content type to be displayed with your chosen list_view
// and detail_view templates, and the rest displayed as "blobs" (just their text).
// write a string or Regexp here that will be matched against the analyzed.metadata["Content-Type"]
// of each document to determine whether to use the chosen template (if it matches)
// or the blob template (if it doesn't match)
Stevedore.content_types = {
  'email': "message/rfc822",
  'hypothetical': /application\\\/pdf/,
  'social-media': /.*/,
}
CONFIG
    end

    def upload_front_end(new_index_details=nil)
      Aws.config.update({
        region: 'us-east-1',
      })
      s3 = Aws::S3::Resource.new
      bucket = s3.bucket(@frontend_s3_bucket)
      THINGS_TO_WRITE.each do |path|
        Dir.glob(File.join(File.dirname(__FILE__), '../..', path)).each do |filename|
          puts "starting #{filename}"
          next if File.directory?(filename)
          open(filename, 'r') do |f|
            file_contents = f.read
            content_type =  if filename.match(/\.json$/)
                              "application/json"
                            elsif filename.match(/\.template$/)
                              "text/plain"
                            elsif filename.match(/\.js$/)
                              "text/javascript"
                            elsif filename.match(/\.html$/)
                              "text/html"
                            elsif filename.match(/\.svg$/)
                              "image/svg+xml"
                            elsif filename.match(/\.eot$/)
                              "application/vnd.ms-fontobject"
                            elsif filename.match(/\.ttf$/)
                              "application/x-font-ttf"
                            elsif filename.match(/\.woff$/)
                              "application/font-woff"
                            elsif filename.match(/\.css$/)
                              "text/css"
                            else
                              "text/plain"
                            end
            if filename == "app/config.js"
              file_contents = frontend_config_details
            elsif filename == "document_sets.json"
              document_sets = if File.exists?(filename)
                                open(filename, 'r') do |f|
                                  begin
                                    JSON.load(f.read)
                                  rescue JSON::ParserError
                                    {"document sets" => []}
                                  end
                                end
                              else
                                {"document sets" => []}
                              end 
              document_sets["document sets"] ||= []
              new_document_sets = document_sets["document sets"]
              new_document_sets << new_index_details if new_index_details
              document_sets["document sets"] =  new_document_sets
              file_contents = JSON.dump(document_sets)
            elsif filename == "index.html" || filename == "search.html"
              file_contents.gsub("<head>", "<head><base href='#{File.join(@frontend_s3_basepath, 'stevedore/')}'")
            end
            puts "writing #{filename} to #{File.join(@frontend_s3_path, "stevedore", filename)}"
            puts "size: #{file_contents.size}"
            resp = bucket.put_object({
              key: File.join(@frontend_s3_path, "stevedore", filename),
              body: file_contents,
              content_type: content_type
            })

          end
        end
      end
    end
  end
end

