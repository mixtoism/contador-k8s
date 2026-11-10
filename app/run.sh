#!/bin/sh
# Arranque en AWS Lambda. El Lambda Web Adapter (una capa) lanza este script, espera a que
# el servidor responda en $PORT y le reenvía cada evento de API Gateway como petición HTTP.
# Es el mismo server.js que corre en Kubernetes y en Elastic Beanstalk.
exec node server.js
