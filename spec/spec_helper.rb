# frozen_string_literal: true

# Copyright 2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

begin
  if ENV['COVERAGE']
    require 'simplecov'
    SimpleCov.start { add_filter 'spec' }
  end
rescue LoadError
end

$LOAD_PATH << File.join(File.dirname(File.dirname(__FILE__)), 'lib')

require 'rspec'
require 'active_support'
require 'action_dispatch'
require 'aws-sessionstore-dynamodb'
require 'rack/test'

# Default Rack application
class MultiplierApplication
  def initialize(app, options = {})
    @app = app
  end

  def call(env)
    if env['rack.session'][:multiplier]
      env['rack.session'][:multiplier] *= 2
    else
      env['rack.session'][:multiplier] = 1
    end
    [200, { 'Content-Type' => 'text/plain' }, ['All good!']]
  end
end

class RoutedRackApp
  attr_reader :routes

  def self.build(options)
    self.new(ActionDispatch::Routing::RouteSet.new) do |middleware|
      middleware.use ActionDispatch::DebugExceptions
      middleware.use ActionDispatch::Callbacks
      middleware.use ActionDispatch::Cookies
      middleware.use ActionDispatch::Flash
      middleware.use Aws::SessionStore::DynamoDB::RackMiddleware, options
      middleware.use MultiplierApplication
    end
  end

  def initialize(routes, &blk)
    @routes = routes
    @stack = ActionDispatch::MiddlewareStack.new(&blk).build(@routes)
  end

  def call(env)
    @stack.call(env)
  end
end

ConstantHelpers = lambda do
  let(:token_error_msg) { 'The security token included in the request is invalid' }
  let(:resource_error) do
    Aws::DynamoDB::Errors::ResourceNotFoundException.new(double('Seahorse::Client::RequestContext'), resource_error_msg)
  end
  let(:resource_error_msg) { 'The Resource is not found.' }
  let(:key_error) { Aws::DynamoDB::Errors::ValidationException.new(double('Seahorse::Client::RequestContext'), key_error_msg) }
  let(:key_error_msg) { 'The provided key element does not match the schema' }
  let(:client_error) do
    Aws::DynamoDB::Errors::UnrecognizedClientException.new(double('Seahorse::Client::RequestContext'), client_error_msg)
  end
  let(:client_error_msg) { 'Unrecognized Client.'}
  let(:invalid_cookie) { { 'HTTP_COOKIE' => 'rack.session=ApplePieBlueberries' } }
  let(:rack_default_error_msg) { "Warning! Aws::SessionStore::DynamoDB failed to save session. Content dropped.\n" }
end

RSpec.configure do |c|
  c.raise_errors_for_deprecations!
  c.before(:each, integration: true) do
    options = {
      endpoint:
        'http://localhost:8000'
    }
    dynamo_db_client = Aws::DynamoDB::Client.new(options)
    opts = { table_name: 'sessionstore-integration-test', dynamo_db_client: dynamo_db_client }

    defaults = Aws::SessionStore::DynamoDB::Configuration::DEFAULTS
    defaults = defaults.merge(opts)
    stub_const('Aws::SessionStore::DynamoDB::Configuration::DEFAULTS', defaults)

    Aws::SessionStore::DynamoDB::Table.create_table(opts)
  end
end
