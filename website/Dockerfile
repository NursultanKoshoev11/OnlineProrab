FROM node:22-alpine AS styles
WORKDIR /build
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:1.27-alpine
COPY index.html script.js /usr/share/nginx/html/
COPY assets /usr/share/nginx/html/assets
COPY privacy /usr/share/nginx/html/privacy
COPY terms /usr/share/nginx/html/terms
COPY support /usr/share/nginx/html/support
COPY account-deletion /usr/share/nginx/html/account-deletion
COPY --from=styles /build/styles.css /usr/share/nginx/html/styles.css
COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN find /usr/share/nginx/html -type d -exec chmod 755 {} \; \
  && find /usr/share/nginx/html -type f -exec chmod 644 {} \;

EXPOSE 80
