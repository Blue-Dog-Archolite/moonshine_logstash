module Moonshine
  module Logstash
    def logstash(options = {})
      package 'simonmcc/logstash', :ensure => :installed
    end
  end
end
