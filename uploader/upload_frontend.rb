require 'aws-sdk'


# same arguments as stevedore uploader.
if __FILE__ == $0
  require 'optparse'
  require 'ostruct'
  options = OpenStruct.new
  options.ocr = true

  op = OptionParser.new("Usage: upload_frontend [options] target_(dir_or_csv)") do |opts|
    opts.on("-hSERVER:PORT", "--host=SERVER:PORT",
            "The location of the ElasticSearch server") do |host|
      options.host = host
    end

    opts.on("-iNAME", "--index=NAME",
            "A name to use for the ES index (defaults to using the directory name)") do |index|
      options.index = index
    end

    opts.on("-sPATH", "--s3path=PATH",
            "The path under your S3 bucket where these files will be uploaded. (defaults to ES index)"
      ) do |s3path|
      options.s3path = s3path
    end

    opts.on("--title_column=COLNAME",
            "If target file is a CSV, which column contains the title of the row. Integer index or string column name."
      ) do |title_column|
      options.title_column = title_column
    end
    opts.on("--text_column=COLNAME",
            "If target file is a CSV, which column contains the main, searchable of the row. Integer index or string column name."
      ) do |text_column|
      options.text_column = text_column
    end

    opts.on("-fPATH", "--front-end=PATH", 
            ""
      ) do |frontend_location|
      OPTIONS.frontend_location
    end
    
    opts.on("-o", "--[no-]ocr", "don't attempt to OCR any PDFs, even if they contain no text") do |v|
      options.ocr = v 
    end

    opts.on( '-?', '--help', 'Display this screen' ) do     
      puts opts
      exit
    end
  end

  op.parse!

  # to delete an index: curl -X DELETE localhost:9200/indexname/
  unless ARGV.length == 1
    puts op
    exit
  end
end

ES_INDEX =  if options.index.nil? || options.index == ''
              if(FOLDER.downcase.include?('s3://'))
                s3_path_without_bucket = FOLDER.gsub(/s3:\/\//i, '').split("/", 2).last
                s3_path_without_bucket.gsub(/^.+\//, '').gsub(/[^A-Za-z0-9\-_]/, '')
              else
                FOLDER.gsub(/^.+\//, '').gsub(/[^A-Za-z0-9\-_]/, '')
              end
            else
              options.index
            end

ES_HOST = options.host || "localhost:9200"


if (!OPTIONS.no_front_end) || !OPTIONS.frontend_location.nil?
  FRONTEND_S3_BUCKET = OPTIONS.frontend_location.gsub(/s3:\/\//i, '').split("/", 2).first
  FRONTEND_S3_PATH = OPTIONS.frontend_location.gsub(/s3:\/\//i, '').split("/", 2).last  
end

raise ArgumentError, "specify a destination" unless FOLDER
raise ArgumentError, "specify the elasticsearch host" unless ES_HOST


if __FILE__ == $0
  f = Stevedore::FrontendUploader.new("../stevedore", ES_HOST, ES_INDEX, FRONTEND_S3_BUCKET, FRONTEND_S3_PATH)
  puts "Uploading front end"
  f.upload_front_end unless OPTIONS.no_front_end
  puts "Finished at #{Time.now}"
  frontend_s3_basepath = "https://#{FRONTEND_S3_BUCKET}.s3.amazonaws.com/#{FRONTEND_S3_PATH}"
  puts "Uploaded to #{ES_INDEX}; go check out the search engine at: \n #{File.join(frontend_s3_basepath.gsub("https:", 'http:'), "/stevedore/search.html##{ES_INDEX}")}\n "
end
