{{/*
Common labels
*/}}
{{- define "layer-0.labels" -}}
app.kubernetes.io/managed-by: argocd
app.kubernetes.io/part-of: layer-0
{{- end }}

{{/*
Sync policy for infrastructure components
*/}}
{{- define "layer-0.syncPolicy" -}}
automated:
  prune: true
  selfHeal: true
syncOptions:
  - CreateNamespace=true
  - ServerSideApply=true
{{- end }}
