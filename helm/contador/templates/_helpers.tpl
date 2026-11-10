{{- define "contador.etiquetas" -}}
app.kubernetes.io/part-of: contador
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/instance: {{ .Release.Name }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{- define "contador.version" -}}
{{ .Values.imagen.tag | default .Chart.AppVersion }}
{{- end }}
