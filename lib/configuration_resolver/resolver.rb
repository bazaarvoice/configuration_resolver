require 'configuration_resolver/version'
require 'configuration_resolver/user_input'

module ConfigurationResolver

  class Resolver
    # Map of param -> config
    @@all_params = {}
    # Map of param -> group -> config
    @@group_functions = {}
    # Flag that tells us that we no longer needs to perform group function collapsing.
    @@group_functions_are_merged = false

    def self.group_functions
      @@group_functions
    end

    def self.all_params
      @@all_params
    end

    def self.supported_features
      [
        # Tagging a parameter with :executeOnlyOnce => true will execute its function once, and
        # record the value as an immutable override.  This has a couple of ramifications:
        #
        # - if parameter P depends on parameter D, and a new value is provided
        #   for D, P will /not/ re-evaluate.
        # - This makes the property behave exactly as if it were specified on the command line during deploy.
        #
        # One reason for this behavior might be that the value is expensive to compute, or might be platform-specific,
        # making it unreliable or inconvenient to recompute later.
        # This field is optional, and defaults to false.
        :executeOnlyOnce,
        # When true, parameter binding functions can call yield(p) to effectively call super - that is,
        # to call the parameter binding function that was available to all_params before this
        # parameter binding was pushed onto the parameter binding stack.
        :useSuper,
        # Tagging a parameter with :publish => true will allow your group params to contribute to the parameter
        # graph even if the deploy time group is not your group.
        # This field is optional, and defaults to false.
        :publish,
        # This list of params will be passed in order to your function.
        # This field is optional, and defaults to an empty array.
        :dependencies,
        # This is the function that should be invoked to retrieve the value of the parameter we're configuring.
        # This field is optional, and defaults to a function that takes no arguments and returns nil.
        :function,
        # Once in a very rare while, a parameter's dependencies need to be determined based on dynamic criteria.
        # To support this, users are permitted to add a dependencyFunction to their parameter bindings.  Using
        # a dependencyFunction means that your dependencies array will be used as the dependencies for your
        # dependencyFunction.  Your parameter binding's function will not be called until all of the parameters
        # given by calling your dependencyFunction are non-null.
        :dependencyFunction
      ]
    end

    def self.mutate_binding(param_name, config_block)

      # Enable yield to pass execution to super.
      if config_block[:useSuper]
        parent_config_block = @@all_params[param_name].last || {}
        parent_dependency_function = parent_config_block[:dependencyFunction]
        child_dependency_function = config_block[:dependencyFunction]
        unless parent_dependency_function.nil? && child_dependency_function.nil?
          parent_dependency_function ||= ->(p) {[]}
          child_dependency_function ||= ->(p) {[]}
          config_block[:dependencyFunction] = ->(p) {
            (child_dependency_function.call(p, parent_dependency_function)).to_set.to_a
          }
        end
        parent_dependencies = parent_config_block[:dependencies].nil? ? [] : parent_config_block[:dependencies]
        config_block[:dependencies] = ((config_block[:dependencies] || []).to_set + parent_dependencies.to_set).to_a
        parent_function = parent_config_block[:function] || ->(p) {}
        child_function = config_block[:function]

        # Special wrapper for executeOnlyOnce parent
        if parent_config_block[:executeOnlyOnce]
          parent_value = nil
          has_run = false
          parent_meta_function = ->(p) {
            unless has_run
              parent_value = parent_function.call
              has_run = true
            end
            parent_value
          }
          config_block[:function] = ->(p) {
            child_function.call(p, parent_meta_function)
          }
        else
          # simple super binding for regular parents
          config_block[:function] = ->(p) {
            child_function.call(p, parent_function)
          }
        end
      end
      config_block
    end

    def self.deploy_time_group
      all_params[:group].last[:function].call({})
    end

    def self.merge_group_functions
      unless @@group_functions_are_merged
        @@group_functions.each do |groupParam, configOptions|
          unless configOptions[deploy_time_group].nil?
            all_params[groupParam] ||= []
            all_params[groupParam] << @@group_functions[groupParam][deploy_time_group]
          end
        end
        @@group_functions_are_merged = true
      end
    end

    def self.merge_params(params)
      # If you don't define a group in your group params, then we can't correctly handle unpublished functions.
      raise "Must provide a group to merge params into." if params[:group].nil? || params[:group][:function].nil?
      # Group should not have any other parameters because it defines the layer for this set of parameters
      raise "Group must not depend on any other parameters." unless params[:group][:dependencies].nil?
      # Record the group doing the merge so that only this group exercises this group's function overrides.  (Unless the functions are published.)
      param_group = params[:group][:function].call({})
      # Your group function must return an actual group.
      raise "Group must have a value" if param_group.nil? || param_group.empty?

      # For each parameter configuration being merged,
      params.each do |param_name, config_block|

        # make sure no features are requested that have not been implemented.
        config_block.keys.each do |config_key|
          raise "#{config_key.to_s} is not a supported feature.  Options for parameter configuration include: [#{supported_features.join(", ")}]" unless supported_features.include? config_key
        end

        # When publish is explicitly set to false, (rather than being null),
        if config_block[:publish].nil? || config_block[:publish] || param_name == :group
          # Published parameter configurations operate in a last-one-wins fashion.
          @@all_params[param_name] ||= []
          @@all_params[param_name] << mutate_binding(param_name, config_block)
        else
          # Store the new config, and only merge it into core_params if the deploy time group is the group that owns this param.
          @@group_functions[param_name] ||= {}
          @@group_functions[param_name][param_group] = mutate_binding(param_name, config_block)
        end
      end
    end

  end

end
