FROM ruby:3.4.7
RUN apt-get update && apt-get install -y curl git gh && rm -rf /var/lib/apt/lists/*
VOLUME /usr/local/bundle
WORKDIR /workdir
ENTRYPOINT ["/root/.detritus/detritus.rb"]
