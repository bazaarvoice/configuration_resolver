require 'test_helper'

class ConfigurationResolverTest < Minitest::Test

  @@group0 = {
    group: {
      publish: false,
      function: lambda { |_|
        'layer0'
      }
    },

    dep0: {
      function: lambda { |_|
        'layer0:dep0'
      }
    },

    config: {
      dependencies: [:group, :dep0],
      function: lambda { |p|
        "layer0:config with dependencies: group:'#{p[:group]}' dep0:'#{p[:dep0]}'"
      }
    }
  }

  @@group1 = {

    group: {
      publish: false,
      function: lambda { |_|
        'layer1'
      }
    },

    dep1: {
      function: lambda { |_|
        'layer1:dep1'
      }
    },

    config: {
      dependencies: [:group, :dep0, :dep1],
      function: lambda { |p|
        "layer1:config with dependencies: group:'#{p[:group]}' dep0:'#{p[:dep0]}' dep1:'#{p[:dep1]}'"
      }
    }
  }

  def test_version_number_exists
    refute_nil ::ConfigurationResolver::VERSION
  end

  def test_single_group
    ConfigurationResolver::Resolver.merge_params(@@group0)

    ConfigurationResolver::Resolver.merge_group_functions
    params = ConfigurationResolver::UserInput.get_arguments_using(
      ConfigurationResolver::Resolver.all_params,
      {:acceptDefaults => 'true'},
      {}
    )

    expected = {
      acceptDefaults: 'true',
      config: "layer0:config with dependencies: group:'layer0' dep0:'layer0:dep0'",
      dep0: 'layer0:dep0',
      group: 'layer0'
    }

    assert params.sort_by { |k, _| k }.to_h == expected
  end

  def test_multiple_groups
    ConfigurationResolver::Resolver.merge_params(@@group0)
    ConfigurationResolver::Resolver.merge_params(@@group1)

    ConfigurationResolver::Resolver.merge_group_functions
    params = ConfigurationResolver::UserInput.get_arguments_using(
      ConfigurationResolver::Resolver.all_params,
      {:acceptDefaults => 'true'},
      {}
    )

    expected = {
      acceptDefaults: 'true',
      config: "layer1:config with dependencies: group:'layer1' dep0:'layer0:dep0' dep1:'layer1:dep1'",
      dep0: 'layer0:dep0',
      dep1: 'layer1:dep1',
      group: 'layer1'
    }

    assert params.sort_by { |k, _| k }.to_h == expected
  end
end
