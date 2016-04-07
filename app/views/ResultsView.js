Stevedore.Views.Results = Backbone.View.extend({
  events:{
    'click': 'closeItem',
    'click #paginate': 'paginate',
  },
  initialize: function(){
    _.bindAll(this, 'render', 'closeItem');
    this.listenTo(this.collection, 'reset', this.render);
    this.listenTo(this.collection, 'add', _.debounce(this.render, 0.5));

  },

  closeItem: function(){
    if(Stevedore.detail_view && Stevedore.detail_view.$el.is(':visible')){
      Stevedore.detail_view.close();
    }
  },

  paginate: function(){
    Stevedore.search_view.model.set('pageNum', Stevedore.search_view.model.get('pageNum') + 1);

    Stevedore.search_view.model.search(); // lol this is bad programming
    // but you know. whatever.
  },

  render: function(){
    this.$el.children('ol').empty();
    this.collection.each(_.bind(function(hit, i){
      var list_item_view;
      list_item_view = new Stevedore.Views.ListItem({model: hit});
      list_item_view.render();
      this.$el.children('ol').append(list_item_view.$el);
    }, this));
    // display the more results button only if there are already some results, but not all of them (and there's no button yet)
    if((!this.$el.find('#paginate').length) && this.collection.size() > 0 && this.collection.size() < Stevedore.search_view.model.get('hit_count') ) {
      this.$el.children('ol').after('<div id="pagination-controls" class="row"><button id="paginate" class="btn btn-adcom btn-primary">More Results</button></div>')
    }
    if(typeof Stevedore.search_view.model !== 'undefined' && this.collection.size() >= Stevedore.search_view.model.get('hit_count')){
      this.$el.find('#pagination-controls').remove();
    }
  }
});
