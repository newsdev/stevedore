Stevedore.Views.EmailSenderAnalysis = Backbone.View.extend({
  initialize: function(){
    _.bindAll(this, 'render');

    this.model = new Stevedore.Models.EmailSenderAnalysis();
    this.listenTo(this.model, 'stevedore:analysis-loaded', this.render);
    this.model.fetch();
  },

  render: function(){
    var self = this;
    this.$el.show();
    this.$el.empty();

    this.$el.html('<div class="outgoing"><h2>Outgoing emails</h2>  <ol></ol></div><div class="incoming"><h2>Incoming emails</h2><ol></ol></div>')

    _.each(this.model.get('relations').outgoing, function(relation) {
      // bleh
      var html = '<li><h4>'+relation.from+'</h4><ol>';

      _.each(relation.recipients, function(recip) {
        html += '<li><a href="'+self.build_endpoint(recip.to, relation.from)+'">'+recip.to+'</a> ('+recip.count+')</li>';
      });

      html += '</ol></li>';
      self.$el.find('.outgoing > ol').append(html);
    });

    _.each(this.model.get('relations').incoming, function(relation) {
      // bleh
      var html = '<li><h4>'+relation.to+'</h4><ol>';

      _.each(relation.senders, function(sender) {
        html += '<li><a href="'+self.build_endpoint(relation.to, sender.from)+'">'+sender.from+'</a> ('+sender.count+')</li>';
      });

      html += '</ol></li>';
      self.$el.find('.incoming > ol').append(html);
    });
  },

  build_endpoint: function(to, from) {
    return '/search/' + Stevedore.project + '/search/|' + from + '|' + to + '|||';
  }
});
