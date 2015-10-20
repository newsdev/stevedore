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
    this.$el.attr('id', "hit-" + this.model.get('id'));
    return this;
  },
  preview: function(e){
    if(e.which == 2 || e.metaKey ){ //middle clicks should actually open in a new tab (so no JS-specific behavior, just a link)
      return;
    }
    e.preventDefault();
    e.stopPropagation();
    Stevedore.detail_view = new Stevedore.Views.Detail({'el': $('#preview-pane'), 
                                                      'model': this.model, 
                                                      'attributes': { 'previous': window.location.hash }
                                                    });
    Stevedore.router.navigate(Stevedore.project + "/" + "document/" + this.model.get('id') );

    Stevedore.detail_view.render();
  },
});

