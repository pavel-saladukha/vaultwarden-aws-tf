FROM nginx:${nginx_image_tag}@${nginx_image_digest}

COPY nginx.conf /etc/nginx/nginx.conf
COPY fullchain.pem /etc/nginx/conf.d/fullchain.pem
COPY privkey.pem /etc/nginx/conf.d/privkey.pem
