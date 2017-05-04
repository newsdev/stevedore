Stevedore.Models.AllDocumentsAnalysis = Backbone.Model.extend({

  initialize: function(){
    _.bindAll(this, 'fetch');
    this.set('document_names', {});
  },

  fetch: function(){
    $('#loading').addClass('loading');

    var document_names = []

    var getMoreUntilDone = _.bind(function (err, response) {
      if(!response){
        return;
      }
      response.hits.hits.forEach(_.bind(function (hit) {
        if(typeof hit.fields !== 'undefined'){
          document_names.push(hit);        
        }
      }, this));
      this.set('document_names', document_names);
      this.trigger('stevedore:analysis-loaded');


      if (response.hits.total !== document_names.length) {
        // now we can call scroll over and over
        Stevedore.client.scroll({
          scrollId: response._scroll_id,
          scroll: '10s'
        }, getMoreUntilDone) ;
      } else {
        this.set('document_names', document_names)
      }

      this.trigger('stevedore:analysis-loaded');
      $('#loading').removeClass('loading');
    }, this);

    Stevedore.client.search({
      index: Stevedore.es_index,
      scroll: '10s',
      search_type: 'scan',      
      body: {
        size: 100,
        fields: ["source_url"],
        "partial_fields" : {
            "title" : {
                "include" : ["file.title"],
            }
        },
        query: { match_all: {} }
      }
    }).then(_.bind(function(r){ getMoreUntilDone(null, r); }, this), function (err) {
      //TODO: error messages
    });
  }

});
