FROM nginx:1.27-alpine

COPY . /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN find /usr/share/nginx/html -type d -exec chmod 755 {} \; \
  && find /usr/share/nginx/html -type f -exec chmod 644 {} \;

EXPOSE 80
