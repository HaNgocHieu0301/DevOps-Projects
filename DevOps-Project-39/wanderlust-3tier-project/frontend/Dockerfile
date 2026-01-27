# Use a specific version of node
FROM node:21

# Set the working directory
WORKDIR /app

# Copy only the necessary files first (e.g., package.json) to leverage Docker cache
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy the rest of your application code
COPY . .

# Use a non-root user to run your container
RUN adduser --disabled-password --gecos "" appuser && chown -R appuser /app
USER appuser

# Expose the port the app runs on
EXPOSE 5173

# Command to run your application
CMD ["npm", "run", "dev", "--", "--host"]

