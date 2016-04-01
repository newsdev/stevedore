Stevedore.Views.ListItem = Backbone.View.extend({
  tagName: 'li',
  className: 'es-hit',
  events:{
    'click a.preview': 'preview',
  },

  initialize: function(){
    _.bindAll(this, 'preview', 'setTemplate', 'render');
    this.setTemplate();
  },
  setTemplate: function(){
    if(  (this.model.get('analyzed').metadata ? this.model.get('analyzed').metadata["Content-Type"] : '').match(  new RegExp(Stevedore.content_types[Stevedore.template_names['list_view']]) ) ){
      this.template = !_.isUndefined(Stevedore.templates[Stevedore.template_names['list_view']].list_view) ? Stevedore.templates[Stevedore.template_names['list_view']].list_view : _.template('<div></div>');
    }else{
      this.template = !_.isUndefined(Stevedore.templates['blob'].list_view) ? Stevedore.templates['blob'].list_view : _.template('<div></div>');
    }

  },
  render: function(){
    this.setTemplate();
    this.$el.addClass(Stevedore.template_names['list_view']);   
    this.$el.html(this.template( 
      _.extend({}, Stevedore.def_obj, this.model.attributes)
    ));
    this.$el.attr("href", this.detail_view_link());
    this.$el.attr('id', "hit-" + this.model.get('id'));
    return this;
  },
  preview: function(e){
    if(e.which == 2 || e.metaKey ){ //middle clicks should actually open in a new tab (so no JS-specific behavior, just a link)
      return;
    }
    e.preventDefault();
    e.stopPropagation();

    if(Stevedore.config.use_slash_based_routing){
      var split_location = window.location.href.split("/");
      var current_location = 'search/' + split_location[split_location.length - 1]
    }else{
      var current_location = window.location.hash;
    }

    Stevedore.detail_view = new Stevedore.Views.Detail({'el': $('#preview-pane'), 
                                                      'model': this.model, 
                                                      'attributes': { 'previous': current_location }
                                                    });
    Stevedore.router.navigate(this.detail_view_link());

    Stevedore.detail_view.render();
  },


  // just an internal helper
  detail_view_link: function(){
    return (Stevedore.config.use_slash_based_routing ? '/' : Stevedore.project + "/") + "document/" + this.model.get('id')
  },

});

