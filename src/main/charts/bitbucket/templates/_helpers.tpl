{{/*This file contains template snippets used by the other files in this directory.*/}}
{{/*Most of them were generated by the "helm chart create" tool, and then some others added.*/}}

{{/* vim: set filetype=mustache: */}}

{{/* Define a sanitized list of additionalEnvironmentVariables */}}
{{- define "bitbucket.sanitizedAdditionalEnvVars" -}}
{{- range .Values.bitbucket.additionalEnvironmentVariables }}
- name: {{ .name }}
  value: {{ if regexMatch "(?i)(secret|token|password)" .name }}"Sanitized by Support Utility"{{ else}}{{ .value }}{{ end }}
{{- end }}
{{- end }}

{{/* Define a sanitized list of additionalJvmArgs */}}
{{- define "bitbucket.sanitizedAdditionalJvmArgs" -}}
{{- range .Values.bitbucket.additionalJvmArgs }}
 {{- $jvmArgs := regexSplit "=" . -1 }}
   {{- if regexMatch "(?i)(secret|token|password).*$" (first $jvmArgs) }}
-  {{ first $jvmArgs }}=Sanitized by Support Utility{{ else}}
-  {{ . }}
{{ end }}
{{- end }}
{{- end }}

{{/* Define sanitized Helm values */}}
{{- define "bitbucket.sanitizedValues" -}}
{{- $sanitizedAdditionalEnvs := dict .Chart.Name (dict "additionalEnvironmentVariables" (include "bitbucket.sanitizedAdditionalEnvVars" .)) }}
{{- $sanitizedAdditionalJvmArgs := dict .Chart.Name (dict "additionalJvmArgs" (include "bitbucket.sanitizedAdditionalJvmArgs" .)) }}
{{- $mergedValues := merge $sanitizedAdditionalEnvs $sanitizedAdditionalJvmArgs .Values }}
{{- toYaml $mergedValues | replace " |2-" "" | replace " |-" "" |  replace "|2" "" | nindent 4 }}
{{- end }}

{{- define "bitbucket.analyticsJson" }}
{
  "imageTag": {{ if or (eq .Values.image.tag "") (eq .Values.image.tag nil) }}{{ .Chart.AppVersion | quote }}{{ else }}{{ regexSplit "-" .Values.image.tag -1 | first |  quote }}{{ end }},
  "replicas": {{ .Values.replicaCount }},
  "isJmxEnabled": {{ .Values.monitoring.exposeJmxMetrics }},
"ingressType": {{ if not .Values.ingress.create }}"NONE"{{ else }}{{ if .Values.ingress.nginx }}"NGINX"{{ else }}"OTHER"{{ end }}{{ end }},
{{- $sanitizedMinorVersion := regexReplaceAll "[^0-9]" .Capabilities.KubeVersion.Minor "" }}
  "k8sVersion": "{{ .Capabilities.KubeVersion.Major }}.{{ $sanitizedMinorVersion }}",
  "serviceType": {{ if regexMatch "^(ClusterIP|NodePort|LoadBalancer|ExternalName)$" .Values.bitbucket.service.type }}{{ .Values.bitbucket.service.type | upper | quote }}{{ else }}"UNKNOWN"{{ end }},
{{- if eq .Values.database.driver nil }}
  "dbType": "UNKNOWN",
{{- else }}
{{- $databaseTypeMap := dict "postgres" "POSTGRES" "sqlserver" "MSSQL" "oracle" "ORACLE" "mysql" "MYSQL" }}
{{- $dbTypeInValues := .Values.database.driver }}
{{- $dbType := "UNKNOWN" | quote }}
{{- range $key, $value := $databaseTypeMap }}
{{- if regexMatch (printf "(?i)%s" $key) $dbTypeInValues }}
  {{- $dbType = $value | quote }}
{{- end }}
{{- end }}
  "dbType": {{ $dbType }},
{{- end }}
  "isClusteringEnabled": {{ .Values.bitbucket.clustering.enabled }},
  "isSharedHomePVCCreated": {{ .Values.volumes.sharedHome.persistentVolumeClaim.create }},
  "isServiceMonitorCreated": {{ .Values.monitoring.serviceMonitor.create }},
  "isGrafanaDashboardsCreated": {{ .Values.monitoring.grafana.createDashboards }},
  "isBitbucketMeshEnabled": {{ .Values.bitbucket.mesh.enabled }}
}
{{- end }}

