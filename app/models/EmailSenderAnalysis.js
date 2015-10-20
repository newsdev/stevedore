Stevedore.Models.EmailSenderAnalysis = Backbone.Model.extend({

  initialize: function(){
    _.bindAll(this, 'fetch');
    this.set('relations', {});
  },

  fetch: function(){
    $('#loading').addClass('loading');

    Stevedore.client.search({
      index: Stevedore.es_index,
      body: {
        // Don't need any docs, just the agg results
        size: 0,

        aggs: {
          // Top 10 people who have emailed the most,
          // and the top 10 people they have emailed to.
          email_from: {
            terms: {
              field: 'analyzed.metadata.Message-From.email',
              size: 10,
              order: {_count: 'desc'}
            },
            aggs: {
              email_to: {
                terms: {
                  field: 'analyzed.metadata.Message-To.email',
                  size: 10,
                  order: {_count: 'desc'}
                }
              }
            }
          },

          // Top 10 people who have been emailed the most,
          // and the top 10 people who have emailed them.
          email_to: {
            terms: {
              field: 'analyzed.metadata.Message-To.email',
              size: 10,
              order: {_count: 'desc'}
            },
            aggs: {
              email_from: {
                terms: {
                  field: 'analyzed.metadata.Message-From.email',
                  size: 10,
                  order: {_count: 'desc'}
                }
              }
            }
          }
        }
      }
    }).then(_.bind(function (resp) {
      if(!resp){
        return;
      }

      var relations = {
        outgoing: [],
        incoming: []
      };

      // Outgoing
      _.each(resp.aggregations.email_from.buckets, function(agg) {
        var relation = {
          from: agg.key,
          recipients: []
        };
        _.each(agg.email_to.buckets, function(bucket) {
          relation.recipients.push({
            to: bucket.key,
            count: bucket.doc_count
          });
        });
        relations.outgoing.push(relation);
      });

      // Incoming
      _.each(resp.aggregations.email_to.buckets, function(agg) {
        var relation = {
          to: agg.key,
          senders: []
        };
        _.each(agg.email_from.buckets, function(bucket) {
          relation.senders.push({
            from: bucket.key,
            count: bucket.doc_count
          });
        });
        relations.incoming.push(relation);
      });
      this.set('relations', relations);

      this.trigger('stevedore:analysis-loaded');
      $('#loading').removeClass('loading');
    }, this), function (err) {
      //TODO: error messages
    });
  }

});
