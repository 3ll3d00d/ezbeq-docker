# ezbeq-docker

Creates and publishes an image for [ezBEQ](https://github.com/3ll3d00d/ezbeq) to github packages, for use with [JRiver Media Center](https://www.jriver.com), or any ezBEQ client that uses the [MiniDSP-RS](https://github.com/mrene/minidsp-rs) project.

> [!NOTE]
> ⚠ This image has not been tested with USB connected devices.
> There are instructions on how to mount USB devices, from another legacy docker image project:
> - [General docker discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#general-linux-docker-instructions)
> - [Synology NAS discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#general-linux-docker-instructions)
>  - [Higher privileges discussion](https://github.com/jmery/ezbeq-docker/tree/ef3f954f37b1b420e31635a699bfbb864e861ad9?tab=readme-ov-file#note-on-execute-container-using-high-privilege)

## Setup

- Expects a volume mapped to `/config `to allow user supplied `ezbeq.yml`

Example docker compose file for your reference: [docker-compose.yaml](./docker-compose.yaml)

## FAQ

> Does this docker image work for [MiniDSP](https://www.minidsp.com) devices?

Yes.

> Does this build and publish an image for every ezBEQ release?

Yes, see https://github.com/3ll3d00d/ezbeq/blob/main/.github/workflows/create-app.yaml#L108

> Why is this not mentioned in the ezBEQ readme?

It is, in the [Docker section](https://github.com/3ll3d00d/ezbeq?tab=readme-ov-file#docker).


> What architectures are supported?

The docker image get's built to target:

- `linux/amd64`
- `linux/arm64`

---

## Running in Kubernetes

It's assumed that anyone using k8s has an idea of what they're doing and has a particular (network) architecture in their design which will be specific to their own setup. 

An example of such a setup is provided by [@Frick](https://github.com/Frick) which may serve as useful jumping off point

```
---
apiVersion: v1
kind: Namespace
metadata:
  name: ezbeq
  labels:
    kubernetes.io/metadata.name: ezbeq
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: ezbeq-config
  namespace: ezbeq
data:
# see https://github.com/3ll3d00d/ezbeq/tree/main/examples for more
  ezbeq.yml: |
    accessLogging: false
    debugLogging: false
    devices:
      dsp1:
        channels:
          - sub1
          - sub2
        ip: 192.168.1.123:80
        type: htp1
        autoclear: true
    port: 8080
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app.kubernetes.io/instance: ezbeq
  name: ezbeq
  namespace: ezbeq
spec:
  progressDeadlineSeconds: 30
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: ezbeq
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ezbeq
    spec:
      containers:
        - name: ezbeq
          image: ghcr.io/3ll3d00d/ezbeq-docker:main
          imagePullPolicy: IfNotPresent
          volumeMounts:
            # this path is baked into the ezbeq-docker container and is where
            # the log is created and config file must be mounted
            - mountPath: /config
              name: ezbeq-scratch
            - mountPath: /config/ezbeq.yml
              name: ezbeq-config
              subPath: ezbeq.yml
          livenessProbe:
            failureThreshold: 3
            httpGet:
              path: /api/1/version
              port: http
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          ports:
            - containerPort: 8080
              name: http
              protocol: TCP
          readinessProbe:
            failureThreshold: 3
            httpGet:
              path: /api/1/version
              port: http
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
          resources:
            limits:
              cpu: 200m
              memory: 256Mi
            requests:
              cpu: 200m
              memory: 256Mi
          startupProbe:
            failureThreshold: 30
            httpGet:
              path: /api/1/version
              port: http
              scheme: HTTP
            periodSeconds: 10
            successThreshold: 1
            timeoutSeconds: 1
      volumes:
        - name: ezbeq-scratch
          emptyDir:
            sizeLimit: 120Mi
        - name: ezbeq-config
          configMap:
            name: ezbeq-config
      terminationGracePeriodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: ezbeq
  namespace: ezbeq
spec:
  selector:
    app.kubernetes.io/name: ezbeq
  type: ClusterIP
  ports:
    - name: http
      port: 8080
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ezbeq
  namespace: ezbeq
  annotations:
    cert-manager.io/cluster-issuer: lets-encrypt
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/websocket-services: "ezbeq"
    external-dns.alpha.kubernetes.io/hostname: ezbeq.yourdomain.dev
spec:
  ingressClassName: nginx
  rules:
    - host: ezbeq.yourdomain.dev
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: ezbeq
                port:
                  number: 8080
  tls:
    - hosts:
        - ezbeq.yourdomain.dev
      secretName: ezbeq-tls
```

## Developer Documentation

### Multi Platform Docker Image

Build for two architectures in parallel, push:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t <HUB USERNAME>/ezbeq-docker:latest \
  --push .
```

#### Setup

Requires Docker's `buildx` setup:

- `docker buildx create --use`
- `docker buildx inspect --bootstrap`
