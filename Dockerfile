FROM ruby:3.4.7
RUN apt-get update && apt-get install -y curl git gh ca-certificates gnupg chromium && rm -rf /var/lib/apt/lists/*
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
RUN apt-get install -y nodejs
RUN npx playwright install-deps chromium
RUN mkdir -p /root/bin && ln -s /root/.detritus/detritus.rb /root/bin/detritus
ENV PATH="/root/bin:${PATH}"
VOLUME /usr/local/bundle
WORKDIR /workdir
ENTRYPOINT ["/root/.detritus/detritus.rb"]