{{/*
The name of the service account to be used.
If the name is defined in the chart values, then use that,
else if we're creating a new service account then use the name of the Helm release,
else just use the "default" service account.
*/}}
{{- define "bitbucket.serviceAccountName" -}}
{{- if .Values.serviceAccount.name -}}
{{- .Values.serviceAccount.name -}}
{{- else -}}
{{- if .Values.serviceAccount.create -}}
{{- include "common.names.fullname" . -}}
{{- else -}}
default
{{- end -}}
{{- end -}}
{{- end }}

{{/*
The name of the ClusterRole that will be created.
If the name is defined in the chart values, then use that,
else use the name of the Helm release.
*/}}
{{- define "bitbucket.clusterRoleName" -}}
{{- if and .Values.serviceAccount.clusterRole.name .Values.serviceAccount.clusterRole.create }}
{{- .Values.serviceAccount.clusterRole.name }}
{{- else }}
{{- include "common.names.fullname" . -}}
{{- end }}
{{- end }}

{{/*
The name of the ClusterRoleBinding that will be created.
If the name is defined in the chart values, then use that,
else use the name of the ClusterRole.
*/}}
{{- define "bitbucket.clusterRoleBindingName" -}}
{{- if and .Values.serviceAccount.clusterRoleBinding.name .Values.serviceAccount.clusterRoleBinding.create }}
{{- .Values.serviceAccount.clusterRoleBinding.name }}
{{- else }}
{{- include "bitbucket.clusterRoleName" . -}}
{{- end }}
{{- end }}

{{/*
Pod labels
*/}}
{{- define "bitbucket.podLabels" -}}
{{ with .Values.podLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Mesh Pod labels
*/}}
{{- define "bitbucket.mesh.podLabels" -}}
{{ with .Values.bitbucket.mesh.podLabels }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{- define "bitbucket.baseUrl" -}}
{{ ternary "https" "http" .Values.ingress.https -}}
://
{{- .Values.ingress.host -}}
{{ with .Values.ingress.port }}:{{ . }}{{ end }}
{{- end }}

{{/*
Create default value for ingress path
*/}}
{{- define "bitbucket.ingressPath" -}}
{{- if .Values.ingress.path -}}
{{- .Values.ingress.path -}}
{{- else -}}
{{ default ( "/" ) .Values.bitbucket.service.contextPath -}}
{{- end }}
{{- end }}

{{- define "bitbucket.ingressPort" -}}
{{ default (ternary "443" "80" .Values.ingress.https) .Values.ingress.port -}}
{{- end }}

{{/*
The command that should be run by the nfs-fixer init container to correct the permissions of the shared-home root directory.
*/}}
{{- define "bitbucket.sharedHome.permissionFix.command" -}}
{{- $securityContext := .Values.bitbucket.securityContext }}
{{- with .Values.volumes.sharedHome.nfsPermissionFixer }}
    {{- if .command }}
        {{ .command }}
    {{- else }}
        {{- if and $securityContext.gid $securityContext.enabled }}
            {{- printf "(chgrp %v %s; chmod g+w %s)" $securityContext.gid .mountPath .mountPath }}
        {{- else if $securityContext.fsGroup }}
            {{- printf "(chgrp %v %s; chmod g+w %s)" $securityContext.fsGroup .mountPath .mountPath }}
        {{- else }}
            {{- printf "(chgrp 2001 %s; chmod g+w %s)" .mountPath .mountPath }}
        {{- end }}
    {{- end }}
{{- end }}
{{- end }}

