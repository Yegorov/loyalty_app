ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require "minitest/reporters"
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
require 'rack/test'
require_relative '../app'

class Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  # def run(*args, &block)
  #   Sequel::Model.db.transaction(rollback: :always, auto_savepoint: true) do
  #     super
  #   end
  # end
end
