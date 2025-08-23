FROM ruby:3.2-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copy Gemfile first for better caching
COPY Gemfile* ./

# Install Ruby dependencies
RUN bundle install --no-cache

# Copy application code
COPY . .

EXPOSE 5000

CMD ["ruby", "app.rb"]
