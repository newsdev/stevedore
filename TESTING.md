

I haven't written tests for this. If you want to, then I'd happily accept that pull request... ha.

Anyways, here are the things I'd check if I had made a big change. (The answers should all be "yes".)

index.html:
  - Do search indices in document_sets.json that exist in ElasticSearch have links on index.html?
  - Are search indices in document_sets.json that exist in ElasticSearch ranked by ascending "sort_order"?
  - Do search indices in ElasticSearch that are not in document_sets.json appear at the bottom (under "Document sets that aren\'t ready for widespread use yet")?
  - Do search engines marked "private" in document_sets.json not show up anywhere on the index page?
  - Do sample searches show up correctly if specified in document_sets.json?
  - Do links to search engines work?
  - Do links to sample searches work?

search.html:
  - If you search for something, do you get results?
  - If you search for something that isn't there, do you get 0 results?
  - If you search for something with >50 results, does the More results button work?
  - If you make a search, then refresh the page, is the search preloaded?
  - If you click on a result, is the document pulled up in the modal?
  - If you click on a result, then refresh the page, is the result preloaded?
  - If you click on a result, then click off the modal, is the search still there (and in the URL bar)?
  - If there are any analyses (like the EmailSenderAnalysis) do those work?
  - Are saved searches prepopulated in the saved search bar?

