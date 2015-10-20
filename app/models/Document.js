Stevedore.Models.Document = Backbone.Model.extend({
  initialize: function(){
    _.bindAll(this, 'fetch');
  },

  fetch: function(){
    Stevedore.client.search({
      index: Stevedore.es_index,
      // type: es_doctype,
      body: {
        query: {
          "term" : { "_id" : this.get('id') }
        },
      }
    }).then(_.bind(function (resp) {
      var hits = resp.hits.hits;
      if(_.isEmpty(hits)){
        this.trigger('notfound');
      }else{
        this.set(Stevedore.es_hit_to_blob(hits[0]));
      }
    }, this), function (err) {
        console.trace(err.message);
    });
  }
});


