this template is kind of complicated:

it depends on lib/pdfjs/
which includes a sneakily modified lib/pdfjs/pdf.viewer.js to add the Stevedore URLs to a list of URLs that can accept cross-domain PDF views. (An alternative would be to remove that security check and allow pdf.viewer.js to load cross-domain PDFs regardless of what the window's URL is.)

and it depends on adding a CORS config to the s3://my-s3-bucket bucket to allow the Stevedore URLs to load PDFs from S3, (in https://console.aws.amazon.com/s3/buckets/my-s3-bucket/?region=us-east-1&tab=permissions)