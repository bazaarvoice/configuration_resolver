# ConfigurationResolver

## Overview

This is a dependency based hierarchical configuration resolver. It can be used to merge multiple groups of configuration, with each group containing configuration values or functions that override previously merged groups.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'configuration_resolver'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install configuration_resolver

## Usage

Call `ConfigurationResolver::Resolver.merge_params` for each group of params that need to be merged in. The order in which the parameter groups are merged in will determine the hierarchical order, with later groups overriding previously merged ones.

Once the groups are merged in, any group functions can be merged using `    ConfigurationResolver::Resolver.merge_group_functions
`.

The final resolved parameter list can be retrieved using 

```ruby
    params = ConfigurationResolver::UserInput.get_arguments_using(
      ConfigurationResolver::Resolver.all_params,
      {:acceptDefaults => 'true'},
      {}
    )
```

See the [configuration_resolver_test](test) for sample invocations.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/bazaarvoice/configuration_resolver.