{{/*
The command that should be run to start the fluentd service
*/}}
{{- define "fluentd.start.command" -}}
{{- if .Values.fluentd.command }}
{{ .Values.fluentd.command }}
{{- else }}
{{- print "exec fluentd -c /fluentd/etc/fluent.conf -v" }}
{{- end }}
{{- end }}

{{- define "bitbucket.image" -}}
{{- if .Values.image.registry -}}
{{ .Values.image.registry}}/{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- else -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end }}
{{- end }}

{{/*
Define pod annotations here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.podAnnotations" -}}
{{- range $key, $value := .Values.podAnnotations }}
{{ $key }}: {{ tpl $value $ | quote }}
{{- end }}
{{- end }}

{{/*
Define pod annotations here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.mesh.podAnnotations" -}}
{{- with .Values.bitbucket.mesh.podAnnotations }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional init containers here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.additionalInitContainers" -}}
{{- with .Values.additionalInitContainers }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional init containers here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.mesh.additionalInitContainers" -}}
{{- with .Values.bitbucket.mesh.additionalInitContainers }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional containers here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.additionalContainers" -}}
{{- with .Values.additionalContainers }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional ports here instead of in values.yaml to allow template overrides
*/}}
{{- define "bitbucket.additionalPorts" -}}
{{- with .Values.bitbucket.additionalPorts }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional volume mounts here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.additionalVolumeMounts" -}}
{{- with .Values.bitbucket.additionalVolumeMounts }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional environment variables here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.additionalEnvironmentVariables" -}}
{{- with .Values.bitbucket.additionalEnvironmentVariables }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
Define additional environment variables here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.mesh.additionalEnvironmentVariables" -}}
{{- with .Values.bitbucket.mesh.additionalEnvironmentVariables }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{/*
For each additional library declared, generate a volume mount that injects that library into the Bitbucket lib directory
*/}}
{{- define "bitbucket.additionalLibraries" -}}
{{- range .Values.bitbucket.additionalLibraries }}
- name: {{ .volumeName }}
  mountPath: "/opt/atlassian/bitbucket/app/WEB-INF/lib/{{ .fileName }}"
  {{- if .subDirectory }}
  subPath: {{ printf "%s/%s" .subDirectory .fileName | quote }}
  {{- else }}
  subPath: {{ .fileName | quote }}
  {{- end }}
{{- end }}
{{- end }}

{{/*
For each additional plugin declared, generate a volume mount that injects that library into the Bitbucket plugins directory
*/}}
{{- define "bitbucket.additionalBundledPlugins" -}}
{{- range .Values.bitbucket.additionalBundledPlugins }}
- name: {{ .volumeName }}
  mountPath: "/opt/atlassian/bitbucket/app/WEB-INF/atlassian-bundled-plugins/{{ .fileName }}"
  {{- if .subDirectory }}
  subPath: {{ printf "%s/%s" .subDirectory .fileName | quote }}
  {{- else }}
  subPath: {{ .fileName | quote }}
  {{- end }}
{{- end }}
{{- end }}


{{/*
Define additional hosts here to allow template overrides when used as a sub chart
*/}}
{{- define "bitbucket.additionalHosts" -}}
{{- with .Values.additionalHosts }}
{{- toYaml . }}
{{- end }}
{{- end }}

{{- define "bitbucket.volumes" -}}
{{ if not .Values.volumes.localHome.persistentVolumeClaim.create }}
{{ include "bitbucket.volumes.localHome" . }}
{{- end }}
{{ include "bitbucket.volumes.sharedHome" . }}
{{- with .Values.volumes.additional }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- if .Values.bitbucket.additionalCertificates.secretName }}
- name: keystore
  emptyDir: {}
- name: certs
  secret:
    secretName: {{ .Values.bitbucket.additionalCertificates.secretName }}
{{- end }}
{{- if or .Values.atlassianAnalyticsAndSupport.analytics.enabled .Values.atlassianAnalyticsAndSupport.helmValues.enabled }}
- name: helm-values
  configMap:
    name: {{ include "common.names.fullname" . }}-helm-values
{{- end }}
{{- end }}

{{- define "bitbucket.volumes.localHome" -}}
{{- if not .Values.volumes.localHome.persistentVolumeClaim.create }}
- name: local-home
{{ if .Values.volumes.localHome.customVolume }}
{{- toYaml .Values.volumes.localHome.customVolume | nindent 2 }}
{{ else }}
  emptyDir: {}
{{- end }}
{{- end }}
{{- end }}

{{- define "bitbucket.volumes.sharedHome" -}}
{{- if .Values.volumes.sharedHome.persistentVolumeClaim.create }}
- name: shared-home
  persistentVolumeClaim:
    claimName: {{ include "common.names.fullname" . }}-shared-home
{{ else if .Values.volumes.sharedHome.customVolume }}
- name: shared-home
{{- toYaml .Values.volumes.sharedHome.customVolume | nindent 2 }}
{{- else if and (eq .Values.bitbucket.applicationMode "mirror") .Values.monitoring.exposeJmxMetrics }}
- name: shared-home
  emptyDir: {}
{{- end }}
{{- end }}

{{- define "bitbucket.volume.sharedHome.name" -}}
{{ include "common.names.fullname" . }}-shared-home-pv
{{- end }}

{{- define "bitbucket.volumeClaimTemplates" -}}
{{- if or .Values.volumes.localHome.persistentVolumeClaim.create .Values.bitbucket.additionalVolumeClaimTemplates }}
volumeClaimTemplates:
{{- if .Values.volumes.localHome.persistentVolumeClaim.create }}
- metadata:
    name: local-home
  spec:
    accessModes: [ "ReadWriteOnce" ]
    {{- if .Values.volumes.localHome.persistentVolumeClaim.storageClassName }}
    storageClassName: {{ .Values.volumes.localHome.persistentVolumeClaim.storageClassName | quote }}
    {{- end }}
    {{- with .Values.volumes.localHome.persistentVolumeClaim.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- range .Values.bitbucket.additionalVolumeClaimTemplates }}
- metadata:
    name: {{ .name }}
  spec:
    accessModes: [ "ReadWriteOnce" ]
    {{- if .storageClassName }}
    storageClassName: {{ .storageClassName | quote }}
    {{- end }}
    {{- with .resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "bitbucket.mesh.volumeClaimTemplates" -}}
{{- if .Values.bitbucket.mesh.volume.create }}
volumeClaimTemplates:
- metadata:
    name: mesh-home
  spec:
    accessModes: [ "ReadWriteOnce" ]
    {{- if .Values.bitbucket.mesh.volume.storageClass }}
    storageClassName: {{ .Values.bitbucket.mesh.volume.storageClass | quote }}
    {{- end }}
    {{- with .Values.bitbucket.mesh.volume.resources }}
    resources:
      {{- toYaml . | nindent 6 }}
    {{- end }}
{{- end }}
{{- end }}

{{- define "bitbucket.databaseEnvVars" -}}
{{ with .Values.database.driver }}
- name: JDBC_DRIVER
  value: {{ . | quote }}
{{ end }}
{{ with .Values.database.url }}
- name: JDBC_URL
  value: {{ . | quote }}
{{ end }}
{{ with .Values.database.credentials.secretName }}
- name: JDBC_USER
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.database.credentials.usernameSecretKey }}
- name: JDBC_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: {{ $.Values.database.credentials.passwordSecretKey }}
{{ end }}
{{ end }}

