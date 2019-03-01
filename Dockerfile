FROM golang:1.11.5 AS builder

RUN apt-get update
RUN apt-get install -y autoconf build-essential

ENV GOPATH=/go
ENV PATH=$GOPATH/bin:$PATH

RUN mkdir -p /go/src \
 && mkdir -p /go/bin \
 && mkdir -p /go/pkg

RUN go env

RUN mkdir -p $GOPATH/src/github.com/CodisLabs
RUN cd $GOPATH/src/github.com/CodisLabs && git clone https://github.com/CodisLabs/codis.git -b release3.2

WORKDIR $GOPATH/src/github.com/CodisLabs/codis

RUN make
RUN cat bin/version

ENTRYPOINT [ "tail","-f","/dev/null" ]

#codis-dashboard
FROM debian:buster as codis-dashboard

RUN mkdir -p /usr/local/codis/

COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-dashboard /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-admin /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/config/dashboard.toml /usr/local/codis/
WORKDIR /usr/local/codis
EXPOSE 18080 

ENTRYPOINT [ "./codis-dashboard", "--config=./dashboard.toml", "--log=./dashboard.log", "--log-level=DEBUG", "--zookeeper=codis-zookeeper:2181", "--product_name=headball-dev"]


#codis-fe
FROM debian:buster as codis-fe

RUN mkdir -p /usr/local/codis && mkdir /tmp/codis

COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-fe /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/assets/ /usr/local/codis/

WORKDIR /usr/local/codis
EXPOSE 9090
ENTRYPOINT [ "./codis-fe", "--ncpu=4", "--listen=0.0.0.0:9090", "--zookeeper=codis-zookeeper:2181", "--assets-dir=/usr/local/codis", "--log=./fe.log", "--log-level=DEBUG"]

#codis-server
FROM debian:buster as codis-server

RUN mkdir -p /usr/local/codis

COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-server /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-admin /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/config/redis.conf /usr/local/codis/

WORKDIR /usr/local/codis

EXPOSE 6379

RUN sed -i '/bind 127.0.0.1/c\bind 0.0.0.0' ./redis.conf
RUN sed -i '/daemonize yes/c\daemonize no' ./redis.conf

ENTRYPOINT [ "./codis-server", "./redis.conf"]

#codis-proxy
FROM debian:buster as codis-proxy

ENV DASHBOARD 127.0.0.1:18080
ENV NCPU 4
ENV PRODUCT_NAME headball

RUN mkdir -p /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-proxy /usr/local/codis/
COPY --from=builder /go/src/github.com/CodisLabs/codis/config/proxy.toml /usr/local/codis/

WORKDIR /usr/local/codis

EXPOSE 11080
EXPOSE 19000

ENTRYPOINT [ "./codis-proxy","--config=./proxy.toml", "--zookeeper=codis-zookeeper:2181", "--log=./codis-proxy.log", "--log-level=DEBUG", "--ncpu=4", "--product_name=headball-dev" ]

#codis-ha
FROM debian:buster as codis-ha

RUN mkdir -p /usr/local/codis/

COPY --from=builder /go/src/github.com/CodisLabs/codis/bin/codis-ha /usr/local/codis/
WORKDIR /usr/local/codis

ENTRYPOINT [ "./codis-ha", "--interval=5","--log=./ha.log","--dashboard=codis-dashboard:18080"]
