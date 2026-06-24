ENV['RACK_ENV'] = 'test'

require 'minitest/autorun'
require 'minitest/reporters'
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new
require 'rack/test'
require_relative '../app'

class BaseTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def run(*args, &block)
    DB.transaction(rollback: :always, auto_savepoint: true) do
      super
    end
  end

  def seed_db
    DB['INSERT INTO templates(id, name, discount, cashback) VALUES(?, ?, ?, ?)', 1, 'Bronze', 0, 5].insert
    DB['INSERT INTO templates(id, name, discount, cashback) VALUES(?, ?, ?, ?)', 2, 'Silver', 5, 5].insert
    DB['INSERT INTO templates(id, name, discount, cashback) VALUES(?, ?, ?, ?)', 3, 'Gold', 15, 0].insert

    DB['INSERT INTO users(id, template_id, name, bonus) VALUES(?, ?, ?, ?)', 1, 1, 'Иван', 10000].insert
    DB['INSERT INTO users(id, template_id, name, bonus) VALUES(?, ?, ?, ?)', 2, 2, 'Марина', 10000].insert
    DB['INSERT INTO users(id, template_id, name, bonus) VALUES(?, ?, ?, ?)', 3, 3, 'Женя', 10000].insert

    DB['INSERT INTO products(id, name, type, value) VALUES(?, ?, ?, ?)', 2, 'Молоко', 'increased_cashback', 10].insert
    DB['INSERT INTO products(id, name, type, value) VALUES(?, ?, ?, ?)', 3, 'Хлеб', 'discount', 15].insert
    DB['INSERT INTO products(id, name, type, value) VALUES(?, ?, ?, ?)', 4, 'Сахар', 'noloyalty', nil].insert
  end
end