{{- define "bitbucket.sysadminEnvVars" -}}
{{ with .Values.bitbucket.sysadminCredentials }}
{{ if .secretName }}
- name: SETUP_SYSADMIN_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .usernameSecretKey }}
- name: SETUP_SYSADMIN_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .passwordSecretKey }}
- name: SETUP_SYSADMIN_DISPLAYNAME
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .displayNameSecretKey }}
- name: SETUP_SYSADMIN_EMAILADDRESS
  valueFrom:
    secretKeyRef:
      name: {{ .secretName }}
      key: {{ .emailAddressSecretKey }}
{{ end }}
{{ end }}
{{ end }}

{{- define "bitbucket.clusteringEnvVars" -}}
{{ if .Values.bitbucket.clustering.enabled }}
- name: KUBERNETES_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: HAZELCAST_KUBERNETES_SERVICE_NAME
  value: {{ include "common.names.fullname" . | quote }}
- name: HAZELCAST_NETWORK_KUBERNETES
  value: "true"
- name: HAZELCAST_PORT
  value: {{ .Values.bitbucket.ports.hazelcast | quote }}
{{- include "bitbucket.hazelcastGroupEnvVars" . }}
{{ end }}
{{ end }}

{{- define "bitbucket.hazelcastGroupSecretName" -}}
{{- .Values.bitbucket.clustering.group.secretName | default (printf "%s-clustering" (include "common.names.fullname" .)) -}}
{{- end }}

