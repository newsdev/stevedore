FROM nginx

RUN mkdir -p /var/www/html

# the nginx image is supposed to this; idk why it didn't
# RUN echo "\ndaemon off;" >> /etc/nginx/nginx.conf
ADD conf/nginx.conf /etc/nginx/nginx.conf

ADD app/ /var/www/html/app/
ADD lib/ /var/www/html/lib/
ADD templates/ /var/www/html/templates/
ADD index.html /var/www/html/
ADD search.html /var/www/html/
ADD document_sets.json /var/www/html/
ADD conf/stevedore.nginx.conf /etc/nginx/conf.d/
ADD user-files/ /var/www/files/user-files/

EXPOSE 8080
CMD ["nginx"]
