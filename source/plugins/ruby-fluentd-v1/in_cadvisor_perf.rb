#!/usr/local/bin/ruby
# frozen_string_literal: true
require 'fluent/plugin/input'

module Fluent::Plugin

  class CAdvisor_Perf_Input < Input
    Fluent::Plugin.register_input("cadvisorperf", self)

    def initialize
      super
      require "yaml"
      require 'yajl/json_gem'
      require "time"

      require_relative "CAdvisorMetricsAPIClient"
      require_relative "oms_common"
      require_relative "omslog"
      require_relative "constants"
    end

    config_param :run_interval, :time, :default => 60
    config_param :tag, :string, :default => "oneagent.containerInsights.LINUX_PERF_BLOB"
    config_param :mdmtag, :string, :default => "mdm.cadvisorperf"
    config_param :nodehealthtag, :string, :default => "kubehealth.DaemonSet.Node"
    config_param :containerhealthtag, :string, :default => "kubehealth.DaemonSet.Container"
    config_param :insightsmetricstag, :string, :default => "oneagent.containerinsights.INSIGHTS_METRICS_BLOB"

    def configure(conf)
      super
    end

    def start       
      if @run_interval
        super
        @finished = false
        @condition = ConditionVariable.new
        @mutex = Mutex.new
        @thread = Thread.new(&method(:run_periodic))
        if !ENV["AAD_MSI_AUTH_ENABLE"].nil? && !ENV["AAD_MSI_AUTH_ENABLE"].empty? && ENV["AAD_MSI_AUTH_ENABLE"].downcase == "true"
          @aad_msi_auth_enable = true
        end              
        $log.info("in_cadvisor_perf::start: aad auth enable:#{@aad_msi_auth_enable}")
      end
    end

    def shutdown
      if @run_interval
        @mutex.synchronize {
          @finished = true
          @condition.signal
        }
        @thread.join
        super # This super must be at the end of shutdown method
      end
    end

    def enumerate()
      currentTime = Time.now
      time = currentTime.to_f
      batchTime = currentTime.utc.iso8601
      @@istestvar = ENV["ISTEST"]
      begin
        eventStream = Fluent::MultiEventStream.new
        insightsMetricsEventStream = Fluent::MultiEventStream.new
        metricData = CAdvisorMetricsAPIClient.getMetrics(winNode: nil, metricTime: batchTime )
        metricData.each do |record|          
          eventStream.add(Fluent::Engine.now, record) if record
        end

        overrideTagsWithStreamIdsIfAADAuthEnabled()
        router.emit_stream(@tag, eventStream) if eventStream
        router.emit_stream(@mdmtag, eventStream) if eventStream
        router.emit_stream(@containerhealthtag, eventStream) if eventStream
        router.emit_stream(@nodehealthtag, eventStream) if eventStream

        
        if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && eventStream.count > 0)
          $log.info("cAdvisorPerfEmitStreamSuccess @ #{Time.now.utc.iso8601}")
        end

        #start GPU InsightsMetrics items
        begin
          containerGPUusageInsightsMetricsDataItems = []
          containerGPUusageInsightsMetricsDataItems.concat(CAdvisorMetricsAPIClient.getInsightsMetrics(winNode: nil, metricTime: batchTime))          

          containerGPUusageInsightsMetricsDataItems.each do |insightsMetricsRecord|
            insightsMetricsEventStream.add(Fluent::Engine.now, insightsMetricsRecord) if insightsMetricsRecord
          end

          router.emit_stream(@insightsmetricstag, insightsMetricsEventStream) if insightsMetricsEventStream
          router.emit_stream(@mdmtag, insightsMetricsEventStream) if insightsMetricsEventStream
          
          if (!@@istestvar.nil? && !@@istestvar.empty? && @@istestvar.casecmp("true") == 0 && insightsMetricsEventStream.count > 0)
            $log.info("cAdvisorInsightsMetricsEmitStreamSuccess @ #{Time.now.utc.iso8601}")
          end
        rescue => errorStr
          $log.warn "Failed when processing GPU Usage metrics in_cadvisor_perf : #{errorStr}"
          $log.debug_backtrace(errorStr.backtrace)
          ApplicationInsightsUtility.sendExceptionTelemetry(errorStr)
        end 
        #end GPU InsightsMetrics items

      rescue => errorStr
        $log.warn "Failed to retrieve cadvisor metric data: #{errorStr}"
        $log.debug_backtrace(errorStr.backtrace)
      end
    end

    def run_periodic
      @mutex.lock
      done = @finished
      @nextTimeToRun = Time.now
      @waitTimeout = @run_interval
      until done
        @nextTimeToRun = @nextTimeToRun + @run_interval
        @now = Time.now
        if @nextTimeToRun <= @now
          @waitTimeout = 1
          @nextTimeToRun = @now
        else
          @waitTimeout = @nextTimeToRun - @now
        end
        @condition.wait(@mutex, @waitTimeout)
        done = @finished
        @mutex.unlock
        if !done
          begin
            $log.info("in_cadvisor_perf::run_periodic.enumerate.start @ #{Time.now.utc.iso8601}")
            enumerate
            $log.info("in_cadvisor_perf::run_periodic.enumerate.end @ #{Time.now.utc.iso8601}")
          rescue => errorStr
            $log.warn "in_cadvisor_perf::run_periodic: enumerate Failed to retrieve cadvisor perf metrics: #{errorStr}"
          end
        end
        @mutex.lock
      end
      @mutex.unlock
    end

    def overrideTagsWithStreamIdsIfAADAuthEnabled()
      begin
        if @aad_msi_auth_enable        
          # perf
          if @tag.nil? || @tag.empty? || !@tag.start_with?("dcr-")     
            @tag = Extension.instance.get_output_stream_id("LINUX_PERF_BLOB")  
            if @tag.nil? || @tag.empty?
              $log.warn("in_cadvisor_perf::overrideTagsWithStreamIdsIfAADAuthEnabled: got the outstream id is nil or empty for the datatypeid: LINUX_PERF_BLOB")           
            else            
              $log.info("in_cadvisor_perf::overrideTagsWithStreamIdsIfAADAuthEnabled: using perf tag: #{@tag}")     
            end
          end   
          # insights metrics         
          if @insightsmetricstag.nil? || @insightsmetricstag.empty? || !@insightsmetricstag.start_with?("dcr-")     
            @insightsmetricstag = Extension.instance.get_output_stream_id("INSIGHTS_METRICS_BLOB")  
            if @insightsmetricstag.nil? || @insightsmetricstag.empty?
              $log.warn("in_cadvisor_perf::overrideTagsWithStreamIdsIfAADAuthEnabled: got the outstream id is nil or empty for the datatypeid: INSIGHTS_METRICS_BLOB")           
            else            
              $log.info("in_cadvisor_perf::overrideTagsWithStreamIdsIfAADAuthEnabled: using insightsmetrics tag: #{@insightsmetricstag}")  
            end
          end     
        end   
      rescue => errorStr
        $log.warn("in_cadvisor_perf::overrideTagsWithStreamIdsIfAADAuthEnabled:failed with an error: #{errorStr}")           
      end 
    end         

  end # CAdvisor_Perf_Input
end # module