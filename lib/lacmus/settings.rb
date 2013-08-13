module Lacmus
	module Settings
		extend self

		def load!
	    YAML.load(File.open("#{root}/config/lacmus.yml"))[env_name]
	  end

		def env_name
			return Lacmus::ENV if defined?(Lacmus::ENV)
	    return Rails.env   if defined?(Rails)
	    return 'development'
	  end

	  def root
	  	return Lacmus::ROOT if defined?(Lacmus::ROOT)
	  	return Rails.root   if defined?(Rails)
	  	return Dir.pwd
	  end

	  def running_under_rails?
	  	defined?(Rails)
	  end

	end
end