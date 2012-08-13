require 'l2met/config'
require 'l2met/metric'
require 'librato/metrics'

module L2met
  module Processor
    extend self
    INTERVAL = 60
    Librato::Metrics.authenticate(Config.librato_email, Config.librato_token)

    def log(data, &blk)
      Scrolls.log({ns: "processor"}.merge(data), &blk)
    end

    def lm_queue
      @lm_queue ||= Librato::Metrics::Queue.new
    end

    def start
      Thread.new do
        loop do
          sleep(INTERVAL)
          Thread.new {snapshot!; drain_queue!}
        end
      end
    end

    def drain_queue!
      ql = lm_queue.length
      log(fn: __method__, length: ql) do
        if ql > 0
          lm_queue.submit
        end
      end
    end

    def snapshot!
      cntrs, hists = Metric.counters.length, Metric.histograms.length
      Metric.count(name: "l2met.snapshot", source: "counters", value: cntrs)
      Metric.count(name: "l2met.snapshot", source: "histograms", value: hists)
      log(fn: __method__, counters: cntrs, histograms: hists) do
        snapshot_histogram
        snapshot_counter
      end
    end

    def snapshot_counter
      Metric.counters!.each do |k, metric|
        name = [metric[:name], "count"].map(&:to_s).join(".")
        lm_queue.add(name => {source: metric[:source], type: "gauge",
                       value: metric[:value], attributes: metric[:attrs],
                       measure_time: Time.now.to_i})
      end
    end

    def snapshot_histogram
      Metric.histograms!.each do |k, metric|
        values = metric[:values].sort
        data = {min: values[0], max: values[-1],
          mean: values.reduce(:+) / values.length.to_f,
          median: values[values.length/2],
          perc95: values[(0.95 * values.length).ceil - 1],
          perc99: values[(0.99 * values.length).ceil - 1]}
        data.each do |stat, val|
          name = [metric[:name], stat].map(&:to_s).join(".")
          lm_queue.add(name => {source: metric[:source], type: "gauge",
                         value: val, attributes: metric[:attrs],
                         measure_time: Time.now.to_i})
        end
      end
    end
  end
end
