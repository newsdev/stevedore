
// the details for how to connect to your ElasticSearch instance
// and where to get metadata from 
// are written here.

Stevedore.config = {
  prdHost: "localhost",
  prdPort: 9200,
  // prdHost: "12.3.45.6", // IP address of your elasticsearch server
  // prdPort: 80,          // your elasticsearch server's port is probably 9200, but might be 80 or 443
  // prdScheme: "http",    // is your elasticsearch server set up on HTTPS or HTTP? // "https",
  // prdPath: "",          // is your elasticsearch server accessed by some path below the root?
  // document_set_meta_json: 'https://s3.amazonaws.com/your-bucket-name/applications/stevedore/document_sets.json',


  // use_slash_based_routing: false // Stevedore supports routing requests
                                    // that is, different URLs for different search engines, individual searches and documents
                                    // via a hash (e.g. http://path.to.stevedore/index.html#mydocuments/search/pizza )
                                    // or via a slash (e.g. http://path.to.stevedore/search/mydocuments/search/pizza )
                                    // the hash-based routing is the default, since it works in all hosting scenarios
                                    // but if you're hosting Stevedore with Nginx or another rewrite-capable server
                                    // you may turn this on.
                                    // if you're hosting Stevedore on S3, you must leave this false (or commented out)
}






// if a document set has multiple data types in it,
// you can choose one content type to be displayed with your chosen list_view
// and detail_view templates, and the rest displayed as "blobs" (just their text).
// write a string or Regexp here that will be matched against the analyzed.metadata["Content-Type"]
// of each document to determine whether to use the chosen template (if it matches)
// or the blob template (if it doesn't match)
Stevedore.content_types = {
  'email': "message/rfc822",
  'hypothetical': /application\/pdf/,
}
