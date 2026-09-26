# build ステージ: Go でビルド
FROM golang:1.27 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /todo .

# 実行ステージ: シェルなし・非 root の最小イメージ
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /todo /todo
ENTRYPOINT ["/todo"]