{{- define "bitbucket.hazelcastGroupEnvVars" }}
- name: HAZELCAST_GROUP_NAME
  valueFrom:
    secretKeyRef:
      name: {{ include "bitbucket.hazelcastGroupSecretName" . | quote }}
      key: {{ .Values.bitbucket.clustering.group.nameSecretKey | quote }}
- name: HAZELCAST_GROUP_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "bitbucket.hazelcastGroupSecretName" . | quote }}
      key: {{ .Values.bitbucket.clustering.group.passwordSecretKey | quote }}
{{- end }}

{{- define "bitbucket.elasticSearchEnvVars" -}}
{{- if or .Values.bitbucket.elasticSearch.baseUrl .Values.bitbucket.clustering.enabled }}
- name: SEARCH_ENABLED
  value: "false"
{{- end }}
{{ with .Values.bitbucket.elasticSearch.baseUrl }}
- name: PLUGIN_SEARCH_ELASTICSEARCH_BASEURL
  value: {{ . | quote }}
{{ end }}
{{ if .Values.bitbucket.elasticSearch.credentials.secretName }}
- name: PLUGIN_SEARCH_ELASTICSEARCH_USERNAME
  valueFrom:
    secretKeyRef:
      name: {{ .Values.bitbucket.elasticSearch.credentials.secretName | quote }}
      # this is for backward compatability with 1.0.0
      key: {{ coalesce .Values.bitbucket.elasticSearch.credentials.usernameSecretKey .Values.bitbucket.elasticSearch.credentials.usernameSecreyKey | quote }}
- name: PLUGIN_SEARCH_ELASTICSEARCH_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ .Values.bitbucket.elasticSearch.credentials.secretName | quote }}
      key: {{ .Values.bitbucket.elasticSearch.credentials.passwordSecretKey | quote }}
{{ end }}
{{ end }}

{{- define "flooredCPU" -}}
    {{- if hasSuffix "m" (. | toString) }}
    {{- div (trimSuffix "m" .) 1000 | default 1 }}
    {{- else }}
    {{- . }}
    {{- end }}
{{- end}}

{{- define "bitbucket.addCrtToKeystoreCmd" }}
{{- if .Values.bitbucket.additionalCertificates.customCmd}}
{{ .Values.bitbucket.additionalCertificates.customCmd}}
{{- else }}
set -e; cp $JAVA_HOME/lib/security/cacerts /var/ssl/cacerts; for crt in /tmp/crt/*.*; do echo "Adding $crt to keystore"; keytool -import -keystore /var/ssl/cacerts -storepass changeit -noprompt -alias $(echo $(basename $crt)) -file $crt; done;
{{- end }}
{{- end }}

{{- define "bitbucketMesh.addCrtToKeystoreCmd" }}
{{- if .Values.bitbucket.mesh.additionalCertificates.customCmd}}
{{ .Values.bitbucket.mesh.additionalCertificates.customCmd}}
{{- else }}
set -e; cp $JAVA_HOME/lib/security/cacerts /var/ssl/cacerts; for crt in /tmp/crt/*.*; do echo "Adding $crt to keystore"; keytool -import -keystore /var/ssl/cacerts -storepass changeit -noprompt -alias $(echo $(basename $crt)) -file $crt; done;
{{- end }}
{{- end }}
