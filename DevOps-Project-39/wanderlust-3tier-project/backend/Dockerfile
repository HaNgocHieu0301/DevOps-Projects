# Use a specific version of node
FROM node:21

# Set the working directory
WORKDIR /app

# Copy package.json and package-lock.json first to leverage Docker cache
COPY package*.json ./

# Install dependencies
RUN npm install

# Now copy the rest of your application code
COPY . .

# Use a non-root user to run your container for better security
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

# Expose the port your app runs on
EXPOSE 5000

# Command to start your application
CMD ["npm", "start"]
