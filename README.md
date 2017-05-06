Stevedore, an ElasticSearch Frontend & Ingestion Engine
=======================================================

From a bunch of documents to an easy-to-use search engine for emails, websites, social media posts or just about anything.

For more in-depth projects, you can easily customize the interface to easily make new document-specific custom formats for searching and exploring. To deploy to your newsroom, just add your own standalone ElasticSearch server; Stevedore's frontend framework is all-frontend.

I just want to make a search engine!
====================================

Do you have all the documents in a folder (or a zip archive) somewhere? Then you're ready to go. Just [download the last release](../../releases) then double-click to run it.

Be sure to have Java 8 installed.

Stevedore can make two types of search engines:

- *Local search engine* that only your computer can access.
- *Production search engine* that other computers can access. If you choose this option, you need to have a separate ElasticSearch server to host the search index and an Amazon S3 bucket to host the frontend. 

![An example of a search page.](/screenshots/blob_search_form_annotated.png?raw=true "An example of a search page.")

GUI option:
-----------

1. Double-click the Stevedore icon, which will open [127.0.0.1:8080](127.0.0.1:8080) in your default web browser.
2. Give your new search engine a name.
3. Select whether you're creating a local-only-mode search engine (that only you will be able to access) or a production search engine with a separate ElasticSearch server and hosted on S3.
3. Type in the path to your documents -- either a folder on your computer or on an Amazon S3 bucket -- onto the page. If you're uploading to a separate ElasticSearch server, you'll have to add its URL here too.
4. You can watch the progress logs, or just close the window. (Don't close the app though!)
5. After a bit, the app will redirect you to your search engine, once it is ready.

Command line option:
--------------------

1. Run the command-line app with arguments for (the location of your app)

`bundle exec ruby uploader/upload_to_elasticsearch.rb --index=foss-test --host=http://12.3.45.67:80 s3://int-data-dumps/foss-test-data`

--frontend-location (s3:// only)


Installation
============

1. Be sure you have Java 1.7 or newer installed on your local machine.
2. Download and double-click the Jar file. Wait a few seconds, then a webpage with instructions should open at [http://127.0.0.1:8080](http://127.0.0.1:8080)

If you want other people to use the search engine you create (that is, to deploy Stevedore to a production environment), you also need:

3. an Elasticsearch server running somewhere -- not on your computer.
4. an Amazon S3 bucket for the frontend and your files to go to. (If you have sensitive documents, you could deploy Stevedore's files to a local HTTP server, so the sensitive documents don't go into the cloud.)

Stevedore has no security of its own, besides the security of your Amazon S3 bucket and your ElasticSearch server's policies. Anyone who can access the S3 bucket and the ElasticSearch server can use your search engine, so be sure to set your access policies correctly. How to set these up _securely_ is outside the scope of this document. (Unless someone else wants to write instructions and submit a pull request.)


Customizing Stevedore with New Templates
========================================

![The Email template](/screenshots/email_search_form.png?raw=true)

### Intro to Templates

Each template must contain four distinct files. Whether inheritance will be possible is TBD.

  - a "detail view" template for seeing an entire, single document inside the app 
  - a "list view" template for seeing a single document in a list of returned search results matching a query
  - a "search box" containing all the relevant fields to be searched. Design is important here. 
  - a "query builder" JavaScript function to transform the search box into a valid ElasticSearch query.

Optionally, you can include custom CSS too.

### How to write a new template

1. Pick a name for your template file. All of your templates will use that name as their entire filename (except for the extension, either `.template`, `.js` or `.css`.)
2. Create the files themselves as `templates/<template_type>/<template_name>.<extension>`, e.g. `templates/list_view/blogpost.template`
3. Write template files for detail_view, list_view and search_form. Copy/paste will be your friend (until there's [a DSL for creating these](issues/20)) to make styles easy, as well as making sure the `detail_view` modal works well.
4. Write a query_builder. This is a JavaScript file that manages transforming your `search_form`'s HTML into a Backbone object representing a search (e.g. so pagination works, etc.) in the `likeActuallyCreate` method and transforming that object into an ElasticSearch query (`toQuery`). The examples provided will be your guide.
5. The query_builder is also involved in  serializing/deserializing the query fields into a URL (and saved search format). All you have to do is specify the fields, in an array, in a sensical-ish order in the `fieldOrder` method.
6. Your query_builder's `likeActuallyCreate` method should, referring to the search template, populate the search Backbone object from the values of the form fields in the search from (which should be now rendered onto the page, but which ought to cope with null values.)
7. Your query_builder's `toQuery` method will require some ElasticSearch knowledge. Follow the examples. :)

The availability of templating relies on Stevedore's objects each containing, at a bare minimum, an `id` field that is persistent across reindexing, a `source_url` field to the original document and an `analyzed.body` field that contains the full text.

Customizing the Upload Process
==============================

You may have documents that need to be searchable in Stevedore, but need to be indexed in a different way. You have two options here: customize the uploader, or go it alone and create your own upload script.

Creating your own upload script is relatively easy. Using whatever method you prefer, shove your data into ElasticSearch, being sure to include an `id` field, a `source_url` field and an 'analyzed.body' field. Stevedore will infer the existence of your database directly from ElasticSearch, with no action from you necessary (you may still want to add metadata in document_sets.json).

Information on how to customize the uploader is TK.

Architecture & Theory
=====================

Stevedore consists of two main pieces:
  - an ingestion GUI and script to process your documents -- emails, powerpoints, whatever -- and send them to ElasticSearch.
  - a website frontend/framework for actually searching ElasticSearch. If you choose to deploy this frontend to the web, you can easily write custom templates for searching with custom fields.

The ingestion script is in another repo: [stevedore-uploader](https://github.com/newsdev/stevedore-uploader) [uploader/upload.rb](blob/master/uploader/upload.rb) and most of the logic is in [lib/stevedore_uploader.rb](https://github.com/newsdev/stevedore-uploader/blob/master/lib/stevedore-uploader.rb). The ingestion GUI is a work in progress, but it lives in the `uploader/` folder in this repo, along with `config.ru`.

The frontend framework is all JavaScript and HTML. No backend (besides vanilla ElasticSearch). You run it (in development) by running `rackup` in the root of this project. In production, put the root of this project somewhere where it gets served on the web -- like Amazon S3 or Nginx. (The files? [search.html](blob/master/search.html), [index.html](blob/master/index.html), [app/](tree/master/app), [lib/](tree/master/lib) and [templates/](tree/master/templates))

The `app/` folder contains the framework: a set of common components (frames, sort of) that render project-specific templates (in `templates/`) to handle variation in search app UIs. The common interface includes a place for search forms, a list view and detail view -- as well as an index page (`index.html`) for listing all your search engines. `lib/` is supporting libraries like JQuery.

The results list looks like this:

![An example of a results page.](/screenshots/blob_results.png?raw=true "An example of a results page.")

And detail pages, for each result, look like this:

![An example of a list detail page.](/screenshots/detail_view.png?raw=true "An example of a list detail page.")

Here's the workflow we've envisioned for this:

  Sometimes we're a bit blindsided by a document dump. This tool has two goals: To easily stand up a generic, workable search tool quickly; and to, when necessary, tweak the tool for highlight project-specific fields or priorities. A generic email-search template is not sufficient: in one case, the focus may be on searching emails by who they're addressed to, so the To: search field should be foregrounded; in another, the focus may be on searching the Subject: fields, and so that ought to be foregrounded. Copying, pasting and modifying the HTML of a template seems to be the easiest way to do this -- in an environment where a person who's minimally aware of this app config can do it.

Another, separate design goal is to use the URL as a config store: my-stevedore-site.my-company.local/jeb searches Jeb Bush emails on production, whatevertheappurlis.my-stevedore-site.my-company.local/hrc searches Hillary Clinton emails on production; 127.0.0.1:8080/jeb searches Jeb Bush emails using the local search app.

Development
===========
1. clone the repo
2. Be sure to have JRuby 1.7 or 9.0.0.0 installed (e.g. with [rbenv](https://github.com/sstephenson/rbenv))
2. `bundle install`
3. `bundle exec rackup`
4. edit `templates/` (or `app/`) code

Building
--------

```
bundle install
warble jar # to build the stevedore.jar file
````

Running in Docker
-----------------
docker run -e AWS_ACCESS_KEY_ID=AKIAwhatever -e AWS_SECRET_ACCESS_KEY='asdfasdf' -p 8080:8080 -p 9200:9200 -v /path/to/stevedore:/jar -t java:8 java -jar /jar/stevedore.jar

Questions?
==========
Check out the [GitHub issues](https://github.com/newsdev/stevedore/issues) or these Theoretically Asked Questions:

#### Why is this file so big?

☕ Java. ☕

(And the fact that we're packaging JRuby, ElasticSearch, etc.)

#### Why is local-only mode so slow?


Because it's running Elasticsearch from inside the same Java process as the app itself. It's probably faster if you set up your own separate Elasticsearch server.

#### Why does this exist? Shouldn't you use DocumentCloud or Overview or Kibana or ________?

Great question! Those are all great tools made by great people, but they solve a different problem than Stevedore. What problem does Stevedore aim to solve? I don't like doing 'training' for software. I think it's pathological and teaches dependency instead of self-sufficiency. Training for how to use Stevedore's search engines (as opposed to the uploader) should be as simple as *Go to this URL, and then type in that box*. Stevedore is designed to make easy-to-use search engines.

#### Has this been used in real life?

Yeah, we use this code all the time at The New York Times. Reporters use the Stevedore frontend to search emails from politicians, scraped websites and all sorts of other document sets.

Want to contribute?
===================
You can help by:

1. Reporting a bug.
2. Adding or editing documentation.
3. Contributing code via a Pull Request from ideas, e.g. your templates, if they're general use.
4. Fixing bugs in the [issues section](https://github.com/newsdev/stevedore/issues).
5. Telling your friends if Stevedore might be useful to them.
6. Helping other people in the [issues section](https://github.com/newsdev/stevedore/issues) if you know how to fix the problem their experiencing.
