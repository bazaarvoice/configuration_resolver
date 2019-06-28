# EFFECT: parses a dependency graph of default value functions, possibly setting them interactively.
# CALLERS: core_params.rb

require 'optparse'
require 'json'

module ConfigurationResolver

  class UserInput

    # Map of param -> overriden value
    @@user_overrides = {}

    # Getter for the user overrides.
    def self.user_overrides
      @@user_overrides
    end

    # Remember a user override for persistence later.
    def self.set_user_overrides!(param, value)
      @@user_overrides[param.to_sym] = value
    end

    # Remove all the user overrides from the state
    def self.clear_user_overrides
      @@user_overrides = {}
    end


    # Takes a map of parameter default value functions, a map of key-value parameter overrides,
    # and an array of parameters that the user should be prompted for interactively.
    #
    # If neither tryDefaults or acceptDefaults are passed to this method, then this library
    # will walk through the dependency graph of default value functions interactively, prompting
    # the user to either verify that the default value should be used, or accepting a new value
    # from the user. The overrides passed into this method, are not prompted for.  When the
    # resolution is complete, the user will be prompted to confirm that the values look correct.
    # The user can then choose to proceed, or to run through the parameters and either override
    # or accept the current value for each.
    #
    # When tryDefaults is among the literal overrides, then this library will resolve the dependency graph
    # automatically with default value functions, and will prompt the user to confirm or revisit the parameters
    # whether it was able to resolve all the parameters or not.
    #
    # When acceptDefaults is among the literal overrides, then this library will resolve the dependency
    # graph of default value functions and will not prompt the user at all before executing the deployment unless
    # it is unable to resolve a parameter's value.
    def self.get_arguments_using(default_param_functions, already_set={}, promptable_parameters=[])
      clear_user_overrides
      already_set.each do |key, value|
        set_user_overrides!(key, value)
      end

      try_defaults = already_set[:tryDefaults] == "true"
      accept_defaults = already_set[:acceptDefaults] == "true"
      parameters = {}.merge(already_set)

      # Collect all of the arguments into the parameter hash using an option parser.
      OptionParser.new do |opts|
        opts.banner = "Usage: #{__FILE__} [options]"
        default_param_functions.keys.each do |param|
          name = "--" + param.to_s[0, 1].downcase + param.to_s[1..-1]
          opts.on(name + "=" + param.to_s) do |value|
            set_user_overrides!(param, value.to_s)
            parameters[param] = value.to_s
          end
        end
        opts.on("--acceptDefaults") do
          accept_defaults = true
        end
        opts.on("--tryDefaults") do
          try_defaults = true
        end
        opts.on("-h", "--help", "Prints this help") do
          puts(opts)
          exit
        end
      end.parse!


      # Turning this on means we won't do interactive deployment unless we can't resolve the parameters by using defaults.
      if accept_defaults or try_defaults
        parameters = self.resolve_parameters(default_param_functions, parameters)
      end

      parameters = self.interactively_set_params(default_param_functions, parameters, promptable_parameters)

      parameters = self.resolve_parameters(default_param_functions, parameters)

      parameters = self.interactively_revise_params(accept_defaults, try_defaults, parameters)

      parameters
    end

    # If applicable, prompt the user with the resolved parameters, and ask for confirmation.  Failing confirmation,
    # passes over each parameter allowing it to be revised.
    def self.interactively_revise_params(accept_defaults, try_defaults, parameters)
      # Revise parameters.
      # Until we break out,
      until accept_defaults
        puts "Revising parameters interactively\n"
        # Tell the user what parameters we're going to use for the build.
        puts "Current parameters are:\n#{JSON.pretty_generate parameters}"
        # Prompt the user to tell us whether we need to revise the parameters.
        puts "Are we happy?  Hit return to accept these parameters, or enter \"no\" to refine them."
        # Get user input.
        response = gets.strip
        # If the user didn't say anything, break out of the parameter revision loop.
        if response.empty?
          break
        end
        # For every parameter,
        parameters.each do |key, value|
          # prompt the user to decide on the value.
          puts "\nCurrent value of #{key} is #{value}.  Enter the value you'd like to use, or hit return to keep the current value."
          # Get user input.
          response = gets.strip
          # If the user changed the value,
          if !response.empty?
            # then set it.
            parameters[key] = response
            set_user_overrides!(key, response)
          end
          # Tell the user what's being persisted in the parameters hash post-revision.
          puts "Okay, we'll use #{parameters[key]} for #{key}"
        end
      end
      parameters
    end

    # If applicable, prompt the user for each unresolved parameter from promptable parameters, and ask for confirmation of the default value, if any.  Failing confirmation,
    # allow it to be revised.
    def self.interactively_set_params(default_param_functions, parameters, promptable_parameters)

      prev_unset = nil
      all_deps = []
      # Interactively set the remaining parameters.

      # While there are unset parameters,
      until (unset_params = default_param_functions.keys.select{|param| parameters[param].nil?}.select{|param| promptable_parameters.include?(param)}).empty?
        # If it's clear we're not going to be able to resolve the function graph,
        if !prev_unset.nil? && prev_unset.length == unset_params.length
          # display the responsible parameters.
          raise "Can't resolve parameters.  Parameters still unset:\n#{JSON.pretty_generate(unset_params)}\nDependencies not set for unset params:\n#{JSON.pretty_generate(
            unset_params.map{ |e|
              {
                :param => e,
                :unset_dependencies => default_param_functions[e].last[:dependencies].select{ |d|
                  parameters[d].nil?
                }
              }
            }
          )
          }"
        end
        # Go through the unset parameters,
        prev_unset = unset_params.dup
        unset_params.each do |param|
          no_dependencies = default_param_functions[param].last[:dependencies].nil?
          unless no_dependencies
            all_deps += default_param_functions[param].last[:dependencies]
          end
          # If all of the dependencies are set,
          if (
          no_dependencies ||
            default_param_functions[param].last[:dependencies].select{
              |p| parameters[p].nil?
            }.empty?
          )
            if default_param_functions[param].last.keys.include?(:dependencyFunction)
              real_dependencies = default_param_functions[param].last[:dependencyFunction].call(default_param_functions[param].last[:dependencies].map{|p| [p, parameters[p]]}.to_h)
              # Skip this parameter unless the real dependencies are met too.
              next unless real_dependencies.select{|e| parameters[e].nil?}.empty?
            end

            # Then call the default value function for this parameter to get the default value.
            # Pass as parameters to that function all of the parameter values specified in this parameter's dependencies.
            if no_dependencies
              default_value = default_param_functions[param].last[:function].nil? ? nil : default_param_functions[param].last[:function].call({})
            elsif !default_param_functions[param].last[:dependencyFunction].nil?
              default_value = default_param_functions[param].last[:function].nil? ? nil : default_param_functions[param].last[:function].call(Hash[real_dependencies.map{|p| [p, parameters[p]]}])
            else
              default_value = default_param_functions[param].last[:function].nil? ? nil : default_param_functions[param].last[:function].call(Hash[default_param_functions[param].last[:dependencies].map{|p| [p, parameters[p]]}])
            end
            if parameters[:loadFrom].nil? || parameters[:loadFrom].empty?
              # First bit of user prompting is to inform the user of which parameter we're inspecting.
              puts "\nNeed to set #{param.to_s}.  Enter the value you'd like to use."
              # Second bit of user prompting is to ask the user to input a value, and tell them the default value if there is one.
              unless default_value.nil?
                puts "(You can hit return to accept the default value {#{default_value}})"
              end
              # Get user input.
              value = gets.strip
            else
              value = nil
            end
            unless value.nil? || value.empty?
              set_user_overrides!(param, value)
            end
            # Default the user input if necessary.
            value = (value.nil? || value.empty?) ? default_value.to_s : value
            # Tell the user what we're going to use for this parameter if we have something.
            # If there is no default, and the user didn't specify anything, tell them we'll
            # still need this question answered later.
            puts value == nil ? "You need to specify this one - but we'll come back to it." : "Okay, we'll use #{value} for #{param.to_s}\n"
            # Set the parameter.
            parameters[param] = value
          end
        end
      end
      parameters
    end

    # Override the dependency graph of default value functions with a set of set_params, and then resolve that dependency
    # graph of functions into key-value parameters that result.
    def self.resolve_parameters(default_param_functions, set_params={})
      parameters = set_params
      loop do
        # assume we can't set any more params so we'll break out of this loop if we find none that we can set.
        can_set_more_parameters = false
        # Get all the params that aren't set.
        unset_params = default_param_functions.keys.select{|param| parameters[param].nil?}
        # Go through the unset parameters,
        unset_params.each do |param|
          begin
            no_dependencies = default_param_functions[param].last[:dependencies].nil?
            # If all of the dependencies are set, and this parameter isn't set,
            if (no_dependencies ||
              default_param_functions[param].last[:dependencies].select{
                |p| parameters[p].nil?
              }.empty?
            ) && parameters[param].nil?

              if default_param_functions[param].last.keys.include?(:dependencyFunction)
                real_dependencies = default_param_functions[param].last[:dependencyFunction].call(default_param_functions[param].last[:dependencies].map{|p| [p, parameters[p]]}.to_h)
                # Skip this parameter unless the real dependencies are met too.
                next unless real_dependencies.select{|e| parameters[e].nil?}.empty?
              end

              # Then call the default value function for this parameter to get the default value.
              # Pass as parameters to that function all of the parameter values specified in this parameter's dependencies.
              default_value = nil
              unless default_param_functions[param].last[:function].nil?
                if no_dependencies
                  default_value = default_param_functions[param].last[:function].call({})
                elsif !default_param_functions[param].last[:dependencyFunction].nil?
                  default_value = default_param_functions[param].last[:function].nil? ? nil : default_param_functions[param].last[:function].call(Hash[real_dependencies.map{|p| [p, parameters[p]]}])
                else
                  default_value = default_param_functions[param].last[:function].call(Hash[default_param_functions[param].last[:dependencies].map{|p| [p, parameters[p]]}])
                end
              end
              if default_param_functions[param].last[:executeOnlyOnce]
                set_user_overrides!(param, default_value)
              end
              # We may be able to set more parameters now that we've modified the parameter hash, so prevent breaking out of the loop this iteration.
              can_set_more_parameters = can_set_more_parameters || !default_value.nil?
              # Set the default value.
              parameters[param] = default_value.nil? ? nil : default_value
            end
          end
        end
        break unless can_set_more_parameters
      end
      parameters
    end
  end
end