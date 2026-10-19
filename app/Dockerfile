# Build stage: compile a static binary.
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/hello-api .

# Runtime stage: distroless has no shell or package manager, and runs as a
# non-root user (65532 is distroless's "nonroot"; numeric so Kubernetes can
# verify runAsNonRoot), which keeps the attack surface small.
FROM gcr.io/distroless/static-debian13:nonroot
COPY --from=build /out/hello-api /hello-api
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/hello-api"]
