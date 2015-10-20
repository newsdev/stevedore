
// the details for how to connect to your ElasticSearch instance
// and where to get metadata from 
// are written here.

Stevedore.config = {
  prdHost: "localhost",
  prdPort: 9200,
  // prdHost: "10.214.1.254",//window.location.host.split(":")[0],
  // prdPort: 80,//9200,
  // prdScheme: "http",//"https",
  // prdPath: "",
  // document_set_meta_json: 'https://s3.amazonaws.com/int.nyt.com/applications/stevedore/document_sets.json',
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
  'daily_worker': /.*/,
}
