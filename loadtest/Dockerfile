FROM ubuntu:22.04

# Install Vegeta and Python dependencies
RUN apt-get update && apt-get install -y \
    wget \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/tsenart/vegeta/releases/download/v12.12.0/vegeta_12.12.0_linux_amd64.tar.gz \
    && tar xfz vegeta_12.12.0_linux_amd64.tar.gz \
    && mv vegeta /usr/bin/vegeta

RUN pip3 install prometheus-client

COPY vegeta-targets.txt /app/
COPY ramp.sh /app/

WORKDIR /app
RUN chmod +x ramp.sh
CMD ["./ramp.sh"]
