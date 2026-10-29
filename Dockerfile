FROM ruby:3.4.7

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4
