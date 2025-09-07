# Stage 1: Build the Angular app
FROM node:22-alpine AS build

# Set working directory inside container
WORKDIR /app

# Copy package.json and package-lock.json (if available)
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the entire Angular app source code
COPY . .

# Build the Angular app in production mode
RUN npm run build -- --output-path=dist/client-app --configuration production

# Stage 2: Serve the app with Nginx
FROM nginx:stable-alpine

# Remove default nginx welcome files, copy built Angular app into nginx html root
# This ensures we don't accidentally leave the default nginx index.html
RUN rm -rf /usr/share/nginx/html/*
COPY --from=build /app/dist/client-app/browser/ /usr/share/nginx/html/

# Copy custom Nginx configuration into conf.d so it becomes the default server
# (putting it into conf.d/default.conf makes intent explicit and avoids issues
# with distribution-specific default files)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 80
EXPOSE 80

# Start Nginx server
CMD ["nginx", "-g", "daemon off;"]
 