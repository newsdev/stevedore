Stevedore.Collections.SavedSearches = Backbone.Collection.extend({
  model: Stevedore.Models.Search,
  comparator: function(model){ return -Date.parse(model.get('searched_at'))},
  localStorage: new Backbone.LocalStorage("Searches|" + Stevedore.project ),

  initialize: function(){
    _.bindAll(this, 'save');
  },
  
  save: function(){
    this.reset(this.first(20), {'silent': true});
    this.each(_.bind(function(model){
      if(model.isNew()){
        model.save();
      }
    }))
  }
})
