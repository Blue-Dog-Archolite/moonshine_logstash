module Moonshine
  module Logstash
    def logstash(options = {})
      package 'wget', :ensure => :installed

      exec 'install grok',
        :command => ['wget -O grok.deb http://semicomplete.googlecode.com/files/grok_1.20101030.3088_amd64.deb',
                     'dpkg -i grok.deb'].join(' && '),
        :cwd => '/tmp'

      exec 'download logstash',
        :command => ['mkdir -p ~/dev/tools/',
                     'cd ~/dev/tools/',
                     'wget -O logstash-1.1.5.jar http://semicomplete.com/files/logstash/logstash-1.1.5-monolithic.jar'].join(' && ')
    end
  end
end
