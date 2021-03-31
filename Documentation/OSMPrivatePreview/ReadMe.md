# Azure Monitor Container Insights Open Service Mesh Monitoring

Azure Monitor container insights now supporting preview of Open Service Mesh(OSM) Monitoring. As part of this support. Customer can
1.	Filter & view inventory of all the services that are part of your service mesh.
2.	Visualize and monitor requests between services in your service mesh, with request latency, error rate & resource utilization by services.
3.	Provides connection summary for OSM infrastructure running on AKS.

## How to onboard Container Insights OSM monitoring?
OSM exposes Prometheus metrics which container insights collect, for container insights agent to collect OSM metrics follow the following steps.
1.	Enable OSM to expose Prometheus metrics https://github.com/openservicemesh/osm/blob/main/docs/patterns/observability/metrics.md#configuring-prometheus-metrics-scraping
2.	If you are using Azure Monitor container insights, if not on-board here.
3.	If you are configuring your existing ConfigMap, append the following section in your existing ConfigMap yaml file
a.	Set the setting here for monitor_kubernetes_pods to true
4.	 Else if you don't have ConfigMap, download the new ConfigMap from here. & then
a.	Set the setting here for monitor_kubernetes_pods to true
5.	Run the following kubectl command: kubectl apply -f<configmap_yaml_file.yaml>
               Example: kubectl apply -f container-azm-ms-agentconfig.yaml.
The configuration change can take a few minutes //15 mins to finish before taking effect, and all omsagent pods in the cluster will restart. The restart is a rolling restart for all omsagent pods, not all restart at the same time.


## Validate the metrics flow
1.	Kusto query insight metrics name contains envoy.

## How to consume OSM monitoring dashboard?
1.	Access your AKS cluster & container insights through this [link.](https://aka.ms/azmon/osmux)
2.	Go to reports tab and access Open Service Mesh (OSM) workbook (screen below)
3.	Select the time-range & namespace to scope your services. By default, we only show services deployed by customers and we exclude internal service communication. In case you want to view that you select Show All in the filter. Please note OSM is managed service mesh, we show all internal connections for transparency. 

### Requests Tab
1.	This tab provides you the summary of all the http requests sent via service to service in OSM.
2.	You can view all the services and all the services it is communicating to by selecting the service in grid.
3.	You can view total requests, request error rate & P90 latency.
4.	You can drill-down to destination and view trends for HTTP error/success code, success rate, Pods resource utilization, latencies at different percentiles.

### Connections Tab
1.	This tab provides you a summary of all the connections between your services in Open Service Mesh. 
2.	Outbound connections: Total number of connections between Source and destination services.
3.	Outbound active connections: Last count of active connections between source and destination in selected time range.
4.	Outbound failed connections: Total number of failed connections between source and destination service

### Troubleshooting guidance when Outbound active connections is 0 or failed connection count is >10k.
1. Please check your connection policy in OSM configuration.
2. If connection policy is fine, please refer the OSM documentation. https://aka.ms/osm/tsg
3. From this view as well, you can drill-down to destination and view trends for HTTP error/success code, success rate, Pods resource utilization, latencies at different percentiles.


### Known Issues
1.	Scale 50 pods; can select namespace; cost issue
2.	Large scale UX limit.
3.	Local here.
4.	OSM controller no latency & for internal services no resource utilization. 

Feedback: This is private preview, the goal for us is to get feedback. Feel free to reach out to us at [askcoin@microsoft.com](mailto:askcoin@microsoft.com) for any feedback and questions!
